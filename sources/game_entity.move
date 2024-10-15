module recoop::game_entity {
  use std::error;
  use std::signer;
  use std::string::{String};
  use aptos_framework::object::{Self, Object, ExtendRef};
  use aptos_std::table_with_length::{Self, TableWithLength};
  use aptos_token_objects::collection::{Self};

  friend recoop::game_collection;
  friend recoop::game;
  friend recoop::player;
  friend recoop::commission;

  /// The entity does not exist
  const EENTITY_DOES_NOT_EXIST: u64 = 1;

  /// The entity directory does not exist
  const EENTITY_DIRECTORY_DOES_NOT_EXIST: u64 = 2;

  /// The entity already exists
  const EENTITY_ALREADY_EXISTS: u64 = 3;

  /// Signer does not own this entity
  const ENOT_OWNER: u64 = 4;

  struct Entity has key {
    name: String,
    extend_ref: ExtendRef,
  }

  struct EntityDirectory has key {
    entities: TableWithLength<String, Object<Entity>>,
  }

  public entry fun init(
    creator: &signer,
    name: String,
  ) acquires EntityDirectory, Entity {
    let entity_seed = collection::create_collection_seed(&name);
    assert_dne(creator, &name);

    let constructor_ref = object::create_named_object(creator, entity_seed);
    let object_signer = object::generate_signer(&constructor_ref);
    let extend_ref = object::generate_extend_ref(&constructor_ref);

    move_to(&object_signer,
      Entity {
        name,
        extend_ref,
      }
    );

    let entity = object::object_from_constructor_ref(&constructor_ref);

    create_add_directory(creator, entity);
  }

  // Helper functions

  fun create_add_directory(account: &signer, entity: Object<Entity>) acquires EntityDirectory, Entity {
    let account_address = signer::address_of(account);
    if (!exists<EntityDirectory>(account_address)) {
      move_to(account,
        EntityDirectory {
          entities: table_with_length::new(),
        }
      )
    };
    let directory = borrow_global_mut<EntityDirectory>(account_address);
    table_with_length::add(&mut directory.entities, name(entity), entity);
  }

  public (friend) fun name<T: key>(entity: Object<T>): String acquires Entity {
    let entity_address = object::object_address(&entity);
    assert_exists(entity_address);

    let entity_info = borrow_global<Entity>(entity_address);
    entity_info.name
  }

  fun assert_exists(addr: address) {
    assert!(
        exists<Entity>(addr),
        error::not_found(EENTITY_DOES_NOT_EXIST),
    );
  }

  fun assert_dne(account: &signer, name: &String) {
    let entity_address = collection::create_collection_address(
      &signer::address_of(account),
      name
    );
    assert!(
        !exists<Entity>(entity_address),
        error::invalid_argument(EENTITY_ALREADY_EXISTS),
    );
  }

  fun assert_directory_exists(addr: address) {
    assert!(
      exists<EntityDirectory>(addr),
      error::not_found(EENTITY_DIRECTORY_DOES_NOT_EXIST),
    );
  }

  public (friend) fun get_signer(account: &signer, name: String): signer acquires EntityDirectory, Entity {
    let entity_address = get_address(account, name);
    assert_exists(entity_address);

    let entity_info = borrow_global<Entity>(entity_address);
    let extend_ref = &entity_info.extend_ref;

    object::generate_signer_for_extending(extend_ref)
  }

  public (friend) fun get_signer_from_address(entity_address: address): signer acquires Entity {
    assert_exists(entity_address);

    let entity_info = borrow_global<Entity>(entity_address);
    let extend_ref = &entity_info.extend_ref;

    object::generate_signer_for_extending(extend_ref)
  }

  public (friend) fun get_address(account: &signer, name: String): address acquires EntityDirectory {
    let account_address = signer::address_of(account);
    assert_directory_exists(account_address);

    let directory = borrow_global<EntityDirectory>(account_address);
    let entity_obj = table_with_length::borrow(&directory.entities, name);

    object::object_address(entity_obj)
  }

  public (friend) fun get(entity_address: address): Object<Entity> {
    assert!(
      exists<Entity>(entity_address),
      error::invalid_argument(EENTITY_DOES_NOT_EXIST),
    );
    object::address_to_object<Entity>(entity_address)
  }

  public (friend) fun assert_signer_owns_entity(entity_address: address, owner_address: address) {
    let entity_obj = object::address_to_object<Entity>(entity_address);
    assert!(
        object::is_owner(entity_obj, owner_address),
        error::not_found(ENOT_OWNER),
    );
  }

  // Tests
  #[test_only]
  use std::string;
  #[test_only]
  friend recoop::testing_flow;

  #[test(creator = @recoop)]
  fun test_init_success(creator: &signer) acquires EntityDirectory, Entity {
    init_helper(creator);

    let entity_address = collection::create_collection_address(&signer::address_of(creator), &name_helper());
    assert_exists(entity_address);
    let entity_obj = object::address_to_object<Entity>(entity_address);
    assert!(
      name(entity_obj) == name_helper(), 99
    );
  }

  #[test(creator = @recoop)]
  #[expected_failure]
  fun test_init_fail_entity_exists(creator: &signer) acquires EntityDirectory, Entity {
    init_helper(creator);
    // Failure - Entity already exists
    init_helper(creator);
  }

  #[test_only]
  public(friend) fun init_helper(creator: &signer) acquires EntityDirectory, Entity {
    init(creator, name_helper());
  }

  #[test_only]
  public(friend) fun name_helper(): String {
    string::utf8(b"ReCoop Game")
  }

  #[test_only]
  public(friend) fun init_for_test(creator: &signer):signer acquires EntityDirectory, Entity{
    init_helper(creator);
    get_signer(creator, name_helper())
  }
}
