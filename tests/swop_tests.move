#[test_only]
module swop::swop_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, UID, ID};
    use swop::swop::{Self, SwapDB};
    // use std::debug::{print as print};
    // use sui::test_utils::{print as sprint};
    use sui::clock::{Self, Clock};
    // use sui::bag::{Self};
    use std::vector::{Self};
    // use std::debug::print;

    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const MS_IN_A_DAY: u64 = 86400000;
    const COINS_TO_MINT: u64 = 100;

    // Example of an object type used for exchange
    struct ItemA has key, store {
        id: UID
    }

    // Example of the other object type used for exchange
    struct ItemB has key, store {
        id: UID
    }

    fun take_swop_db(scenario: &mut Scenario): SwapDB {
        ts::next_tx(scenario, ALICE);
        swop::init_test(ts::ctx(scenario));
        ts::next_tx(scenario, ALICE);
        ts::take_shared<SwapDB>(scenario)
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user:address, amount: u64) : Coin<T>{
        ts::next_tx(scenario, user);
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin= coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun get_coins_balance<T: drop>(scenario: &mut Scenario, user: address): u64{
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_sender<Coin<T>>(scenario);
        let combined_balance = 0;

        while(!vector::is_empty(&ids)){
            let id = vector::pop_back(&mut ids);
            let coin = ts::take_from_address_by_id<Coin<T>>(scenario, user, id);
            combined_balance = combined_balance + coin::value(&coin);
            ts::return_to_address(user, coin);
        };
        combined_balance
    }

    fun init_test_env(scenario: &mut Scenario, ): (SwapDB, Clock, ID, ID, ID, ID) {
        ts::next_tx(scenario, ALICE);
        transfer::public_transfer(coin::mint_for_testing<SUI>(COINS_TO_MINT, ts::ctx(scenario)), ALICE);
        transfer::public_transfer(coin::mint_for_testing<SUI>(COINS_TO_MINT, ts::ctx(scenario)), BOB);

        let alice_obj1 = ItemA { id: object::new(ts::ctx(scenario)) };
        let alice_obj2 = ItemA { id: object::new(ts::ctx(scenario)) };
        let bob_obj1 = ItemB { id: object::new(ts::ctx(scenario)) };
        let bob_obj2 = ItemB { id: object::new(ts::ctx(scenario)) };

        let alice_id1= object::id(&alice_obj1);
        let alice_id2= object::id(&alice_obj2);
        let bob_id1= object::id(&bob_obj1);
        let bob_id2= object::id(&bob_obj2);

        transfer::transfer(alice_obj1, ALICE);
        transfer::transfer(alice_obj2, ALICE);
        transfer::transfer(bob_obj1, BOB);
        transfer::transfer(bob_obj2, BOB);

        ts::next_tx(scenario, ALICE);
        let swap_db = take_swop_db(scenario);
        {
            let clock = clock::create_for_testing(ts::ctx(scenario));
            clock::share_for_testing(clock);
        };

        ts::next_tx(scenario, ALICE);
        let clock = ts::take_shared<Clock>(scenario);
        (swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2)
    }


    // Create swop request - [one item] for [multiple items]
    #[test]
    fun swap_single_for_multiple(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (swap_db, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);

        // Initiator creates a swap request
        ts::next_tx(scenario, ALICE);
        let swap_id = swop::create(
            &mut swap_db,
            BOB,
            vector::singleton(bob_id1),
            0,
            ts::ctx(scenario)
        );

        // Initiator adds nfts to initiator_offer
        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Initiator publishes swap request
        ts::next_tx(scenario, ALICE);
        swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));

        // Counterparty adds nft to counterparty_offer
        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Counterparty accepts swap request
        ts::next_tx(scenario, BOB);
        swop::accept( &mut swap_db, swap_id, &clock);

        // Initiator claim nft
        ts::next_tx(scenario, ALICE);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Counterparty claim nft
        ts::next_tx(scenario, BOB);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Make sure swap request is no longer in requests
        assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);

        // Make sure swap request status equals accepted
        assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);

        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }

    // Create swop request - [multiple items] for [multiple items]
    #[test]
    fun swap_multiple_for_multiple(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);

        // Initiator creates a swap request
        ts::next_tx(scenario, ALICE);
        let nfts_to_receive = vector::singleton(bob_id1);
        vector::push_back(&mut nfts_to_receive, bob_id2);
        let swap_id = swop::create(
            &mut swap_db,
            BOB,
            nfts_to_receive,
            0,
            ts::ctx(scenario)
        );

        // Initiator adds nfts to initiator_offer
        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Initiator publishes swap request
        ts::next_tx(scenario, ALICE);
        swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));

        // Counterparty adds nfts to counterparty_offer
        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Counterparty accepts swap request
        ts::next_tx(scenario, BOB);
        swop::accept( &mut swap_db, swap_id, &clock);

        // Initiator claim nft
        ts::next_tx(scenario, ALICE);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Counterparty claim nft
        ts::next_tx(scenario, BOB);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Make sure swap request is no longer in requests
        assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);

        // Make sure swap request status equals accepted
        assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);

        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }

    // Create swop request - [multiple items] for [one item]
    #[test]
    fun swap_multiple_for_single(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);

        // Initiator creates a swap request
        ts::next_tx(scenario, ALICE);
        let nfts_to_receive = vector::singleton(bob_id1);
        vector::push_back(&mut nfts_to_receive, bob_id2);
        let swap_id = swop::create(
            &mut swap_db,
            BOB,
            nfts_to_receive,
            0,
            ts::ctx(scenario)
        );

        // Initiator adds nft to initiator_offer
        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Initiator publishes swap request
        ts::next_tx(scenario, ALICE);
        swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));

        // Counterparty adds nfts to counterparty_offer
        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Counterparty accepts swap request
        ts::next_tx(scenario, BOB);
        swop::accept( &mut swap_db, swap_id, &clock);

        // Initiator claim nft
        ts::next_tx(scenario, ALICE);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Counterparty claim nft
        ts::next_tx(scenario, BOB);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Make sure swap request is no longer in requests
        assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);

        // Make sure swap request status equals accepted
        assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);

        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }


    // Create swop request - [one item] for [one item]
    #[test]
    fun swap_single_for_single(){
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);

        // Initiator creates a swap request
        ts::next_tx(scenario, ALICE);
        let nfts_to_receive = vector::singleton(bob_id1);
        let swap_id = swop::create(
            &mut swap_db,
            BOB,
            nfts_to_receive,
            0,
            ts::ctx(scenario)
        );

        // Initiator adds nft to initiator_offer
        ts::next_tx(scenario, ALICE);
        let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Initiator publishes swap request
        ts::next_tx(scenario, ALICE);
        swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));

        // Counterparty adds nfts to counterparty_offer
        ts::next_tx(scenario, BOB);
        let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
        swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));

        // Counterparty accepts swap request
        ts::next_tx(scenario, BOB);
        swop::accept( &mut swap_db, swap_id, &clock);

        // Initiator claim nft
        ts::next_tx(scenario, ALICE);
        let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Counterparty claim nft
        ts::next_tx(scenario, BOB);
        let (obj, initiator) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
        transfer::public_transfer(obj, initiator);

        // Make sure swap request is no longer in requests
        assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);

        // Make sure swap request status equals accepted
        assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);

        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }
