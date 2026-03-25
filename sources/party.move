// Copyright (c) Subsonic Labs, LLC
// SPDX-License-Identifier: Apache-2.0

/// Represents parties (individuals or groups) that participate in on-chain
/// activities. A party is a named entity with capability-based authorization.
///
/// ### Key Features:
///
/// - Individual and group party types
/// - Extensible metadata via dynamic fields
/// - Capability-based authorization for modifications
/// - Groups can contain multiple individual parties
module partyos::party;

use std::string::String;
use sui::derived_object::claim;
use sui::event::emit;
use sui::vec_set::{Self, VecSet};

public use fun party_admin_cap_party_id as PartyAdminCap.party_id;
public use fun party_kind_name as PartyKind.name;

// === Structs ===

/// One-time witness for the party module.
public struct PARTY() has drop;

/// A party in the ecosystem. Can represent an individual or a group of parties.
public struct Party has key {
    /// Unique identifier for this party.
    id: UID,
    /// Whether this is an individual or group party.
    kind: PartyKind,
    /// Human-readable name of the party.
    /// Note this name is not "official" or "verified" in any way.
    /// Verification should be performed by the application layer.
    name: String,
}

/// Capability that authorizes modifications to a specific party.
/// Created when a party is registered and transferred to the owner.
public struct PartyAdminCap has key, store {
    /// Unique identifier for this capability.
    id: UID,
    /// ID of the party this capability controls.
    party_id: ID,
}

// === Derivation Keys ===

/// Key for deriving the admin capability's deterministic address.
public struct PartyAdminCapKey(
    /// ID of the party.
    ID,
) has copy, drop, store;

// === Enums ===

/// The type of self: individual person or group.
public enum PartyKind has copy, drop, store {
    /// A single person (artist, producer, etc.).
    Individual,
    /// A group containing multiple individual parties.
    Group(
        /// Set of individual party IDs in this group.
        VecSet<ID>,
    ),
}

// === Events ===

public struct PartyCreatedEvent has copy, drop {
    /// ID of the newly created party.
    party_id: ID,
    /// Name of the party.
    name: String,
    /// Kind of the party.
    kind: String,
    /// Address of the creator.
    created_by: address,
}

public struct PartyNameSetEvent has copy, drop {
    /// ID of the party.
    party_id: ID,
    /// Name of the party.
    name: String,
}

/// Emitted when a party is added to a group.
public struct PartyAddedToGroupEvent has copy, drop {
    /// ID of the group.
    group_id: ID,
    /// ID of the party added to the group.
    member_id: ID,
}

/// Emitted when a party is removed from a group.
public struct PartyRemovedFromGroupEvent has copy, drop {
    /// ID of the group.
    group_id: ID,
    /// ID of the party removed from the group.
    member_id: ID,
}

// === Constants ===

/// Maximum number of members allowed in a group.
const MAX_GROUP_MEMBERS: u64 = 200;
/// Maximum length of a party name in bytes.
const MAX_NAME_LENGTH: u64 = 200;

// === Errors ===

// Authorization errors (0-9)
/// The provided admin capability does not match this party.
const EUnauthorized: u64 = 0;

// State errors (10-19)
/// Operation requires an individual party, but a group was provided.
const ENotIndividualKind: u64 = 10;
/// Operation requires a group party, but an individual was provided.
const ENotGroupKind: u64 = 11;

// Constraint errors (30-39)
/// Group has too many members.
const EMaxGroupMembersExceeded: u64 = 30;
/// Name exceeds maximum length.
const EMaxNameLengthExceeded: u64 = 31;
/// String must not be empty.
const EEmptyString: u64 = 32;

// Conflict errors (40-49)
/// Attempted to add a party that is already a member of the group.
const EDuplicateParty: u64 = 40;
/// Attempted to add a group as a member of itself.
const ECantAddSelfAsMember: u64 = 41;

// === Public Functions ===

/// Creates a new party with the specified kind and name.
/// Returns the admin capability for managing the party.
/// The party is shared and starts in the Created state.
public fun new(kind: PartyKind, name: String, ctx: &mut TxContext): (Party, PartyAdminCap) {
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);

    let mut party = Party {
        id: object::new(ctx),
        kind,
        name,
    };

    let party_id = party.id();

    let party_admin_cap = PartyAdminCap {
        id: claim(&mut party.id, PartyAdminCapKey(party_id)),
        party_id,
    };

    emit(PartyCreatedEvent {
        party_id: party.id(),
        name,
        kind: party.kind.name(),
        created_by: ctx.sender(),
    });

    (party, party_admin_cap)
}

/// Shares the party object, making it publicly accessible.
/// Requires the admin capability.
public fun share(self: Party, cap: &PartyAdminCap) {
    self.authorize(cap);
    transfer::share_object(self);
}

