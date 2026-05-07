# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Layer 2 serde tests for Session-level composition: golden round-trip,
## structural, missing/invalid field, and fixture round-trip tests.
## CoreCapabilities and ServerCapability tests are in tserde_capabilities.nim.
## Account and AccountCapabilityEntry tests are in tserde_account.nim.

import std/json
import std/sets
import std/strutils
import std/tables

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session
import jmap_client/internal/types/errors
import jmap_client/internal/types/validation

import ../massertions
import ../mfixtures

# =============================================================================
# A. Session — Golden Test & Round-Trip
# =============================================================================

# Golden and valid Session JSON fixtures are in mfixtures.nim:
# goldenSessionJson() — RFC 8620 section 2.1 golden example
# validSessionJson() — minimal valid Session for edge-case modifications

block sessionDeserGoldenRfcAndRoundTrip:
  let j = goldenSessionJson()
  let s = Session.fromJson(j).get()
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
  let rt = Session.fromJson(j2).get()
  doAssert sessionEq(rt, s), "golden round-trip values differ"

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
  let s = Session.fromJson(j).get()
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
  assertErrContains Session.fromJson(j), "capabilities"

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
  assertOk Session.fromJson(j)

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
  assertErrContains Session.fromJson(j2), "primaryAccounts"

block sessionDeserPrimaryAccountsValueIsInt:
  var j = validSessionJson()
  j["primaryAccounts"] = %*{"urn:ietf:params:jmap:mail": 42}
  assertErrContains Session.fromJson(j), "at /primaryAccounts/"

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
  assertErrContains Session.fromJson(j2), "username"

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
  assertErrContains Session.fromJson(j2), "apiUrl"

block sessionDeserEmptyApiUrl:
  var j = validSessionJson()
  j["apiUrl"] = %""
  assertErrContains Session.fromJson(j), "apiUrl"

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
  assertErrContains Session.fromJson(j2), "state"

block sessionDeserNotObjectOrNil:
  assertErr Session.fromJson(%*[1, 2])
  const nilNode: JsonNode = nil
  assertErr Session.fromJson(nilNode)

block sessionDeserDeepInvalidValue:
  ## Proves exception propagation through the full 4-level chain:
  ## Session -> ServerCapability -> CoreCapabilities -> UnsignedInt
  var j = validSessionJson()
  j["capabilities"]["urn:ietf:params:jmap:core"]["maxSizeUpload"] = %(-1)
  assertErrType Session.fromJson(j), "UnsignedInt"

# =============================================================================
# C. Session fixture round-trip tests
# =============================================================================

block roundTripSessionDefault:
  let session = parseSessionFromArgs(makeSessionArgs())
  let j = session.toJson()
  let rt = Session.fromJson(j).get()
  doAssert sessionEq(rt, session), "default round-trip values differ"

block roundTripSessionMinimal:
  let session = parseSessionFromArgs(makeMinimalSession())
  let j = session.toJson()
  let rt = Session.fromJson(j).get()
  doAssert sessionEq(rt, session), "minimal round-trip values differ"

block roundTripSessionFastmail:
  let session = parseSessionFromArgs(makeFastmailSession())
  let j = session.toJson()
  let rt = Session.fromJson(j).get()
  doAssert sessionEq(rt, session), "fastmail round-trip values differ"

block roundTripSessionCyrus:
  let session = parseSessionFromArgs(makeCyrusSession())
  let j = session.toJson()
  let rt = Session.fromJson(j).get()
  doAssert sessionEq(rt, session), "cyrus round-trip values differ"

# =============================================================================
# D. Session structural and maximal round-trip
# =============================================================================

block sessionMaximalStructureRoundTrip:
  ## Session with many accounts, multiple capabilities, all fields populated.
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
  let s = Session.fromJson(j).get()
  assertEq s.capabilities.len, 5
  assertEq s.accounts.len, 3
  assertEq s.primaryAccounts.len, 3
  # Round-trip
  let rt = Session.fromJson(s.toJson()).get()
  assertEq rt.capabilities.len, 5
  assertEq rt.accounts.len, 3

# =============================================================================
# E. Equality helper verification
# =============================================================================

block equalityHelperSessionEqDifferentState:
  ## Verify sessionEq returns false for sessions with different state.
  let s1 = parseSessionFromArgs(makeMinimalSession())
  var args2 = makeMinimalSession()
  args2.state = makeState("differentState")
  let s2 = parseSessionFromArgs(args2)
  doAssert not sessionEq(s1, s2), "sessionEq must return false for different state"

block equalityHelperSetErrorEqDifferentType:
  ## Verify setErrorEq returns false for SetErrors with different errorType.
  let se1 = setError("forbidden")
  let se2 = setError("notFound")
  doAssert not setErrorEq(se1, se2),
    "setErrorEq must return false for different errorType"

# =============================================================================
# F. Phase 3C: Session URL template field serde tests
# =============================================================================

