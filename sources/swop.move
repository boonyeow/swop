module swop::swop {
    use std::type_name::{Self};
    use std::vector::{Self};
    use std::ascii::{String};
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

    const SWAP_INITIATOR: u8 = 0;
    const SWAP_COUNTERPARTY: u8 = 1;

    struct SwapDB has key, store {
        id: UID,
        registry: Table<address, UID>,
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
        coin_type_to_receive: String,
        initiator_offer: Option<Offer>,
        counterparty_offer: Option<Offer>,
        status: u64,
        expiry: u64,
        platform_fee_balance: Balance<SUI>
    }

    struct Offer has store {
        owner: address,
        escrowed_nfts: Bag,
        escrowed_balance_wrapper: UID,
    }

    struct Receipt {
        swap_id: ID,
        tx_type: u64,
        platform_fee_to_pay: u64,
    }

    fun init(ctx: &mut TxContext) {
        let swap_db = SwapDB {
            id: object::new(ctx),
            registry: table::new<address, UID>(ctx),
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
        coin_type_to_receive: String,
        ctx: &mut TxContext
    ): ID {
        assert!((!vector::is_empty(&nfts_to_receive) || coins_to_receive > 0), EInvalidOffer);
        assert!(field::exists_(&swap_db.allowed_coins, coin_type_to_receive), ECoinNotAllowed);

        let sender = tx_context::sender(ctx);
        assert!(sender != counterparty, EActionNotAllowed);

        let initiator_offer = option::some(
            Offer { owner: sender, escrowed_nfts: bag::new(ctx), escrowed_balance_wrapper: object::new(ctx) }
        );
        let counterparty_offer = option::some(
            Offer { owner: counterparty, escrowed_nfts: bag::new(ctx), escrowed_balance_wrapper: object::new(ctx) }
        );

        let swap = SwapRequest {
            id: object::new(ctx),
            initiator: sender,
            counterparty,
            nfts_to_receive: vec_set::from_keys(nfts_to_receive),
            coins_to_receive,
            coin_type_to_receive,
            initiator_offer,
            counterparty_offer,
            status: SWAP_STATUS_PENDING_INITIATOR,
            expiry: 0,
            platform_fee_balance: balance::zero()
        };
        let swap_id = object::id(&swap);
        transfer::share_object(swap);

        let registry = &mut swap_db.registry;
        add_swap_id_to_registry(registry, swap_id, sender, SWAP_INITIATOR, ctx);
        add_swap_id_to_registry(registry, swap_id, counterparty, SWAP_COUNTERPARTY, ctx);
        swap_id
    }

    entry fun add_swap_id_to_registry(
        registry: &mut Table<address, UID>,
        swap_id: ID,
        user: address,
        user_type: u8,
        ctx: &mut TxContext
    ) {
        if (!table::contains(registry, user)) {
            table::add(registry, user, object::new(ctx));
        };
        field::add(table::borrow_mut(registry, user), swap_id, user_type);
    }

    public fun add_nft_to_offer<T: key+store>(swap_db: &SwapDB, swap: &mut SwapRequest, nft: T, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(
            (swap.status == SWAP_STATUS_PENDING_INITIATOR && sender == swap.initiator) ||
                (swap.status == SWAP_STATUS_PENDING_COUNTERPARTY && sender == swap.counterparty),
            EActionNotAllowed
        );

        let type_name = type_name::into_string(type_name::get<T>());
        assert!(field::exists_(&swap_db.allowed_projects, type_name), EProjectNotAllowed);

        let offer = {
            if (sender == swap.counterparty) {
                assert!(vec_set::contains(&swap.nfts_to_receive, object::borrow_id(&nft)), 0);
                option::borrow_mut(&mut swap.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        let escrowed_nft_len = bag::length(&offer.escrowed_nfts);
        bag::add(&mut offer.escrowed_nfts, escrowed_nft_len, nft);
    }

    public fun add_coins_to_offer<CoinType>(
        swap_db: &SwapDB,
        swap: &mut SwapRequest,
        coins: Coin<CoinType>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(
            (swap.status == SWAP_STATUS_PENDING_INITIATOR && sender == swap.initiator) ||
                (swap.status == SWAP_STATUS_PENDING_COUNTERPARTY && sender == swap.counterparty),
            EActionNotAllowed
        );

        let type_name = type_name::into_string(type_name::get<CoinType>());

        let offer = {
            if (sender == swap.counterparty) {
                assert!(swap.coins_to_receive == coin::value(&coins), EInsufficientValue);
                assert!(type_name == swap.coin_type_to_receive, ECoinNotAllowed); // need to change it to cmp_u8_vector
                option::borrow_mut(&mut swap.counterparty_offer)
            } else {
                assert!(field::exists_(&swap_db.allowed_coins, type_name), ECoinNotAllowed);
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        let escrowed_balance: &mut Balance<CoinType> = field::borrow_mut(
            &mut offer.escrowed_balance_wrapper,
            type_name
        );
        assert!(balance::value(escrowed_balance) == 0, ECoinAlreadyAddedToOffer);
        coin::put(escrowed_balance, coins);
        // TODO: emit events later on
    }

    fun is_offer_empty<CoinType>(offer: &Offer): bool {
        let type_name = type_name::into_string(type_name::get<CoinType>());
        let escrowed_balance: &Balance<CoinType> = field::borrow(&offer.escrowed_balance_wrapper, type_name);
        balance::value(escrowed_balance) == 0 && bag::is_empty(&offer.escrowed_nfts)
    }

    public fun create<CoinType>(
        swap_db: &mut SwapDB,
        swap: &mut SwapRequest,
        clock: &Clock,
        valid_for: u64,
        ctx: &mut TxContext
    ): Receipt {
        let sender = tx_context::sender(ctx);

        assert!(sender == swap.initiator, EActionNotAllowed);
        // Makes sure initiator offer and counterparty offer requested are not empty
        assert!((is_offer_empty<CoinType>(option::borrow(&swap.initiator_offer))), EInvalidOffer);

        swap.expiry = clock::timestamp_ms(clock) + valid_for;
        swap.status = SWAP_STATUS_PENDING_COUNTERPARTY;

        // Add swap to open requests
        let requests = &mut swap_db.requests;
        let swap_id = object::id(swap);
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
        swap: &mut SwapRequest,
        clock: &Clock,
        ctx: &mut TxContext
    ): Receipt {
        let sender = tx_context::sender(ctx);
        assert!(swap.initiator == sender && swap.status == SWAP_STATUS_PENDING_INITIATOR, EActionNotAllowed);

        swap.status = {
            if (clock::timestamp_ms(clock) > swap.expiry) {
                SWAP_STATUS_EXPIRED
            } else {
                SWAP_STATUS_CANCELLED
            }
        };

        // Remove swap_id from requests
        let swap_id = object::id(swap);
        let open_swaps = table::borrow_mut(&mut swap_db.requests, sender);
        vec_set::remove(open_swaps, &swap_id);

        Receipt {
            swap_id,
            tx_type: TX_TYPE_CANCEL,
            platform_fee_to_pay: 0
        }
    }

    public fun refund_platform_fee(swap: &mut SwapRequest, receipt: Receipt, ctx: &mut TxContext): Coin<SUI> {
        let swap_id = object::id(swap);
        let sender = tx_context::sender(ctx);

        assert!(receipt.tx_type == TX_TYPE_CANCEL, 0);
        assert!(swap_id == receipt.swap_id, EInvalidSwapId);
        assert!(sender == swap.initiator, EActionNotAllowed);

        let Receipt { swap_id: _, tx_type: _, platform_fee_to_pay: _ } = receipt;
        let platform_fee_value = balance::value(&swap.platform_fee_balance);
        coin::take(&mut swap.platform_fee_balance, platform_fee_value, ctx)
    }

    public fun claim_nft<T: key+store>(swap: &mut SwapRequest, item_key: u64, ctx: &mut TxContext): T {
        let sender = tx_context::sender(ctx);

        assert!(
            sender == swap.initiator || (sender == swap.counterparty && swap.status == SWAP_STATUS_ACCEPTED),
            EActionNotAllowed
        );

        let offer = {
            if (swap.status == SWAP_STATUS_ACCEPTED) {
                if (sender == swap.counterparty) {
                    option::borrow_mut(&mut swap.initiator_offer)
                }else {
                    option::borrow_mut(&mut swap.counterparty_offer)
                }
            }else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        bag::remove(&mut offer.escrowed_nfts, item_key)
    }

    public fun claim_coins<CoinType>(swap: &mut SwapRequest, ctx: &mut TxContext): Coin<CoinType> {
        let sender = tx_context::sender(ctx);
        assert!(
            sender == swap.initiator ||
                (sender == swap.counterparty && swap.status == SWAP_STATUS_ACCEPTED),
            EActionNotAllowed
        );

        let offer = {
            if (swap.status == SWAP_STATUS_ACCEPTED) {
                if (sender == swap.counterparty) {
                    option::borrow_mut(&mut swap.initiator_offer)
                }else {
                    option::borrow_mut(&mut swap.counterparty_offer)
                }
            }else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        let type_name = type_name::into_string(type_name::get<CoinType>());
        let escrowed_balance_wrapper: &mut Balance<CoinType> = field::borrow_mut(
            &mut offer.escrowed_balance_wrapper,
            type_name
        );
        let current_balance = balance::value(escrowed_balance_wrapper);
        assert!(current_balance > 0, EInsufficientValue);
        coin::take(escrowed_balance_wrapper, current_balance, ctx)
    }

    public fun accept<CoinType>(
        swap_db: &mut SwapDB,
        swap: &mut SwapRequest,
        clock: &Clock,
        ctx: &mut TxContext
    ): Receipt {
        let sender = tx_context::sender(ctx);
        assert!(clock::timestamp_ms(clock) > swap.expiry, ERequestExpired);
        assert!((sender == swap.counterparty && swap.status == SWAP_STATUS_PENDING_COUNTERPARTY), EActionNotAllowed);
        // Check if coins and nfts supplied by counterparty matches swap terms
        let offer = option::borrow(&swap.counterparty_offer);

        let type_name = type_name::into_string(type_name::get<CoinType>());
        let escrowed_balance: &Balance<CoinType> = field::borrow(&offer.escrowed_balance_wrapper, type_name);
        assert!(balance::value(escrowed_balance) == swap.coins_to_receive, EInsufficientValue);
        assert!(bag::length(&offer.escrowed_nfts) == vec_set::size(&swap.nfts_to_receive), ESuppliedLengthMismatch);

        swap.status = SWAP_STATUS_ACCEPTED;

        // Remove swap_id from requests
        let swap_id = object::id(swap);
        let open_swaps = table::borrow_mut(&mut swap_db.requests, swap.initiator);
        vec_set::remove(open_swaps, &swap_id);

        Receipt {
            swap_id,
            tx_type: TX_TYPE_ACCEPT,
            platform_fee_to_pay: swap_db.platform_fee
        }
    }

    public fun take_swop_fee(coin: Coin<SUI>, swap: &mut SwapRequest, receipt: Receipt) {
        assert!(object::id(swap) == receipt.swap_id, EInvalidSwapId);
        assert!(receipt.tx_type == TX_TYPE_CREATE || receipt.tx_type == TX_TYPE_ACCEPT, EInvalidSequence);
        assert!(coin::value(&coin) == receipt.platform_fee_to_pay, EInsufficientValue);

        let Receipt { swap_id: _, tx_type: _, platform_fee_to_pay: _ } = receipt;
        coin::put(&mut swap.platform_fee_balance, coin);
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

    public(friend) fun borrow_mut_registry(swap_db: &mut SwapDB): &mut Table<address, UID> {
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
            registry: table::new<address, UID>(ctx),
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
    public fun is_swap_accepted(swap: &SwapRequest): bool {
        swap.status == SWAP_STATUS_ACCEPTED
    }
}