/// Sets the human-readable name of the party.
/// Requires the admin capability.
public fun set_name(self: &mut Party, cap: &PartyAdminCap, name: String) {
    self.authorize(cap);
    assert!(!name.is_empty(), EEmptyString);
    assert!(name.length() <= MAX_NAME_LENGTH, EMaxNameLengthExceeded);
    self.name = name;

    emit(PartyNameSetEvent {
        party_id: self.id(),
        name,
    });
}

/// Adds an individual party to a group.
/// Requires the admin capability for the group.
/// The party being added must be an individual (not another group).
public fun add_party(self: &mut Party, cap: &PartyAdminCap, member: &Party) {
    self.authorize(cap);

    let group_id = self.id();
    let member_id = member.id();

    match (&mut self.kind) {
        PartyKind::Group(parties) => {
            assert!(parties.length() < MAX_GROUP_MEMBERS, EMaxGroupMembersExceeded);

            // Assert the party being added is not the group itself.
            assert!(member_id != group_id, ECantAddSelfAsMember);
            // Assert the party that is being added is an individual.
            member.assert_is_individual_kind();
            // Assert the party that is being added is not already a member of the group.
            assert!(!parties.contains(&member_id), EDuplicateParty);
            // Add the party to the group.
            parties.insert(member_id);

            emit(PartyAddedToGroupEvent {
                group_id,
                member_id,
            });
        },
        _ => abort ENotGroupKind,
    }
}

/// Removes a party from a group by their ID.
/// Requires the admin capability for the group.
public fun remove_party(self: &mut Party, cap: &PartyAdminCap, member_id: ID) {
    self.authorize(cap);

    match (&mut self.kind) {
        PartyKind::Group(members) => {
            members.remove(&member_id);

            emit(PartyRemovedFromGroupEvent {
                group_id: self.id(),
                member_id,
            });
        },
        _ => abort ENotGroupKind,
    }
}

/// Creates a new individual party kind.
public fun new_individual_kind(): PartyKind {
    PartyKind::Individual
}

/// Creates a new group party kind with an empty member set.
public fun new_group_kind(): PartyKind {
    PartyKind::Group(vec_set::empty())
}

// === Public View Functions ===

/// Returns the ID of this party.
public fun id(self: &Party): ID {
    self.id.to_inner()
}

/// Returns the human-readable name of this party.
public fun name(self: &Party): String {
    self.name
}

/// Returns true if this party is an individual.
public fun is_individual_kind(self: &Party): bool {
    match (&self.kind) {
        PartyKind::Individual => true,
        _ => false,
    }
}

/// Returns true if this party is a group.
public fun is_group_kind(self: &Party): bool {
    match (&self.kind) {
        PartyKind::Group(_) => true,
        _ => false,
    }
}

/// Returns a reference to the group members.
/// Aborts if this party is not a group.
public fun group_members(self: &Party): &VecSet<ID> {
    match (&self.kind) {
        PartyKind::Group(members) => members,
        _ => abort ENotGroupKind,
    }
}

/// Returns the human-readable name of the party kind.
public fun party_kind_name(self: &PartyKind): String {
    match (self) {
        PartyKind::Individual => "Individual",
        PartyKind::Group(_) => "Group",
    }
}

/// Verifies that the admin capability matches this party.
public fun authorize(self: &Party, cap: &PartyAdminCap) {
    assert!(cap.party_id == self.id(), EUnauthorized);
}

/// Returns the ID of the party associated with the admin capability.
public fun party_admin_cap_party_id(cap: &PartyAdminCap): ID {
    cap.party_id
}

// === UID Functions ===

/// Returns a reference to the party's UID for reading dynamic fields.
/// Requires the admin capability.
public fun uid(self: &Party): &UID {
    &self.id
}

/// Returns a mutable reference to the party's UID for dynamic field operations.
/// Requires the admin capability.
public fun uid_mut(self: &mut Party, cap: &PartyAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Assert Functions ===

/// Aborts if this party is not an individual.
public fun assert_is_individual_kind(self: &Party) {
    assert!(is_individual_kind(self), ENotIndividualKind);
}

/// Aborts if this party is not a group.
public fun assert_is_group_kind(self: &Party) {
    assert!(is_group_kind(self), ENotGroupKind);
}

// === Test Only ===

#[test_only]
public fun new_group_with_n_members_for_testing(
    n: u64,
    ctx: &mut TxContext,
): (Party, PartyAdminCap) {
    let mut members = vec_set::empty();
    n.do!(|_| {
        let uid = object::new(ctx);
        let id = uid.to_inner();
        uid.delete();
        members.insert(id);
    });

    let mut party = Party {
        id: object::new(ctx),
        kind: PartyKind::Group(members),
        name: b"Test Group".to_string(),
    };

    let party_id = party.id();

    let party_admin_cap = PartyAdminCap {
        id: claim(&mut party.id, PartyAdminCapKey(party_id)),
        party_id,
    };

    (party, party_admin_cap)
}
