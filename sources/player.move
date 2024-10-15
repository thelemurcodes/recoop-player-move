module recoop::player {
  use std::signer;
  use std::string::{Self, String};
  use aptos_std::table_with_length::{Self, TableWithLength};
  use std::vector;
  use aptos_token_objects::property_map::{Self};
  use aptos_framework::object::{Self, Object, TransferRef, ConstructorRef};
  use recoop::game_entity;
  use recoop::game_collection;
  use aptos_token_objects::royalty;
  use aptos_token_objects::token;
  use aptos_token_objects::collection;
  use std::option;
  use std::error;
  use std::bcs;
  use recoop::game_dollar;
  use recoop::game_utils;
  use aptos_std::from_bcs;
  // use std::debug;

  friend recoop::game_item;
  friend recoop::game;
  #[test_only]
  friend recoop::testing_flow;

  const SALARY_MIN: u64 = 50000000;
  const SALARY_MAX: u64 = 150000000;

  /// Player directory already exists
  const EPLAYER_DIRECTORY_ALREADY_EXISTS: u64 = 1;

  /// Player already staked
  const EPLAYER_ALREADY_STAKED: u64 = 2;

  /// Player not owned by signer
  const EPLAYER_NOT_OWNED: u64 = 3;

  /// Player does not exist at this address
  const EPLAYER_DOES_NOT_EXIST: u64 = 4;

  /// Player not staked
  const EPLAYER_NOT_STAKED: u64 = 5;

  /// Staking is not on
  const ESTAKING_NOT_ON: u64 = 6;

  struct Player has key {
    tkn_mutator_ref: token::MutatorRef,
    pm_mutator_ref: property_map::MutatorRef,
    transfer_ref: TransferRef
  }

  struct PlayerDirectory has key {
    players: TableWithLength<u64, Object<Player>>,
    staking_on: bool
  }

  public (friend) fun init(
    creator: &signer,
  ){
    assert_player_directory_dne(creator);

    move_to(creator,
      PlayerDirectory {
        players: table_with_length::new(),
        staking_on: false
      }
    );
  }

  fun assert_player_directory_dne(account: &signer) {
    let account_address = signer::address_of(account);
    assert!(
        !exists<PlayerDirectory>(account_address),
        error::invalid_argument(EPLAYER_DIRECTORY_ALREADY_EXISTS),
    );
  }

  public (friend) fun mint_to_buyer(
    buyer: &signer,
    player_count: u64,
    rr_addr: address
  ): vector<address> acquires PlayerDirectory {
    let player_addresses = vector::empty<address>();

    let entity_signer = game_entity::get_signer_from_address(rr_addr);
    let collection = game_collection::get(rr_addr, string::utf8(b"Players"));
    let royalty = royalty::create(2, 100, @recoop);

    let i = 0;
    while (i < player_count) {
      let constructor_ref = token::create_numbered_token(
        &entity_signer,
        collection::name(collection),
        string::utf8(b"Your player card, when staked, entitles you to weekly [irl time] airdropped income during the ReCoop game period."),
        string::utf8(b"Player #"),
        string::utf8(b""),
        option::some(royalty),
        string::utf8(b"recooprentals.com"),
      );

      init_property_map(&constructor_ref);

      // Get object refs
      let transfer_ref = object::generate_transfer_ref(&constructor_ref);
      let tkn_mutator_ref = token::generate_mutator_ref(&constructor_ref);
      let pm_mutator_ref = property_map::generate_mutator_ref(&constructor_ref);

      // Pack Object
      let object_signer = object::generate_signer(&constructor_ref);
      move_to(&object_signer,
        Player {
          tkn_mutator_ref,
          pm_mutator_ref,
          transfer_ref
        }
      );

      // send player to user
      let player: Object<Player> = object::object_from_constructor_ref(&constructor_ref);
      object::transfer(&entity_signer, player, signer::address_of(buyer));

      // debug::print<String>(&token::name(player));
      // debug::print<address>(&rr_addr);

      // add to player directory
      let directory = borrow_global_mut<PlayerDirectory>(rr_addr);
      let index = table_with_length::length(&directory.players) + 1;
      table_with_length::add(
        &mut directory.players,
        index,
        player,
      );

      let player_address = object::object_address(&player);
      vector::push_back(&mut player_addresses, player_address);

      i = i + 1;
    };

    player_addresses
  }

  fun init_property_map(
    constructor_ref: &ConstructorRef,
  ) {
    let properties = property_map::prepare_input(
      vector[
        string::utf8(b"name"),
        string::utf8(b"vocation"),
        string::utf8(b"backstory"),
        string::utf8(b"revenue_yr"),
        string::utf8(b"staked")
      ],
      vector[
        string::utf8(b"0x1::string::String"),
        string::utf8(b"0x1::string::String"),
        string::utf8(b"0x1::string::String"),
        string::utf8(b"u64"),
        string::utf8(b"bool")
      ],
      vector[
        bcs::to_bytes<String>(&string::utf8(b"pending")),
        bcs::to_bytes<String>(&string::utf8(b"pending")),
        bcs::to_bytes<String>(&string::utf8(b"pending")),
        bcs::to_bytes<u64>(&0),
        bcs::to_bytes<bool>(&false)
      ]
    );
    property_map::init(constructor_ref, properties);
  }

  public entry fun stake(
    owner: &signer,
    rr_addr: address,
    player_addr: address
  ) acquires Player, PlayerDirectory {
    // assert owned
    let player = get_from_address(player_addr);
    assert_ownership(signer::address_of(owner), player);

    // TODO: assert staking is on
    let directory = borrow_global<PlayerDirectory>(rr_addr);
    assert!(
      directory.staking_on,
      error::invalid_state(ESTAKING_NOT_ON)
    );

    // assert not staked
    assert!(
      object::ungated_transfer_allowed(player),
      error::invalid_state(EPLAYER_ALREADY_STAKED)
    );

    // freeze player
    let player_info = borrow_global<Player>(player_addr);
    object::disable_ungated_transfer(&player_info.transfer_ref);

    // update property map status: true
    update_staked(player_addr, true);
  }

  public entry fun unstake(
    owner: &signer,
    player_addr: address
  ) acquires Player {
    // assert owned
    let player = get_from_address(player_addr);
    assert_ownership(signer::address_of(owner), player);

    // assert staked
    assert!(
      !object::ungated_transfer_allowed(player),
      error::invalid_state(EPLAYER_NOT_STAKED)
    );

    // unfreeze player
    let player_info = borrow_global<Player>(player_addr);
    object::enable_ungated_transfer(&player_info.transfer_ref);

    // update property map status: false
    update_staked(player_addr, false);
  }

  public entry fun payday(
    admin: &signer,
    rr_addr: address,
  ) acquires PlayerDirectory {
    game_utils::assert_is_admin(admin);
    let dollar_addr = game_dollar::get_address(rr_addr);

    let directory = borrow_global<PlayerDirectory>(rr_addr);
    let directory_len = table_with_length::length(&directory.players);

    let i = 1;
    while (i <= directory_len){
      let player = *table_with_length::borrow(&directory.players, i);

      // if player is frozen
      if(!object::ungated_transfer_allowed(player)){
        let (_, revenue) = property_map::read(&player, &string::utf8(b"revenue_yr"));
        let revenue_yr = from_bcs::to_u64(revenue);
        let revenue_qtr = revenue_yr / 4;

        game_dollar::mint(
          dollar_addr,
          object::owner(player),
          revenue_qtr
        );
      };
      i = i + 1;
    };
  }

  fun get_from_address(
    player_addr: address
  ): Object<Player> {
    assert!(
      exists<Player>(player_addr),
      error::invalid_argument(EPLAYER_DOES_NOT_EXIST),
    );
    object::address_to_object<Player>(player_addr)
  }

  fun assert_ownership(
    owner_addr: address,
    obj: Object<Player>
  ){
    assert!(
      object::owns(obj, owner_addr),
      error::invalid_argument(EPLAYER_NOT_OWNED)
    );
  }

  fun update_staked (
    player_addr: address,
    new_status: bool
  ) acquires Player {
    let player = borrow_global<Player>(player_addr);
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"staked"),
      string::utf8(b"bool"),
      bcs::to_bytes<bool>(&new_status)
    );
  }

  public (friend) fun get_player_from_address(
    object_addr: address
  ): Object<Player> {
    object::address_to_object<Player>(object_addr)
  }

  public (friend) fun get_revenue(
    player: Object<Player>
  ): u64 {
    let (_, revenue) = property_map::read(&player, &string::utf8(b"revenue_yr"));
    from_bcs::to_u64(revenue)
  }

  public entry fun update_properties(
    admin: &signer,
    player_addr: address,
    name: String,
    vocation: String,
    backstory: String,
    uri: String
  ) acquires Player {
    game_utils::assert_is_admin(admin);

    let player = borrow_global<Player>(player_addr);
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"name"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&name)
    );
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"vocation"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&vocation)
    );
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"backstory"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&backstory)
    );

    token::set_uri(&player.tkn_mutator_ref, uri);
  }

public entry fun update_properties_v2(
    admin: &signer,
    player_addr: address,
    name: String,
    vocation: String,
    backstory: String,
    uri: String,
    revenue: u64
  ) acquires Player {
    game_utils::assert_is_admin(admin);

    let player = borrow_global<Player>(player_addr);
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"name"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&name)
    );
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"vocation"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&vocation)
    );
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"backstory"),
      string::utf8(b"0x1::string::String"),
      bcs::to_bytes<String>(&backstory)
    );
    property_map::update(
      &player.pm_mutator_ref,
      &string::utf8(b"revenue_yr"),
      string::utf8(b"u64"),
      bcs::to_bytes<u64>(&revenue)
    );

    token::set_uri(&player.tkn_mutator_ref, uri);
  }

  public entry fun toggle_staking(
    admin: &signer,
    rr_addr: address
  ) acquires PlayerDirectory {
    game_utils::assert_is_admin(admin);

    let directory = borrow_global_mut<PlayerDirectory>(rr_addr);
    directory.staking_on = !directory.staking_on;
  }
}
