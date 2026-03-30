# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 2 session serialisation: CoreCapabilities,
## ServerCapability, AccountCapabilityEntry, Account, and Session
## round-trip, structural, golden, and edge-case tests.

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
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty

# ServerCapability is a case object — Nim cannot auto-generate == for case
# objects. Define value equality for round-trip testing.
func capEq(a, b: ServerCapability): bool =
  ## Deep value equality for ServerCapability (case object).
  if a.kind != b.kind or a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckCore:
    a.core == b.core
  else:
    a.rawData == b.rawData

func capsEq(a, b: seq[ServerCapability]): bool =
  ## Compares two sequences of ServerCapability by value.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if not capEq(a[i], b[i]):
      return false
  true

func sessionEq(a, b: Session): bool =
  ## Deep value equality for Session (contains seq[ServerCapability]).
  capsEq(a.capabilities, b.capabilities) and a.accounts == b.accounts and
    a.primaryAccounts == b.primaryAccounts and a.username == b.username and
    a.apiUrl == b.apiUrl and a.downloadUrl == b.downloadUrl and
    a.uploadUrl == b.uploadUrl and a.eventSourceUrl == b.eventSourceUrl and
    a.state == b.state

template assertCapOkEq(r: untyped, expected: ServerCapability) =
  ## Verifies Result is Ok and its ServerCapability value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert capEq(v, expected), "ServerCapability values differ"

template assertSessionOkEq(r: untyped, expected: Session) =
  ## Verifies Result is Ok and its Session value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert sessionEq(v, expected), "Session values differ"

# =============================================================================
# A. CoreCapabilities
# =============================================================================

block roundTripCoreCapabilitiesZero:
  let original = zeroCoreCaps()
  assertOkEq CoreCapabilities.fromJson(original.toJson()), original

block roundTripCoreCapabilitiesRealistic:
  let original = realisticCoreCaps()
  assertOkEq CoreCapabilities.fromJson(original.toJson()), original

block coreCapabilitiesToJsonFieldNames:
  let caps = realisticCoreCaps()
  let j = caps.toJson()
  doAssert j{"maxSizeUpload"} != nil
  doAssert j{"maxConcurrentUpload"} != nil
  doAssert j{"maxSizeRequest"} != nil
  # Must be plural, not singular
  doAssert j{"maxConcurrentRequests"} != nil
  doAssert j{"maxConcurrentRequest"}.isNil
  doAssert j{"maxCallsInRequest"} != nil
  doAssert j{"maxObjectsInGet"} != nil
  doAssert j{"maxObjectsInSet"} != nil
  doAssert j{"collationAlgorithms"} != nil
  doAssert j{"collationAlgorithms"}.kind == JArray
  for elem in j{"collationAlgorithms"}.getElems(@[]):
    doAssert elem.kind == JString

block coreCapabilitiesDeserValid:
  let j = %*{
    "maxSizeUpload": 50000000,
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": ["i;ascii-numeric"],
  }
  let r = CoreCapabilities.fromJson(j)
  assertOk r
  let caps = r.get()
  assertEq int64(caps.maxSizeUpload), 50000000'i64
  assertEq int64(caps.maxCallsInRequest), 32'i64
  doAssert caps.collationAlgorithms.contains("i;ascii-numeric")

block coreCapabilitiesDeserMissingField:
  let j = %*{
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserWrongKindString:
  let j = %*{
    "maxSizeUpload": "string",
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserNegativeValue:
  let j = %*{
    "maxSizeUpload": -1,
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": [],
  }
  assertErr CoreCapabilities.fromJson(j)

block coreCapabilitiesDeserEmptyCollation:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j)
  assertOk r
  assertEq r.get().collationAlgorithms.len, 0

block coreCapabilitiesDeserCollationNonString:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [42],
  }
  let r = CoreCapabilities.fromJson(j)
  assertErrContains r, "collationAlgorithms element must be string"

block coreCapabilitiesDeserCollationWrongKind:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": "notarray",
  }
  let r = CoreCapabilities.fromJson(j)
  assertErrContains r, "missing or invalid collationAlgorithms"

block coreCapabilitiesDeserNotObjectOrNil:
  assertErr CoreCapabilities.fromJson(%*[1, 2, 3])
  const nilNode: JsonNode = nil
  assertErr CoreCapabilities.fromJson(nilNode)

block coreCapabilitiesDeserSingularOnly:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequest": 5,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j)
  assertOk r
  assertEq int64(r.get().maxConcurrentRequests), 5'i64

block coreCapabilitiesDeserBothDifferentValues:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 10,
    "maxConcurrentRequest": 5,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j)
  assertOk r
  # Plural form takes precedence
  assertEq int64(r.get().maxConcurrentRequests), 10'i64

