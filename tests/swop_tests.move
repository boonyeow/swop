#[test_only]
module swop::swop_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, UID, ID, id_from_address};
    use swop::swop::{Self, SwapDB, SwapRequest};
    use swop::admin::{Self, AdminCap};
    // use sui::test_utils::{print as sprint};
    use sui::clock::{Self, Clock};
    // use sui::bag::{Self};
    use std::vector::{Self};
    use std::type_name::{Self};
    use sui::tx_context::{Self};
    // use std::string;
    // use std::ascii::string;
    // use std::debug::print;

    const ADMIN: address = @0x000A;
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

    struct BTC has drop {}

    struct InvalidCoinType has drop {}

    fun take_swop_db(scenario: &mut Scenario): SwapDB {
        ts::next_tx(scenario, ALICE);
        swop::init_test(ts::ctx(scenario));
        ts::next_tx(scenario, ALICE);
        ts::take_shared<SwapDB>(scenario)
    }

    fun take_admin_cap(scenario: &mut Scenario): AdminCap {
        ts::next_tx(scenario, ADMIN);
        admin::init_test(ts::ctx(scenario));
        ts::next_tx(scenario, ADMIN);
        ts::take_from_sender<AdminCap>(scenario)
    }

    fun take_coins<T: drop>(scenario: &mut Scenario, user: address, amount: u64): Coin<T> {
        ts::next_tx(scenario, user);
        let coins = ts::take_from_address<Coin<T>>(scenario, user);
        let split_coin = coin::split(&mut coins, amount, ts::ctx(scenario));
        ts::return_to_address(user, coins);
        split_coin
    }

    fun get_coins_balance<T: drop>(scenario: &mut Scenario, user: address): u64 {
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_sender<Coin<T>>(scenario);
        let combined_balance = 0;
        while (!vector::is_empty(&ids)) {
            let id = vector::pop_back(&mut ids);
            let coin = ts::take_from_address_by_id<Coin<T>>(scenario, user, id);
            combined_balance = combined_balance + coin::value(&coin);
            ts::return_to_address(user, coin);
        };
        combined_balance
    }

    fun is_object_in_inventory<T: key>(scenario: &mut Scenario, user: address, object_id: ID): bool {
        ts::next_tx(scenario, user);
        let ids = ts::ids_for_sender<T>(scenario);
        while (!vector::is_empty(&ids)) {
            let id = vector::pop_back(&mut ids);
            if (id == object_id) {
                return true
            }
        };
        false
    }

    fun add_nfts_to_offer_<T: key + store>(
        scenario: &mut Scenario,
        swap_db: &mut SwapDB,
        swap: &mut SwapRequest,
        user: address,
        obj_id: ID
    ) {
        ts::next_tx(scenario, user);
        let obj = ts::take_from_address_by_id<T>(scenario, user, obj_id);
        swop::add_nft_to_offer(swap_db, swap, obj, ts::ctx(scenario));
    }

    fun add_coin_to_offer_<CoinType: drop>(
        scenario: &mut Scenario,
        swap_db: &mut SwapDB,
        swap: &mut SwapRequest,
        user: address,
        amount: u64
    ) {
        ts::next_tx(scenario, user);
        let coins = take_coins<CoinType>(scenario, user, amount);
        swop::add_coins_to_offer(swap_db, swap, coins, ts::ctx(scenario));
    }

    // fun claim_nft_from_offer_(scenario: &mut Scenario, swap_db: &mut SwapDB, swap: &mut SwapRequest, user: address) {
    //     ts::next_tx(scenario, user);
    //     swop::claim_nft_from_offer(swap, item_key)
    // }

    fun mint_coins_to_user<CoinType>(scenario: &mut Scenario, amount_to_mint: u64, user: address) {
        ts::next_tx(scenario, user);
        transfer::public_transfer(
            coin::mint_for_testing<CoinType>(amount_to_mint, ts::ctx(scenario)), user
        );
    }

    fun init_test_env(scenario: &mut Scenario): (AdminCap, SwapDB, SwapRequest, Clock, ID, ID, ID, ID) {
        ts::next_tx(scenario, ALICE);
        mint_coins_to_user<SUI>(scenario, 100, ALICE);
        mint_coins_to_user<SUI>(scenario, 100, BOB);
        mint_coins_to_user<BTC>(scenario, 100, BOB);

        let alice_obj1 = ItemA { id: object::new(ts::ctx(scenario)) };
        let alice_obj2 = ItemA { id: object::new(ts::ctx(scenario)) };
        let bob_obj1 = ItemB { id: object::new(ts::ctx(scenario)) };
        let bob_obj2 = ItemB { id: object::new(ts::ctx(scenario)) };

        let alice_id1 = object::id(&alice_obj1);
        let alice_id2 = object::id(&alice_obj2);
        let bob_id1 = object::id(&bob_obj1);
        let bob_id2 = object::id(&bob_obj2);

        transfer::transfer(alice_obj1, ALICE);
        transfer::transfer(alice_obj2, ALICE);
        transfer::transfer(bob_obj1, BOB);
        transfer::transfer(bob_obj2, BOB);

        let (swap_db, admin_cap, clock) = {
            ts::next_tx(scenario, ALICE);
            let swap_db = take_swop_db(scenario);

            let admin_cap = take_admin_cap(scenario);
            admin::list_project<ItemA>(&admin_cap, &mut swap_db);
            admin::list_project<ItemB>(&admin_cap, &mut swap_db);

            let clock = clock::create_for_testing(ts::ctx(scenario));
            clock::share_for_testing(clock);

            ts::next_tx(scenario, ALICE);
            let clock = ts::take_shared<Clock>(scenario);
            (swap_db, admin_cap, clock)
        };

        let type_name = type_name::into_string(type_name::get<SUI>());
        let swap_id = swop::create_init(
            &mut swap_db,
            BOB,
            vector::singleton(id_from_address(@0x400)),
            0,
            type_name,
            ts::ctx(scenario)
        );

        ts::next_tx(scenario, ALICE);
        let swap = ts::take_shared_by_id<SwapRequest>(scenario, swap_id);

        (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2)
    }

    // Create swop request - [one item] for [multiple items]
    #[test]
    fun swap_single_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);

        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;

        // Initiator sets nft(s) to be received, nft(s) to be swapped
        ts::next_tx(scenario, ALICE);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nfts_to_offer_<ItemA>(
                scenario,
                swap_db_mut,
                swap_mut,
                sender,
                alice_id1
            );
        };

        ts::next_tx(scenario, ALICE);
        let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

        // Initiator pays platform fee
        ts::next_tx(scenario, ALICE);
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
        assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, 0);

        // Counterparty add(s) nft to swap
        ts::next_tx(scenario, BOB);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nfts_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nfts_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
        };
        // Counterparty accepts swap request
        ts::next_tx(scenario, BOB);
        let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

        swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
        assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), 0);

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut) == false, 0);
        assert!(swop::is_swap_accepted(swap_mut) == true, 1);

        // Initiator claim nft(s)
        ts::next_tx(scenario, ALICE);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            let obj = swop::claim_nft_from_offer<ItemB>(swap_mut, 0, ts::ctx(scenario));
            transfer::public_transfer(obj, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1) == true, 2);

            let obj = swop::claim_nft_from_offer<ItemB>(swap_mut, 1, ts::ctx(scenario));
            transfer::public_transfer(obj, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2) == true, 3);
        };

        // Counterparty claim nft
        ts::next_tx(scenario, BOB);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            let obj = swop::claim_nft_from_offer<ItemA>(swap_mut, 0, ts::ctx(scenario));
            transfer::public_transfer(obj, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1) == true, 4);
        };


        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(swap);
        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }
}


