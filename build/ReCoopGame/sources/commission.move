module recoop::commission {
  use std::option::{Self, Option};
  use std::vector;
  use std::signer;
  use std::error;
  use aptos_std::table_with_length::{Self, TableWithLength};
  use recoop::game_utils;

  friend recoop::game;
  friend recoop::game_item;
  #[test_only]
  friend recoop::testing_flow;

  /// Commission directory already exists on this account
  const ECOMM_DIR_ALREADY_EXISTS: u64 = 1;

  /// Commission directory does not exist on this account
  const ECOMM_DIR_DNE: u64 = 2;

  /// Referral status already exists on this account
  const EREFERRAL_STATUS_ALREADY_EXISTS: u64 = 3;

  /// Recoop is not accepting requests
  const ENOT_ACCEPTING_REQUESTS: u64 = 4;

  /// Referrer has already requested a commission structure
  const EALREADY_REQUESTED: u64 = 5;

  /// Address does not exist on this list
  const EADDRESS_DOES_NOT_EXIST: u64 = 6;

  /// Request has already been answered
  const EREQUEST_ANSWERED: u64 = 7;

  /// Request has not been answered yet
  const EREQUEST_UNANSWERED: u64 = 8;

  /// Request has been denied
  const EREQUEST_DENIED: u64 = 9;

  /// Commission is not active
  const ECOMMISSION_INACTIVE: u64 = 10;

  struct CommissionRate has store, drop, copy {
    numerator: u64,
    denominator: u64,
  }

  struct Threshold has store, drop, copy {
    min_sales: u64,
    rate: CommissionRate
  }

  struct CommissionStructure has key, store {
    thresholds: vector<Threshold>,
    current_sales: u64,
    active: bool,
  }

  struct CommissionDirectory has key {
    commissions: TableWithLength<address, CommissionStructure>,
  }

  struct ReferralStatus has key {
    list: TableWithLength<address, Option<bool>>,
    accepting: bool,
  }

  public (friend) fun init(
    creator: &signer,
  ){
    assert_comm_directory_dne(signer::address_of(creator));
    move_to(creator,
      CommissionDirectory {
        commissions: table_with_length::new()
      }
    );

    assert_referral_status_dne(signer::address_of(creator));
    move_to(creator,
      ReferralStatus {
        list: table_with_length::new(),
        accepting: true,
      }
    );
  }

  public entry fun apply_for_commission(
    referrer: &signer,
    rr_address: address
  ) acquires ReferralStatus {
    let referrer_address = signer::address_of(referrer);
    assert_accepting_requests(rr_address);
    assert_new_request(rr_address, referrer_address);
    add_to_requests(rr_address, referrer_address);
  }

  public entry fun approve_referral_request(
    admin: &signer,
    rr_address: address,
    referrer_address: address,
  ) acquires ReferralStatus {
    game_utils::assert_is_admin(admin);

    let requests = borrow_global_mut<ReferralStatus>(rr_address);
    assert!(
      table_with_length::contains(&requests.list, referrer_address),
      error::not_found(EADDRESS_DOES_NOT_EXIST)
    );

    let current_status = table_with_length::borrow(&requests.list, referrer_address);
    assert!(
      option::is_none(current_status),
      error::not_found(EREQUEST_ANSWERED)
    );

    let current_status_mut = table_with_length::borrow_mut(&mut requests.list, referrer_address);
    option::swap_or_fill(current_status_mut, true);
  }

  public entry fun add_update_commission(
    admin: &signer,
    rr_address: address,
    referrer_address: address,
    numerator: u64,
    denominator: u64,
    min_sales: Option<u64>
  ) acquires CommissionDirectory, ReferralStatus {
    game_utils::assert_is_admin(admin);

    // check for existence of CommissionDirectory on rr_addr
    assert_comm_directory_exists(rr_address);
    let directory = borrow_global_mut<CommissionDirectory>(rr_address);

    // Extract min_sales value, default to 0 if None
    let min_sales_value = if (option::is_some(&min_sales)) {
        *option::borrow(&min_sales)
    } else {
        0
    };

    // Build the commission rate and threshold
    let rate = CommissionRate { numerator, denominator };
    let new_threshold = Threshold {
        min_sales: min_sales_value,
        rate,
    };

    // check for existing CommissionStructure for address
    if (table_with_length::contains(&directory.commissions, referrer_address)){
      let commission_structure = table_with_length::borrow_mut(
        &mut directory.commissions,
        referrer_address
      );

      // Update threshold if it exists
      let found = false;
      let len = vector::length(&commission_structure.thresholds);
      let i = 0;
      while (i < len) {
        let threshold_ref = vector::borrow_mut(&mut commission_structure.thresholds, i);
        if (threshold_ref.min_sales == min_sales_value) {
            // Update the existing rate
            *threshold_ref = copy new_threshold;
            found = true;
            break
        };
        i = i + 1;
      };

      // Add new threshold if it doesn't exist
      if (!found) {
        vector::push_back(&mut commission_structure.thresholds, new_threshold);

        // Sort thresholds based on min_sales
        sort_thresholds(&mut commission_structure.thresholds);
      };
    } else {
      // assert referrer is approved for commission
      let requests = borrow_global<ReferralStatus>(rr_address);
      assert!(
        table_with_length::contains(&requests.list, referrer_address),
        error::not_found(EADDRESS_DOES_NOT_EXIST)
      );

      //assert option is some value
      let current_status = table_with_length::borrow(&requests.list, referrer_address);
      assert!(
        option::is_some(current_status),
        error::not_found(EREQUEST_UNANSWERED)
      );
      assert!(
        *option::borrow(current_status),
        error::invalid_argument(EREQUEST_DENIED)
      );

      // Create new commission structure
      let thresholds = vector::singleton(new_threshold);

      // Build and insert new threshold
      let commission_structure = CommissionStructure {
        thresholds,
        current_sales: 0,
        active: true,
      };

      // Insert into directory.commissions
      table_with_length::add(
        &mut directory.commissions,
        referrer_address,
        commission_structure
      );
    };
  }

  public entry fun update_accepting_status(
    admin: &signer,
    rr_address: address,
    accepting: bool
  ) acquires ReferralStatus {
    game_utils::assert_is_admin(admin);

    let user_requests = borrow_global_mut<ReferralStatus>(rr_address);
    user_requests.accepting = accepting;
  }

  public entry fun update_active_status(
    admin: &signer,
    rr_address: address,
    referrer_address: address,
    active: bool
  ) acquires CommissionDirectory {
    game_utils::assert_is_admin(admin);

    let directory = borrow_global_mut<CommissionDirectory>(rr_address);
    assert!(
      table_with_length::contains(&directory.commissions, referrer_address),
      error::not_found(EADDRESS_DOES_NOT_EXIST)
    );

    let commission_structure = table_with_length::borrow_mut(
      &mut directory.commissions,
      referrer_address
    );

    commission_structure.active = active;
  }

  public (friend) fun assert_valid_commission(
    rr_address: address,
    referrer_address: address
  ) acquires CommissionDirectory {
    let directory = borrow_global<CommissionDirectory>(rr_address);
    assert!(
      table_with_length::contains(&directory.commissions, referrer_address),
      error::not_found(EADDRESS_DOES_NOT_EXIST)
    );

    let commission_structure = table_with_length::borrow(
      &directory.commissions,
      referrer_address
    );

    assert!(
      commission_structure.active,
      error::invalid_argument(ECOMMISSION_INACTIVE)
    );
  }

  public (friend) fun calculate_total(
    rr_address: address,
    referrer_address: address,
    total_quantity: u64,
    total_price: u64
  ): u64 acquires CommissionDirectory {
      let directory = borrow_global<CommissionDirectory>(rr_address);
      assert!(
          table_with_length::contains(&directory.commissions, referrer_address),
          error::not_found(EADDRESS_DOES_NOT_EXIST)
      );

      let commission_structure = table_with_length::borrow(
          &directory.commissions,
          referrer_address
      );

      let thresholds = &commission_structure.thresholds;

      // The referrer's current sales before the purchase
      let previous_sales = commission_structure.current_sales;

      // The total sales after the current purchase
      let new_sales = previous_sales + total_quantity;

      let len = vector::length(thresholds);
      let i = 0;

      // Initialize commission amount
      let commission_amount = 0;

      // The total_price corresponds to total_quantity units
      // Compute the average price per unit
      let average_unit_price = total_price / total_quantity;

      // Remaining quantity to account for
      let remaining_quantity = total_quantity;

      // For each threshold
      while (i < len && remaining_quantity > 0) {
          let threshold = vector::borrow(thresholds, i);

          let start_sales = threshold.min_sales;
          let end_sales = if (i + 1 < len) {
              let next_threshold = vector::borrow(thresholds, i + 1);
              next_threshold.min_sales - 1
          } else {
              // For the last threshold, end_sales is u64::MAX
              0xFFFFFFFFFFFFFFFF
          };

          // Calculate the overlap between previous_sales + 1 and new_sales
          let overlap_start = game_utils::max_u64(previous_sales + 1, start_sales);
          let overlap_end = game_utils::min_u64(new_sales, end_sales);

          if (overlap_start <= overlap_end) {
              let quantity_in_threshold = overlap_end - overlap_start + 1;

              // Ensure quantity_in_threshold does not exceed remaining_quantity
              if (quantity_in_threshold > remaining_quantity) {
                  quantity_in_threshold = remaining_quantity;
              };

              // Commission for this threshold
              let amount_in_threshold = quantity_in_threshold * average_unit_price;
              let commission_for_threshold = (amount_in_threshold * threshold.rate.numerator) / threshold.rate.denominator;

              commission_amount = commission_amount + commission_for_threshold;

              remaining_quantity = remaining_quantity - quantity_in_threshold;
          };

          i = i + 1;
      };

      commission_amount
  }

  public (friend) fun update_current_sales(
    rr_address: address,
    referrer_address: address,
    quantity: u64
  ) acquires CommissionDirectory {
      let directory = borrow_global_mut<CommissionDirectory>(rr_address);
      let commission_structure = table_with_length::borrow_mut(
        &mut directory.commissions,
        referrer_address
      );

      commission_structure.current_sales = commission_structure.current_sales + quantity;
  }

  // Helper functions

  // Helper function to sort thresholds based on min_sales
  fun sort_thresholds(thresholds: &mut vector<Threshold>) {
    let len = vector::length(thresholds);
    let i = 1;
    while (i < len) {
        let j = i;
        while (j > 0) {
            let a = vector::borrow(thresholds, j - 1);
            let b = vector::borrow(thresholds, j);
            if (a.min_sales > b.min_sales) {
                vector::swap(thresholds, j - 1, j);
            } else {
                break
            };
            j = j - 1;
        };
        i = i + 1;
    };
  }

  fun comm_dir_exists(addr: address): bool {
    exists<CommissionDirectory>(addr)
  }

  fun assert_comm_directory_dne(addr: address) {
    assert!(
      !comm_dir_exists(addr),
      error::not_found(ECOMM_DIR_ALREADY_EXISTS),
    );
  }

  fun assert_comm_directory_exists(addr: address) {
    assert!(
      comm_dir_exists(addr),
      error::not_found(ECOMM_DIR_DNE),
    );
  }

  fun comm_str_exists(addr: address): bool {
    exists<CommissionStructure>(addr)
  }

  fun assert_referral_status_dne(addr: address) {
    assert!(
      !referral_status_exists(addr),
      error::not_found(EREFERRAL_STATUS_ALREADY_EXISTS),
    );
  }

  fun referral_status_exists(addr: address): bool {
    exists<ReferralStatus>(addr)
  }

  fun assert_accepting_requests(
    recoop_address: address
  ) acquires ReferralStatus {
    let user_requests = borrow_global<ReferralStatus>(recoop_address);
    assert!(
      user_requests.accepting,
      error::invalid_argument(ENOT_ACCEPTING_REQUESTS)
    );
  }

  fun assert_new_request(
    recoop_address: address,
    referrer_address: address
  ) acquires ReferralStatus {
    let user_requests = borrow_global<ReferralStatus>(recoop_address);
    assert!(
      !table_with_length::contains(&user_requests.list, referrer_address),
      error::invalid_argument(EALREADY_REQUESTED)
    );
  }

  fun add_to_requests(
    recoop_address: address,
    referrer_address: address
  ) acquires ReferralStatus {
    let user_requests = borrow_global_mut<ReferralStatus>(recoop_address);
    table_with_length::add(&mut user_requests.list, referrer_address, option::none());
  }
}
