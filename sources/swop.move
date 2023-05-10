module swop::swop {

    use sui::bag::{Self, Bag};
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use std::option::{Self, Option};
    use std::vector::{Self};
    use swop::vec_set::{Self, VecSet};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};

    const SWAP_STATUS_PENDING:u64 = 0;
    const SWAP_STATUS_ACCEPTED:u64 = 1;
    const SWAP_STATUS_REJECTED:u64 = 2;
    const SWAP_STATUS_CANCELLED:u64 = 3;
    const SWAP_STATUS_EXPIRED:u64 = 4;
    const SWAP_STATUS_INACTIVE:u64 = 5;


    const EInsufficientValue:u64 = 0;
    const EInvalidExpiry: u64 = 1;
    const EInvalidSwapId: u64 = 2;
    const EInvalidOffer: u64 = 3;
    const ENotInitiator: u64 = 4;
    const ENotCounterparty: u64 = 5;
    const EActionNotAllowed: u64 = 6;
    const ESuppliedLengthMismatch: u64 = 7;
    const EUnexpectedObjectFound: u64 = 8;
    const ERequestExpired: u64 = 9;

    struct SwapDB has key, store{
        id: UID,
        registry: Bag,
        requests: Table<address,VecSet<ID>>
    }

    struct SwapRequest has key, store{
        id: UID,
        initiator: address,
        counterparty: address,
        nfts_to_receive: VecSet<ID>,
        coins_to_receive: u64,
        initiator_offer: Option<Offer>,
        counterparty_offer: Option<Offer>,
        status: u64,
        expiry: u64,
        platform_fee: Balance<SUI>
    }

    struct Offer has store{
        owner: address,
        escrowed_nfts: Bag,
        escrowed_balance: Balance<SUI>,
    }

    fun init(ctx: &mut TxContext){
        transfer::share_object(SwapDB{
            id: object::new(ctx),
            registry: bag::new(ctx),
            requests: table::new<address, VecSet<ID>>(ctx)
        })
    }

    #[test_only]
    public fun init_test(ctx: &mut TxContext){
        transfer::share_object(SwapDB{
            id: object::new(ctx),
            registry: bag::new(ctx),
            requests: table::new<address, VecSet<ID>>(ctx)
        })
    }

    #[test_only]
    public fun is_swap_in_requests(initiator: address, swap_id: ID, swap_db: &SwapDB) : bool{
        let requests = &swap_db.requests;
        let open_swaps = table::borrow(requests, initiator);
        vec_set::contains(open_swaps, &swap_id)
    }

    #[test_only]
    public fun is_swap_accepted(swap_id: ID, swap_db: &SwapDB) : bool{
        let registry = &swap_db.registry;
        let swap = bag::borrow<ID, SwapRequest>(registry, swap_id);
        swap.status == SWAP_STATUS_ACCEPTED
    }

    public fun create(swap_db: &mut SwapDB, counterparty: address, nfts_to_receive: vector<ID>, coins_to_receive: u64, ctx: &mut TxContext) : ID {
        let initiator_offer = option::some(
            Offer { owner: tx_context::sender(ctx), escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );
        let counterparty_offer = option::some(
            Offer { owner: counterparty, escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>() }
        );

        let swap = SwapRequest{
            id: object::new(ctx),
            initiator: tx_context::sender(ctx),
            counterparty,
            nfts_to_receive: vec_set::from_keys(nfts_to_receive),
            coins_to_receive,
            initiator_offer,
            counterparty_offer,
            status: SWAP_STATUS_INACTIVE,
            expiry: 0,
            platform_fee: balance::zero()
        };
        let swap_id = object::id(&swap);
        bag::add(&mut swap_db.registry, swap_id, swap);
        swap_id
    }

    public entry fun add_nft_to_offer<T: key+store>(swap_db: &mut SwapDB, swap_id: ID, nft: T, ctx: &mut TxContext){
        let swap = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        assert!(sender == swap.initiator || sender == swap.counterparty, EActionNotAllowed);

        if(sender == swap.counterparty){
            // Check if nft in nfts_to_receive
            assert!(vec_set::contains(&swap.nfts_to_receive, &object::id(&nft)), EUnexpectedObjectFound);

            // Check if status is pending
            // Counterparty can add nft to offer only if it is pending
            assert!(swap.status == SWAP_STATUS_PENDING, EActionNotAllowed);
        } else {

            // Check if status is inactive
            // Initiator can add nft to offer only if it is inactive
            assert!(swap.status == SWAP_STATUS_INACTIVE, EActionNotAllowed);
        };

        let offer = {
            if (swap.counterparty == sender) {
                option::borrow_mut(&mut swap.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        let escrowed_nft_len = bag::length(&offer.escrowed_nfts);
        bag::add(&mut offer.escrowed_nfts, escrowed_nft_len, nft);

        // TODO: emit events later on
    }

    public entry fun add_coins_to_offer(swap_db: &mut SwapDB, swap_id: ID, coins: Coin<SUI>, ctx: &mut TxContext){
        // can consider refactoring
        let swap = bag::borrow_mut<ID, SwapRequest>(&mut swap_db.registry, swap_id);
        let sender = tx_context::sender(ctx);

        if(sender == swap.counterparty){
            // Check if status is pending
            // Counterparty can add nft to offer only if it is pending
            assert!(swap.status == SWAP_STATUS_PENDING, EActionNotAllowed);
        } else {
            // Check if status is inactive
            // Initiator can add nft to offer only if it is inactive
            assert!(swap.status == SWAP_STATUS_INACTIVE, EActionNotAllowed);
        };

        assert!((swap.status == SWAP_STATUS_INACTIVE) && (sender == swap.initiator || sender == swap.counterparty), EActionNotAllowed);

        let offer = {
            if (swap.counterparty == sender) {
                option::borrow_mut(&mut swap.counterparty_offer)
            } else {
                option::borrow_mut(&mut swap.initiator_offer)
            }
        };

        coin::put(&mut offer.escrowed_balance, coins);

        // TODO: emit events later on
    }


    fun is_offer_empty(offer: &Offer) : bool{
        balance::value(&offer.escrowed_balance) == 0 &&
        bag::is_empty(&offer.escrowed_nfts)
    }

    public fun publish(swap_db: &mut SwapDB, swap_id: ID, clock: &Clock, valid_for:u64, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let registry = &mut swap_db.registry;
        let requests = &mut swap_db.requests;

        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);

        // Makes sure initiator offer and counterparty offer requested are not empty
        assert!(
            !is_offer_empty(option::borrow(&swap_mut.initiator_offer)) &&
            (!vec_set::is_empty(&swap_mut.nfts_to_receive) || swap_mut.coins_to_receive > 0),
            EInvalidOffer
        );

        swap_mut.status = SWAP_STATUS_PENDING;
        swap_mut.expiry = clock::timestamp_ms(clock) + valid_for;

        // Add swap to open requests
        if(table::contains(requests, sender)){
            let open_swaps = table::borrow_mut(requests, sender);
            vec_set::insert(open_swaps, swap_id);
        } else {
            table::add(requests, sender, vec_set::singleton(swap_id));
        }
    }

    public fun cancel(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext) : Coin<SUI>{
        let registry = &mut swap_db.registry;
        let sender = tx_context::sender(ctx);
        let swap_mut: &mut SwapRequest = bag::borrow_mut(registry, swap_id);
        assert!(swap_mut.initiator == sender, ENotInitiator);
        assert!(swap_mut.status == SWAP_STATUS_INACTIVE || swap_mut.status == SWAP_STATUS_PENDING, EActionNotAllowed);

        swap_mut.status = SWAP_STATUS_CANCELLED;

        // Remove swap_id from requests
        let open_swaps = table::borrow_mut(&mut swap_db.requests, sender);
        vec_set::remove(open_swaps, &swap_id);

        // Refund initial swop fee paid
        let platform_fee_value =  balance::value(&swap_mut.platform_fee);
        coin::take(&mut swap_mut.platform_fee, platform_fee_value, ctx)
    }

    public fun claim_nft<T: key+store>(swap_db: &mut SwapDB, swap_id: ID, item_key: u64, ctx: &mut TxContext): (T, address) {
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        let sender = tx_context::sender(ctx);
        assert!((swap_mut.status == SWAP_STATUS_ACCEPTED || swap_mut.status == SWAP_STATUS_CANCELLED || swap_mut.status == SWAP_STATUS_REJECTED || swap_mut.status == SWAP_STATUS_EXPIRED) &&
                (sender == swap_mut.counterparty || sender == swap_mut.initiator), EActionNotAllowed);

        let (offer, recipient) = {
            if(swap_mut.status == SWAP_STATUS_ACCEPTED) {
                if(sender == swap_mut.counterparty){
                    (option::borrow_mut(&mut swap_mut.initiator_offer), swap_mut.initiator)
                } else {
                    (option::borrow_mut(&mut swap_mut.counterparty_offer), swap_mut.counterparty)
                }
            } else {
                if(sender == swap_mut.counterparty){
                    (option::borrow_mut(&mut swap_mut.counterparty_offer), swap_mut.counterparty)
                } else {
                    (option::borrow_mut(&mut swap_mut.initiator_offer), swap_mut.initiator)
                }
            }
        };

        (bag::remove(&mut offer.escrowed_nfts, item_key), recipient)
    }

    public fun claim_coins(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext) : (Coin<SUI>, address){
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        let sender = tx_context::sender(ctx);
        assert!((swap_mut.status == SWAP_STATUS_ACCEPTED || swap_mut.status == SWAP_STATUS_CANCELLED || swap_mut.status == SWAP_STATUS_REJECTED || swap_mut.status == SWAP_STATUS_EXPIRED) &&
            (sender == swap_mut.counterparty || sender == swap_mut.initiator), EActionNotAllowed);
        let (offer, recipient) = {
            if(swap_mut.status == SWAP_STATUS_ACCEPTED) {
                if(sender == swap_mut.counterparty){
                    (option::borrow_mut(&mut swap_mut.initiator_offer), swap_mut.initiator)
                } else {
                    (option::borrow_mut(&mut swap_mut.counterparty_offer), swap_mut.counterparty)
                }
            } else {
                if(sender == swap_mut.counterparty){
                    (option::borrow_mut(&mut swap_mut.counterparty_offer), swap_mut.counterparty)
                } else {
                    (option::borrow_mut(&mut swap_mut.initiator_offer), swap_mut.initiator)
                }
            }
        };

        let current_balance = balance::value(&offer.escrowed_balance);
        assert!(current_balance > 0, EInsufficientValue);

        (coin::take(&mut offer.escrowed_balance, current_balance, ctx), recipient)
    }

    public fun accept(swap_db: &mut SwapDB, swap_id: ID, clock: &Clock){
        let registry = &mut swap_db.registry;
        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);

        // Check if request is still valid

        assert!(clock::timestamp_ms(clock) < swap_mut.expiry, ERequestExpired);
        assert!(swap_mut.status == SWAP_STATUS_PENDING, EActionNotAllowed);

        // Check if coins and nfts supplied by counterparty matches swap terms
        let counterparty_offer = option::borrow_mut(&mut swap_mut.counterparty_offer);
        assert!(balance::value(&counterparty_offer.escrowed_balance) == swap_mut.coins_to_receive, EInsufficientValue);
        assert!(bag::length(&counterparty_offer.escrowed_nfts) == vec_set::size(&swap_mut.nfts_to_receive), ESuppliedLengthMismatch);

        swap_mut.status = SWAP_STATUS_ACCEPTED;

        // Remove swap_id from requests
        let open_swaps = table::borrow_mut(&mut swap_db.requests, swap_mut.initiator);
        vec_set::remove(open_swaps, &swap_id);
    }

    public fun take_swop_fee(coin: Coin<SUI>, swap_id: ID, swap_db: &mut SwapDB){
        assert!(coin::value(&coin) == 10000000000, EInsufficientValue);
        let registry = &mut swap_db.registry;

        let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
        coin::put(&mut swap_mut.platform_fee, coin);
    }

    public fun update_swap_status(swap_db: &mut SwapDB, swap_ids: vector<ID>, clock: &Clock, ctx: &mut TxContext): Coin<SUI>{
        let registry = &mut swap_db.registry;
        let requests = &mut swap_db.requests;
        let current_timestamp = clock::timestamp_ms(clock);
        let temp = coin::zero(ctx);
        while(!vector::is_empty(&swap_ids)){
            let swap_id = vector::pop_back(&mut swap_ids);
            let swap_mut = bag::borrow_mut<ID, SwapRequest>(registry, swap_id);
            if(current_timestamp > swap_mut.expiry){
                // Update status and remove swap_id from open_swaps
                swap_mut.status = SWAP_STATUS_EXPIRED;
                let open_swaps = table::borrow_mut(requests,swap_mut.initiator);
                vec_set::remove(open_swaps, &swap_id);

                // Refund initial swop fee paid
                let platform_fee_value =  balance::value(&swap_mut.platform_fee);
                coin::join(&mut temp, coin::take(&mut swap_mut.platform_fee, platform_fee_value, ctx))
            }
        };
        temp
    }
}