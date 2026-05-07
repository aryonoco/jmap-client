# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailAddress and EmailAddressGroup (scenarios 4-8, 12 + edge cases).

import std/json

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/serde_addresses
import jmap_client/internal/types/validation

import ../../massertions

# ============= A. EmailAddress toJson =============

block toJsonEmailAddressWithName: # scenario 4
  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let node = ea.toJson()
  assertJsonFieldEq node, "email", %"joe@example.com"
  assertJsonFieldEq node, "name", %"Joe"

block toJsonEmailAddressWithoutName: # scenario 5
  let ea = parseEmailAddress("joe@example.com").get()
  let node = ea.toJson()
  assertJsonFieldEq node, "email", %"joe@example.com"
  let nameField = node{"name"}
  doAssert nameField != nil, "name field must be present"
  doAssert nameField.kind == JNull, "name field must be null"

# ============= B. EmailAddress fromJson =============

block fromJsonEmailAddressValidWithName: # scenario 6
  let node = %*{"name": "Joe", "email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  let ea = res.get()
  assertEq ea.email, "joe@example.com"
  assertSomeEq ea.name, "Joe"

block fromJsonEmailAddressMissingEmail: # scenario 7
  let node = %*{"name": "Joe"}
  assertErr EmailAddress.fromJson(node)

block fromJsonEmailAddressNullEmail: # scenario 8
  let node = %*{"name": "Joe", "email": nil}
  assertErr EmailAddress.fromJson(node)

# ============= C. EmailAddress round-trip =============

block roundTripEmailAddressWithName:
  let original = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let roundTripped = EmailAddress.fromJson(original.toJson()).get()
  assertEq roundTripped.email, original.email
  assertSomeEq roundTripped.name, "Joe"

block roundTripEmailAddressWithoutName:
  let original = parseEmailAddress("joe@example.com").get()
  let roundTripped = EmailAddress.fromJson(original.toJson()).get()
  assertEq roundTripped.email, original.email
  assertNone roundTripped.name

# ============= D. EmailAddress fromJson edge cases =============

block fromJsonEmailAddressNameAbsent:
  let node = %*{"email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  assertNone res.get().name

block fromJsonEmailAddressNameNull:
  let node = %*{"name": nil, "email": "joe@example.com"}
  let res = EmailAddress.fromJson(node)
  assertOk res
  assertNone res.get().name

block fromJsonEmailAddressNotObject:
  let node = %"just a string"
  assertErr EmailAddress.fromJson(node)

block fromJsonEmailAddressEmptyEmail:
  let node = %*{"email": ""}
  assertErr EmailAddress.fromJson(node)

# ============= E. EmailAddressGroup serde =============

block roundTripEmailAddressGroupFull: # scenario 12
  let ea1 = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let ea2 = parseEmailAddress("jane@example.com", Opt.some("Jane")).get()
  let group = EmailAddressGroup(name: Opt.some("Team"), addresses: @[ea1, ea2])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertSomeEq roundTripped.name, "Team"
  assertLen roundTripped.addresses, 2
  assertEq roundTripped.addresses[0].email, "joe@example.com"
  assertEq roundTripped.addresses[1].email, "jane@example.com"

block roundTripEmailAddressGroupNullName:
  let ea = parseEmailAddress("joe@example.com").get()
  let group = EmailAddressGroup(name: Opt.none(string), addresses: @[ea])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertNone roundTripped.name
  assertLen roundTripped.addresses, 1

block roundTripEmailAddressGroupEmptyAddresses:
  let group = EmailAddressGroup(name: Opt.some("Empty"), addresses: @[])
  let roundTripped = EmailAddressGroup.fromJson(group.toJson()).get()
  assertSomeEq roundTripped.name, "Empty"
  assertLen roundTripped.addresses, 0

block fromJsonEmailAddressGroupMissingAddresses:
  let node = %*{"name": "Team"}
  assertErr EmailAddressGroup.fromJson(node)

block fromJsonEmailAddressGroupBadElement:
  let node = %*{"name": "Team", "addresses": [{"email": ""}]}
  assertErr EmailAddressGroup.fromJson(node)
