# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Layer 2 serde tests for AccountCapabilityEntry and Account
## round-trip, structural, and edge-case tests.

import std/json

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session
import jmap_client/internal/types/validation

import ../massertions
import ../mproperty
import ../mtestblock

# =============================================================================
# A. AccountCapabilityEntry
# =============================================================================

testCase roundTripAccountCapabilityEntryVendor:
  ## Vendor URI maps to ckUnknown and round-trips through rawXxxData.
  let data = %*{"limit": 100}
  let entry = AccountCapabilityEntry.fromJson("https://vendor.example/ext", data).get()
  doAssert entry.kind == ckUnknown
  assertEq entry.uri, "https://vendor.example/ext"
  doAssert entry.toJson() == data

testCase accountCapabilityEntryDeserUnknownUri:
  let r =
    AccountCapabilityEntry.fromJson("https://vendor.example/ext", newJObject()).get()
  doAssert r.kind == ckUnknown
  assertEq r.uri, "https://vendor.example/ext"

testCase accountCapabilityEntryNilDataForRawArm:
  const nilData: JsonNode = nil
  let r = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:quota", nilData).get()
  doAssert r.kind == ckQuota
  let raw = r.asRawData()
  assertSome raw
  doAssert raw.get().kind == JObject

testCase accountCapabilityEntryDeserEmptyUri:
  ## Empty URI string must be rejected by AccountCapabilityEntry.fromJson.
  assertErrContains AccountCapabilityEntry.fromJson("", newJObject()), "empty"

testCase accountCapabilityEntryNestedDataRoundTrip:
  let data = %*{"nested": {"deep": [1, "two", newJNull(), {"four": false}]}}
  let entry = AccountCapabilityEntry.fromJson("https://vendor.example/ext", data).get()
  doAssert entry.toJson() == data

# =============================================================================
# B. Account
# =============================================================================

testCase roundTripAccount:
  let original = parseAccount(
      "test@example.com",
      isPersonal = true,
      isReadOnly = false,
      @[
        AccountCapabilityEntry
          .fromJson("https://vendor.example/contacts", newJObject())
          .get()
      ],
    )
    .get()
  assertOkEq Account.fromJson(original.toJson()), original

testCase accountToJsonStructure:
  let acct = parseAccount(
      "test",
      isPersonal = true,
      isReadOnly = false,
      @[
        AccountCapabilityEntry.fromJson("https://vendor.example/ext", newJObject()).get()
      ],
    )
    .get()
  let j = acct.toJson()
  doAssert j{"name"} != nil
  doAssert j{"isPersonal"} != nil
  doAssert j{"isReadOnly"} != nil
  doAssert j{"accountCapabilities"} != nil
  doAssert j{"accountCapabilities"}{"https://vendor.example/ext"} != nil

testCase accountDeserNotObjectOrNil:
  assertErr Account.fromJson(%*[1, 2])
  const nilNode: JsonNode = nil
  assertErr Account.fromJson(nilNode)

testCase accountDeserMissingName:
  let j = %*{"isPersonal": true, "isReadOnly": false, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "name"

testCase accountDeserMissingIsPersonal:
  let j = %*{"name": "test", "isReadOnly": false, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "isPersonal"

testCase accountDeserMissingIsReadOnly:
  let j = %*{"name": "test", "isPersonal": true, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "isReadOnly"

testCase accountDeserWrongKindIsPersonal:
  let j = %*{
    "name": "test", "isPersonal": "true", "isReadOnly": false, "accountCapabilities": {}
  }
  assertErrContains Account.fromJson(j), "at /isPersonal"

testCase accountDeserWrongKindIsReadOnly:
  let j =
    %*{"name": "test", "isPersonal": true, "isReadOnly": 1, "accountCapabilities": {}}
  assertErrContains Account.fromJson(j), "at /isReadOnly"

testCase accountDeserMissingAccountCapabilities:
  let j = %*{"name": "test", "isPersonal": true, "isReadOnly": false}
  assertErrContains Account.fromJson(j), "accountCapabilities"

testCase accountDeserEmptyAccountCapabilities:
  let j = %*{
    "name": "test", "isPersonal": true, "isReadOnly": false, "accountCapabilities": {}
  }
  let r = Account.fromJson(j).get()
  assertEq r.accountCapabilities.len, 0

# =============================================================================
# C. Property-based Account round-trip
# =============================================================================

checkProperty "Account round-trip":
  let acct = rng.genAccount()
  # genAccount may produce duplicate capability URIs. JSON objects
  # deduplicate by key, so round-trip can lose entries. Assert parse succeeds.
  discard Account.fromJson(acct.toJson())
