#[test_only]
module swop::swop_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::object::{Self, UID, ID, id_from_address};
    use swop::swop::{Self, SwapDB, SwapRequest, remove_open_swap};
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

    fun add_nft_to_offer_<T: key + store>(
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

    fun init_test_env(scenario: &mut Scenario): (AdminCap, SwapDB, SwapRequest, Clock, ID, ID, ID, ID) {
        ts::next_tx(scenario, ALICE);
        mint_coins_to_user<SUI>(scenario, COINS_TO_MINT, ALICE);
        mint_coins_to_user<SUI>(scenario, COINS_TO_MINT, BOB);
        mint_coins_to_user<BTC>(scenario, COINS_TO_MINT, BOB);

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

    // Create swop request - [coin] for [(other) coin]
    #[test]
    fun swap_success_coin_for_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

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

    // Create swop request - [coin] for [one item]
    #[test]
    fun swap_success_coin_for_single() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [coin] for [one item + (other) coin]
    #[test]
    fun swap_success_coin_for_single_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

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

    // Create swop request - [coin] for [multiple items]
    #[test]
    fun swap_success_coin_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [coin] for [multiple items + (other) coin]
    #[test]
    fun swap_success_coin_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

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


    // Create swop request - [one item] for [(other) coin]
    #[test]
    fun swap_success_single_for_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item] for [one item]
    #[test]
    fun swap_success_single_for_single() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item] for [one item + (other) coin]
    #[test]
    fun swap_success_single_for_single_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item] for [multiple items]
    #[test]
    fun swap_success_single_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item] for [multiple items + (other) coin]
    #[test]
    fun swap_success_single_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }


    // Create swop request - [multiple items] for [(other) coin]
    #[test]
    fun swap_success_multiple_for_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swap request - [multiple items] for [single item]
    #[test]
    fun swap_success_multiple_for_single() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [multiple items] for [one item + (other) coin]
    #[test]
    fun swap_success_multiple_for_single_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [multiple items] for [multiple items]
    #[test]
    fun swap_success_multiple_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [multiple items] for [multiple items + (other) coin]
    #[test]
    fun swap_success_multiple_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<BTC>(scenario, BOB) == COINS_TO_MINT - counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }


    // Create swop request - [one item + coin] for [(other) coin]
    #[test]
    fun swap_success_single_with_coin_for_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
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

    // Create swop request - [one item + coin] for [one item]
    #[test]
    fun swap_success_single_with_coin_for_single() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item + coin] for [one item + (other) coin]
    #[test]
    fun swap_success_single_with_coin_for_single_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
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

    // Create swop request - [one item + coin] for [multiple items]
    #[test]
    fun swap_success_single_with_coin_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [one item + coin] for [multiple items + (other) coin]
    #[test]
    fun swap_success_single_with_coin_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
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


    // Create swop request - [multiple items + coin] for [(other) coin)]
    #[test]
    fun swap_success_multiple_with_coin_for_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
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

    // Create swop request - [multiple items + coin] for [one item]
    #[test]
    fun swap_success_multiple_with_coin_for_single() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [multiple items + coin] for [one item + (other) coin]
    #[test]
    fun swap_success_multiple_with_coin_for_single_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
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

    // Create swop request - [multiple items + coin] for [multiple items]
    #[test]
    fun swap_success_multiple_with_coin_for_multiple() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT - initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
            assert!(
                get_coins_balance<SUI>(scenario, BOB) == COINS_TO_MINT + initiator_sui_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Create swop request - [multiple items + coin] for [multiple items + (other) coin]
    #[test]
    fun swap_success_multiple_with_coin_for_multiple_with_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
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
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 1, sender);
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id2), EObjectNotInInventory);
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
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        // Make sure swap request is in open requests
        let swap_id = object::id(swap_mut);
        assert!(swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotInOpenSwaps);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator cancels swap request and claims deposited nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = swop::remove_open_swap(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(swap_mut, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);
        };

        // Make sure swap request is no longer in requests & its status equals cancelled
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_cancelled(swap_mut), EIncorrectSwapStatus);
        assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT, EIncorrectCoinBalance);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Expired swap request
    #[test]
    fun swap_status_expired() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;
        let swap_valid_duration = 1000000;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, swap_valid_duration, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        // Make sure swap request is in open requests
        let swap_id = object::id(swap_mut);
        assert!(swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotInOpenSwaps);

        clock::increment_for_testing(&mut clock, swap_valid_duration + 1);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator cancels swap request and claims deposited nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = swop::remove_open_swap(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(swap_mut, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);
        };

        // Make sure swap request is no longer in requests & its status equals cancelled
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_expired(swap_mut), EIncorrectSwapStatus);
        assert!(get_coins_balance<SUI>(scenario, ALICE) == COINS_TO_MINT, EIncorrectCoinBalance);

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }


    // Create an offer with no items or coins to be received
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_create_offer_empty_initiator() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let swap_db = take_swop_db(scenario);

        let type_name = type_name::into_string(type_name::get<SUI>());
        swop::create_init(
            &mut swap_db,
            BOB,
            vector::empty(),
            0,
            type_name,
            ts::ctx(scenario)
        );

        ts::return_shared(swap_db);
        ts::end(scenario_val);
    }

    // Create an offer with an unallowed coin to be received
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_create_offer_receive_unallowed_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;

        let swap_db = take_swop_db(scenario);

        let type_name = type_name::into_string(type_name::get<ETH>());
        swop::create_init(
            &mut swap_db,
            BOB,
            vector::singleton(id_from_address(@0x400)),
            0,
            type_name,
            ts::ctx(scenario)
        );

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
        swop::create_init(
            &mut swap_db,
            ALICE,
            vector::singleton(id_from_address(@0x400)),
            0,
            type_name,
            ts::ctx(scenario)
        );

        ts::return_shared(swap_db);
        ts::end(scenario_val);
    }

    // Initiator tries to add nft after creation
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_add_nft_after_creation() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, ALICE);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add nft after accepting
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_add_nft_after_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            let sender = tx_context::sender(ts::ctx(scenario));
            let bob_obj3 = ItemB { id: object::new(ts::ctx(scenario)) };
            let bob_id3 = object::id(&bob_obj3);
            transfer::transfer(bob_obj3, BOB);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id3);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // User tries to add unallowed project to nft offer
    #[test, expected_failure(abort_code = swop::swop::EProjectNotAllowed)]
    fun swap_fail_add_unallowed_nft() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        let alice_obj3 = ItemC { id: object::new(ts::ctx(scenario)) };
        let alice_id3 = object::id(&alice_obj3);
        transfer::transfer(alice_obj3, ALICE);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemC>(scenario, swap_db_mut, swap_mut, sender, alice_id3);


            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add nft that is not requested for
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_add_unrequested_nft() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to add coin after creation
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_add_coin_after_creation() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to add unallowed coin
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_initiator_add_unallowed_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_eth_coin_offer = 10;
        let counter_btc_coin_offer = 20;


        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            mint_coins_to_user<ETH>(scenario, COINS_TO_MINT, ALICE);
            add_coin_to_offer_<ETH>(scenario, swap_db_mut, swap_mut, ALICE, initiator_eth_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to add coin after accepting
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_add_coin_after_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds coin below requested value
    #[test, expected_failure(abort_code = swop::swop::EInsufficientValue)]
    fun swap_fail_counterparty_add_insufficient_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer / 2);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds unrequested coin
    #[test, expected_failure(abort_code = swop::swop::ECoinNotAllowed)]
    fun swap_fail_counterparty_add_unrequested_coin() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty adds coin twice
    #[test, expected_failure(abort_code = swop::swop::ECoinAlreadyAddedToOffer)]
    fun swap_fail_counterparty_add_coin_twice() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Wrong initiator for swap
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_sender_not_initiator() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);
        };

        ts::next_tx(scenario, CAROL);
        {
            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator empty swap offer in create
    #[test, expected_failure(abort_code = swop::swop::EInvalidOffer)]
    fun swap_fail_empty_initiator_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to remove open swap
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_remove_unaccepted_swap() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            let receipt = remove_open_swap(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));
            let coin = swop::refund_platform_fee(swap_mut, receipt, ts::ctx(scenario));
            transfer::public_transfer(coin, sender);

            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to claim nft without accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_claim_nft_without_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemA>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemA>(scenario, BOB, alice_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to claim nft without counterparty accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_claim_nft_without_counterparty_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s)
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_nft_from_offer_<ItemB>(scenario, swap_mut, 0, sender);
            assert!(is_object_in_inventory<ItemB>(scenario, ALICE, bob_id1), EObjectNotInInventory);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to claim coins without accepting offer
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_counterparty_claim_coin_without_accepting() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, _alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, sender, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<SUI>(scenario, swap_mut, sender);

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
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

            assert!(
                get_coins_balance<BTC>(scenario, ALICE) == counter_btc_coin_offer,
                EIncorrectCoinBalance
            );
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // User tries to claim coin twice
    #[test, expected_failure(abort_code = swop::swop::EInsufficientValue)]
    fun swap_fail_user_tries_to_claim_coin_twice() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, _bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let counter_btc_coin_offer = 20;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector::empty());
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        // Make sure swap request is no longer in requests & its status equals accepted
        let swap_id = object::id(swap_mut);
        assert!(!swop::is_swap_in_requests(ALICE, swap_id, swap_db_mut), ESwapNotRemovedFromOpenSwaps);
        assert!(swop::is_swap_accepted(swap_mut), EIncorrectSwapStatus);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator claims nft(s) and coins
            let sender = tx_context::sender(ts::ctx(scenario));
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);
            claim_coins_from_offer_<BTC>(scenario, swap_mut, sender);

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
        let (admin_cap, swap_db, swap, clock, alice_id1, alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);
        let initiator_sui_coin_offer = 10;
        let counter_btc_coin_offer = 20;
        let swap_valid_duration = 1000000;

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            swop::set_coins_to_receive<BTC>(swap_mut, counter_btc_coin_offer);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id2);
            add_coin_to_offer_<SUI>(scenario, swap_db_mut, swap_mut, ALICE, initiator_sui_coin_offer);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, swap_valid_duration, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id2);
            add_coin_to_offer_<BTC>(scenario, swap_db_mut, swap_mut, sender, counter_btc_coin_offer);

            clock::increment_for_testing(&mut clock, swap_valid_duration + 1);

            // Counterparty accepts swap request
            let receipt = swop::accept<BTC>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };


        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Initiator tries to accept offer after counterparty adds assets
    #[test, expected_failure(abort_code = swop::swop::EActionNotAllowed)]
    fun swap_fail_initiator_accept_offer() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, _bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, sender, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);
        };

        ts::next_tx(scenario, ALICE);
        {
            // Initiator tries to accept swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Filler to consume the receipt
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }

    // Counterparty tries to accept offer without adding all nfts
    #[test, expected_failure(abort_code = swop::swop::ESuppliedLengthMismatch)]
    fun swap_fail_counterparty_accept_offer_insufficient_nft_added() {
        let scenario_val = ts::begin(ALICE);
        let scenario = &mut scenario_val;
        let (admin_cap, swap_db, swap, clock, alice_id1, _alice_id2, bob_id1, bob_id2) = init_test_env(scenario);
        let swap_db_mut = &mut swap_db;
        let swap_mut = &mut swap;
        let platform_fee = swop::get_platform_fee(swap_db_mut);

        ts::next_tx(scenario, ALICE);
        {
            // Initiator sets nft(s) to be received, nft(s) to be swapped
            let sender = tx_context::sender(ts::ctx(scenario));
            swop::set_nfts_to_receive(swap_mut, vector[bob_id1, bob_id2]);
            add_nft_to_offer_<ItemA>(scenario, swap_db_mut, swap_mut, sender, alice_id1);

            // Initiator creates swap
            let receipt = swop::create<SUI>(swap_db_mut, swap_mut, &clock, 1000000, ts::ctx(scenario));

            // Initiator pays platform fee
            swop::take_swop_fee(take_coins(scenario, ALICE, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == platform_fee, EIncorrectPlatformFee);
        };

        ts::next_tx(scenario, BOB);
        {
            // Counterparty adds nft(s) to swap
            let sender = tx_context::sender(ts::ctx(scenario));
            add_nft_to_offer_<ItemB>(scenario, swap_db_mut, swap_mut, sender, bob_id1);

            // Counterparty accepts swap request
            let receipt = swop::accept<SUI>(swap_db_mut, swap_mut, &clock, ts::ctx(scenario));

            // Counterparty pays platform fee
            swop::take_swop_fee(take_coins(scenario, BOB, platform_fee), swap_mut, receipt);
            assert!(swop::get_platform_fee_balance(swap_mut) == (platform_fee * 2), EIncorrectPlatformFee);
        };

        end_scenario(admin_cap, swap, swap_db, clock, scenario_val);
    }
}