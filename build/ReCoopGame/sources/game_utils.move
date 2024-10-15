module recoop::game_utils {
  use std::signer;
  use std::error;
  #[test_only]
  use std::string::{String};
  #[test_only]
  use aptos_token_objects::token;

  /// Signer does not own this module
  const ENOT_RECOOP: u64 = 1;

  friend recoop::game_item;
  friend recoop::game;
  friend recoop::player;
  friend recoop::commission;
  friend recoop::game_dollar;
  #[test_only]
  friend recoop::testing_flow;

  public (friend) fun assert_is_admin(admin: &signer) {
    assert!(
      signer::address_of(admin) == @recoop,
      error::permission_denied(ENOT_RECOOP)
    );
  }

  #[test_only]
  public (friend) fun get_address_for_test(
    entity_addr: address,
    collection: String,
    token_name: String
  ): address {
    token::create_token_address(
      &entity_addr,
      &collection,
      &token_name
    )
  }

  public (friend) fun max_u64(a: u64, b: u64): u64 {
    if (a > b) {
        a
    } else {
        b
    }
  }

  public (friend) fun min_u64(a: u64, b: u64): u64 {
      if (a < b) {
          a
      } else {
          b
      }
  }
}
