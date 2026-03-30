# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Layer 2 serde tests for Session-level composition: golden round-trip,
## structural, missing/invalid field, and fixture round-trip tests.
## CoreCapabilities and ServerCapability tests are in tserde_capabilities.nim.
## Account and AccountCapabilityEntry tests are in tserde_account.nim.

import std/json
import std/sets
import std/strutils
import std/tables

import results

import jmap_client/serde
import jmap_client/serde_session
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures

# =============================================================================
# A. Session — Golden Test & Round-Trip
# =============================================================================

# RFC section 2.1 golden Session JSON (design doc section 13.1).
# Built as proc (not func) to avoid {.cast(noSideEffect).} ARC interference.
# Each call returns a fresh tree so ARC tracking is correct.
proc goldenSessionJson(): JsonNode =
  ## Builds a fresh copy of the RFC section 2.1 golden Session JSON.
  %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 50000000,
        "maxConcurrentUpload": 8,
        "maxSizeRequest": 10000000,
        "maxConcurrentRequest": 8,
        "maxCallsInRequest": 32,
        "maxObjectsInGet": 256,
        "maxObjectsInSet": 128,
        "collationAlgorithms":
          ["i;ascii-numeric", "i;ascii-casemap", "i;unicode-casemap"],
      },
      "urn:ietf:params:jmap:mail": {},
      "urn:ietf:params:jmap:contacts": {},
      "https://example.com/apis/foobar": {"maxFoosFinangled": 42},
    },
    "accounts": {
      "A13824": {
        "name": "john@example.com",
        "isPersonal": true,
        "isReadOnly": false,
        "accountCapabilities":
          {"urn:ietf:params:jmap:mail": {}, "urn:ietf:params:jmap:contacts": {}},
      },
      "A97813": {
        "name": "jane@example.com",
        "isPersonal": false,
        "isReadOnly": true,
        "accountCapabilities": {"urn:ietf:params:jmap:mail": {}},
      },
    },
    "primaryAccounts":
      {"urn:ietf:params:jmap:mail": "A13824", "urn:ietf:params:jmap:contacts": "A13824"},
    "username": "john@example.com",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "75128aab4b1b",
  }

# Minimal valid Session JSON for edge-case modifications.
proc validSessionJson(): JsonNode =
  ## Builds a fresh minimal valid Session JSON.
  %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 1,
        "maxConcurrentUpload": 1,
        "maxSizeRequest": 1,
        "maxConcurrentRequests": 1,
        "maxCallsInRequest": 1,
        "maxObjectsInGet": 1,
        "maxObjectsInSet": 1,
        "collationAlgorithms": [],
      }
    },
    "accounts": {},
    "primaryAccounts": {},
    "username": "",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "s1",
  }

block sessionDeserGoldenRfcAndRoundTrip:
  let j = goldenSessionJson()
  let r = Session.fromJson(j)
  assertOk r
  let s = r.get()
  # Verify all 8 expected parsed values per section 13.1
  assertEq s.capabilities.len, 4
  assertEq int64(s.coreCapabilities().maxSizeUpload), 50000000'i64
  # D2.6: singular maxConcurrentRequest parsed into plural field
  assertEq int64(s.coreCapabilities().maxConcurrentRequests), 8'i64
  assertEq s.coreCapabilities().collationAlgorithms.len, 3
  assertEq s.accounts.len, 2
  doAssert s.accounts[parseAccountId("A13824").get()].isPersonal
  assertEq s.primaryAccounts["urn:ietf:params:jmap:mail"],
    parseAccountId("A13824").get()
  assertEq s.username, "john@example.com"
  assertEq s.state, parseJmapState("75128aab4b1b").get()
  # Round-trip: parse -> toJson -> parse -> compare
  let j2 = s.toJson()
  let rt = Session.fromJson(j2)
  doAssert rt.isOk, "golden round-trip failed"
  doAssert sessionEq(rt.get(), s), "golden round-trip values differ"

block sessionToJsonCapabilityKeys:
  let j = goldenSessionJson()
  let s = Session.fromJson(j).get()
  let sj = s.toJson()
  let capsObj = sj{"capabilities"}
  doAssert capsObj != nil
  # Vendor extension must use rawUri, not "ckUnknown"
  doAssert capsObj{"https://example.com/apis/foobar"} != nil
  doAssert capsObj{"ckUnknown"}.isNil

