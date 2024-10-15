// TODO: add item_statuses to PurchaseEvent and PurchaseItem
// TODO: add functions to update item_statuses and PurchaseEvent.status
// TODO: initiate these updates during cloud function handling of purchase event

module recoop::game_item {
  use aptos_framework::coin;
  use std::signer;
  use std::error;
  use std::string::{Self, String};
  use aptos_std::table_with_length::{Self, TableWithLength};
  use aptos_std::type_info;
  use std::vector;
  use recoop::game_utils;
  use recoop::player;
  use std::option::{Self, Option};
  use recoop::commission;
  // use std::debug;

  #[test_only]
  friend recoop::testing_flow;
  friend recoop::game;

  /// Signer does not own this module
  const ERECEIPT_MAP_ALREADY_EXISTS: u64 = 1;

  /// Signer does not own this module
  const EITEM_MAP_ALREADY_EXISTS: u64 = 2;

  /// Signer does not own this module
  const ECOINTYPE_MISMATCH: u64 = 3;

  /// Signer does not own this module
  const EITEM_QUANTITY_MISMATCH: u64 = 4;

  /// Signer does not own this module
  const EITEM_NOT_FOR_SALE: u64 = 5;

  #[event]
  struct PurchaseEvent has drop, copy, store {
    items: vector<RowItem>,
    total_price: u64,
    // status: 'pending' | 'completed' | 'failed'
  }

  struct RowItem has drop, copy, store {
    name: String,
    item_addresses: vector<address>,
    // item_statuses: vector<string>,
    price_apt: u64,
    quantity: u64
  }

  struct ReceiptMap has key {
    receipts: TableWithLength<u64, PurchaseEvent>
  }

  struct ItemInfo has store {
    price_apt: u64,
    sale_status: bool
  }

  struct ItemMap has key {
    info: TableWithLength<String, ItemInfo>
  }

  public (friend) fun init(
    creator: &signer
  ) {
    init_receipt_map_for_admin(creator);
    init_item_map(creator);
  }

  fun init_receipt_map_for_admin(
    creator: &signer
  ) {
    assert_receipt_map_dne(creator);
    create_receipt_map(creator);
  }

  fun init_item_map(
    creator: &signer
  ) {
    assert_item_map_dne(creator);
    create_item_map(creator);
  }

  fun init_receipt_map_for_buyer(
    buyer: &signer
  ) {
    let buyer_address = signer::address_of(buyer);
    if (!exists<ReceiptMap>(buyer_address)) {
      create_receipt_map(buyer);
    };
  }

  fun create_receipt_map(account: &signer) {
    move_to(account,
      ReceiptMap {
        receipts: table_with_length::new(),
      }
    );
  }

  fun assert_receipt_map_dne(account: &signer) {
    let account_address = signer::address_of(account);
    assert!(
        !exists<ReceiptMap>(account_address),
        error::invalid_argument(ERECEIPT_MAP_ALREADY_EXISTS),
    );
  }

  fun assert_item_map_dne(account: &signer) {
    let account_address = signer::address_of(account);
    assert!(
        !exists<ItemMap>(account_address),
        error::invalid_argument(EITEM_MAP_ALREADY_EXISTS),
    );
  }

  fun create_item_map(account: &signer) {
    move_to(account,
      ItemMap {
        info: table_with_length::new(),
      }
    );
  }

  public entry fun create(
    name: String,
    price_apt: u64,
    sale_status: bool,
    admin: &signer,
    rr_address: address
  ) acquires ItemMap {
    game_utils::assert_is_admin(admin);

    let item_info = ItemInfo {
      price_apt,
      sale_status
    };

    let item_map = borrow_global_mut<ItemMap>(rr_address);
    table_with_length::add(&mut item_map.info, name, item_info);
  }

  public (friend) fun get_price(
    name: String,
    rr_address: address
  ): u64 acquires ItemMap {
    let item_map = borrow_global<ItemMap>(rr_address);
    let item_info = table_with_length::borrow(&item_map.info, name);
    item_info.price_apt
  }

  public fun set_price(
    name: String,
    price_apt: u64,
    admin: &signer,
    rr_address: address
  ) acquires ItemMap {
    game_utils::assert_is_admin(admin);

    let item_map = borrow_global_mut<ItemMap>(rr_address);
    let item_info = table_with_length::borrow_mut(&mut item_map.info, name);
    item_info.price_apt = price_apt;
  }

  public fun set_sale_status(
    name: String,
    sale_status: bool,
    admin: &signer,
    rr_address: address
  ) acquires ItemMap {
    game_utils::assert_is_admin(admin);

    let item_map = borrow_global_mut<ItemMap>(rr_address);
    let item_info = table_with_length::borrow_mut(&mut item_map.info, name);
    item_info.sale_status = sale_status;
  }

