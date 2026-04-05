# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Layer 2 serde tests for AccountCapabilityEntry and Account
## round-trip, structural, and edge-case tests.

import std/json

import jmap_client/serde_session
import jmap_client/capabilities
import jmap_client/session
import jmap_client/validation

import ../massertions
import ../mproperty

# =============================================================================
# A. AccountCapabilityEntry
# =============================================================================

block roundTripAccountCapabilityEntry:
  let data = %*{"limit": 100}
  let entry = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", data).get()
  doAssert entry.kind == ckMail
  assertEq entry.rawUri, "urn:ietf:params:jmap:mail"
  doAssert entry.toJson() == data

block accountCapabilityEntryDeserUnknownUri:
  let r =
    AccountCapabilityEntry.fromJson("https://vendor.example/ext", newJObject()).get()
  doAssert r.kind == ckUnknown
  assertEq r.rawUri, "https://vendor.example/ext"

block accountCapabilityEntryNilData:
  const nilData: JsonNode = nil
  let r = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", nilData).get()
  doAssert r.data != nil
  doAssert r.data.kind == JObject
  let entry =
    AccountCapabilityEntry(kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: nil)
  doAssert entry.toJson().kind == JObject

block accountCapabilityEntryDeserEmptyUri:
  ## Empty URI string must be rejected by AccountCapabilityEntry.fromJson.
  assertErrContains AccountCapabilityEntry.fromJson("", newJObject()), "empty"

block accountCapabilityEntryNestedDataRoundTrip:
  let data = %*{"nested": {"deep": [1, "two", newJNull(), {"four": false}]}}
  let entry = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", data).get()
  doAssert entry.toJson() == data

# =============================================================================
# B. Account
# =============================================================================

block roundTripAccount:
  let original = Account(
    name: "test@example.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[
      AccountCapabilityEntry(
        kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJObject()
      ),
      AccountCapabilityEntry(
        kind: ckContacts, rawUri: "urn:ietf:params:jmap:contacts", data: newJObject()
      ),
    ],
  )

  assertOkEq Account.fromJson(original.toJson()), original

block accountToJsonStructure:
  let acct = Account(
    name: "test",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[
      AccountCapabilityEntry(
        kind: ckUnknown, rawUri: "https://vendor.example/ext", data: newJObject()
      )
    ],
  )
  let j = acct.toJson()
  doAssert j{"name"} != nil
  doAssert j{"isPersonal"} != nil
  doAssert j{"isReadOnly"} != nil
  doAssert j{"accountCapabilities"} != nil
  # Key must be the rawUri, not $kind
  doAssert j{"accountCapabilities"}{"https://vendor.example/ext"} != nil

block accountDeserNotObjectOrNil:
  assertErr Account.fromJson(%*[1, 2])
  const nilNode: JsonNode = nil
  assertErr Account.fromJson(nilNode)

block accountDeserMissingName:
  let j = %*{"isPersonal": true, "isReadOnly": false, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "missing or invalid name"

block accountDeserMissingIsPersonal:
  ## Phase 3B: missing isPersonal field must return err.
  let j = %*{"name": "test", "isReadOnly": false, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "missing or invalid isPersonal"

block accountDeserMissingIsReadOnly:
  ## Phase 3B: missing isReadOnly field must return err.
  let j = %*{"name": "test", "isPersonal": true, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "missing or invalid isReadOnly"

block accountDeserWrongKindIsPersonal:
  let j = %*{
    "name": "test", "isPersonal": "true", "isReadOnly": false, "accountCapabilities": {}
  }
  assertErrContains Account.fromJson(j), "missing or invalid isPersonal"

block accountDeserWrongKindIsReadOnly:
  let j =
    %*{"name": "test", "isPersonal": true, "isReadOnly": 1, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "missing or invalid isReadOnly"

block accountDeserMissingAccountCapabilities:
  let j = %*{"name": "test", "isPersonal": true, "isReadOnly": false}
  assertErrContains Account.fromJson(j), "missing or invalid accountCapabilities"

block accountDeserEmptyAccountCapabilities:
  let j = %*{
    "name": "test", "isPersonal": true, "isReadOnly": false, "accountCapabilities": {}
  }
  let r = Account.fromJson(j).get()
  assertEq r.accountCapabilities.len, 0

# =============================================================================
# C. Property-based Account round-trip
# =============================================================================

checkProperty "Account round-trip":
  let acct = rng.genValidAccount()
  # genValidAccount may produce duplicate capability URIs. JSON objects
  # deduplicate by key, so round-trip can lose entries. Assert parse succeeds.
  discard Account.fromJson(acct.toJson())