block sessionToJsonAccountKeys:
  let j = goldenSessionJson()
  let s = Session.fromJson(j).get()
  let sj = s.toJson()
  let acctsObj = sj{"accounts"}
  doAssert acctsObj != nil
  doAssert acctsObj{"A13824"} != nil
  doAssert acctsObj{"A97813"} != nil

block sessionToJsonUnicodePreserved:
  var j = validSessionJson()
  j["username"] = %"noño@example.com"
  j["accounts"] = %*{
    "A1": {
      "name": "日本語ユーザー",
      "isPersonal": true,
      "isReadOnly": false,
      "accountCapabilities": {},
    }
  }
  let r = Session.fromJson(j)
  assertOk r
  let s = r.get()
  assertEq s.username, "noño@example.com"
  # Round-trip preserves Unicode
  let rt = Session.fromJson(s.toJson()).get()
  assertEq rt.username, "noño@example.com"

# =============================================================================
# B. Session deserialisation — missing/invalid fields
# =============================================================================

block sessionDeserMissingCapabilities:
  let j = %*{
    "accounts": {},
    "primaryAccounts": {},
    "username": "",
    "apiUrl": "https://example.com/api/",
    "downloadUrl":
      "https://example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://example.com/es/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "s1",
  }
  assertErrContains Session.fromJson(j), "missing or invalid capabilities"

block sessionDeserCapabilitiesNotObject:
  var j = validSessionJson()
  j["capabilities"] = %*[1, 2, 3]
  assertErr Session.fromJson(j)

block sessionDeserMissingCoreCapability:
  var j = validSessionJson()
  j["capabilities"] = %*{"urn:ietf:params:jmap:mail": {}}
  assertErrContains Session.fromJson(j), "capabilities must include"

block sessionDeserUnknownCapabilityUris:
  let j = validSessionJson()
  let r = Session.fromJson(j)
  assertOk r

block sessionDeserExtraTopLevelFields:
  var j = validSessionJson()
  j["extraField"] = %"ignored"
  j["anotherExtra"] = %42
  assertOk Session.fromJson(j)

block sessionDeserMissingPrimaryAccounts:
  var j = validSessionJson()
  # Remove primaryAccounts by rebuilding without it
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "username": j["username"],
    "apiUrl": j["apiUrl"],
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "missing or invalid primaryAccounts"

block sessionDeserPrimaryAccountsValueIsInt:
  var j = validSessionJson()
  j["primaryAccounts"] = %*{"urn:ietf:params:jmap:mail": 42}
  assertErrContains Session.fromJson(j), "primaryAccounts value must be string"

block sessionDeserEmptyAccounts:
  let j = validSessionJson()
  assertOk Session.fromJson(j)

block sessionDeserMissingUsername:
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "apiUrl": j["apiUrl"],
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "missing or invalid username"

block sessionDeserMissingApiUrl:
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "username": j["username"],
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "missing or invalid apiUrl"

block sessionDeserEmptyApiUrl:
  var j = validSessionJson()
  j["apiUrl"] = %""
  assertErrContains Session.fromJson(j), "apiUrl must not be empty"

block sessionDeserMissingState:
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "username": j["username"],
    "apiUrl": j["apiUrl"],
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
  }
  assertErrContains Session.fromJson(j2), "missing or invalid state"

block sessionDeserNotObjectOrNil:
  assertErr Session.fromJson(%*[1, 2])
  const nilNode: JsonNode = nil
  assertErr Session.fromJson(nilNode)

block sessionDeserDeepInvalidValue:
  ## Proves ? operator propagates through the full 4-level chain:
  ## Session -> ServerCapability -> CoreCapabilities -> UnsignedInt
  var j = validSessionJson()
  j["capabilities"]["urn:ietf:params:jmap:core"]["maxSizeUpload"] = %(-1)
  let r = Session.fromJson(j)
  assertErr r
  assertErrType r, "UnsignedInt"

# =============================================================================
# C. Session fixture round-trip tests
# =============================================================================

block roundTripSessionDefault:
  let session = parseSessionFromArgs(makeSessionArgs()).get()
  let j = session.toJson()
  let rt = Session.fromJson(j)
  doAssert rt.isOk, "default round-trip failed"
  doAssert sessionEq(rt.get(), session), "default round-trip values differ"

