module swop::swop {
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::balance::{Balance};
    use sui::sui::{SUI};
    use std::vector::{Self};
    use sui::bag::{Self, Bag};
    use sui::pay::{Self};
    use sui::vec_set::VecSet;
    use sui::vec_set;

    struct SwapDB has key, store{
        id: UID,
        requests: Bag,
        registry: Table<address, VecSet<ID>>
    }

    struct SwapRequest<T: key + store> has key, store{
        id: UID,
        initiator: address,
        counterparty: address,
        nfts_to_receive: VecSet<ID>,
        coins_to_receive: u64,
        escrowed_nft: vector<T>,
        escrowed_balance: Balance<SUI>,
        status:u64,
        expiry: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(SwapDB{
            id: object::new(ctx),
            requests: bag::new(ctx),
            registry: table::new<address, VecSet<ID>>(ctx)
        })
    }

    fun handle_coin_vector(coins: vector<Coin<SUI>>, value: u64, sender: address, ctx: &mut TxContext): Coin<SUI>{
        let coin = coin::zero(ctx);
        if(vector::is_empty(&coins)){
            vector::destroy_empty(coins);
            return coin
        };

        pay::join_vec(&mut coin, coins);
        let current_value = coin::value(&coin);
        assert!(current_value >= value, 0); // revert if insufficient value sent
        if (current_value > value) {
            pay::split_and_transfer(&mut coin, current_value - value, sender, ctx);
        };

        coin
    }

    public entry fun create<T: key + store>(
        swap_db: &mut SwapDB,
        counterparty: address,
        nfts_to_receive: vector<ID>, // used to be a vecset
        coins_to_receive:u64,
        escrowed_nft: vector<T>,
        escrowed_coins: vector<Coin<SUI>>,
        escrowed_value: u64,
        clock: &Clock,
        expiry: u64,
        ctx: &mut TxContext
    ){
        assert!(expiry > clock::timestamp_ms(clock), 0);

        let initiator = tx_context::sender(ctx);
        let temp = handle_coin_vector(escrowed_coins, escrowed_value, initiator, ctx);
        let balance = coin::into_balance(temp);


        let swap = SwapRequest{
            id: object::new(ctx),
            initiator,
            counterparty,
            nfts_to_receive: convert_to_set(&nfts_to_receive),
            coins_to_receive,
            escrowed_nft,
            escrowed_balance: balance,
            status: 0, // to change to status code later-- accepted, rejected, cancelled, pending,
            expiry
        };

        let swap_id = object::id(&swap);
        // // update requests
        bag::add(&mut swap_db.requests, swap_id, swap);
        // // update registry
        if(table::contains(&swap_db.registry, initiator)){
            let open_swaps = table::borrow_mut(&mut swap_db.registry, initiator);
            vec_set::insert(open_swaps, swap_id);
        } else {
            table::add(&mut swap_db.registry, initiator, vec_set::singleton(swap_id));
        }
    }

    public entry fun cancel<T: key + store>(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext){
        let requests = &mut swap_db.requests;
        assert!(bag::contains(requests, swap_id), 0); // invalid swap id
        let sender = tx_context::sender(ctx);
        let swap: &SwapRequest<T> = bag::borrow(requests, swap_id);
        assert!(swap.initiator == sender, 1); // reject if dude cancelling is not sender


        let SwapRequest{
            id,
            initiator: _,
            counterparty:_,
            nfts_to_receive:_,
            coins_to_receive:_,
            escrowed_nft,
            escrowed_balance,
            status:_,
            expiry:_,
        } = bag::remove(requests, swap_id);

        object::delete(id);
        while(!vector::is_empty(&escrowed_nft)){
            transfer::public_transfer(vector::pop_back<T>(&mut escrowed_nft), sender);
        };
        vector::destroy_empty(escrowed_nft);
        transfer::public_transfer(coin::from_balance(escrowed_balance, ctx), sender);

        // update registry
        let registry = &mut swap_db.registry;
        let open_swaps = table::borrow_mut(registry, sender);
        vec_set::remove(open_swaps, &swap_id);
        if(vec_set::is_empty(open_swaps)){
            table::remove(registry, sender);
        }
    }

