# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for EmailAddress and EmailAddressGroup types (scenarios 1-3, 9-11).

import jmap_client/mail/addresses
import jmap_client/validation

import ../../massertions

# ============= A. parseEmailAddress =============

block parseEmailAddressValid: # scenario 1
  let res = parseEmailAddress("joe@example.com")
  assertOk res
  let ea = res.get()
  assertEq ea.email, "joe@example.com"
  assertNone ea.name

block parseEmailAddressWithName: # scenario 2
  let res = parseEmailAddress("joe@example.com", Opt.some("Joe"))
  assertOk res
  let ea = res.get()
  assertEq ea.email, "joe@example.com"
  assertSomeEq ea.name, "Joe"

block parseEmailAddressEmpty: # scenario 3
  assertErrFields parseEmailAddress(""), "EmailAddress", "email must not be empty", ""

# ============= B. EmailAddressGroup construction =============

block emailAddressGroupWithNameAndAddresses: # scenario 9
  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let group = EmailAddressGroup(name: Opt.some("Team"), addresses: @[ea])
  assertSomeEq group.name, "Team"
  assertLen group.addresses, 1
  assertEq group.addresses[0].email, "joe@example.com"

block emailAddressGroupNullName: # scenario 10
  let group = EmailAddressGroup(name: Opt.none(string), addresses: @[])
  assertNone group.name

block emailAddressGroupEmptyAddresses: # scenario 11
  let group = EmailAddressGroup(name: Opt.some("Empty Group"), addresses: @[])
  assertLen group.addresses, 0
