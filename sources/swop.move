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

    const SWAP_STATUS_PENDING:u64 = 0;
    const SWAP_STATUS_ACCEPTED:u64 = 1;
    const SWAP_STATUS_REJECTED:u64 = 2;
    const SWAP_STATUS_CANCELLED:u64 = 3;
    const SWAP_STATUS_EXPIRED:u64 = 4;
    const SWAP_STATUS_INACTIVE:u64 = 5;


    const EInsufficientValue:u64 = 0;
    const EInvalidExpiry: u64 = 1;
    const EInvalidSwapId: u64 = 2;
    const ENotInitiator: u64 = 3;
    const ENotCounterparty: u64 = 4;
    const EActionNotAllowed: u64 = 5;
    const ESuppliedLengthMismatch: u64 = 6;
    const EUnexpectedObjectFound: u64 = 7;
    const ERequestExpired: u64 = 8;

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
    }

    struct Offer has store{
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

    public fun create(counterparty: address, nfts_to_receive: vector<ID>, coins_to_receive: u64, ctx: &mut TxContext) : SwapRequest{
        SwapRequest{
            id: object::new(ctx),
            initiator: tx_context::sender(ctx),
            counterparty,
            nfts_to_receive: vec_set::from_keys(nfts_to_receive),
            coins_to_receive,
            initiator_offer: option::none(),
            counterparty_offer: option::none(),
            status: SWAP_STATUS_INACTIVE,
            expiry: 0,
        }
    }

    public entry fun add_nft_to_offer<T: key+store>(swap: &mut SwapRequest, nft: T, ctx: &mut TxContext){
        assert!(swap.status == SWAP_STATUS_INACTIVE, EActionNotAllowed);
        let sender = tx_context::sender(ctx);
        assert!(sender == swap.initiator || sender == swap.counterparty, EActionNotAllowed);

        if(swap.counterparty == sender){
            // Check if nft in nfts_to_receive
            assert!(vec_set::contains(&swap.nfts_to_receive, &object::id(&nft)), EUnexpectedObjectFound);
        };

        let temp = {
            if (swap.counterparty == sender) {
                &mut swap.counterparty_offer
            } else {
                &mut swap.initiator_offer
            }
        };

        if(option::is_none(temp)){
            let offer = Offer { escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>()};
            option::fill(temp, offer);
        };

        let offer = option::borrow_mut(temp);
        bag::add(&mut offer.escrowed_nfts, bag::length(&offer.escrowed_nfts), nft);

        // TODO: emit events later on
    }

    public entry fun add_coins_to_offer(swap: &mut SwapRequest, coins: Coin<SUI>, ctx: &mut TxContext){
        // can consider refactoring
        assert!(swap.status == SWAP_STATUS_INACTIVE, EActionNotAllowed);
        let sender = tx_context::sender(ctx);
        assert!(sender == swap.initiator || sender == swap.counterparty, EActionNotAllowed);

        let temp = {
            if (swap.counterparty == sender) {
                &mut swap.counterparty_offer
            } else {
                &mut swap.initiator_offer
            }
        };

        if(option::is_none(temp)){
            let offer = Offer { escrowed_nfts: bag::new(ctx), escrowed_balance: balance::zero<SUI>()};
            option::fill(temp, offer);
        };

        let offer = option::borrow_mut(temp);
        coin::put(&mut offer.escrowed_balance, coins);
    }

    public fun publish(swap_db: &mut SwapDB, swap: SwapRequest , clock: &Clock, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let registry = &mut swap_db.registry;
        let requests = &mut swap_db.requests;
        let swap_id = object::id(&swap);
        swap.status = SWAP_STATUS_PENDING;
        swap.expiry = clock::timestamp_ms(clock) + 604800000; // 604800000 should be 7 days in ms
        bag::add(registry, swap_id, swap);

        if(table::contains(requests, sender)){
            let open_swaps = table::borrow_mut(requests, sender);
            vec_set::insert(open_swaps, swap_id);
        } else {
            table::add(requests, sender, vec_set::singleton(swap_id));
        }
    }

    public fun cancel(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext){
        let registry = &mut swap_db.registry;
        assert!(bag::contains(registry, swap_id), EInvalidSwapId);

        let sender = tx_context::sender(ctx);
        let swap_mut: &mut SwapRequest = bag::borrow_mut(registry, swap_id);
        assert!(swap_mut.initiator == sender, ENotInitiator);
        assert!(swap_mut.status == SWAP_STATUS_INACTIVE || swap_mut.status == SWAP_STATUS_PENDING, EActionNotAllowed);

        swap_mut.status = SWAP_STATUS_CANCELLED;
    }

    public fun claim<T: key+store>(swap_db: &mut SwapDB, swap_id: ID, item_idx: u8, ctx: &mut TxContext): T{
        // Case 1: Initiator decides to cancel a swap request
        // Initiator will be able to withdraw all funds + nfts associated with a swap_id from initiator_offer

        // Case 2: Counterparty decides to reject a swap request
        // Counterparty will be able to withdraw all funds + nfts associated with a swap_id from counterparty_offer

        // Case 3: Swap request has been accepted by Counterparty
        // Initiator will be able to withdraw from counterparty's offer
        // Counterparty will be able to withdraw from initiator's offer
    }

    public fun execute_swap(swap_id: ID, swap_db: &mut SwapDB){

    }

    fun validate_swap_conditions(){
        // If bag.length != nfts_to_receive, then counterparty has not provided the necessary nfts for swap
    }
}