    public entry fun reject<T: key + store>(swap_db: &mut SwapDB, swap_id: ID, ctx: &mut TxContext){
        let requests = &mut swap_db.requests;
        assert!(bag::contains(requests, swap_id), 0); // invalid swap id
        let sender = tx_context::sender(ctx);
        let swap_mut: &mut SwapRequest<T> = bag::borrow_mut(requests, swap_id);
        assert!(swap_mut.counterparty == sender, 1); // reject if dude cancelling is not counterparty
        swap_mut.status = 1;
    }

    public entry fun accept<T: key + store>(swap_db: &mut SwapDB, swap_id: ID, nfts_for_swap: vector<T>, coins_for_swap: vector<Coin<SUI>>, ctx: &mut TxContext){
        let requests = &mut swap_db.requests;
        assert!(bag::contains(requests, swap_id), 0); // invalid swap id

        let sender = tx_context::sender(ctx);
        let swap_mut: &mut SwapRequest<T> = bag::borrow_mut(requests, swap_id);
        let nfts_to_receive = &swap_mut.nfts_to_receive;
        assert!(swap_mut.counterparty == sender, 0); // make sure sender is the counterparty
        assert!(vec_set::size(nfts_to_receive) == vector::length(&nfts_for_swap), 1); // len must be equal
        let i = 0;
        while(i < vector::length(&nfts_for_swap)){
            let nft = vector::borrow(&nfts_for_swap, i);
            assert!(vec_set::contains(nfts_to_receive, &object::id(nft)), 0); // check for exact match
            i = i + 1;
        };

        let coin = handle_coin_vector(coins_for_swap, swap_mut.coins_to_receive, sender, ctx); // kinda weird if allow coins on both sides but thats what maple does

        transfer::public_transfer(coin::take(&mut swap_mut.escrowed_balance, swap_mut.coins_to_receive, ctx), swap_mut.initiator);
        while(!vector::is_empty(&swap_mut.escrowed_nft)){
            let nft = vector::pop_back(&mut swap_mut.escrowed_nft);
            transfer::public_transfer(nft, swap_mut.initiator);
        };

        // reuse escrowed nft and balance for subsequent claim
        coin::put(&mut swap_mut.escrowed_balance, coin);
        vector::append(&mut swap_mut.escrowed_nft, nfts_for_swap);

        swap_mut.status = 2 // update later to accepted status
    }

    public entry fun claim_rejected_swaps<T: key + store>(swap_db: &mut SwapDB, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let registry = &mut swap_db.registry;
        let requests = &mut swap_db.requests;
        assert!(table::contains(registry, sender), 0); // if not in registry -> no swap to claim
        let open_swaps = table::borrow_mut(registry, sender);
        let keys = vec_set::into_keys(*open_swaps);

        while(!vector::is_empty(&keys)){
            let key = vector::pop_back(&mut keys);
            let swap = bag::borrow<ID, SwapRequest<T>>(requests, key);
            if(swap.status == 2){
                // remember to change to status_rejected
                let SwapRequest{
                    id,
                    initiator: _,
                    counterparty:_,
                    nfts_to_receive:_,
                    coins_to_receive:_,
                    escrowed_nft,
                    escrowed_balance,
                    status:_,
                    expiry:_,
                } = bag::remove(requests, key);

                object::delete(id);
                while(!vector::is_empty(&escrowed_nft)){
                    transfer::public_transfer(vector::pop_back<T>(&mut escrowed_nft), sender);
                };
                vector::destroy_empty(escrowed_nft);
                transfer::public_transfer(coin::from_balance(escrowed_balance, ctx), sender);
                vec_set::remove(open_swaps, &key);
            }
        }
    }

    public entry fun claim_accepted_swaps<T: key + store>(swap_db: &mut SwapDB, ctx: &mut TxContext){

    }

    public fun convert_to_set<T: copy + drop>(items: &vector<T>): VecSet<T> {
        let i = 0;
        let set : VecSet<T> = vec_set::empty();
        while(i < vector::length(items)){
            vec_set::insert(&mut set, *vector::borrow(items, i));
            i = i + 1;
        };
        set
    }
}