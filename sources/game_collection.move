module recoop::game_collection {
  use std::error;
  use std::signer;
  use std::option::{Self};
  use std::string::{String};
  use aptos_std::table_with_length::{Self, TableWithLength};
  use aptos_framework::object::{Self, Object};
  use aptos_token_objects::collection::{Collection};
  use aptos_token_objects::royalty::{Self};
  use aptos_token_objects::collection::{Self};

  friend recoop::game;
  friend recoop::player;

  /// The collection already exists
  const ECOLLECTION_ALREADY_EXISTS: u64 = 1;

  struct CollectionDirectory has key {
    collections: TableWithLength<String, Object<Collection>>,
  }

  public entry fun init(
    creator: &signer,
    collection_name: String,
    collection_description: String,
    collection_uri: String,
    numerator: u64,
    denominator: u64,
  ) acquires CollectionDirectory {
    assert!(
      !collection_exists(signer::address_of(creator), collection_name),
      error::invalid_argument(ECOLLECTION_ALREADY_EXISTS),
    );
    let init_royalty = royalty::create(
      numerator,
      denominator,
      signer::address_of(creator)
    );
    let constructor_ref = collection::create_unlimited_collection(
      creator,
      collection_description,
      collection_name,
      option::some(init_royalty),
      collection_uri,
    );

    let collection = object::object_from_constructor_ref(&constructor_ref);

    create_add_directory(creator, collection);
  }

  // Helper functions

  public (friend) fun create_add_directory(
    account: &signer,
    collection: Object<Collection>
  ) acquires CollectionDirectory {
    let account_address = signer::address_of(account);
    if (!directory_exists(account_address)) {
      move_to(account,
        CollectionDirectory {
          collections: table_with_length::new(),
        }
      )
    };
    let directory = borrow_global_mut<CollectionDirectory>(account_address);
    table_with_length::add(
      &mut directory.collections,
      collection::name(collection),
      collection,
    );
  }

  public (friend) fun get(
    addr: address,
    name: String,
  ): Object<Collection> acquires CollectionDirectory {
    let directory = borrow_global<CollectionDirectory>(addr);
    *table_with_length::borrow(&directory.collections, name)
  }

  public (friend) fun directory_exists(addr: address): bool {
    exists<CollectionDirectory>(addr)
  }

  public (friend) fun collection_exists(
    addr: address,
    name: String
  ): bool acquires CollectionDirectory {
    if (!directory_exists(addr)) {
      return false
    };
    let directory = borrow_global<CollectionDirectory>(addr);
    table_with_length::contains(&directory.collections, name)
  }

  // Tests
  #[test_only]
  use std::string;
  #[test_only]
  use recoop::game_entity;

  #[test(creator = @recoop)]
  fun test_init_success(creator: &signer) acquires CollectionDirectory {
    game_entity::init_helper(creator);
    let entity_address = game_entity::get_address(creator, game_entity::name_helper());
    let entity_signer = game_entity::get_signer_from_address(entity_address);
    init_helper(&entity_signer);
    init_helper_two(&entity_signer);
    let collection_address = collection::create_collection_address(&entity_address, &name_helper());
    let collection_obj = object::address_to_object<Collection>(collection_address);

    assert!(
      collection::name(collection_obj) == name_helper(),
      99
    );
  }

  #[test(creator = @recoop)]
  #[expected_failure]
  fun test_init_fail_collection_exists(creator: &signer) acquires CollectionDirectory {
    game_entity::init_helper(creator);
    init_helper(creator);
    init_helper(creator);
  }

  #[test_only]
  public (friend) fun init_helper(creator: &signer) acquires CollectionDirectory {
    init(
      creator,
      name_helper(),
      description_helper(),
      uri_helper(),
      1,
      100,
    );
  }

  #[test_only]
  public (friend) fun init_helper_two(creator: &signer) acquires CollectionDirectory {
    init(
      creator,
      name_helper_two(),
      description_helper(),
      uri_helper(),
      1,
      100,
    );
  }

  #[test_only]
  public (friend) fun name_helper(): String {
    string::utf8(b"ReCoop Passes")
  }

  #[test_only]
  public (friend) fun name_helper_two(): String {
    string::utf8(b"Gold Passes")
  }

  #[test_only]
  fun description_helper(): String {
    string::utf8(b"ReCoop your Rent, today.")
  }

  #[test_only]
  fun uri_helper(): String {
    string::utf8(b"recooprentals.com")
  }
}
