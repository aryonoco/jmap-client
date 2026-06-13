# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailAddress and EmailAddressGroup (scenarios 4-8, 12 + edge cases).

import std/json

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/serde_addresses
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. EmailAddress toJson =============

testCase toJsonEmailAddressWithName: # scenario 4
  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let node = ea.toJson()
  assertJsonFieldEq node, "email", %"joe@example.com"
  assertJsonFieldEq node, "name", %"Joe"

testCase toJsonEmailAddressWithoutName: # scenario 5
  let ea = parseEmailAddress("joe@example.com").get()
  let node = ea.toJson()
  assertJsonFieldEq node, "email", %"joe@example.com"
  let nameField = node{"name"}
  doAssert nameField != nil, "name field must be present"
  doAssert nameField.kind == JNull, "name field must be null"

# ============= B. EmailAddress fromJson =============

testCase fromJsonEmailAddressValidWithName: # scenario 6
  let node = %*{"name": "Joe", "email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  let ea = res.get()
  assertEq ea.email, "joe@example.com"
  assertSomeEq ea.name, "Joe"

testCase fromJsonEmailAddressMissingEmail: # scenario 7
  let node = %*{"name": "Joe"}
  assertErr EmailAddress.fromJson(node)

testCase fromJsonEmailAddressNullEmail: # scenario 8
  let node = %*{"name": "Joe", "email": nil}
  assertErr EmailAddress.fromJson(node)

# ============= C. EmailAddress round-trip =============

testCase roundTripEmailAddressWithName:
  let original = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let roundTripped = EmailAddress.fromJson(original.toJson()).get()
  assertEq roundTripped.email, original.email
  assertSomeEq roundTripped.name, "Joe"

testCase roundTripEmailAddressWithoutName:
  let original = parseEmailAddress("joe@example.com").get()
  let roundTripped = EmailAddress.fromJson(original.toJson()).get()
  assertEq roundTripped.email, original.email
  assertNone roundTripped.name

# ============= D. EmailAddress fromJson edge cases =============

testCase fromJsonEmailAddressNameAbsent:
  let node = %*{"email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  assertNone res.get().name

testCase fromJsonEmailAddressNameNull:
  let node = %*{"name": nil, "email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  assertNone res.get().name

testCase fromJsonEmailAddressNotObject:
  let node = %"just a string"
  assertErr EmailAddress.fromJson(node)

testCase fromJsonEmailAddressEmptyEmail:
  let node = %*{"email": ""}
  assertErr EmailAddress.fromJson(node)

# ============= E. EmailAddressGroup serde =============

testCase roundTripEmailAddressGroupFull: # scenario 12
  let ea1 = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let ea2 = parseEmailAddress("jane@example.com", Opt.some("Jane")).get()
  let group = EmailAddressGroup(name: Opt.some("Team"), addresses: @[ea1, ea2])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertSomeEq roundTripped.name, "Team"
  assertLen roundTripped.addresses, 2
  assertEq roundTripped.addresses[0].email, "joe@example.com"
  assertEq roundTripped.addresses[1].email, "jane@example.com"

testCase roundTripEmailAddressGroupNullName:
  let ea = parseEmailAddress("joe@example.com").get()
  let group = EmailAddressGroup(name: Opt.none(string), addresses: @[ea])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertNone roundTripped.name
  assertLen roundTripped.addresses, 1

testCase roundTripEmailAddressGroupEmptyAddresses:
  let group = EmailAddressGroup(name: Opt.some("Empty"), addresses: @[])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertSomeEq roundTripped.name, "Empty"
  assertLen roundTripped.addresses, 0

testCase fromJsonEmailAddressGroupMissingAddresses:
  let node = %*{"name": "Team"}
  assertErr EmailAddressGroup.fromJson(node)

testCase fromJsonEmailAddressGroupBadElement:
  let node = %*{"name": "Team", "addresses": [{"email": ""}]}
  assertErr EmailAddressGroup.fromJson(node)