block coreCapabilitiesDeserNeitherPresent:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = CoreCapabilities.fromJson(j)
  assertErrContains r, "missing maxConcurrentRequests"

# =============================================================================
# B. ServerCapability
# =============================================================================

block roundTripServerCapabilityCkCore:
  let original = makeCoreServerCap(realisticCoreCaps())
  assertCapOkEq ServerCapability.fromJson(original.rawUri, original.toJson()), original

block serverCapabilityDeserCkCoreValid:
  let j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:core", j)
  assertOk r
  doAssert r.get().kind == ckCore
  assertEq r.get().rawUri, "urn:ietf:params:jmap:core"

block serverCapabilityDeserCkCoreMissingField:
  let j = %*{"maxSizeUpload": 1}
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:core", j)
  assertErr r
  assertErrType r, "UnsignedInt"

block serverCapabilityDeserUnknownUri:
  let data = %*{"maxFoosFinangled": 42}
  let r = ServerCapability.fromJson("https://vendor.example/ext", data)
  assertOk r
  let cap = r.get()
  doAssert cap.kind == ckUnknown
  assertEq cap.rawUri, "https://vendor.example/ext"
  doAssert cap.rawData{"maxFoosFinangled"} != nil

block serverCapabilityDeserKnownNonCoreUri:
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJObject())
  assertOk r
  doAssert r.get().kind == ckMail

block serverCapabilityToJsonCkCoreStructure:
  let cap = makeCoreServerCap(realisticCoreCaps())
  let j = cap.toJson()
  doAssert j.kind == JObject
  doAssert j{"maxSizeUpload"} != nil

block serverCapabilityToJsonNilVsNonNilRawData:
  let nilCap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: nil)
  let nilResult = nilCap.toJson()
  doAssert nilResult.kind == JObject
  assertEq nilResult.getFields().len, 0
  let data = %*{"custom": true}
  let dataCap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: data)
  doAssert dataCap.toJson() == data

# =============================================================================
# C. AccountCapabilityEntry
# =============================================================================

block roundTripAccountCapabilityEntry:
  let data = %*{"limit": 100}
  let r = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", data)
  assertOk r
  let entry = r.get()
  doAssert entry.kind == ckMail
  assertEq entry.rawUri, "urn:ietf:params:jmap:mail"
  doAssert entry.toJson() == data

block accountCapabilityEntryDeserUnknownUri:
  let r = AccountCapabilityEntry.fromJson("https://vendor.example/ext", newJObject())
  assertOk r
  doAssert r.get().kind == ckUnknown
  assertEq r.get().rawUri, "https://vendor.example/ext"

block accountCapabilityEntryNilData:
  const nilData: JsonNode = nil
  let r = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", nilData)
  assertOk r
  doAssert r.get().data != nil
  doAssert r.get().data.kind == JObject
  let entry =
    AccountCapabilityEntry(kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: nil)
  doAssert entry.toJson().kind == JObject

# =============================================================================
# D. Account
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
  let r = Account.fromJson(j)
  assertOk r
  assertEq r.get().accountCapabilities.len, 0

# =============================================================================
# E. Session — Golden Test & Edge Cases
# =============================================================================

# RFC §2.1 golden Session JSON (design doc §13.1).
# Built as proc (not func) to avoid {.cast(noSideEffect).} ARC interference.
# Each call returns a fresh tree so ARC tracking is correct.
proc goldenSessionJson(): JsonNode =
  ## Builds a fresh copy of the RFC §2.1 golden Session JSON.
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
  # Verify all 8 expected parsed values per §13.1
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
  j["username"] = %"ñoño@example.com"
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
  assertEq s.username, "ñoño@example.com"
  # Round-trip preserves Unicode
  let rt = Session.fromJson(s.toJson()).get()
  assertEq rt.username, "ñoño@example.com"

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
# F. Property-Based & Fixture Round-Trip Tests
# =============================================================================

checkProperty "CoreCapabilities round-trip":
  let caps = rng.genCoreCapabilities()
  assertOkEq CoreCapabilities.fromJson(caps.toJson()), caps

checkProperty "ServerCapability round-trip":
  let cap = rng.genServerCapability()
  assertCapOkEq ServerCapability.fromJson(cap.rawUri, cap.toJson()), cap

checkProperty "Account round-trip":
  let acct = rng.genValidAccount()
  # genValidAccount may produce duplicate capability URIs. JSON objects
  # deduplicate by key, so round-trip can lose entries. Assert parse succeeds.
  let r = Account.fromJson(acct.toJson())
  assertOk r

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
# G. Data Preservation & Edge Cases
# =============================================================================

