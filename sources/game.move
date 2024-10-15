module recoop::game {
  use recoop::game_utils;
  use std::signer;
  use recoop::game_entity;
  use recoop::game_collection;
  use recoop::player;
  use recoop::game_item;
  use recoop::game_dollar;
  use recoop::commission;
  use std::string;

  #[test_only]
  friend recoop::testing_flow;

  public entry fun init(
    admin: &signer
  ) {
    // assert admin is recoop_game
    game_utils::assert_is_admin(admin);

    // init recoop game entity
    game_entity::init(admin, string::utf8(b"recoop"));
    let rr_signer = game_entity::get_signer(admin, string::utf8(b"recoop"));

    // init player collection
    game_collection::init(
      &rr_signer,
      string::utf8(b"Players"),
      // TODO: update description and player card usage rights
      string::utf8(b"Player card usage rights."),
      // TODO: update URI?
      string::utf8(b"recooprentals.com"),
      // TODO: update collection royalty
      2,
      100,
    );

    // init in-game currency
    game_dollar::init(&rr_signer);

    // init player directory
    player::init(&rr_signer);

    // init ItemMap
    game_item::init(&rr_signer);

    // init Item - Player and set price
    game_item::create(string::utf8(b"Player"), 100000000, true, admin, signer::address_of(&rr_signer));

    // init CommissionDirectory
    commission::init(&rr_signer);
  }
}