  public entry fun buy<CoinType>(
    items: vector<String>,
    quantities: vector<u64>,
    buyer: &signer,
    rr_address: address,
    referrer_address: Option<address>
  ) acquires ItemMap, ReceiptMap {
    // Assert CoinType is Aptos Coin
    assert!(
      type_info::type_name<CoinType>() == string::utf8(b"0x1::aptos_coin::AptosCoin"),
      error::invalid_argument(ECOINTYPE_MISMATCH)
    );

    // Assert items and quantities are the same length
    let len = vector::length(&items);
    assert!(
      len == vector::length(&quantities),
      error::invalid_argument(EITEM_QUANTITY_MISMATCH)
    );

    let item_map = borrow_global<ItemMap>(rr_address);
    let order = vector::empty<RowItem>();
    let total_price = 0;
    let total_quantity = 0;

    // get each item in ordered_items
    let i = 0;
    while (i < len) {
      let name = *vector::borrow(&items, i);
      let quantity = *vector::borrow(&quantities, i);
      let item_info = table_with_length::borrow(&item_map.info, name);

      assert!(
        item_info.sale_status,
        error::invalid_argument(EITEM_NOT_FOR_SALE),
      );

      let price_apt = item_info.price_apt;
      total_price = total_price + (price_apt * quantity);
      total_quantity = total_quantity + quantity;

      let item_addresses = mint_items(buyer, name, quantity, rr_address);

      let row_item = RowItem {
        name,
        item_addresses,
        price_apt,
        quantity
      };

      vector::push_back(&mut order, row_item);
      i = i + 1;
    };

    // transfer commission to referrer
    let commission = 0;

    if (option::is_some(&referrer_address)) {
      let referrer = *option::borrow(&referrer_address);
      commission::assert_valid_commission(rr_address, referrer);

      commission = commission::calculate_total(rr_address, referrer, total_quantity, total_price);
      coin::transfer<CoinType>(buyer, referrer, commission);
      commission::update_current_sales(rr_address, referrer, total_quantity);
    };

    let remaining = total_price - commission;

    // transfer remaining funds to recoop
    coin::transfer<CoinType>(buyer, @recoop, remaining);

    // emit purchase event
    let event = create_purchase_event(order, total_price);

    // add to buyer's receipt map
    init_receipt_map_for_buyer(buyer);
    let receipt_map_buyer = borrow_global_mut<ReceiptMap>(signer::address_of(buyer));
    add_purchase_event_to_receipt_map(receipt_map_buyer, copy event);

    // add to recoops receipt map
    let receipt_map_recoop = borrow_global_mut<ReceiptMap>(rr_address);
    add_purchase_event_to_receipt_map(receipt_map_recoop, copy event);

    0x1::event::emit(event);
  }

  public entry fun buy_v2<CoinType>(
    buyer: &signer,
    items: vector<String>,
    quantities: vector<u64>,
    rr_address: address,
    referrer_address: Option<address>
  ) acquires ItemMap, ReceiptMap {
    // Assert CoinType is Aptos Coin
    assert!(
      type_info::type_name<CoinType>() == string::utf8(b"0x1::aptos_coin::AptosCoin"),
      error::invalid_argument(ECOINTYPE_MISMATCH)
    );

    // Assert items and quantities are the same length
    let len = vector::length(&items);
    assert!(
      len == vector::length(&quantities),
      error::invalid_argument(EITEM_QUANTITY_MISMATCH)
    );

    let item_map = borrow_global<ItemMap>(rr_address);
    let order = vector::empty<RowItem>();
    let total_price = 0;
    let total_quantity = 0;

    // get each item in ordered_items
    let i = 0;
    while (i < len) {
      let name = *vector::borrow(&items, i);
      let quantity = *vector::borrow(&quantities, i);
      let item_info = table_with_length::borrow(&item_map.info, name);

      assert!(
        item_info.sale_status,
        error::invalid_argument(EITEM_NOT_FOR_SALE),
      );

      let price_apt = item_info.price_apt;
      total_price = total_price + (price_apt * quantity);
      total_quantity = total_quantity + quantity;

      let item_addresses = mint_items(buyer, name, quantity, rr_address);

      let row_item = RowItem {
        name,
        item_addresses,
        price_apt,
        quantity
      };

      vector::push_back(&mut order, row_item);
      i = i + 1;
    };

    // transfer commission to referrer
    let commission = 0;

    if (option::is_some(&referrer_address)) {
      let referrer = *option::borrow(&referrer_address);
      commission::assert_valid_commission(rr_address, referrer);

      commission = commission::calculate_total(rr_address, referrer, total_quantity, total_price);
      coin::transfer<CoinType>(buyer, referrer, commission);
      commission::update_current_sales(rr_address, referrer, total_quantity);
    };

    let remaining = total_price - commission;

    // transfer remaining funds to recoop
    coin::transfer<CoinType>(buyer, @recoop, remaining);

    // emit purchase event
    let event = create_purchase_event(order, total_price);

    // add to buyer's receipt map
    init_receipt_map_for_buyer(buyer);
    let receipt_map_buyer = borrow_global_mut<ReceiptMap>(signer::address_of(buyer));
    add_purchase_event_to_receipt_map(receipt_map_buyer, copy event);

    // add to recoops receipt map
    let receipt_map_recoop = borrow_global_mut<ReceiptMap>(rr_address);
    add_purchase_event_to_receipt_map(receipt_map_recoop, copy event);

    0x1::event::emit(event);
  }

  fun create_purchase_event(items: vector<RowItem>, total_price: u64): PurchaseEvent {
    PurchaseEvent {
        items,
        total_price,
    }
  }

  fun add_purchase_event_to_receipt_map(receipt_map: &mut ReceiptMap, event: PurchaseEvent) {
    let len = table_with_length::length(&receipt_map.receipts) + 1;
    table_with_length::add(&mut receipt_map.receipts, len, event);
  }

  fun mint_items(
    buyer: &signer,
    name: String,
    quantity: u64,
    rr_address: address
  ): vector<address> {
    let item_addresses = vector::empty<address>();
    if (name == string::utf8(b"Player")) {
      item_addresses = player::mint_to_buyer(buyer, quantity, rr_address);
    };

    item_addresses
  }
}