block roundTripSessionMinimal:
  let session = parseSessionFromArgs(makeMinimalSession()).get()
  let j = session.toJson()
  let rt = Session.fromJson(j)
  doAssert rt.isOk, "minimal round-trip failed"
  doAssert sessionEq(rt.get(), session), "minimal round-trip values differ"

block roundTripSessionFastmail:
  let session = parseSessionFromArgs(makeFastmailSession()).get()
  let j = session.toJson()
  let rt = Session.fromJson(j)
  doAssert rt.isOk, "fastmail round-trip failed"
  doAssert sessionEq(rt.get(), session), "fastmail round-trip values differ"

block roundTripSessionCyrus:
  let session = parseSessionFromArgs(makeCyrusSession()).get()
  let j = session.toJson()
  let rt = Session.fromJson(j)
  doAssert rt.isOk, "cyrus round-trip failed"
  doAssert sessionEq(rt.get(), session), "cyrus round-trip values differ"

# =============================================================================
# D. Session structural and maximal round-trip
# =============================================================================

block sessionMaximalStructureRoundTrip:
  ## Session with many accounts, multiple capabilities, all fields populated.
  {.cast(noSideEffect).}:
    let j = %*{
      "capabilities": {
        "urn:ietf:params:jmap:core": {
          "maxSizeUpload": 50000000,
          "maxConcurrentUpload": 4,
          "maxSizeRequest": 10000000,
          "maxConcurrentRequests": 8,
          "maxCallsInRequest": 16,
          "maxObjectsInGet": 500,
          "maxObjectsInSet": 500,
          "collationAlgorithms": ["i;ascii-casemap", "i;unicode-casemap"],
        },
        "urn:ietf:params:jmap:mail": {"maxMailboxDepth": 10},
        "urn:ietf:params:jmap:submission": {},
        "urn:ietf:params:jmap:contacts": {"maxContacts": 5000},
        "urn:ietf:params:jmap:calendars": {},
      },
      "accounts": {
        "A001": {
          "name": "Personal",
          "isPersonal": true,
          "isReadOnly": false,
          "accountCapabilities":
            {"urn:ietf:params:jmap:mail": {}, "urn:ietf:params:jmap:contacts": {}},
        },
        "A002": {
          "name": "Work",
          "isPersonal": false,
          "isReadOnly": false,
          "accountCapabilities": {"urn:ietf:params:jmap:mail": {}},
        },
        "A003": {
          "name": "Shared",
          "isPersonal": false,
          "isReadOnly": true,
          "accountCapabilities": {"urn:ietf:params:jmap:calendars": {}},
        },
      },
      "primaryAccounts": {
        "urn:ietf:params:jmap:mail": "A001",
        "urn:ietf:params:jmap:contacts": "A001",
        "urn:ietf:params:jmap:calendars": "A003",
      },
      "username": "user@example.com",
      "apiUrl": "https://jmap.example.com/api/",
      "downloadUrl":
        "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
      "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
      "eventSourceUrl":
        "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
      "state": "abc123",
    }
    let r = Session.fromJson(j)
    assertOk r
    let s = r.get()
    assertEq s.capabilities.len, 5
    assertEq s.accounts.len, 3
    assertEq s.primaryAccounts.len, 3
    # Round-trip
    let rt = Session.fromJson(s.toJson())
    assertOk rt
    assertEq rt.get().capabilities.len, 5
    assertEq rt.get().accounts.len, 3

# =============================================================================
# E. Equality helper verification
# =============================================================================

block equalityHelperSessionEqDifferentState:
  ## Verify sessionEq returns false for sessions with different state.
  let s1 = parseSessionFromArgs(makeMinimalSession()).get()
  var args2 = makeMinimalSession()
  args2.state = makeState("differentState")
  let s2 = parseSessionFromArgs(args2).get()
  doAssert not sessionEq(s1, s2), "sessionEq must return false for different state"

block equalityHelperSetErrorEqDifferentType:
  ## Verify setErrorEq returns false for SetErrors with different errorType.
  let se1 = setError("forbidden")
  let se2 = setError("notFound")
  doAssert not setErrorEq(se1, se2),
    "setErrorEq must return false for different errorType"