// #[test_only]
// module swop::swop_tests {
//     use sui::test_scenario::{Self as ts, Scenario};
//     use sui::transfer::{Self};
//     use sui::coin::{Self, Coin};
//     use sui::sui::{SUI};
//     use sui::object::{Self, UID, ID};
//     use swop::swop::{Self, SwapDB};
//     use sui::test_utils::{print as sprint};
//     use sui::clock::{Self, Clock};
//     // use sui::bag::{Self};
//     use std::vector::{Self};
//     // use std::debug::print;
//
//     const ALICE: address = @0xAAAA;
//     const BOB: address = @0xBBBB;
//     const MS_IN_A_DAY: u64 = 86400000;
//     const COINS_TO_MINT: u64 = 100;
//
//     // Example of an object type used for exchange
//     struct ItemA has key, store {
//         id: UID
//     }
//
//     // Example of the other object type used for exchange
//     struct ItemB has key, store {
//         id: UID
//     }
//
//     // Create swop request - [one item] for [multiple items]
//     #[test]
//     fun swap_single_for_multiple() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds nfts to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         // let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1) == true, 2);
//
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 3);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swap request - [multiple items] for [single item]
//     #[test]
//     fun swap_multiple_for_single() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
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
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
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
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [multiple items] for [multiple items]
//     #[test]
//     fun swap_multiple_for_multiple() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds nfts to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 3);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 5);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [one item] for [one item]
//     #[test]
//     fun swap_single_for_single() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nft to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds nfts to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [one item + coin] for [one item]
//     #[test]
//     fun swap_single_with_coin_for_single() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
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
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [one item + coin] for [multiple items]
//     #[test]
//     fun swap_single_with_coin_for_multiple() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nfts
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 5);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [one item + coin] for [one item + coin]
//     #[test]
//     fun swap_single_with_coin_for_single_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 15;
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::singleton(bob_id1),
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 6);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [one item + coin] for [multiple items + coin]
//     #[test]
//     fun swap_single_with_coin_for_multiple_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 15;
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 5);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 6);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [multiple item + coin] for [one item]
//     #[test]
//     fun swap_multiple_with_coin_for_single() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
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
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // Create swop request - [multiple item + coin] for [coin]
//     #[test]
//     fun swap_multiple_with_coin_for_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 25;
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::empty(),
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 2);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claims nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 3);
//
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         // Counterparty claims coin
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 5);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 6);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 7);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [multiple item + coin] for [multiple items]
//     #[test]
//     fun swap_multiple_with_coin_for_multiple() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 3);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 4);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 5);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 6);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 7);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [multiple item + coin] for [one item + coin]
//     #[test]
//     fun swap_multiple_with_coin_for_single_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 15;
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::singleton(bob_id1),
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 2);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 3);
//
//         // Initiator claims nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 4);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 5);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 6);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 7);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 8);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 9);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 10);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [multiple item + coin] for [multiple items + coin]
//     #[test]
//     fun swap_multiple_with_coin_for_multiple_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 15;
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds nfts to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id1);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         ts::next_tx(scenario, ALICE);
//         let obj = ts::take_from_address_by_id<ItemA>(scenario, ALICE, alice_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 2);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 3);
//
//         // Initiator claims nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 4);
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 5);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 6);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claim nft
//         ts::next_tx(scenario, BOB);
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 7);
//
//         let (obj, recipient) = swop::claim_nft<ItemA>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemA>(scenario, BOB, obj_id) == true, 8);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 9);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 10);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 11);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [coin] for [one item]
//     #[test]
//     fun swap_coin_for_single() {
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
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 4);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 5);
//
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [coin] for [multiple items]
//     #[test]
//     fun swap_coin_for_multiple() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             0,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claim nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//
//         // Make sure transferred to the right user
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 3);
//
//         // Counterparty claim coins
//         ts::next_tx(scenario, BOB);
//         sprint(b"hey claiming now");
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 0);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send), 4);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send), 5);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [coin] for [one item + coin]
//     #[test]
//     fun swap_coin_for_single_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 30;
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::singleton(bob_id1),
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claims nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 3);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claims coin
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 4);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [coin] for [multiple items + coin]
//     #[test]
//     fun swap_coin_for_multiple_with_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 30;
//         let nfts_to_receive = vector::singleton(bob_id1);
//         vector::push_back(&mut nfts_to_receive, bob_id2);
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             nfts_to_receive,
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
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
//         ts::next_tx(scenario, BOB);
//         let obj = ts::take_from_address_by_id<ItemB>(scenario, BOB, bob_id2);
//         swop::add_nft_to_offer(&mut swap_db, swap_id, obj, ts::ctx(scenario));
//
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 0);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 1);
//
//         // Initiator claims nft
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 0, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 2);
//
//         ts::next_tx(scenario, ALICE);
//         let (obj, recipient) = swop::claim_nft<ItemB>(&mut swap_db, swap_id, 1, ts::ctx(scenario));
//         let obj_id = object::id(&obj);
//         transfer::public_transfer(obj, recipient);
//         assert!(is_object_in_inventory<ItemB>(scenario, ALICE, obj_id) == true, 3);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 4);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claims coin
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 5);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 5);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 6);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     //     Create swop request - [coin] for [coin]
//     #[test]
//     fun swap_coin_for_coin() {
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//         let (swap_db, clock, _alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
//
//         // Initiator creates a swap request
//         ts::next_tx(scenario, ALICE);
//         let coins_to_receive = 15;
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::empty(),
//             coins_to_receive,
//             ts::ctx(scenario)
//         );
//
//         // Initiator adds coin to initiator_offer
//         ts::next_tx(scenario, ALICE);
//         let coins_to_send = 10;
//         let coin = take_coins<SUI>(scenario, ALICE, coins_to_send);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - coins_to_send, 0);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Initiator publishes swap request
//         ts::next_tx(scenario, ALICE);
//         swop::publish(&mut swap_db, swap_id, &clock, 1000000, ts::ctx(scenario));
//
//         // Counterparty adds coin to counterparty_offer
//         ts::next_tx(scenario, BOB);
//         let coin = take_coins<SUI>(scenario, BOB, coins_to_receive);
//         assert!(get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT - coins_to_receive, 1);
//         swop::add_coins_to_offer(&mut swap_db, swap_id, coin, ts::ctx(scenario));
//
//         // Counterparty accepts swap request
//         ts::next_tx(scenario, BOB);
//         swop::accept(&mut swap_db, swap_id, &clock);
//
//         // Make sure swap request is no longer in requests & its status equals accepted
//         assert!(swop::is_swap_in_requests(ALICE, swap_id, &swap_db) == false, 2);
//         assert!(swop::is_swap_accepted(swap_id, &swap_db) == true, 3);
//
//         // Initiator claims coin
//         ts::next_tx(scenario, ALICE);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_receive, 4);
//         transfer::public_transfer(coin, recipient);
//
//         // Counterparty claims coin
//         ts::next_tx(scenario, BOB);
//         let (coin, recipient) = swop::claim_coins(&mut swap_db, swap_id, ts::ctx(scenario));
//         assert!(coin::value(&coin) == coins_to_send, 5);
//         transfer::public_transfer(coin, recipient);
//
//         // Verify balances
//         assert!(get_coins_balance<SUI>(scenario, BOB) == (COINS_TO_MINT + coins_to_send - coins_to_receive), 6);
//         assert!(get_coins_balance<SUI>(scenario, ALICE) == (COINS_TO_MINT - coins_to_send + coins_to_receive), 7);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//     // To do:
//     // Cancel swop request
//     // Remaining test cases to trigger asserts
//     // Update swap status
// }