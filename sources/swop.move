module swop::swop {

    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use std::option::{Self, Option};
    use swop::vec_set::{Self, VecSet};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::type_name::{Self};
    use sui::dynamic_field::{Self as field};
    friend swop::admin;

    const SWAP_STATUS_PENDING: u64 = 100;
    const SWAP_STATUS_ACCEPTED: u64 = 101;
    const SWAP_STATUS_REJECTED: u64 = 102;
    const SWAP_STATUS_CANCELLED: u64 = 103;
    const SWAP_STATUS_EXPIRED: u64 = 104;

    const TX_TYPE_CREATE: u64 = 200;
    const TX_TYPE_ACCEPT: u64 = 201;
    const TX_TYPE_CANCEL: u64 = 202;

    const TX_STEP_START: u64 = 300;
    const TX_STEP_ADD: u64 = 301;
    const TX_STEP_PUBLISH: u64 = 302;
    const TX_STEP_PAY: u64 = 303;
    const TX_STEP_CLAIM: u64 = 304;
    const TX_STEP_ACCEPT: u64 = 305;

    const EInsufficientValue: u64 = 400;
    const EInvalidExpiry: u64 = 401;
    const EInvalidSwapId: u64 = 402;
    const EInvalidOffer: u64 = 403;
    const ENotInitiator: u64 = 404;
    const EInvalidSequence: u64 = 405;
    const ENotCounterparty: u64 = 406;
    const EActionNotAllowed: u64 = 407;
    const ESuppliedLengthMismatch: u64 = 408;
    const EUnexpectedObjectFound: u64 = 409;
    const ERequestExpired: u64 = 410;
    const ECoinAlreadyAddedToOffer: u64 = 413;
    const ECoinNotAllowed: u64 = 414;
    const EProjectNotAllowed: u64 = 415;

    struct SwapDB has key, store {
        id: UID,
        registry: Bag,
        requests: Table<address, VecSet<ID>>,
        allowed_projects: UID,
        allowed_coins: UID,
        platform_fee: u64,
    }

    struct SwapRequest has key, store {
        id: UID,
        initiator: address,
        counterparty: address,
        nfts_to_receive: VecSet<ID>,
        coins_to_receive: u64,
        initiator_offer: Option<Offer>,
        counterparty_offer: Option<Offer>,
        status: u64,
        expiry: u64,
        platform_fee_balance: Balance<SUI>
    }

    struct Offer has store {
        owner: address,
        escrowed_nfts: Bag,
        escrowed_balance: Balance<SUI>,
    }

    struct Receipt {
        swap_id: ID,
        tx_type: u64,
        tx_step: u64,
        platform_fee_to_pay: u64,
    }

    fun init(ctx: &mut TxContext) {
        let swap_db = SwapDB {
            id: object::new(ctx),
            registry: bag::new(ctx),
            requests: table::new<address, VecSet<ID>>(ctx),
            allowed_projects: object::new(ctx),
            allowed_coins: object::new(ctx),
            platform_fee: 0
        };

        transfer::share_object(swap_db);
    }

    public(friend) fun borrow_mut_allowed_projects(swap_db: &mut SwapDB): &mut UID {
        &mut swap_db.allowed_projects
    }

    public(friend) fun borrow_mut_allowed_coins(swap_db: &mut SwapDB): &mut UID {
        &mut swap_db.allowed_coins
    }

    public(friend) fun borrow_mut_platform_fee(swap_db: &mut SwapDB): &mut u64 {
        &mut swap_db.platform_fee
    }

    public(friend) fun borrow_mut_registry(swap_db: &mut SwapDB): &mut Bag {
        &mut swap_db.registry
    }

    public(friend) fun borrow_mut_sr_balance(swap: &mut SwapRequest): &mut Balance<SUI> {
        &mut swap.platform_fee_balance
    }

    public(friend) fun borrow_mut_sr_status(swap: &mut SwapRequest): &mut u64 {
        &mut swap.status
    }


    public fun create(
        swap_db: &mut SwapDB,
        counterparty: address,
        nfts_to_receive: vector<ID>,
        coins_to_receive: u64,
        ctx: &mut TxContext
    ): (ID, Receipt) {
        let initiator = tx_context::sender(ctx);
        let initiator_offer = option::some(
            Offer { owner: initiator, escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );
        let counterparty_offer = option::some(
            Offer { owner: counterparty, escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );

        let swap = SwapRequest {
            id: object::new(ctx),
            initiator: tx_context::sender(ctx),
            counterparty,
            nfts_to_receive: vec_set::from_keys(nfts_to_receive),
            coins_to_receive,
            initiator_offer,
            counterparty_offer,
            status: SWAP_STATUS_PENDING,
            expiry: 0,
            platform_fee_balance: balance::zero()
        };
        let swap_id = object::id(&swap);
        bag::add(&mut swap_db.registry, swap_id, swap);

        let receipt = Receipt {
            swap_id,
            tx_type: TX_TYPE_CREATE,
            tx_step: TX_STEP_START,
            platform_fee_to_pay: swap_db.platform_fee
        };

        (swap_id, receipt)
    }

    public fun add_nft_to_offer<T: key+store>(
        swap_db: &mut SwapDB,
        swap_id: ID,
        nft: T,
        receipt: Receipt,
        ctx: &mut TxContext
    ): Receipt {
        assert!(receipt.swap_id == swap_id, EInvalidSwapId);
        assert!(
            (receipt.tx_type == TX_TYPE_CREATE || receipt.tx_type == TX_TYPE_ACCEPT) &&
                (receipt.tx_step == TX_STEP_START || receipt.tx_step == TX_STEP_ADD),
            EInvalidSequence
        );
        let type_name = type_name::into_string(type_name::get<T>());
        assert!(field::exists_(&swap_db.allowed_projects, type_name), EProjectNotAllowed);

        let swap = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(
            swap.status == SWAP_STATUS_PENDING && (sender == swap.counterparty || sender == swap.initiator),
            EActionNotAllowed
        );

        let offer = {
            if (swap.counterparty == sender) {
                option::borrow_mut(&mut swap.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        receipt.tx_step = TX_STEP_ADD;
        let escrowed_nft_len = bag::length(&offer.escrowed_nfts);
        bag::add(&mut offer.escrowed_nfts, escrowed_nft_len, nft);

        // TODO: emit events later on
        receipt
    }

    public fun add_coins_to_offer(
        swap_db: &mut SwapDB,
        swap_id: ID,
        coins: Coin<SUI>,
        receipt: Receipt,
        ctx: &mut TxContext
    ): Receipt {
        assert!(receipt.swap_id == swap_id, EInvalidSwapId);
        assert!(
            (receipt.tx_type == TX_TYPE_CREATE || receipt.tx_type == TX_TYPE_ACCEPT) &&
                (receipt.tx_step == TX_STEP_START || receipt.tx_step == TX_STEP_ADD),
            EInvalidSequence
        );

        let swap_mut = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(
            swap_mut.status == SWAP_STATUS_PENDING && (sender == swap_mut.counterparty || sender == swap_mut.initiator),
            EActionNotAllowed
        );

        let offer = {
            if (swap_mut.counterparty == sender) {
                option::borrow_mut(&mut swap_mut.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap_mut.initiator_offer)
            }
        };

        assert!(
            balance::value(&offer.escrowed_balance) == 0,
            ECoinAlreadyAddedToOffer
        ); // Coin can be added at most once
        receipt.tx_step = TX_STEP_ADD;

        coin::put(&mut offer.escrowed_balance, coins);

        // TODO: emit events later on
        receipt
    }

    public fun publish(
        swap_db: &mut SwapDB,
        swap_id: ID,
        clock: &Clock,
        valid_for: u64,
        receipt: Receipt,
        ctx: &mut TxContext
    ): Receipt {
        assert!((receipt.tx_type == TX_TYPE_CREATE && receipt.tx_step == TX_STEP_ADD), EInvalidSequence);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);

        let sender = tx_context::sender(ctx);
        let requests = &mut swap_db.requests;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);

        // Makes sure initiator offer and counterparty offer requested are not empty
        assert!(
            (!vec_set::is_empty(&swap_mut.nfts_to_receive) ||
                swap_mut.coins_to_receive > 0),
            EInvalidOffer
        );

        receipt.tx_step = TX_STEP_PUBLISH;
        swap_mut.expiry = clock::timestamp_ms(clock) + valid_for;

        // Add swap to open requests
        if (table::contains(requests, sender)) {
            let open_swaps = table::borrow_mut(requests, sender);
            vec_set::insert(open_swaps, swap_id);
        } else {
            table::add(requests, sender, vec_set::singleton(swap_id));
        };

        receipt
    }

    public fun remove_open_swap(
        swap_db: &mut SwapDB,
        swap_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ): Receipt {
        let registry = &mut swap_db.registry;
        let sender = tx_context::sender(ctx);
        let swap_mut: &mut SwapRequest = bag::borrow_mut(registry, swap_id);
        assert!(swap_mut.initiator == sender, ENotInitiator);
        assert!(swap_mut.status == SWAP_STATUS_PENDING, EActionNotAllowed);
        let current_timestamp = clock::timestamp_ms(clock);

        swap_mut.status = {
            if (current_timestamp > swap_mut.expiry) {
                SWAP_STATUS_EXPIRED
            } else {
                SWAP_STATUS_CANCELLED
            }
        };

        // Remove swap_id from requests
        let open_swaps = table::borrow_mut(&mut swap_db.requests, sender);
        vec_set::remove(open_swaps, &swap_id);


        Receipt {
            swap_id,
            tx_type: TX_TYPE_CANCEL,
            tx_step: TX_STEP_START,
            platform_fee_to_pay: 0
        }
    }

    public fun refund_platform_fee(
        swap_db: &mut SwapDB,
        swap_id: ID,
        receipt: Receipt,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(receipt.tx_type == TX_TYPE_CANCEL && receipt.tx_step == TX_STEP_CLAIM, 0);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);

        let Receipt { swap_id: _, tx_type: _, tx_step: _, platform_fee_to_pay: _ } = receipt;
        let swap_mut: &mut SwapRequest = bag::borrow_mut(&mut swap_db.registry, swap_id);
        // Refund initial swop fee paid
        let platform_fee_value = balance::value(&swap_mut.platform_fee_balance);
        coin::take(&mut swap_mut.platform_fee_balance, platform_fee_value, ctx)
    }

    public fun claim_nft<T: key+store>(
        swap_db: &mut SwapDB,
        swap_id: ID,
        item_key: u64,
        receipt: Receipt,
        ctx: &mut TxContext
    ): (T, address, Receipt) {
        assert!(
            (receipt.tx_type == TX_TYPE_CANCEL && receipt.tx_step == TX_STEP_START) ||
                (receipt.tx_type == TX_TYPE_ACCEPT && (receipt.tx_step == TX_STEP_START || receipt.tx_step == TX_STEP_CLAIM))
            , EInvalidSequence);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);

        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        let sender = tx_context::sender(ctx);
        assert!(
            sender == swap_mut.initiator ||
                (sender == swap_mut.counterparty && swap_mut.status == SWAP_STATUS_ACCEPTED),
            EActionNotAllowed
        );

        let offer = {
            if (swap_mut.status == SWAP_STATUS_ACCEPTED) {
                if (sender == swap_mut.counterparty) {
                    option::borrow_mut(&mut swap_mut.initiator_offer)
                }else {
                    option::borrow_mut(&mut swap_mut.counterparty_offer)
                }
            }else {
                option::borrow_mut(&mut swap_mut.initiator_offer)
            }
        };

        receipt.tx_step = TX_STEP_CLAIM;

        (bag::remove(&mut offer.escrowed_nfts, item_key), sender, receipt)
    }

    public fun claim_coins(
        swap_db: &mut SwapDB,
        swap_id: ID,
        receipt: Receipt,
        ctx: &mut TxContext
    ): (Coin<SUI>, address, Receipt) {
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(
            (receipt.tx_type == TX_TYPE_CANCEL && receipt.tx_step == TX_STEP_START) ||
                (receipt.tx_type == TX_TYPE_ACCEPT && (receipt.tx_step == TX_STEP_CLAIM || receipt.tx_step == TX_STEP_START))
            , EInvalidSequence);

        assert!(
            sender == swap_mut.initiator ||
                (sender == swap_mut.counterparty && swap_mut.status == SWAP_STATUS_ACCEPTED),
            EActionNotAllowed
        );

        let offer = {
            if (swap_mut.status == SWAP_STATUS_ACCEPTED) {
                if (sender == swap_mut.counterparty) {
                    option::borrow_mut(&mut swap_mut.initiator_offer)
                }else {
                    option::borrow_mut(&mut swap_mut.counterparty_offer)
                }
            }else {
                option::borrow_mut(&mut swap_mut.initiator_offer)
            }
        };

        let current_balance = balance::value(&offer.escrowed_balance);
        assert!(current_balance > 0, EInsufficientValue);
        receipt.tx_step = TX_STEP_CLAIM;

        (coin::take(&mut offer.escrowed_balance, current_balance, ctx), sender, receipt)
    }

    public fun accept_init(swap_db: &mut SwapDB, swap_id: ID, clock: &Clock): Receipt {
        let registry = &swap_db.registry;
        let swap = bag::borrow<ID, SwapRequest>(registry, swap_id);

        // Check if request is still valid
        assert!(clock::timestamp_ms(clock) < swap.expiry, ERequestExpired);
        assert!(swap.status == SWAP_STATUS_PENDING, EActionNotAllowed);
        Receipt {
            swap_id,
            tx_type: TX_TYPE_ACCEPT,
            tx_step: TX_STEP_START,
            platform_fee_to_pay: swap_db.platform_fee
        }
    }

    public fun accept(swap_db: &mut SwapDB, swap_id: ID, receipt: Receipt): Receipt {
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);

        // Check if coins and nfts supplied by counterparty matches swap terms
        let counterparty_offer = option::borrow_mut(&mut swap_mut.counterparty_offer);
        assert!(balance::value(&counterparty_offer.escrowed_balance) == swap_mut.coins_to_receive, EInsufficientValue);
        assert!(
            bag::length(&counterparty_offer.escrowed_nfts) == vec_set::size(&swap_mut.nfts_to_receive),
            ESuppliedLengthMismatch
        );

        swap_mut.status = SWAP_STATUS_ACCEPTED;
        receipt.tx_step = TX_STEP_ACCEPT;

        // Remove swap_id from requests
        let open_swaps = table::borrow_mut(&mut swap_db.requests, swap_mut.initiator);
        vec_set::remove(open_swaps, &swap_id);

        receipt
    }

    public fun take_swop_fee(coin: Coin<SUI>, swap_id: ID, swap_db: &mut SwapDB, receipt: Receipt) {
        assert!(coin::value(&coin) == receipt.platform_fee_to_pay, EInsufficientValue);
        assert!(receipt.tx_step == TX_STEP_PUBLISH || receipt.tx_step == TX_STEP_ACCEPT, EInvalidSequence);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);

        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);

        let Receipt { swap_id: _, tx_type: _, tx_step: _, platform_fee_to_pay: _ } = receipt;
        coin::put(&mut swap_mut.platform_fee_balance, coin);
    }


    #[test_only]
    public fun init_test(ctx: &mut TxContext) {
        let swap_db = SwapDB {
            id: object::new(ctx),
            registry: bag::new(ctx),
            requests: table::new<address, VecSet<ID>>(ctx),
            allowed_projects: object::new(ctx),
            allowed_coins: object::new(ctx),
            platform_fee: 0
        };

        transfer::share_object(swap_db);
    }

    #[test_only]
    public fun is_swap_in_requests(initiator: address, swap_id: ID, swap_db: &SwapDB): bool {
        let requests = &swap_db.requests;
        let open_swaps = table::borrow(requests, initiator);
        vec_set::contains(open_swaps, &swap_id)
    }

    #[test_only]
    public fun is_swap_accepted(swap_id: ID, swap_db: &SwapDB): bool {
        let registry = &swap_db.registry;
        let swap = bag::borrow<ID, SwapRequest>(registry, swap_id);
        swap.status == SWAP_STATUS_ACCEPTED
    }
}