//
//     // Create swop request - [one item + coin] for [one item]
//     // Create swop request - [one item + coin] for [multiple items]
//     // Create swop request - [one item + coin] for [one item + coin]
//     // Create swop request - [one item + coin] for [multiple items + coin]
//     // Create swop request - [multiple item + coin] for [one item]
//     // Create swop request - [multiple item + coin] for [multiple items]
//     // Create swop request - [multiple item + coin] for [one item + coin]
//     // Create swop request - [multiple item + coin] for [multiple items + coin]

//     Create swop request - [coin] for [one item]
//     #[test]
//     fun swap_coin_for_single(){
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::singleton(bob_id1),
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coin_value = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coin_value);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds nft to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept( &mut swap_db, swap_id, &clock);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, initiator) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         transfer::public_transfer(obj, initiator);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coin_value, 0);
//         transfer::public_transfer(coin, recipient);
//         std::debug::print(&recipient);
//
//         ts::next_tx(scenario, BOB);
//         std::debug::print(&(COINS_TO_MINT+coin_value));
//         std::debug::print(&get_coins_balance<SUI>(scenario, BOB));
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coin_value), 0);
//
//
//     ts::return_shared(swap_db);
//     ts::return_shared(clock);
//     ts::end(scenario_val);
//     }



//     Create swop request - [coin] for [multiple items]
//     Create swop request - [coin] for [one item + coin]
//     Create swop request - [coin] for [multiple items + coin]
}




//
//     //     const EInsufficientValue:u64 = 0;
//     //     const EInvalidExpiry: u64 = 1;
//     //     const EInvalidSwapId: u64 = 2;
//     //     const ENotInitiator: u64 = 3;
//     //     const ENotCounterparty: u64 = 4;
//     //     const EActionNotAllowed: u64 = 5;
//     //     const ESuppliedLengthMismatch: u64 = 6;
//     //     const EUnexpectedObjectFound: u64 = 7;