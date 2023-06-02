module swop::my_module {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::bag::{Self, Bag};

    struct EscrowObj has key, store {
        id: UID,
        bag: Bag,
    }

    struct Object1 has key, store {
        id: UID,
        num: u8,
    }

    struct Object2 has key, store {
        id: UID,
        num: u8
    }

    // fun init(ctx: &mut TxContext){
    //     transfer::public_share_object(
    //         EscrowObj{
    //             id: object::new(ctx),
    //             bag: bag::new(ctx)
    //         }
    //     );
    // }

    public fun mint_obj_1(ctx: &mut TxContext): Object1 {
        Object1 { id: object::new(ctx), num: 1 }
    }

    public fun mint_obj_2(ctx: &mut TxContext): Object2 {
        Object2 { id: object::new(ctx), num: 2 }
    }

    public entry fun add_to_bag<T1: key+store, T2: key+store>(escrow: &mut EscrowObj, obj1: T1, obj2: T2) {
        bag::add(&mut escrow.bag, 0, obj1);
        bag::add(&mut escrow.bag, 1, obj2);
    }

    public entry fun add_single_to_bag<T: key+store>(escrow: &mut EscrowObj, obj: T) {
        let len = bag::length(&escrow.bag);
        bag::add(&mut escrow.bag, len, obj);
    }

    public entry fun remove_all_from_bag<T1: key+store, T2: key+store>(escrow: &mut EscrowObj, ctx: &mut TxContext) {
        if (!bag::is_empty(&escrow.bag)) {
            transfer::public_transfer(bag::remove<u8, T1>(&mut escrow.bag, 0), tx_context::sender(ctx));
            transfer::public_transfer(bag::remove<u8, T2>(&mut escrow.bag, 1), tx_context::sender(ctx));
        }
    }

    public entry fun fn1(ctx: &mut TxContext) {
        transfer::public_share_object(
            EscrowObj {
                id: object::new(ctx),
                bag: bag::new(ctx)
            }
        );
    }

    public fun fn2(obj: &mut EscrowObj, ctx: &mut TxContext): Object1 {
        std::debug::print(&bag::is_empty(&obj.bag));
        Object1 { id: object::new(ctx), num: 1 }
    }
}