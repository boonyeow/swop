module swop::admin {
    use std::type_name::{Self};
    use std::ascii::{String};
    use sui::dynamic_field::{Self as field};
    use sui::transfer::{Self};
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::balance::{Self};
    use sui::tx_context::{Self, TxContext};
    use swop::swop::{Self, SwapDB, SwapRequest};

    const EProjectAlreadyRegistered: u64 = 400;
    const ECoinTypeAlreadyRegistered: u64 = 401;
    const EProjectNotFound: u64 = 402;
    const ECoinTypeNotFound: u64 = 403;
    const EActionNotAllowed: u64 = 404;

    const SWAP_STATUS_ACCEPTED: u64 = 100;
    const SWAP_STATUS_COMPLETED: u64 = 101;

    struct AdminCap has key {
        id: UID,
    }

    #[test_only]
    public fun init_test(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    public entry fun list_project<T>(_: &AdminCap, swap_db: &mut SwapDB) {
        let type_name = type_name::into_string(type_name::get<T>());
        let allowed_projects = swop::borrow_mut_allowed_projects(swap_db);
        assert!(!field::exists_(allowed_projects, type_name), EProjectAlreadyRegistered);
        field::add(allowed_projects, type_name, true);
    }

    public entry fun list_coin<T>(_: &AdminCap, swap_db: &mut SwapDB) {
        let type_name = type_name::into_string(type_name::get<T>());
        let allowed_coins = swop::borrow_mut_allowed_coins(swap_db);
        assert!(!field::exists_(allowed_coins, type_name), ECoinTypeAlreadyRegistered);
        field::add(allowed_coins, type_name, true);
    }

    public entry fun delist_project<T>(_: &AdminCap, swap_db: &mut SwapDB) {
        let type_name = type_name::into_string(type_name::get<T>());
        let allowed_projects = swop::borrow_mut_allowed_projects(swap_db);
        assert!(field::exists_(allowed_projects, type_name), EProjectNotFound);
        field::remove<String, bool>(allowed_projects, type_name);
    }

    public entry fun delist_coin<T>(_: &AdminCap, swap_db: &mut SwapDB) {
        let type_name = type_name::into_string(type_name::get<T>());
        let allowed_coins = swop::borrow_mut_allowed_coins(swap_db);
        assert!(field::exists_(allowed_coins, type_name), ECoinTypeNotFound);
        field::remove<String, bool>(allowed_coins, type_name);
    }

    public entry fun update_platform_fee(_: &AdminCap, swap_db: &mut SwapDB, new_platform_fee: u64) {
        let platform_fee = swop::borrow_mut_platform_fee(swap_db);
        *platform_fee = new_platform_fee
    }

    public entry fun transfer_admin_cap(admin_cap: AdminCap, to: address) {
        transfer::transfer(admin_cap, to);
    }

    public fun take_platform_fee(
        _: &AdminCap,
        swap: &mut SwapRequest,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let status = swop::borrow_mut_sr_status(swap);
        assert!(*status == SWAP_STATUS_ACCEPTED, EActionNotAllowed);
        *status = SWAP_STATUS_COMPLETED;

        let platform_fee_balance = swop::borrow_mut_sr_balance(swap);
        let value = balance::value(platform_fee_balance);
        coin::take(platform_fee_balance, value, ctx)
    }
}