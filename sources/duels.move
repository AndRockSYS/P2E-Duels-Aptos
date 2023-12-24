//aptos move create-resource-account-and-publish-package --seed [SEED] --address-name MODULE_NAME --named-addresses source_address=ADDRESS

module be_safe::duels {
    use std::signer;
    use std::vector;
    use std::error;

    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    use aptos_framework::aptos_account;
    use aptos_framework::account;
    use aptos_framework::resource_account;

    use aptos_framework::aptos_coin;
    use aptos_framework::coin;

    const INCORRECT_VALUE: u64 = 1;
    const BET_IS_NOT_EQUAL: u64 = 2;
    const LOW_BALANCE: u64 = 3;

    const ROUND_IS_NOT_READY: u64 = 4;
    const ROUND_IS_WAITING_TO_BE_STARTED: u64 = 5;
    const ROUND_HAS_ENDED: u64 = 6;
    const INCORRECT_ROUND_ID: u64 = 7;
    const YOU_ARE_NOT_IN_THAT_ROUND: u64 = 8;

    const DEV_FEE: u64 = 10;

    struct Storage has key, store {
        data: vector<Round>,
        signer_capability: account::SignerCapability,

        create_round_event: EventHandle<CreateRound>,
        enter_round_event: EventHandle<EnterRound>,
        close_round_event: EventHandle<CloseRound>,
        end_round_event: EventHandle<EndRound>
    }

    struct Round has copy, store {
        timestamp: u64,

        red: address,
        blue: address,
        winner: address,

        pool: u64
    }

    struct CreateRound has drop, store {
        id: u64,
        player: address,
        pool: u64
    }

    struct EnterRound has drop, store {
        id: u64,
        player: address,
    }

    struct CloseRound has drop, store {
        id: u64
    }

    struct EndRound has drop, store {
        id: u64,
        winner: address,
        win_amount: u64
    }

    fun init_module(owner: &signer) {
        let signer_capability: account::SignerCapability = resource_account::retrieve_resource_account_cap(owner, @source_address);

        move_to(owner, Storage { 
            data: vector::empty<Round>(),
            signer_capability: signer_capability,

            create_round_event: account::new_event_handle<CreateRound>(owner),
            enter_round_event: account::new_event_handle<EnterRound>(owner),
            close_round_event: account::new_event_handle<CloseRound>(owner),
            end_round_event: account::new_event_handle<EndRound>(owner)
        });
    }

    public entry fun create_round(account: &signer, value: u64, side: bool) acquires Storage {
        assert!(value >= 5000, error::invalid_argument(INCORRECT_VALUE));
        assert!(check_balance(signer::address_of(account), value), error::aborted(LOW_BALANCE));

        let player: address = signer::address_of(account);

        let red: address = if (side) {player} else {@0x0};
        let blue: address = if (side) {@0x0} else {player};

        let new_round = Round {
            timestamp: timestamp::now_microseconds(),

            red: red,
            blue: blue,
            winner: @0x0,

            pool: value
        };

        let storage: &mut Storage = borrow_global_mut<Storage>(@be_safe);

        vector::push_back<Round>(&mut storage.data, new_round);

        aptos_account::transfer(account, @be_safe, value);

        event::emit_event<CreateRound>(&mut storage.create_round_event, CreateRound { id: vector::length(&mut storage.data)-1, player, pool: value });
    }

    public entry fun enter_round(account: &signer, value: u64, round_id: u64) acquires Storage {
        assert!(check_balance(signer::address_of(account), value), error::aborted(LOW_BALANCE));

        let storage: &mut Storage = borrow_global_mut<Storage>(@be_safe);

        let round: &mut Round = vector::borrow_mut<Round>(&mut storage.data, round_id);

        let red = &mut round.red;
        let blue = &mut round.blue;
        let winner = &mut round.winner;
        let pool = &mut round.pool;

        assert!(*winner == @0x0, error::unavailable(ROUND_HAS_ENDED));
        assert!(*pool == value, error::internal(BET_IS_NOT_EQUAL));
        assert!(*red == @0x0 || *blue == @0x0, error::unavailable(ROUND_IS_WAITING_TO_BE_STARTED));

        if(*red == @0x0) 
            {*red = signer::address_of(account)}
        else 
            {*blue = signer::address_of(account)};

        *pool = value * 2;
        
        aptos_account::transfer(account, @be_safe, value);

        event::emit_event<EnterRound>(&mut storage.enter_round_event, EnterRound { id: round_id, player: signer::address_of(account) });
    }

    entry public fun close_round(account: &signer, round_id: u64) acquires Storage {
        let storage: &mut Storage = borrow_global_mut<Storage>(@be_safe);

        let round: &mut Round = vector::borrow_mut<Round>(&mut storage.data, round_id);

        let red = &mut round.red;
        let blue = &mut round.blue;
        let winner = &mut round.winner;
        let pool = &mut round.pool;

        assert!(*winner == @0x0, error::unavailable(ROUND_HAS_ENDED));
        assert!(*red == @0x0 || *blue == @0x0, error::unavailable(ROUND_IS_WAITING_TO_BE_STARTED));

        let resource_signer = account::create_signer_with_capability(&storage.signer_capability);

        *winner = signer::address_of(account);
        aptos_account::transfer(&resource_signer, *winner, *pool);

        event::emit_event<CloseRound>(&mut storage.close_round_event, CloseRound { id: round_id });
    }

    entry public fun end_round(roundEnder: &signer, round_id: u64) acquires Storage {
        let storage: &mut Storage = borrow_global_mut<Storage>(@be_safe);

        let round: &mut Round = vector::borrow_mut<Round>(&mut storage.data, round_id);

        let red = &mut round.red;
        let blue = &mut round.blue;
        let winner = &mut round.winner;
        let pool = &mut round.pool;

        let account: address = signer::address_of(roundEnder);

        assert!(*winner == @0x0, error::unavailable(ROUND_HAS_ENDED));
        assert!(*red != @0x0 && *blue != @0x0, error::unavailable(ROUND_IS_NOT_READY));
        assert!(account == *red || account == *blue, error::permission_denied(YOU_ARE_NOT_IN_THAT_ROUND));

        let random_number: u64 = 23421; //TODO

        *winner = if(random_number % 2 ==0) {*red} else {*blue};

        let win_amount: u64 = *pool - (*pool * 10 / 100);

        let resource_signer = account::create_signer_with_capability(&storage.signer_capability);
        aptos_account::transfer(&resource_signer, *winner, win_amount);

        event::emit_event<EndRound>(&mut storage.end_round_event, EndRound { id: round_id, winner: *winner, win_amount });
    }

    #[view]
    fun check_balance(account: address, value: u64): bool {
        let balance = coin::balance<aptos_coin::AptosCoin>(account);

        (balance >= value)
    }

    #[view]
    public fun get_storage_length(): u64 acquires Storage {
        let data: &mut vector<Round> = &mut borrow_global_mut<Storage>(@be_safe).data;

        vector::length(data)
    }

    #[view]
    public fun get_round_info(round_id: u64): (u64, address, address, address, u64) acquires Storage {
        let data: &mut vector<Round> = &mut borrow_global_mut<Storage>(@be_safe).data;

        assert!(vector::length(data) > round_id, error::out_of_range(INCORRECT_ROUND_ID));

        let round: &mut Round = vector::borrow_mut<Round>(data, round_id);

        (*&mut round.timestamp, *&mut round.red, *&mut round.blue, *&mut round.winner, *&mut round.pool)
    }
}