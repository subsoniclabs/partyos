#[test_only]
module partyos::party_tests;

use partyos::party;
use partyos::test_helpers;
use std::unit_test::{assert_eq, destroy};

// Error codes from party.move
const EUnauthorized: u64 = 0;
const ENotIndividualKind: u64 = 10;
const ENotGroupKind: u64 = 11;
const EMaxGroupMembersExceeded: u64 = 30;
const EMaxNameLengthExceeded: u64 = 31;
const EEmptyString: u64 = 32;
const EDuplicateParty: u64 = 40;

// Must match party.move
const MAX_NAME_LENGTH: u64 = 200;
const MAX_GROUP_MEMBERS: u64 = 200;

// === Individual Party ===

#[test]
fun test_new_individual() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::individual(ctx);
    assert_eq!(party.name(), b"Test Artist".to_string());
    assert!(party.is_individual_kind());
    assert!(!party.is_group_kind());
    destroy(party);
    destroy(cap);
}

#[test]
fun test_new_individual_with_max_name() {
    let ctx = &mut tx_context::dummy();
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    let (party, cap) = test_helpers::individual_named(name, ctx);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    destroy(party);
    destroy(cap);
}

// === Group Party ===

#[test]
fun test_new_group() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::group(ctx);
    assert!(party.is_group_kind());
    assert!(!party.is_individual_kind());
    assert!(party.group_members().is_empty());
    destroy(party);
    destroy(cap);
}

#[test]
fun test_add_party_to_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (individual, individual_cap) = test_helpers::individual(ctx);

    let party_id = individual.id();
    group.add_party(&group_cap, &individual);

    assert_eq!(group.group_members().length(), 1);
    assert!(group.group_members().contains(&party_id));

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

#[test]
fun test_add_multiple_parties_to_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (ind1, cap1) = test_helpers::individual_named(b"Artist 1".to_string(), ctx);
    let (ind2, cap2) = test_helpers::individual_named(b"Artist 2".to_string(), ctx);
    let (ind3, cap3) = test_helpers::individual_named(b"Artist 3".to_string(), ctx);

    group.add_party(&group_cap, &ind1);
    group.add_party(&group_cap, &ind2);
    group.add_party(&group_cap, &ind3);

    assert_eq!(group.group_members().length(), 3);

    destroy(group);
    destroy(group_cap);
    destroy(ind1);
    destroy(cap1);
    destroy(ind2);
    destroy(cap2);
    destroy(ind3);
    destroy(cap3);
}

#[test]
fun test_remove_party_from_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (individual, individual_cap) = test_helpers::individual(ctx);

    let party_id = individual.id();
    group.add_party(&group_cap, &individual);
    assert_eq!(group.group_members().length(), 1);

    group.remove_party(&group_cap, party_id);
    assert_eq!(group.group_members().length(), 0);

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

// === Set Name ===

#[test]
fun test_set_name() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, b"New Name".to_string());
    assert_eq!(party.name(), b"New Name".to_string());
    destroy(party);
    destroy(cap);
}

#[test]
fun test_set_name_at_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    let name = test_helpers::long_string(MAX_NAME_LENGTH);
    party.set_name(&cap, name);
    assert_eq!(party.name().length(), MAX_NAME_LENGTH);
    destroy(party);
    destroy(cap);
}

// === Boundary Tests ===

#[test, expected_failure(abort_code = EMaxGroupMembersExceeded, location = partyos::party)]
fun test_add_party_exceeds_max_group_members() {
    let ctx = &mut tx_context::dummy();
    // Create a group pre-filled with MAX_GROUP_MEMBERS members
    let (mut group, group_cap) = party::new_group_with_n_members_for_testing(MAX_GROUP_MEMBERS, ctx);

    // Adding one more should fail
    let (individual, individual_cap) = test_helpers::individual(ctx);
    group.add_party(&group_cap, &individual);

    destroy(individual);
    destroy(individual_cap);
    destroy(group);
    destroy(group_cap);
}

// === Error Conditions ===

#[test, expected_failure(abort_code = EEmptyString, location = partyos::party)]
fun test_new_empty_name() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(party::new_individual_kind(), b"".to_string(), ctx);
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = EMaxNameLengthExceeded, location = partyos::party)]
fun test_new_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = party::new(
        party::new_individual_kind(),
        test_helpers::long_string(MAX_NAME_LENGTH + 1),
        ctx,
    );
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = EEmptyString, location = partyos::party)]
fun test_set_name_empty() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, b"".to_string());
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = EMaxNameLengthExceeded, location = partyos::party)]
fun test_set_name_too_long() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    party.set_name(&cap, test_helpers::long_string(MAX_NAME_LENGTH + 1));
    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = EDuplicateParty, location = partyos::party)]
fun test_add_party_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut group, group_cap) = test_helpers::group(ctx);
    let (individual, individual_cap) = test_helpers::individual(ctx);

    group.add_party(&group_cap, &individual);
    group.add_party(&group_cap, &individual); // duplicate

    destroy(group);
    destroy(group_cap);
    destroy(individual);
    destroy(individual_cap);
}

#[test, expected_failure(abort_code = ENotGroupKind, location = partyos::party)]
fun test_add_party_to_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::individual(ctx);
    let (party2, cap2) = test_helpers::individual(ctx);

    party1.add_party(&cap1, &party2);

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = ENotIndividualKind, location = partyos::party)]
fun test_add_group_to_group() {
    let ctx = &mut tx_context::dummy();
    let (mut group1, cap1) = test_helpers::group(ctx);
    let (group2, cap2) = test_helpers::group(ctx);

    group1.add_party(&cap1, &group2);

    destroy(group1);
    destroy(cap1);
    destroy(group2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun test_unauthorized_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut party1, cap1) = test_helpers::individual(ctx);
    let (party2, cap2) = test_helpers::individual(ctx);

    // Try to use party2's cap on party1
    party1.set_name(&cap2, b"Hacked".to_string());

    destroy(party1);
    destroy(cap1);
    destroy(party2);
    destroy(cap2);
}

#[test, expected_failure(abort_code = ENotGroupKind, location = partyos::party)]
fun test_remove_party_from_individual() {
    let ctx = &mut tx_context::dummy();
    let (mut party, cap) = test_helpers::individual(ctx);
    let fake_id = test_helpers::fake_id(ctx);

    party.remove_party(&cap, fake_id);

    destroy(party);
    destroy(cap);
}

#[test, expected_failure(abort_code = ENotGroupKind, location = partyos::party)]
fun test_group_members_on_individual() {
    let ctx = &mut tx_context::dummy();
    let (party, cap) = test_helpers::individual(ctx);

    party.group_members(); // should abort

    destroy(party);
    destroy(cap);
}
