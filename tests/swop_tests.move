#[test_only]
module swop::swop_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, UID, ID};
    use swop::swop::{Self, SwapDB, SwapRequest};
    use swop::admin::{Self, AdminCap};
    // use sui::test_utils::{print as sprint};
    use sui::clock::{Self, Clock};
    // use sui::bag::{Self};
    use std::vector::{Self};
    use std::type_name::{Self};
    use sui::tx_context::{Self};
    // use std::string;
    // use std::ascii::{String};
    // use std::debug::print;

    const ADMIN: address = @0x000A;
    const ALICE: address = @0xAAAA;
    const BOB: address = @0xBBBB;
    const CAROL: address = @0xCCCC;
    const MS_IN_A_DAY: u64 = 86400000;
    const COINS_TO_MINT: u64 = 100;

    const EIncorrectPlatformFee: u64 = 0;
    const ESwapNotRemovedFromOpenSwaps: u64 = 1;
    const EIncorrectSwapStatus: u64 = 2;
    const EObjectNotInInventory: u64 = 3;
    const EIncorrectCoinBalance: u64 = 4;
    const ESwapNotInOpenSwaps: u64 = 5;


    // Example of an object type used for exchange
    struct ItemA has key, store {
        id: UID
    }

    // Example of the other object type used for exchange
    struct ItemB has key, store {
        id: UID
    }

    struct ItemC has key, store {
        id: UID
    }

    struct BTC has drop {}

    struct ETH has drop {}

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

    fun add_nft_to_offer_<T: key + store>(
        scenario: &mut Scenario,
        swap_db: &mut SwapDB,
        swap: &mut SwapRequest,
        user: address,
        obj_id: ID
    ) {
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
        let coins = take_coins<CoinType>(scenario, user, amount);
        swop::add_coins_to_offer(swap_db, swap, coins, ts::ctx(scenario));
    }

    fun claim_nft_from_offer_<T: key + store>(
        scenario: &mut Scenario,
        swap_mut: &mut SwapRequest,
        item_key: u64,
        sender: address
    ) {
        let obj = swop::claim_nft_from_offer<T>(swap_mut, item_key, ts::ctx(scenario));
        transfer::public_transfer(obj, sender);
    }

    fun claim_coins_from_offer_<CoinType: drop>(scenario: &mut Scenario, swap_mut: &mut SwapRequest, sender: address) {
        let coin = swop::claim_coins_from_offer<CoinType>(swap_mut, ts::ctx(scenario));
        transfer::public_transfer(coin, sender);
    }

    fun end_scenario(
        admin_cap: AdminCap,
        swap: SwapRequest,
        swap_db: SwapDB,
        clock: Clock,
        scenario_val: Scenario
    ) {
        ts::return_to_address(ADMIN, admin_cap);
        ts::return_shared(swap);
        ts::return_shared(swap_db);
        ts::return_shared(clock);
        ts::end(scenario_val);
    }

    fun mint_coins_to_user<CoinType>(scenario: &mut Scenario, amount_to_mint: u64, user: address) {
        ts::next_tx(scenario, user);
        transfer::public_transfer(
            coin::mint_for_testing<CoinType>(amount_to_mint, ts::ctx(scenario)), user
        );
    }

    fun init_test_env(scenario: &mut Scenario): (AdminCap, SwapDB, Clock, ID, ID, ID, ID) {
        ts::next_tx(scenario, ALICE);
        mint_coins_to_user<SUI>(scenario, COINS_TO_MINT, ALICE);
        mint_coins_to_user<SUI>(scenario, COINS_TO_MINT, BOB);
        mint_coins_to_user<BTC>(scenario, COINS_TO_MINT, BOB);

        let alice_obj1 = ItemA { id: object::new(ts::ctx(scenario)) };
        let alice_obj2 = ItemB { id: object::new(ts::ctx(scenario)) };
        let bob_obj1 = ItemA { id: object::new(ts::ctx(scenario)) };
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
            admin::list_coin<BTC>(&admin_cap, &mut swap_db);

            let clock = clock::create_for_testing(ts::ctx(scenario));
            clock::share_for_testing(clock);

            ts::next_tx(scenario, ALICE);
            let clock = ts::take_shared<Clock>(scenario);
            (swap_db, admin_cap, clock)
        };

        (admin_cap, swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2)
    }

    // Create swop request - [multiple items + coin] for [multiple items + (other) coin]
    #[test]
    fun swap_success_multiple_with_coin_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        let ctrparty_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );

            // Initiator adds nft(s), coins to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, ALICE, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        assert!(swop::get_platform_fee_balance(&mut swap) == platform_fee, EIncorrectPlatformFee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, BOB, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, BOB, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(ctrparty_swap_fee, &mut swap, receipt);
        };
        assert!(swop::get_platform_fee_balance(&mut swap) == (platform_fee * 2), EIncorrectPlatformFee);

        let swap_id = object::id(&swap);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(&swap), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            claim_nft_from_offer_<ItemA>(scenario, &mut swap, 0, ALICE);
            claim_nft_from_offer_<ItemB>(scenario, &mut swap, 1, ALICE);
            claim_coins_from_offer_<BTC>(scenario, &mut swap, ALICE);

            assert!(is_object_in_inventory<ItemA>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            claim_nft_from_offer_<ItemA>(scenario, &mut swap, 0, BOB);
            claim_nft_from_offer_<ItemB>(scenario, &mut swap, 1, BOB);
            claim_coins_from_offer_<SUI>(scenario, &mut swap, BOB);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };
        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Cancel swap request
    #[test]
    fun swap_status_cancelled() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_sui_coin_offer = 10;
        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator adds nft(s), coins to be swapped
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ALICE);

        // Make sure swap request is in open requests
        let swap = ts::take_shared<SwapRequest>(scenario);
        let swap_id = object::id(&swap);
        assert!(swop::get_platform_fee_balance(&swap) == platform_fee, EIncorrectPlatformFee);
        assert!(swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotInOpenSwaps);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator cancels swap request and claims deposited nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = swop::remove_open_swap(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(&mut swap, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, &mut swap, sender);
        };

        // Make sure swap request is no longer in requests & its status equals cancelled
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_cancelled(&swap), EIncorrectSwapStatus);
        assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT, EIncorrectCoinBalance);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Expired swap request
    #[test]
    fun swap_status_expired() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_sui_coin_offer = 10;
        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        let counter_btc_coin_offer = 20;

        let swap_valid_duration = 1000000;

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator adds nft(s), coins to be swapped
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, swap_valid_duration, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };
        ts::next_tx(scenario, ALICE);

        // Make sure swap request is in open requests
        let swap = ts::take_shared<SwapRequest>(scenario);
        let swap_id = object::id(&swap);
        assert!(swop::get_platform_fee_balance(&swap) == platform_fee, EIncorrectPlatformFee);
        assert!(swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotInOpenSwaps);

        clock::increment_for_testing(&mut clock, swap_valid_duration + 1);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator cancels swap request and claims deposited nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = swop::remove_open_swap(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(&mut swap, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, &mut swap, sender);
        };

        // Make sure swap request is no longer in requests & its status equals cancelled
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_expired(&swap), EIncorrectSwapStatus);
        assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT, EIncorrectCoinBalance);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }


    // Create an offer with no items or coins to be received
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_initiator_create_empty_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let swap_db = take_swop_db(scenario);

        let type_name = type_name::into_string(type_name::get<SUI>());
        let swap = swop::create_init(
            &mut swap_db,
            BOB,
            vector::empty(),
            0,
            type_name,
            ts::ctx(scenario)
        );
        transfer::public_share_object(swap);
        ts::return_shared(swap_db);
        ts::end(scenario_val);
    }

    //
    // Create an offer with an unallowed coin to be received
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_create_offer_receive_unallowed_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let swap_db = take_swop_db(scenario);

        let type_name = type_name::into_string(type_name::get<ETH>());
        let swap = swop::create_init(
            &mut swap_db,
            BOB,
            vector::singleton(object::id_from_address(@0x400)),
            0,
            type_name,
            ts::ctx(scenario)
        );
        transfer::public_share_object(swap);
        ts::return_shared(swap_db);
        ts::end(scenario_val);
    }

    // Initiator creating an offer to theirself
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_create_offer_initiator_to_initiator() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let swap_db = take_swop_db(scenario);

        let type_name = type_name::into_string(type_name::get<SUI>());
        let swap = swop::create_init(
            &mut swap_db,
            ALICE,
            vector::singleton(object::id_from_address(@0x400)),
            0,
            type_name,
            ts::ctx(scenario)
        );
        transfer::public_share_object(swap);

        ts::return_shared(swap_db);
        ts::end(scenario_val);
    }

    // Initiator tries to add nft after creation
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_add_nft_after_creation() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, ALICE);
        {
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, ALICE, alice_id2);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add nft after accepting
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_add_nft_after_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id2],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );

            // Initiator sets nft(s) to be received, nft(s) to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };
        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, BOB, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        ts::next_tx(scenario, BOB);
        {
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, BOB, bob_id1);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // User tries to add unallowed project to nft offer
    #[test, expected_failure(abort_code = swop::swop::EProjectNotAllowed)]
    fun swap_fail_add_unallowed_nft() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let alice_obj3 = ItemC { id: object::new(ts::ctx(scenario)) };
        let alice_id3 = object::id(&alice_obj3);
        transfer::transfer(alice_obj3, ALICE);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_nft_to_offer_<ItemC>(scenario, swap_db_mut, &mut swap, ALICE, alice_id3);


            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add nft that is not requested for
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_add_unrequested_nft() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to add coin after creation
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_add_coin_after_creation() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };
        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, ALICE);
        {
            // Counterparty adds nft(s) to swap
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to add unallowed coin
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_initiator_add_unallowed_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;

        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_eth_coin_offer = 10;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        mint_coins_to_user<ETH>(scenario, COINS_TO_MINT, ALICE);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            add_coin_to_offer_<ETH>(scenario, swap_db_mut, &mut swap, ALICE, initiator_eth_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add coin after accepting
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_add_coin_after_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector::empty(),
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        ts::next_tx(scenario, BOB);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, sender, counter_btc_coin_offer);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds coin below requested value
    #[test, expected_failure(abort_code = swop::swop::EInsufficientValue)]
    fun swap_fail_counterparty_add_insufficient_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, _bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, sender, counter_btc_coin_offer / 2);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds unrequested coin
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_counterparty_add_unrequested_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, _alice_id1, _alice_id2, _bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        let ctrparty_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator adds nft(s), coins to be swapped
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, BOB, bob_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(ctrparty_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds coin twice
    #[test, expected_failure(abort_code = swop::swop::ECoinAlreadyAddedToOffer)]
    fun swap_fail_counterparty_add_coin_twice() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        let ctrparty_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, BOB, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);
        };

        ts::next_tx(scenario, BOB);
        {
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);
            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(ctrparty_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator empty swap offer in create
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_empty_initiator_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };
        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to remove open swap
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_remove_unaccepted_swap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = swop::remove_open_swap(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(&mut swap, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, &mut swap, sender);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to claim nft without accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_claim_nft_without_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);

        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, &mut swap, 0, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to claim nft without counterparty accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_claim_nft_without_counterparty_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id2],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, sender, bob_id2);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, &mut swap, 0, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to claim coins without accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_claim_coin_without_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, &mut swap, sender);

            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to claim coin without counterparty accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_claim_coin_without_counterparty_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector::empty(),
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, sender, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, sender, counter_btc_coin_offer);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, &mut swap, sender);

            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // TODO: testing
    // User tries to claim coin twice
    #[test, expected_failure(abort_code = swop::swop::EInsufficientValue)]
    fun swap_fail_user_tries_to_claim_coin_twice() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector::empty(),
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(&swap);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(&swap), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, &mut swap, sender);
            claim_coins_from_offer_<BTC>(scenario, &mut swap, sender);

            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to accept expired offer
    #[test, expected_failure(abort_code = swop::swop::ERequestExpired)]
    fun swap_fail_counterparty_accept_expired_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;
        let swap_valid_duration = 1000000;

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<BTC>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                counter_btc_coin_offer,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, ALICE, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, &mut swap, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, swap_valid_duration, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, BOB, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, BOB, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, &mut swap, BOB, counter_btc_coin_offer);

            clock::increment_for_testing(&mut clock, swap_valid_duration + 1);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };


        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // TODO: testing
    // Initiator tries to accept offer after counterparty adds assets
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_accept_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, _bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id2],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, sender, bob_id2);
        };

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            // Initiator tries to accept swap request
            let receipt = swop::accept<SUI>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Filler to consume the receipt
            swop::take_fee_from_counterparty(initiator_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // TODO: testing
    // Counterparty tries to accept offer without adding all nfts
    #[test, expected_failure(abort_code = swop::swop::ESuppliedLengthMismatch)]
    fun swap_fail_counterparty_accept_offer_insufficient_nft_added() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let initiator_swap_fee = take_coins<SUI>(scenario, ALICE, platform_fee);
        ts::next_tx(scenario, ALICE);
        {
            let coin_type_to_receive = type_name::into_string(type_name::get<SUI>());
            let swap = swop::create_init(
                swap_db_mut,
                BOB,
                vector[bob_id1, bob_id2],
                0,
                coin_type_to_receive,
                ts::ctx(scenario)
            );
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, &mut swap, ALICE, alice_id1);

            // Initiator creates swap
            let (receipt, swap) = swop::create<SUI>(swap_db_mut, swap, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_fee_from_initiator(initiator_swap_fee, swap, receipt);
        };

        ts::next_tx(scenario, ADMIN);
        let swap = ts::take_shared<SwapRequest>(scenario);
        let bob_swap_fee = take_coins<SUI>(scenario, BOB, platform_fee);

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, &mut swap, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, &mut swap, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_fee_from_counterparty(bob_swap_fee, &mut swap, receipt);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }
}