block sessionDeserMissingDownloadUrl:
  ## Session JSON missing downloadUrl must raise ValidationError.
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "username": j["username"],
    "apiUrl": j["apiUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "downloadUrl"

block sessionDeserMissingUploadUrl:
  ## Session JSON missing uploadUrl must raise ValidationError.
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "username": j["username"],
    "apiUrl": j["apiUrl"],
    "downloadUrl": j["downloadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "uploadUrl"

block sessionDeserMissingEventSourceUrl:
  ## Session JSON missing eventSourceUrl must raise ValidationError.
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": j["accounts"],
    "primaryAccounts": j["primaryAccounts"],
    "username": j["username"],
    "apiUrl": j["apiUrl"],
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "state": j["state"],
  }
  assertErrContains Session.fromJson(j2), "eventSourceUrl"

block sessionDeserDownloadUrlMissingBlobId:
  ## downloadUrl lacking {blobId} must be rejected by parseSession validation.
  var j = validSessionJson()
  j["downloadUrl"] = %"https://example.com/download/{accountId}/{name}?accept={type}"
  assertErrContains Session.fromJson(j), "downloadUrl missing {blobId}"

block sessionDeserDownloadUrlMissingAccountId:
  ## downloadUrl lacking {accountId} must be rejected by parseSession validation.
  var j = validSessionJson()
  j["downloadUrl"] = %"https://example.com/download/{blobId}/{name}?accept={type}"
  assertErrContains Session.fromJson(j), "downloadUrl missing {accountId}"

block sessionDeserUploadUrlMissingAccountId:
  ## uploadUrl lacking {accountId} must be rejected by parseSession validation.
  var j = validSessionJson()
  j["uploadUrl"] = %"https://example.com/upload/"
  assertErrContains Session.fromJson(j), "uploadUrl missing {accountId}"

block sessionDeserEventSourceUrlMissingTypes:
  ## eventSourceUrl lacking {types} must be rejected by parseSession validation.
  var j = validSessionJson()
  j["eventSourceUrl"] = %"https://example.com/es/?closeafter={closeafter}&ping={ping}"
  assertErrContains Session.fromJson(j), "eventSourceUrl missing {types}"

block sessionDeserEventSourceUrlMissingCloseafter:
  ## eventSourceUrl lacking {closeafter} must be rejected.
  var j = validSessionJson()
  j["eventSourceUrl"] = %"https://example.com/es/?types={types}&ping={ping}"
  assertErrContains Session.fromJson(j), "eventSourceUrl missing {closeafter}"

block sessionDeserEventSourceUrlMissingPing:
  ## eventSourceUrl lacking {ping} must be rejected.
  var j = validSessionJson()
  j["eventSourceUrl"] = %"https://example.com/es/?types={types}&closeafter={closeafter}"
  assertErrContains Session.fromJson(j), "eventSourceUrl missing {ping}"

# =============================================================================
# G. Phase 3J: Capability URI key preservation for all 12 standard URIs
# =============================================================================

block sessionToJsonPreservesAll12StandardCapabilityUris:
  ## Construct a Session with all 12 known CapabilityKind variants as
  ## server capabilities. Serialise and verify each URI string appears
  ## as a key in the "capabilities" JSON object.
  let coreCaps = zeroCoreCaps()
  let capabilities = @[
    ServerCapability(kind: ckCore, rawUri: "urn:ietf:params:jmap:core", core: coreCaps),
    ServerCapability(
      kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckSubmission,
      rawUri: "urn:ietf:params:jmap:submission",
      rawData: newJObject(),
    ),
    ServerCapability(
      kind: ckVacationResponse,
      rawUri: "urn:ietf:params:jmap:vacationresponse",
      rawData: newJObject(),
    ),
    ServerCapability(
      kind: ckWebsocket, rawUri: "urn:ietf:params:jmap:websocket", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckMdn, rawUri: "urn:ietf:params:jmap:mdn", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckSmimeVerify,
      rawUri: "urn:ietf:params:jmap:smimeverify",
      rawData: newJObject(),
    ),
    ServerCapability(
      kind: ckBlob, rawUri: "urn:ietf:params:jmap:blob", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckQuota, rawUri: "urn:ietf:params:jmap:quota", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckContacts, rawUri: "urn:ietf:params:jmap:contacts", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckCalendars, rawUri: "urn:ietf:params:jmap:calendars", rawData: newJObject()
    ),
    ServerCapability(
      kind: ckSieve, rawUri: "urn:ietf:params:jmap:sieve", rawData: newJObject()
    ),
  ]
  let session = parseSession(
      capabilities = capabilities,
      accounts = initTable[AccountId, Account](),
      primaryAccounts = initTable[string, AccountId](),
      username = "",
      apiUrl = "https://jmap.example.com/api/",
      downloadUrl = makeGoldenDownloadUrl(),
      uploadUrl = makeGoldenUploadUrl(),
      eventSourceUrl = makeGoldenEventSourceUrl(),
      state = makeState("s1"),
    )
    .get()
  let j = session.toJson()
  let capsObj = j{"capabilities"}
  doAssert capsObj != nil
  doAssert capsObj.kind == JObject
  # Verify all 12 standard URIs appear as keys
  const expectedUris = [
    "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
    "urn:ietf:params:jmap:submission", "urn:ietf:params:jmap:vacationresponse",
    "urn:ietf:params:jmap:websocket", "urn:ietf:params:jmap:mdn",
    "urn:ietf:params:jmap:smimeverify", "urn:ietf:params:jmap:blob",
    "urn:ietf:params:jmap:quota", "urn:ietf:params:jmap:contacts",
    "urn:ietf:params:jmap:calendars", "urn:ietf:params:jmap:sieve",
  ]
  for uri in expectedUris:
    doAssert capsObj{uri} != nil, "missing capability URI key: " & uri
  # Verify no enum symbolic names appear (e.g. "ckMail" should not be a key)
  doAssert capsObj{"ckCore"}.isNil, "symbolic name ckCore must not be a JSON key"
  doAssert capsObj{"ckMail"}.isNil, "symbolic name ckMail must not be a JSON key"
