// Copyright (c) Subsonic Labs, LLC
// SPDX-License-Identifier: Apache-2.0

/// Represents a party's credit on a work or activity.
/// A credit pairs a display name with one or more roles, identifying how
/// a party contributed to the work.
module partyos::credit;

use std::string::String;

// === Structs ===

/// A credit attributing roles to a party on a work.
/// Generic over the role type to support domain-specific roles.
public struct Credit<Role: copy + drop + store> has copy, drop, store {
    /// Human-readable name to display for this credit.
    display_name: String,
    /// Roles assigned to the credited party.
    roles: vector<Role>,
}

// === Constants ===

/// Maximum length of a display name in bytes.
const MAX_DISPLAY_NAME_LENGTH: u64 = 200;

// === Errors ===

// Constraint errors (30-39)
/// Display name exceeds maximum length.
const EMaxDisplayNameLengthExceeded: u64 = 30;
/// String must not be empty.
const EEmptyString: u64 = 31;

// Conflict errors (40-49)
/// Credit contains duplicate roles.
const EDuplicateRoles: u64 = 40;

// === Public Functions ===

/// Creates a new credit with the given display name and roles.
/// Aborts with `EDuplicateRoles` if roles contains duplicates.
public fun new<Role: copy + drop + store>(display_name: String, roles: vector<Role>): Credit<Role> {
    assert!(!display_name.is_empty(), EEmptyString);
    assert!(display_name.length() <= MAX_DISPLAY_NAME_LENGTH, EMaxDisplayNameLengthExceeded);
    let len = roles.length();
    let mut i = 0;
    while (i < len) {
        let mut j = i + 1;
        while (j < len) {
            assert!(&roles[i] != &roles[j], EDuplicateRoles);
            j = j + 1;
        };
        i = i + 1;
    };
    Credit { display_name, roles }
}

// === Public View Functions ===

/// Returns the display name for this credit.
public fun display_name<Role: copy + drop + store>(self: &Credit<Role>): &String {
    &self.display_name
}

/// Returns a reference to the roles assigned in this credit.
public fun roles<Role: copy + drop + store>(self: &Credit<Role>): &vector<Role> {
    &self.roles
}
