module recoop::testing_flow {
  #[test_only]
  use recoop::game;
  #[test_only]
  use recoop::game_entity;
  #[test_only]
  use recoop::player;
  // #[test_only]
  // use recoop::game_utils;
  #[test_only]
  use recoop::commission;
  #[test_only]
  use recoop::game_dollar;
  #[test_only]
  use recoop::game_item::{Self, PurchaseEvent};
  #[test_only]
  use std::string::{Self};
  #[test_only]
  use aptos_framework::aptos_coin::{Self, AptosCoin};
  #[test_only]
  use aptos_framework::account;
  #[test_only]
  use std::signer;
  #[test_only]
  use aptos_framework::event;
  #[test_only]
  use std::vector;
  #[test_only]
  use aptos_framework::coin;
  #[test_only]
  use std::option;
  // #[test_only]
  // use std::debug;
  #[test_only]
  use aptos_framework::object;
  #[test_only]
  use aptos_framework::primary_fungible_store;
  // #[test_only]
  // use aptos_token_objects::token;

  #[test(admin = @recoop, buyer = @0x845, aptos_framework = @0x1, referrer = @0x743)]
  fun test_recoop_flow (
    admin: &signer,
    buyer: &signer,
    aptos_framework: &signer,
    referrer: &signer
  ) {
    // init recoop entity, init player collection, init price directory, init commission directory
    game::init(admin);
    let rr_address = game_entity::get_address(admin, string::utf8(b"recoop"));
    let buyer_addr = signer::address_of(buyer);

    // create APT
    account::create_account_for_test(buyer_addr);
    account::create_account_for_test(signer::address_of(admin));
    account::create_account_for_test(signer::address_of(aptos_framework));
    account::create_account_for_test(signer::address_of(referrer));

    let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
    coin::register<AptosCoin>(buyer);
    coin::register<AptosCoin>(admin);
    coin::register<AptosCoin>(referrer);

    aptos_coin::mint(aptos_framework, buyer_addr, 400000000);
    coin::destroy_burn_cap(burn_cap);
    coin::destroy_mint_cap(mint_cap);

    // purchase 2 player
    let items = vector::singleton(string::utf8(b"Player"));
    let quantities = vector::singleton(2);
    game_item::buy_v2<AptosCoin>(buyer, items, quantities, rr_address, option::none());

    // assert balance change for admin
    assert!(
      coin::balance<AptosCoin>(signer::address_of(admin)) == 200000000,
      99
    );

    // assert balance change for buyer
    assert!(
      coin::balance<AptosCoin>(buyer_addr) == 200000000,
      98
    );

    // check event was emitted
    let module_events = event::emitted_events<PurchaseEvent>();
    assert!(vector::length(&module_events) == 1, 0);

    player::update_properties_v2(
      admin,
      @0xe46a3c36283330c97668b5d4693766b8626420a5701c18eb64026075c3ec8a0a,
      string::utf8(b"Charles"),
      string::utf8(b"Rapper"),
      string::utf8(b"This is my backstory"),
      string::utf8(b"www.google.com"),
      100000000
    );

    // stake player
    player::toggle_staking(admin, rr_address);
    player::stake(buyer, rr_address, @0xe46a3c36283330c97668b5d4693766b8626420a5701c18eb64026075c3ec8a0a);
    let player_obj = player::get_player_from_address(@0xe46a3c36283330c97668b5d4693766b8626420a5701c18eb64026075c3ec8a0a);
    assert!(
      !object::ungated_transfer_allowed(player_obj),
      97
    );

    // payday
    player::payday(admin, rr_address);

    // assert paid
    let dollar_address = game_dollar::get_address(rr_address);
    let dollar = game_dollar::get_metadata(dollar_address);
    let buyer_dlr_balance = primary_fungible_store::balance(signer::address_of(buyer), dollar);
    // get player salary
    let revenue_yr = player::get_revenue(player_obj);
    let revenue_qtr = revenue_yr / 4;
    assert!(
      buyer_dlr_balance == revenue_qtr,
      96
    );

    player::unstake(buyer, @0xe46a3c36283330c97668b5d4693766b8626420a5701c18eb64026075c3ec8a0a);
    // assert unstaked
    assert!(
      object::ungated_transfer_allowed(player_obj),
      95
    );

    // payday
    player::payday(admin, rr_address);

    // assert no balance change
    let new_buyer_dlr_balance = primary_fungible_store::balance(signer::address_of(buyer), dollar);
    assert!(
      buyer_dlr_balance == new_buyer_dlr_balance,
      94
    );

    // apply for commission
    commission::apply_for_commission(referrer, rr_address);

    // server accepts commission
    commission::approve_referral_request(admin, rr_address, signer::address_of(referrer));

    // create commission structure
    commission::add_update_commission(admin, rr_address, signer::address_of(referrer), 1, 100, option::none());

    // buy player with referral code
    game_item::buy_v2<AptosCoin>(buyer, items, quantities, rr_address, option::some(signer::address_of(referrer)));

    // assert balance change for referrer
    assert!(
      coin::balance<AptosCoin>(signer::address_of(referrer)) == 2000000,
      93
    );

    // update accepting status
    commission::update_accepting_status(admin, rr_address, false);

    // request will fail
    // commission::apply_for_commission(buyer, rr_address);

    // update active status
    commission::update_active_status(admin, rr_address, signer::address_of(referrer), false);

    // purchase with referral will fail
    // game_item::buy<AptosCoin>(items, quantities, buyer, rr_address, option::some(signer::address_of(referrer)));
  }
}