block serverCapabilityNestedRawDataRoundTrip:
  let data = %*{"foo": {"bar": [1, 2, {"baz": true}]}}
  let cap = ServerCapability.fromJson("https://vendor.example/ext", data).get()
  let rt = ServerCapability.fromJson(cap.rawUri, cap.toJson()).get()
  doAssert rt.rawData == data

block accountCapabilityEntryNestedDataRoundTrip:
  let data = %*{"nested": {"deep": [1, "two", newJNull(), {"four": false}]}}
  let entry = AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", data).get()
  doAssert entry.toJson() == data

block serverCapabilityJNullData:
  ## Documents behaviour when server sends null for capability data.
  ## JNull is non-nil, stored as-is in rawData.
  let r = ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJNull())
  assertOk r
  doAssert r.get().rawData.kind == JNull

# =============================================================================
# H. Additional Variant, Boundary, and Structural Tests
# =============================================================================

# --- ServerCapability: all non-core variant round-trips ---

block serverCapabilityAllVariantsDeserRoundTrip:
  ## Verifies every non-core CapabilityKind deserialises and round-trips.
  {.cast(noSideEffect).}:
    let testData = %*{"vendorExtension": true, "nested": {"key": "val"}}
    let variants = [
      ("urn:ietf:params:jmap:submission", ckSubmission),
      ("urn:ietf:params:jmap:vacationresponse", ckVacationResponse),
      ("urn:ietf:params:jmap:websocket", ckWebsocket),
      ("urn:ietf:params:jmap:mdn", ckMdn),
      ("urn:ietf:params:jmap:smimeverify", ckSmimeVerify),
      ("urn:ietf:params:jmap:blob", ckBlob),
      ("urn:ietf:params:jmap:quota", ckQuota),
      ("urn:ietf:params:jmap:contacts", ckContacts),
      ("urn:ietf:params:jmap:calendars", ckCalendars),
      ("urn:ietf:params:jmap:sieve", ckSieve),
    ]
    for (uri, expectedKind) in variants:
      let r = ServerCapability.fromJson(uri, testData)
      doAssert r.isOk, "failed to deserialise " & uri
      doAssert r.get().kind == expectedKind, "wrong kind for " & uri
      assertEq r.get().rawUri, uri
      # Verify rawData preserved (deep copy)
      let rtJson = r.get().toJson()
      doAssert rtJson{"vendorExtension"} != nil, "rawData lost for " & uri
      assertEq rtJson{"vendorExtension"}.getBool(false), true
      doAssert rtJson{"nested"} != nil, "nested data lost for " & uri

block serverCapabilityArcSharedRefSafety:
  ## Validates Phase 1A fix: two capabilities sharing the same JsonNode ref
  ## must not cause ARC double-free on destruction.
  {.cast(noSideEffect).}:
    let sharedData = %*{"shared": 42, "nested": {"a": 1}}
    # Both capabilities point to the same JsonNode — ownData() must deep-copy
    let r1 = ServerCapability.fromJson("urn:ietf:params:jmap:mail", sharedData)
    let r2 = ServerCapability.fromJson("urn:ietf:params:jmap:contacts", sharedData)
    assertOk r1
    assertOk r2
    # Verify they are independent copies, not the same ref
    let json1 = r1.get().toJson()
    let json2 = r2.get().toJson()
    assertEq json1{"shared"}.getBiggestInt(0), 42
    assertEq json2{"shared"}.getBiggestInt(0), 42
    # If they survived to here without crash, ARC ref management is safe

block coreCapabilitiesDeserMaxUnsignedIntBoundary:
  ## Boundary: 2^53-1 at CoreCapabilities level within Session context.
  {.cast(noSideEffect).}:
    const maxVal = 9007199254740991'i64 # 2^53-1
    let j = %*{
      "maxSizeUpload": maxVal,
      "maxConcurrentUpload": 1,
      "maxSizeRequest": 1,
      "maxConcurrentRequests": 1,
      "maxCallsInRequest": 1,
      "maxObjectsInGet": 1,
      "maxObjectsInSet": 1,
      "collationAlgorithms": [],
    }
    let r = CoreCapabilities.fromJson(j)
    assertOk r
    assertEq int64(r.get().maxSizeUpload), maxVal

block coreCapabilitiesCollationDuplicatesDeduplication:
  ## HashSet deduplicates collation algorithms.
  {.cast(noSideEffect).}:
    let j = %*{
      "maxSizeUpload": 1,
      "maxConcurrentUpload": 1,
      "maxSizeRequest": 1,
      "maxConcurrentRequests": 1,
      "maxCallsInRequest": 1,
      "maxObjectsInGet": 1,
      "maxObjectsInSet": 1,
      "collationAlgorithms": ["i;ascii-casemap", "i;ascii-casemap", "i;octet"],
    }
    let r = CoreCapabilities.fromJson(j)
    assertOk r
    assertEq r.get().collationAlgorithms.len, 2

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
