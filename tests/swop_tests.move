// #[test_only]
// module swop::swop_tests{
//     use sui::test_scenario::{Self as ts, Scenario};
//     use sui::transfer::{Self};
//     use sui::coin::{Self};
//     use sui::sui::{SUI};
//     use sui::object::{Self, UID};
//     use swop::swop::{Self, SwapDB, SwapRequest};
//     use std::debug::{print as print};
//     use sui::test_utils::{print as sprint};
//     use sui::clock::{Self, Clock};
//     use sui::bag::{Self};
//     use std::vector::{Self};
//
//
//     const ALICE:address = @0xAAAA;
//     const BOB:address = @0xBBBB;
//     const MS_IN_A_DAY:u64 = 86400000;
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
//     fun take_swop_db(scenario: &mut Scenario): SwapDB{
//         ts::next_tx(scenario, ALICE);
//         swop::init_test(ts::ctx(scenario));
//         ts::next_tx(scenario, ALICE);
//         ts::take_shared<SwapDB>(scenario)
//     }
//
//     fun init_test_env(scenario: &mut Scenario, coins_to_mint: u64) : (SwapDB, Clock){
//         ts::next_tx(scenario, ALICE);
//         transfer::public_transfer(coin::mint_for_testing<SUI>(coins_to_mint, ts::ctx(scenario)), ALICE);
//         transfer::public_transfer(coin::mint_for_testing<SUI>(coins_to_mint, ts::ctx(scenario)), BOB);
//
//         transfer::transfer(ItemA{ id: object::new(ts::ctx(scenario))}, ALICE);
//         transfer::transfer(ItemA{ id: object::new(ts::ctx(scenario))}, ALICE);
//         transfer::transfer(ItemB{ id: object::new(ts::ctx(scenario))}, BOB);
//         transfer::transfer(ItemB{ id: object::new(ts::ctx(scenario))}, BOB);
//
//         ts::next_tx(scenario, ALICE);
//         let swap_db = take_swop_db(scenario);
//         {
//             let clock = clock::create_for_testing(ts::ctx(scenario));
//             clock::share_for_testing(clock);
//         };
//
//         ts::next_tx(scenario, ALICE);
//         let clock = ts::take_shared<Clock>(scenario);
//         (swap_db, clock)
//     }
//
//     #[test]
//     fun swap_items_only(){
//         let scenario_val = ts::begin(ALICE);
//         let scenario = &mut scenario_val;
//
//         let (swap_db, clock) = init_test_env(scenario, 100);
//
//         // Create swap request
//         ts::next_tx(scenario, ALICE);
//         sprint(b"creating swap request");
//         let alice_item_ids = ts::ids_for_address<ItemA>(ALICE);
//         print(&alice_item_ids);
//         sprint(b"first id to be alice's offer");
//         print(vector::borrow(&alice_item_ids, 0));
//
//         let bob_item_ids = ts::ids_for_address<ItemB>(BOB);
//
//         let swap_id = swop::create(
//             &mut swap_db,
//             BOB,
//             vector::singleton(*vector::borrow(&bob_item_ids, 0)),
//             0,
//             vector::singleton(ts::take_from_address_by_id<ItemA>(scenario, ALICE, *vector::borrow(&alice_item_ids, 0))),
//             vector::empty(),
//             0,
//             &clock,
//             clock::timestamp_ms(&clock) + MS_IN_A_DAY,
//             ts::ctx(scenario)
//         );
//
//         sprint(b"swap request created");
//         print(&swap_db);
//
//
//         // Accept swap request
//         ts::next_tx(scenario, BOB);
//         sprint(b"accepting swap request");
//         let bob_item_ids = ts::ids_for_address<ItemB>(BOB);
//         print(&bob_item_ids);
//         let requests = swop::get_requests(&swap_db);
//         assert!(bag::contains(requests, swap_id) == true, 0);
//
//         let swap: &SwapRequest<ItemA> = bag::borrow(requests, swap_id);
//         print(swap);
//
//         ts::return_shared(swap_db);
//         ts::return_shared(clock);
//         ts::end(scenario_val);
//     }
//
//
//     // Create swop request - [one item] for [one item]
//     // Create swop request - [one item] for [multiple items]
//     // Create swop request - [multiple items] for [one item]
//     // Create swop request - [multiple items] for [multiple items]
//     // #[test]
//     // fun swap_items_only(){
//     //     let scenario_val = ts::begin(ALICE);
//     //     let scenario = &mut scenario_val;
//     //     // std::debug::print(&swap_db);
//     //     let (swap_db, clock) = init_test_env(scenario, 100);
//     //     let a_ids = ts::ids_for_address<ItemA>(ALICE);
//     //     // std::debug::print(&a_ids);
//     //     let b_ids = ts::ids_for_address<ItemB>(BOB);
//     //     // std::debug::print(&a_ids);
//     //
//     //
//     //     sprint(b"before swap");
//     //     {
//     //         print(&ts::ids_for_address<ItemA>(ALICE));
//     //         print(&ts::ids_for_address<ItemA>(BOB));
//     //     };
//     //     // Create a swop request
//     //     ts::next_tx(scenario, ALICE);
//     //     let a_id = *vector::borrow(&a_ids, 0);
//     //     let b_id = *vector::borrow(&b_ids, 0);
//     //     swop::create(
//     //         &mut swap_db,
//     //         BOB,
//     //         vector::singleton(b_id),
//     //         0,
//     //         vector::singleton(ts::take_from_address_by_id<ItemA>(scenario, ALICE, a_id)),
//     //         vector::empty(),
//     //         0,
//     //         &clock,
//     //         clock::timestamp_ms(&clock) + MS_IN_A_DAY,
//     //         ts::ctx(scenario)
//     //     );
//     //
//     //     print(&swap_db);
//     //
//     //     // ts::next_tx(scenario, BOB);
//     //     // let nft_b = ts::take_from_address_by_id<ItemB>(scenario, BOB, b_id);
//     //     // print(&nft_b);
//     //     print(&swap_id);
//     // // Error accepting is because swap_db isn't requests--
//     //     ts::return_shared(swap_db);
//     //     ts::return_shared(clock);
//     //     ts::end(scenario_val);
//     // }
//
//     // Create swop request - [one item + coin] for [one item]
//     // Create swop request - [one item + coin] for [multiple items]
//     // Create swop request - [one item + coin] for [one item + coin]
//     // Create swop request - [one item + coin] for [multiple items + coin]
//
//     // Create swop request - [multiple item + coin] for [one item]
//     // Create swop request - [multiple item + coin] for [multiple items]
//     // Create swop request - [multiple item + coin] for [one item + coin]
//     // Create swop request - [multiple item + coin] for [multiple items + coin]
//
//     //     const EInsufficientValue:u64 = 0;
//     //     const EInvalidExpiry: u64 = 1;
//     //     const EInvalidSwapId: u64 = 2;
//     //     const ENotInitiator: u64 = 3;
//     //     const ENotCounterparty: u64 = 4;
//     //     const EActionNotAllowed: u64 = 5;
//     //     const ESuppliedLengthMismatch: u64 = 6;
//     //     const EUnexpectedObjectFound: u64 = 7;
//
//
// }