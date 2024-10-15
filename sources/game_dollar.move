module recoop::game_dollar {
  use aptos_framework::fungible_asset::{
    Self,
    BurnRef,
    MintRef,
    Metadata,
  };
  use aptos_framework::primary_fungible_store;
  use std::option;
  use std::string;
  use std::signer;
  use aptos_framework::object::{Self, Object};
  use recoop::game_utils;

  friend recoop::game;
  friend recoop::player;
  #[test_only]
  friend recoop::testing_flow;

  /// Dollar Coin does not exist at this address
  const ECOIN_STORE_DOES_NOT_EXIST: u64 = 1;

  struct Dollar has key {}

  struct DollarRef has key {
    dlr_addr: address
  }

  struct MintRefStore has key {
      mint_ref: MintRef,
  }

  struct BurnRefStore has key {
      burn_ref: BurnRef,
  }

  public (friend) fun init(
    creator: &signer
  ) {
    // Create named object
    let ref = object::create_named_object(creator, b"Dollar");
    // Move coin struct to object
    let object_signer = object::generate_signer(&ref);
    move_to(&object_signer, Dollar {});

    // initialize metadata
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      &ref,
      option::none(),
      string::utf8(b"Dollar"),
      string::utf8(b"DLR"),
      3,
      string::utf8(b"http://www.recooprentals.com/icon"),
      string::utf8(b"http://recooprentals.com"),
    );

    // get references
    let mint_ref = fungible_asset::generate_mint_ref(&ref);
    let burn_ref = fungible_asset::generate_burn_ref(&ref);

    // Store references
    move_to(&object_signer, MintRefStore { mint_ref });
    move_to(&object_signer, BurnRefStore { burn_ref });
    move_to(creator, DollarRef {
        dlr_addr: signer::address_of(&object_signer)
      }
    );
  }

  public entry fun mint_from_server (
    admin: &signer,
    dlr_addr: address,
    to_addr: address,
    amount: u64
  ) acquires MintRefStore {
    game_utils::assert_is_admin(admin);

    mint(dlr_addr, to_addr, amount);
  }

  public (friend) fun mint(
    dlr_addr: address,
    to_addr: address,
    amount: u64,
  ) acquires MintRefStore {
    let ref_store = borrow_global<MintRefStore>(dlr_addr);
    primary_fungible_store::mint(&ref_store.mint_ref, to_addr, amount);
  }

  public (friend) fun get_metadata(
    dlr_addr: address
  ): Object<Metadata> {
    object::address_to_object<Metadata>(dlr_addr)
  }

  public (friend) fun get_address(
    creator: address
  ):address acquires DollarRef {
    borrow_global<DollarRef>(creator).dlr_addr
  }

  // Testing
  #[test_only]
  use aptos_framework::account;

  #[test(recoop_admin = @recoop)]
  fun test_init_success(
    recoop_admin: &signer
  ) acquires DollarRef {
    init_helper(recoop_admin);
    let admin_addr = signer::address_of(recoop_admin);
    assert!(
      exists<DollarRef>(admin_addr),
      99
    );
    let dlr_ref = borrow_global<DollarRef>(admin_addr);
    assert!(
      exists<Dollar>(dlr_ref.dlr_addr),
      98
    );
    assert!(
      exists<MintRefStore>(dlr_ref.dlr_addr),
      97
    );
    assert!(
      exists<BurnRefStore>(dlr_ref.dlr_addr),
      96
    );
  }

  #[test_only]
  public (friend) fun init_helper(
    recoop_admin: &signer
  ){
    let admin_addr = signer::address_of(recoop_admin);
    if(!account::exists_at(admin_addr)){
      account::create_account_for_test(admin_addr);
    };
    init(recoop_admin);
  }

  #[test_only]
  public (friend) fun mint_helper(
    recoop_admin: &signer,
    minter: &signer,
    amount: u64
  ) acquires DollarRef, MintRefStore {
    let minter_addr = signer::address_of(minter);
    account::create_account_for_test(minter_addr);

    let admin_addr = signer::address_of(recoop_admin);
    let dlr_ref = borrow_global<DollarRef>(admin_addr);

    mint(
      dlr_ref.dlr_addr,
      signer::address_of(minter),
      amount
    );
  }
}
