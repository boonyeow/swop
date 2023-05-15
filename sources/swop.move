module swop::swop {
    use std::type_name::{Self};
    use std::vector::{Self};
    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use std::option::{Self, Option};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::dynamic_field::{Self as field};
    use swop::vec_set::{Self, VecSet};
    friend swop::admin;

    const SWAP_STATUS_PENDING_INITIATOR: u64 = 100;
    const SWAP_STATUS_PENDING_COUNTERPARTY: u64 = 101;
    const SWAP_STATUS_ACCEPTED: u64 = 102;
    const SWAP_STATUS_REJECTED: u64 = 103;
    const SWAP_STATUS_CANCELLED: u64 = 104;
    const SWAP_STATUS_EXPIRED: u64 = 105;

    const TX_TYPE_CREATE: u64 = 200;
    const TX_TYPE_ACCEPT: u64 = 201;
    const TX_TYPE_CANCEL: u64 = 202;

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

    public fun create_init(
        swap_db: &mut SwapDB,
        counterparty: address,
        nfts_to_receive: vector<ID>,
        coins_to_receive: u64,
        ctx: &mut TxContext
    ): ID {
        let initiator = tx_context::sender(ctx);
        let initiator_offer = option::some(
            Offer { owner: initiator, escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );
        let counterparty_offer = option::some(
            Offer { owner: counterparty, escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );

        assert!(initiator != counterparty, EActionNotAllowed);
        assert!((!vector::is_empty(&nfts_to_receive) || coins_to_receive > 0), EInvalidOffer);

        let swap = SwapRequest {
            id: object::new(ctx),
            initiator: tx_context::sender(ctx),
            counterparty,
            nfts_to_receive: vec_set::from_keys(nfts_to_receive),
            coins_to_receive,
            initiator_offer,
            counterparty_offer,
            status: SWAP_STATUS_PENDING_INITIATOR,
            expiry: 0,
            platform_fee_balance: balance::zero()
        };
        let swap_id = object::id(&swap);
        bag::add(&mut swap_db.registry, swap_id, swap);
        swap_id
    }

    public fun add_nft_to_offer<T: key+store>(swap_db: &mut SwapDB, swap_id: ID, nft: T, ctx: &mut TxContext) {
        let type_name = type_name::into_string(type_name::get<T>());
        assert!(field::exists_(&swap_db.allowed_projects, type_name), EProjectNotAllowed);

        let swap_mut = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(
            (swap_mut.status == SWAP_STATUS_PENDING_INITIATOR && sender == swap_mut.initiator) ||
                (swap_mut.status == SWAP_STATUS_PENDING_COUNTERPARTY && sender == swap_mut.counterparty),
            EActionNotAllowed
        );

        let offer = {
            if (swap_mut.counterparty == sender) {
                option::borrow_mut(&mut swap_mut.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap_mut.initiator_offer)
            }
        };

        let escrowed_nft_len = bag::length(&offer.escrowed_nfts);
        bag::add(&mut offer.escrowed_nfts, escrowed_nft_len, nft);

        // TODO: emit events later on
    }

    public fun add_coins_to_offer(swap_db: &mut SwapDB, swap_id: ID, coins: Coin<SUI>, ctx: &mut TxContext) {
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(
            (swap_mut.status == SWAP_STATUS_PENDING_INITIATOR && sender == swap_mut.initiator) ||
                (swap_mut.status == SWAP_STATUS_PENDING_COUNTERPARTY && sender == swap_mut.counterparty),
            EActionNotAllowed
        );

        let offer = {
            if (swap_mut.counterparty == sender) {
                option::borrow_mut(&mut swap_mut.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap_mut.initiator_offer)
            }
        };

        // Coin can be added at most once
        assert!(balance::value(&offer.escrowed_balance) == 0, ECoinAlreadyAddedToOffer);
        coin::put(&mut offer.escrowed_balance, coins);
        // TODO: emit events later on
    }

    fun is_offer_empty(offer: &Offer): bool {
        balance::value(&offer.escrowed_balance) == 0 && bag::is_empty(&offer.escrowed_nfts)
    }

    public fun create(
        swap_db: &mut SwapDB,
        swap_id: ID,
        clock: &Clock,
        valid_for: u64,
        ctx: &mut TxContext
    ): Receipt {
        let sender = tx_context::sender(ctx);
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);

        assert!(sender == swap_mut.initiator, EActionNotAllowed);
        // Makes sure initiator offer and counterparty offer requested are not empty
        assert!((is_offer_empty(option::borrow(&swap_mut.initiator_offer))), EInvalidOffer);

        swap_mut.expiry = clock::timestamp_ms(clock) + valid_for;
        swap_mut.status = SWAP_STATUS_PENDING_COUNTERPARTY;

        // Add swap to open requests
        let requests = &mut swap_db.requests;
        if (table::contains(requests, sender)) {
            let open_swaps = table::borrow_mut(requests, sender);
            vec_set::insert(open_swaps, swap_id);
        } else {
            table::add(requests, sender, vec_set::singleton(swap_id));
        };

        Receipt {
            swap_id,
            tx_type: TX_TYPE_CREATE,
            platform_fee_to_pay: swap_db.platform_fee
        }
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
        assert!(swap_mut.initiator == sender && swap_mut.status == SWAP_STATUS_PENDING_INITIATOR, EActionNotAllowed);

        swap_mut.status = {
            if (clock::timestamp_ms(clock) > swap_mut.expiry) {
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
            platform_fee_to_pay: 0
        }
    }

    public fun refund_platform_fee(
        swap_db: &mut SwapDB,
        swap_id: ID,
        receipt: Receipt,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(receipt.tx_type == TX_TYPE_CANCEL, 0);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);

        let Receipt { swap_id: _, tx_type: _, platform_fee_to_pay: _ } = receipt;
        let swap_mut: &mut SwapRequest = bag::borrow_mut(&mut swap_db.registry, swap_id);

        // Refund initial swop fee paid
        let platform_fee_value = balance::value(&swap_mut.platform_fee_balance);
        coin::take(&mut swap_mut.platform_fee_balance, platform_fee_value, ctx)
    }

    public fun claim_nft<T: key+store>(
        swap_db: &mut SwapDB,
        swap_id: ID,
        item_key: u64,
        ctx: &mut TxContext
    ): T {
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

        bag::remove(&mut offer.escrowed_nfts, item_key)
    }

    public fun claim_coins(
        swap_db: &mut SwapDB,
        swap_id: ID,
        ctx: &mut TxContext
    ): Coin<SUI> {
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

        let current_balance = balance::value(&offer.escrowed_balance);
        assert!(current_balance > 0, EInsufficientValue);

        coin::take(&mut offer.escrowed_balance, current_balance, ctx)
    }

    public fun accept(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext): Receipt {
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(sender == swap_mut.counterparty, EActionNotAllowed);

        // Check if coins and nfts supplied by counterparty matches swap terms
        let offer = option::borrow(&swap_mut.counterparty_offer);
        assert!(balance::value(&offer.escrowed_balance) == swap_mut.coins_to_receive, EInsufficientValue);
        assert!(bag::length(&offer.escrowed_nfts) == vec_set::size(&swap_mut.nfts_to_receive), ESuppliedLengthMismatch);

        swap_mut.status = SWAP_STATUS_ACCEPTED;

        // Remove swap_id from requests
        let open_swaps = table::borrow_mut(&mut swap_db.requests, swap_mut.initiator);
        vec_set::remove(open_swaps, &swap_id);

        Receipt {
            swap_id,
            tx_type: TX_TYPE_ACCEPT,
            platform_fee_to_pay: swap_db.platform_fee
        }
    }

    public fun take_swop_fee(coin: Coin<SUI>, swap_id: ID, swap_db: &mut SwapDB, receipt: Receipt) {
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);
        assert!(receipt.tx_type == TX_TYPE_CREATE || receipt.tx_type == TX_TYPE_ACCEPT, EInvalidSequence);
        assert!(coin::value(&coin) == receipt.platform_fee_to_pay, EInsufficientValue);

        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);

        let Receipt { swap_id: _, tx_type: _, platform_fee_to_pay: _ } = receipt;
        coin::put(&mut swap_mut.platform_fee_balance, coin);
    }


    // Getters
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