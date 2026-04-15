# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8620 compliance tests. Each block verifies a normative requirement
## traceable to a specific section of RFC 8620. Block names follow the
## convention rfc8620_S<section>_<description>.

import std/json
import std/sets
import std/strutils
import std/tables

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/methods_enum
import jmap_client/framework
import jmap_client/errors
import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_errors
import jmap_client/serde_framework
import jmap_client/serde_session

import ../massertions
import ../mfixtures

# =============================================================================
# S1.2 — Id (RFC 8620 section 1.2)
# =============================================================================

block rfc8620_S1_2_idCharsetBase64url:
  ## Id charset is the base64url alphabet (A-Z, a-z, 0-9, hyphen, underscore).
  const full = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  assertOk parseId(full)

block rfc8620_S1_2_idEveryBase64urlCharAccepted:
  ## Every individual base64url character must be accepted as a valid Id.
  for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_":
    assertOk parseId($ch)

block rfc8620_S1_2_idSpaceRejected:
  ## Space (0x20) is not in the base64url alphabet.
  assertErr parseId("abc def")

block rfc8620_S1_2_idAtSignRejected:
  ## The '@' character is not in the base64url alphabet.
  assertErr parseId("user@host")

block rfc8620_S1_2_idMinLength:
  ## Id length MUST be at least 1 octet.
  assertOk parseId("x")

block rfc8620_S1_2_idEmptyRejected:
  ## Empty string (0 octets) violates the minimum length constraint.
  assertErr parseId("")

block rfc8620_S1_2_idMaxLength:
  ## Id length MUST be at most 255 octets.
  assertOk parseId('a'.repeat(255))

block rfc8620_S1_2_id256OctetsRejected:
  ## A 256-octet string exceeds the maximum allowed Id length.
  assertErr parseId('a'.repeat(256))

block rfc8620_S1_2_idPadCharExcluded:
  ## The base64url alphabet excludes the pad character '='.
  assertErr parseId("abc=def")

block rfc8620_S1_2_serverIdLenientAcceptsNonBase64url:
  ## Server-assigned IDs may contain chars outside base64url (interop decision).
  assertOk parseIdFromServer("abc+def")
  assertOk parseIdFromServer("user@host")

block rfc8620_S1_2_serverIdShouldRecommendations:
  ## RFC S1.2 SHOULD recommendations for Id allocation: IDs starting with dash,
  ## containing only digits, or the sequence "NIL" are still valid per the MUST.
  assertOk parseId("-abc")
  assertOk parseId("12345")
  assertOk parseId("NIL")

# =============================================================================
# S1.3 — Int / UnsignedInt (RFC 8620 section 1.3)
# =============================================================================

block rfc8620_S1_3_unsignedIntLowerBound:
  ## UnsignedInt minimum value is 0.
  assertOk parseUnsignedInt(0'i64)

block rfc8620_S1_3_unsignedIntUpperBound:
  ## UnsignedInt maximum value is 2^53-1 = 9007199254740991.
  assertOk parseUnsignedInt(9_007_199_254_740_991'i64)
  doAssert MaxUnsignedInt == 9_007_199_254_740_991'i64

block rfc8620_S1_3_unsignedIntNegativeRejected:
  ## UnsignedInt MUST NOT be negative.
  assertErr parseUnsignedInt(-1'i64)

block rfc8620_S1_3_unsignedIntOverflowRejected:
  ## UnsignedInt exceeding 2^53-1 MUST be rejected.
  assertErr parseUnsignedInt(9_007_199_254_740_992'i64)

block rfc8620_S1_3_jmapIntBounds:
  ## JmapInt range is -(2^53-1) to 2^53-1.
  assertOk parseJmapInt(9_007_199_254_740_991'i64)
  assertOk parseJmapInt(-9_007_199_254_740_991'i64)
  doAssert MaxJmapInt == 9_007_199_254_740_991'i64
  doAssert MinJmapInt == -9_007_199_254_740_991'i64

block rfc8620_S1_3_jmapIntOverflowRejected:
  ## Values outside the JSON-safe integer range MUST be rejected.
  assertErr parseJmapInt(9_007_199_254_740_992'i64)
  assertErr parseJmapInt(-9_007_199_254_740_992'i64)

# =============================================================================
# S1.4 — Date / UTCDate (RFC 8620 section 1.4)
# =============================================================================

block rfc8620_S1_4_dateFormat:
  ## Date format: YYYY-MM-DDTHH:MM:SS with timezone offset.
  assertOk parseDate("2024-11-15T09:30:00Z")

block rfc8620_S1_4_dateFractionalSeconds:
  ## Optional fractional seconds are permitted.
  assertOk parseDate("2024-11-15T09:30:00.123Z")

block rfc8620_S1_4_dateUppercaseTSeparator:
  ## The 'T' separator MUST be uppercase; lowercase 't' is rejected.
  assertErr parseDate("2024-11-15t09:30:00Z")

block rfc8620_S1_4_dateTimezoneZOrOffset:
  ## Timezone MUST be 'Z' or +/-HH:MM.
  assertOk parseDate("2024-11-15T09:30:00Z")
  assertOk parseDate("2024-11-15T09:30:00+05:30")
  assertOk parseDate("2024-11-15T09:30:00-08:00")

block rfc8620_S1_4_utcDateMustUseZ:
  ## UTCDate MUST use 'Z' as the timezone offset, not +00:00 or -00:00.
  assertOk parseUtcDate("2024-11-15T09:30:00Z")
  assertErr parseUtcDate("2024-11-15T09:30:00+00:00")
  assertErr parseUtcDate("2024-11-15T09:30:00-00:00")

block rfc8620_S1_4_zeroFractionalOmitted:
  ## Zero fractional seconds (.000) MUST be omitted; the parser rejects them.
  assertErr parseDate("2024-11-15T09:30:00.000Z")
  assertErr parseDate("2024-11-15T09:30:00.0Z")
  assertErr parseDate("2024-11-15T09:30:00.00Z")

block rfc8620_S1_4_dateLowercaseZRejected:
  ## Lowercase 'z' timezone violates the uppercase requirement.
  assertErr parseDate("2024-11-15T09:30:00z")

block rfc8620_S1_4_dateMissingTimezoneRejected:
  ## A date string with no timezone is too short (19 chars < 20 minimum).
  assertErr parseDate("2024-11-15T09:30:00")

block rfc8620_S1_4_dateCalendarSemanticsNotValidated:
  ## Intentional design decision: structural validation only. Feb 30 is accepted.
  ## This diverges from RFC 3339 Section 5.7 SHOULD but matches Layer 1 scope.
  assertOk parseDate("2024-02-30T12:00:00Z")

block rfc8620_S1_4_dateEmptyFractionalRejected:
  ## A dot with no following digits is rejected.
  assertErr parseDate("2024-01-01T12:00:00.Z")

block rfc8620_S1_4_dateHour24Accepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Hour 24 is
  ## structurally valid (two digits in the hour position).
  assertOk parseDate("2024-01-01T24:00:00Z")

block rfc8620_S1_4_dateMinute60Accepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Minute 60
  ## is structurally valid (two digits in the minute position).
  assertOk parseDate("2024-01-01T12:60:00Z")

block rfc8620_S1_4_dateSecond60Accepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Second 60
  ## is structurally valid and also meaningful as an RFC 3339 leap second.
  assertOk parseDate("2024-01-01T12:00:60Z")

block rfc8620_S1_4_dateMonthZeroAccepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Month 00
  ## is structurally valid (two digits in the month position).
  assertOk parseDate("2024-00-01T12:00:00Z")

block rfc8620_S1_4_dateDayZeroAccepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Day 00 is
  ## structurally valid (two digits in the day position).
  assertOk parseDate("2024-01-00T12:00:00Z")

block rfc8620_S1_4_dateYearZeroAccepted:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Year 0000
  ## is structurally valid (four digits in the year position).
  assertOk parseDate("0000-01-01T12:00:00Z")

block rfc8620_S1_4_dateTwoDigitFrac:
  ## Layer 1 validates structural format (correct digit positions, separators,
  ## uppercase T/Z) but defers value-range and calendar validation. Two-digit
  ## fractional seconds are structurally valid.
  assertOk parseDate("2024-01-01T12:00:00.12Z")

# =============================================================================
# S1.6.2 / S1.8 — AccountId and Vendor Extensions
# =============================================================================

block rfc8620_S1_6_2_accountIdLenientForServerAssigned:
  ## AccountId uses lenient validation because account IDs are server-assigned.
  ## Characters outside base64url (like '@') are accepted.
  assertOk parseAccountId("user@example.com")
  assertOk parseAccountId("abc+def/ghi")

block rfc8620_S1_8_vendorExtensionMapsToUnknown:
  ## Vendor extension URIs that are not IANA-registered map to ckUnknown.
  doAssert parseCapabilityKind("https://vendor.example/custom-ext") == ckUnknown

block rfc8620_S1_8_rawUriPreservedForVendorExtension:
  ## ServerCapability preserves the raw URI string for vendor extensions.
  let sc = ServerCapability(
    rawUri: "https://vendor.example/custom", kind: ckUnknown, rawData: newJObject()
  )
  doAssert sc.rawUri == "https://vendor.example/custom"
  doAssert sc.kind == ckUnknown

# =============================================================================
# S2 — Session (RFC 8620 section 2)
# =============================================================================

block rfc8620_S2_sessionRequiresCoreCapability:
  ## Session MUST include urn:ietf:params:jmap:core in capabilities.
  let args = makeSessionArgs()
  let noCore: seq[ServerCapability] = @[]
  assertErrContains parseSession(
    noCore, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  ), "urn:ietf:params:jmap:core"

block rfc8620_S2_sessionApiUrlNonEmpty:
  ## apiUrl MUST be non-empty.
  let args = makeSessionArgs()
  assertErrContains parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, "",
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  ), "apiUrl"

block rfc8620_S2_sessionDownloadUrlVariables:
  ## downloadUrl MUST contain {accountId}, {blobId}, {type}, {name}.
  let args = makeSessionArgs()
  # A URL missing required template variables must be rejected.
  let badDl = parseUriTemplate("https://example.com/download/").get()
  assertErrContains parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    badDl, args.uploadUrl, args.eventSourceUrl, args.state,
  ), "downloadUrl"

block rfc8620_S2_sessionUploadUrlVariable:
  ## uploadUrl MUST contain {accountId}.
  let args = makeSessionArgs()
  let badUp = parseUriTemplate("https://example.com/upload/").get()
  assertErrContains parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, badUp, args.eventSourceUrl, args.state,
  ), "uploadUrl"

block rfc8620_S2_sessionEventSourceUrlVariables:
  ## eventSourceUrl MUST contain {types}, {closeafter}, {ping}.
  let args = makeSessionArgs()
  let badEs = parseUriTemplate("https://example.com/events/").get()
  assertErrContains parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, badEs, args.state,
  ), "eventSourceUrl"

block rfc8620_S2_sessionValidConstructionSucceeds:
  ## A Session with all required fields and core capability succeeds.
  let args = makeSessionArgs()
  discard parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()

block rfc8620_S2_coreCapabilityUri:
  ## The core capability URI is urn:ietf:params:jmap:core.
  doAssert parseCapabilityKind("urn:ietf:params:jmap:core") == ckCore
  doAssert capabilityUri(ckCore).get() == "urn:ietf:params:jmap:core"

block rfc8620_S2_sessionStatePreserved:
  ## The constructed Session's state field equals the input state.
  let args = makeSessionArgs()
  let session = parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert session.state == args.state

block rfc8620_S2_primaryAccountsCoreAccepted:
  ## RFC S2 says urn:ietf:params:jmap:core SHOULD NOT be in primaryAccounts.
  ## Library accepts it (lenient for server data).
  let args = makeSessionArgs()
  var pa = args.primaryAccounts
  pa["urn:ietf:params:jmap:core"] = makeAccountId("A1")
  discard parseSession(
      args.capabilities, args.accounts, pa, args.username, args.apiUrl,
      args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()

block rfc8620_S2_coreCapabilitiesAllEightFields:
  ## RFC S2 defines exactly 8 MUST properties on the core capability object.
  let caps = realisticCoreCaps()
  doAssert caps.maxSizeUpload == parseUnsignedInt(50_000_000).get()
  doAssert caps.maxConcurrentUpload == parseUnsignedInt(4).get()
  doAssert caps.maxSizeRequest == parseUnsignedInt(10_000_000).get()
  doAssert caps.maxConcurrentRequests == parseUnsignedInt(8).get()
  doAssert caps.maxCallsInRequest == parseUnsignedInt(32).get()
  doAssert caps.maxObjectsInGet == parseUnsignedInt(1000).get()
  doAssert caps.maxObjectsInSet == parseUnsignedInt(500).get()
  doAssert caps.collationAlgorithms.len == 2

block rfc8620_S2_accountObjectStructure:
  ## RFC S2 Account object has name, isPersonal, isReadOnly, accountCapabilities.
  let acct = Account(
    name: "Personal", isPersonal: true, isReadOnly: false, accountCapabilities: @[]
  )
  doAssert acct.name == "Personal"
  doAssert acct.isPersonal == true
  doAssert acct.isReadOnly == false
  doAssert acct.accountCapabilities.len == 0

block rfc8620_S2_collationAlgorithmStandardIdentifiers:
  ## RFC 4790 standard collation identifiers used in JMAP core capabilities.
  let caps = realisticCoreCaps()
  doAssert caps.hasCollation(CollationAsciiCasemap)
  doAssert caps.hasCollation(CollationUnicodeCasemap)
  doAssert not caps.hasCollation(parseCollationAlgorithm("i;nonexistent").get())

# =============================================================================
# S3.2 — Invocation (RFC 8620 section 3.2)
# =============================================================================

block rfc8620_S3_2_invocationStructure:
  ## An Invocation has three elements: name, arguments, methodCallId.
  let mcid = makeMcid("call0")
  let inv = parseInvocation("Foo/get", newJObject(), mcid).get()
  doAssert inv.rawName == "Foo/get"
  doAssert inv.arguments.kind == JObject
  doAssert inv.methodCallId == mcid

block rfc8620_S3_2_methodCallIdCorrelation:
  ## methodCallId correlates a request invocation to its response.
  let mcid1 = makeMcid("c1")
  let mcid2 = makeMcid("c2")
  doAssert mcid1 != mcid2
  let inv1 = parseInvocation("A/get", newJObject(), mcid1).get()
  let inv2 = parseInvocation("B/get", newJObject(), mcid2).get()
  doAssert inv1.methodCallId != inv2.methodCallId

# =============================================================================
# S3.3 — The Request Object (RFC 8620 section 3.3)
# =============================================================================

block rfc8620_S3_3_requestUsingContainsCapabilities:
  ## The using property lists capability URIs the client wishes to use.
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[makeInvocation()],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`.len == 2
  doAssert req.`using`[0] == "urn:ietf:params:jmap:core"

block rfc8620_S3_3_requestMethodCallsOrderPreserved:
  ## Method calls are processed sequentially; ordering MUST be preserved.
  let mc0 = makeInvocation("A/get", makeMcid("c0"))
  let mc1 = makeInvocation("B/get", makeMcid("c1"))
  let mc2 = makeInvocation("C/get", makeMcid("c2"))
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[mc0, mc1, mc2],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 3
  doAssert req.methodCalls[0].rawName == "A/get"
  doAssert req.methodCalls[1].rawName == "B/get"
  doAssert req.methodCalls[2].rawName == "C/get"

block rfc8620_S3_3_requestCreatedIdsOptional:
  ## createdIds is optional; none is valid.
  let req = makeRequest()
  doAssert req.createdIds.isNone

block rfc8620_S3_3_requestCreatedIdsPresent:
  ## createdIds can carry a Table[CreationId, Id] for proxy splitting.
  var cids = initTable[CreationId, Id]()
  cids[makeCreationId("k0")] = makeId("serverId1")
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[makeInvocation()],
    createdIds: Opt.some(cids),
  )
  doAssert req.createdIds.isSome
  doAssert req.createdIds.get()[makeCreationId("k0")] == makeId("serverId1")

# =============================================================================
# S3.4 — The Response Object (RFC 8620 section 3.4)
# =============================================================================

block rfc8620_S3_4_responseMethodResponsesOrdering:
  ## Method responses maintain the order of the original request's method calls.
  let r0 = makeInvocation("A/get", makeMcid("c0"))
  let r1 = makeInvocation("B/get", makeMcid("c1"))
  let resp = Response(
    methodResponses: @[r0, r1],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("s1"),
  )
  doAssert resp.methodResponses.len == 2
  doAssert resp.methodResponses[0].rawName == "A/get"
  doAssert resp.methodResponses[1].rawName == "B/get"

block rfc8620_S3_4_responseSessionStateMandatory:
  ## sessionState is always present in a Response.
  let resp = makeResponse()
  doAssert resp.sessionState == makeState("rs1")

block rfc8620_S3_4_responseCreatedIdsOnlyIfRequested:
  ## createdIds in response is present only if given in the request.
  let resp = makeResponse()
  doAssert resp.createdIds.isNone

block rfc8620_S3_3_requestEmptyUsing:
  ## RFC 8620 S3.3: Layer 1 does not validate the using list contents.
  ## An empty using list is structurally valid at Layer 1; the server
  ## will reject it with unknownCapability if needed.
  let req = Request(
    `using`: @[],
    methodCalls: @[makeInvocation()],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`.len == 0

block rfc8620_S3_3_requestEmptyMethodCalls:
  ## RFC 8620 S3.3: Layer 1 does not validate the method calls list.
  ## An empty methodCalls list is structurally valid at Layer 1; the
  ## server may return an empty response.
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 0

block rfc8620_S3_3_requestDuplicateMethodCallIds:
  ## RFC 8620 S3.3: Layer 1 does not enforce method call ID uniqueness
  ## within a request. The RFC does not require unique IDs; the server
  ## correlates each response to its request position.
  let mcid = makeMcid("c0")
  let inv1 = makeInvocation("A/get", mcid)
  let inv2 = makeInvocation("B/get", mcid)
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[inv1, inv2],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 2
  doAssert req.methodCalls[0].methodCallId == req.methodCalls[1].methodCallId

block rfc8620_S3_4_responseErrorInvocation:
  ## RFC 8620 S3.4: A response may contain an Invocation with name="error"
  ## to signal a per-method failure. Layer 1 accepts any invocation name.
  let errInv = parseInvocation("error", %*{"type": "serverFail"}, makeMcid("c0")).get()
  let resp = makeResponse(methodResponses = @[errInv])
  doAssert resp.methodResponses.len == 1
  doAssert resp.methodResponses[0].rawName == "error"

# =============================================================================
# S3.6.1 — Request-Level Errors (RFC 8620 section 3.6.1)
# =============================================================================

block rfc8620_S3_6_1_requestErrorTypes:
  ## Request-level error types use the URN format urn:ietf:params:jmap:error:*.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:unknownCapability") ==
    retUnknownCapability
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notJSON") == retNotJson
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notRequest") ==
    retNotRequest
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:limit") == retLimit

block rfc8620_S3_6_1_requestErrorUrnFormat:
  ## All known request error types start with urn:ietf:params:jmap:error:.
  doAssert ($retUnknownCapability).startsWith("urn:ietf:params:jmap:error:")
  doAssert ($retNotJson).startsWith("urn:ietf:params:jmap:error:")
  doAssert ($retNotRequest).startsWith("urn:ietf:params:jmap:error:")
  doAssert ($retLimit).startsWith("urn:ietf:params:jmap:error:")

block rfc8620_S3_6_1_unknownRequestErrorFallback:
  ## Unknown request error types are gracefully handled as retUnknown.
  doAssert parseRequestErrorType("urn:vendor:custom:error") == retUnknown

block rfc8620_S3_6_1_limitErrorMustHaveLimitProperty:
  ## RFC S3.6.1: A "limit" property MUST be present for the "limit" error type.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest")
  )
  doAssert re.errorType == retLimit
  doAssert re.limit.isSome
  doAssert re.limit.get() == "maxCallsInRequest"

block rfc8620_S3_6_1_rfc7807TypeField:
  ## RFC 7807: the type field (rawType) round-trips the error URI.
  let re = requestError("urn:ietf:params:jmap:error:notJSON")
  doAssert re.rawType == "urn:ietf:params:jmap:error:notJSON"
  doAssert re.errorType == retNotJson

block rfc8620_S3_6_1_rfc7807ExtrasPreservesExtraFields:
  ## Non-standard fields in the problem details object are preserved in extras.
  let extra = %*{"vendor-field": "vendor-value"}
  let re = requestError(
    "urn:ietf:params:jmap:error:unknownCapability", extras = Opt.some(extra)
  )
  doAssert re.extras.isSome
  doAssert re.extras.get()["vendor-field"].getStr() == "vendor-value"

# =============================================================================
# S3.6.2 — Method-Level Errors (RFC 8620 section 3.6.2)
# =============================================================================

block rfc8620_S3_6_2_allMethodErrorTypesRecognised:
  ## Every RFC 8620 method error type must parse to its corresponding enum.
  doAssert parseMethodErrorType("serverUnavailable") == metServerUnavailable
  doAssert parseMethodErrorType("serverFail") == metServerFail
  doAssert parseMethodErrorType("serverPartialFail") == metServerPartialFail
  doAssert parseMethodErrorType("unknownMethod") == metUnknownMethod
  doAssert parseMethodErrorType("invalidArguments") == metInvalidArguments
  doAssert parseMethodErrorType("invalidResultReference") == metInvalidResultReference
  doAssert parseMethodErrorType("forbidden") == metForbidden
  doAssert parseMethodErrorType("accountNotFound") == metAccountNotFound
  doAssert parseMethodErrorType("accountNotSupportedByMethod") ==
    metAccountNotSupportedByMethod
  doAssert parseMethodErrorType("accountReadOnly") == metAccountReadOnly

block rfc8620_S3_6_2_extendedMethodErrorTypes:
  ## Additional method-level errors from standard /query, /changes, /set, /copy.
  doAssert parseMethodErrorType("anchorNotFound") == metAnchorNotFound
  doAssert parseMethodErrorType("unsupportedSort") == metUnsupportedSort
  doAssert parseMethodErrorType("unsupportedFilter") == metUnsupportedFilter
  doAssert parseMethodErrorType("cannotCalculateChanges") == metCannotCalculateChanges
  doAssert parseMethodErrorType("tooManyChanges") == metTooManyChanges
  doAssert parseMethodErrorType("requestTooLarge") == metRequestTooLarge
  doAssert parseMethodErrorType("stateMismatch") == metStateMismatch
  doAssert parseMethodErrorType("fromAccountNotFound") == metFromAccountNotFound
  doAssert parseMethodErrorType("fromAccountNotSupportedByMethod") ==
    metFromAccountNotSupportedByMethod

block rfc8620_S3_6_2_unknownMethodErrorFallback:
  ## Server extensions that define new error types must not crash the parser.
  doAssert parseMethodErrorType("vendorExtensionError") == metUnknown

block rfc8620_S3_6_2_methodErrorMayHaveDescription:
  ## RFC S3.6.2: A method error MAY include a "description" property.
  let me =
    methodError("invalidArguments", description = Opt.some("missing required field"))
  doAssert me.errorType == metInvalidArguments
  doAssert me.description.isSome
  doAssert me.description.get() == "missing required field"

block rfc8620_S3_6_2_errorResponseNameConvention:
  ## RFC S3.6.2: Method-level error responses use "error" as the invocation name.
  ## This is a convention verified at the type level by constructing an Invocation.
  let errInv =
    parseInvocation("error", %*{"type": "invalidArguments"}, makeMcid("c0")).get()
  doAssert errInv.rawName == "error"

block rfc8620_S3_6_1_requestErrorCaseSensitiveFirstChar:
  ## RFC 8620 S3.6.1: parseRequestErrorType uses strutils.parseEnum which
  ## applies nimIdentNormalize. The first character is case-sensitive, so
  ## capitalising the 'u' in 'urn' causes the parse to fall through to
  ## retUnknown.
  doAssert parseRequestErrorType("Urn:ietf:params:jmap:error:limit") == retUnknown

block rfc8620_S3_6_2_methodErrorCaseSensitiveFirstChar:
  ## RFC 8620 S3.6.2: parseMethodErrorType uses strutils.parseEnum which
  ## applies nimIdentNormalize. The first character is case-sensitive, so
  ## capitalising the 's' in 'serverFail' causes the parse to fall through
  ## to metUnknown.
  doAssert parseMethodErrorType("ServerFail") == metUnknown

block rfc8620_S3_6_2_methodErrorCaseInsensitiveAfterFirst:
  ## RFC 8620 S3.6.2: nimIdentNormalize is case-insensitive after the first
  ## character and strips underscores. "serverFAIL" matches "serverFail"
  ## because the first character 's' matches and subsequent characters are
  ## normalised.
  doAssert parseMethodErrorType("serverFAIL") == metServerFail

block rfc8620_S3_6_2_setErrorCaseSensitiveFirstChar:
  ## RFC 8620 S3.6.2: parseSetErrorType uses strutils.parseEnum which
  ## applies nimIdentNormalize. The first character is case-sensitive, so
  ## capitalising the 'f' in 'forbidden' causes the parse to fall through
  ## to setUnknown.
  doAssert parseSetErrorType("Forbidden") == setUnknown

block rfc8620_S3_6_1_requestErrorMinimalFields:
  ## RFC 8620 S3.6.1: a RequestError can be constructed with only rawType;
  ## all optional fields default to none.
  let re = requestError("urn:ietf:params:jmap:error:limit")
  doAssert re.errorType == retLimit
  doAssert re.rawType == "urn:ietf:params:jmap:error:limit"
  doAssert re.status.isNone
  doAssert re.title.isNone
  doAssert re.detail.isNone
  doAssert re.limit.isNone
  doAssert re.extras.isNone

block rfc8620_S3_6_2_methodErrorMinimalFields:
  ## RFC 8620 S3.6.2: a MethodError can be constructed with only rawType;
  ## all optional fields default to none.
  let me = methodError("serverFail")
  doAssert me.errorType == metServerFail
  doAssert me.rawType == "serverFail"
  doAssert me.description.isNone
  doAssert me.extras.isNone

block rfc8620_S3_6_2_setErrorMinimalFields:
  ## RFC 8620 S3.6.2: a SetError can be constructed with only rawType;
  ## all optional fields default to none.
  let se = setError("forbidden")
  doAssert se.errorType == setForbidden
  doAssert se.rawType == "forbidden"
  doAssert se.description.isNone
  doAssert se.extras.isNone

# =============================================================================
# S3.7 — ResultReference (RFC 8620 section 3.7)
# =============================================================================

block rfc8620_S3_7_resultReferencePathConstants:
  ## The spec defines standard JSON Pointer paths for result references.
  doAssert $rpIds == "/ids"
  doAssert $rpListIds == "/list/*/id"
  doAssert $rpAddedIds == "/added/*/id"
  doAssert $rpCreated == "/created"
  doAssert $rpUpdated == "/updated"
  doAssert $rpUpdatedProperties == "/updatedProperties"

block rfc8620_S3_7_resultReferenceConstruction:
  ## A ResultReference ties a back-reference to a previous call's result.
  let mcid = makeMcid("c0")
  let rr = initResultReference(resultOf = mcid, name = mnMailboxGet, path = rpIds)
  doAssert rr.resultOf == mcid
  doAssert rr.name == mnMailboxGet
  doAssert rr.path == rpIds

block rfc8620_S3_7_referencableVariants:
  ## Referencable[T] is either a direct value or a result reference.
  let directIds = direct(@[makeId("id1")])
  doAssert directIds.kind == rkDirect

  let mcid = makeMcid("c0")
  let rr = initResultReference(resultOf = mcid, name = mnMailboxQuery, path = rpIds)
  let refIds = referenceTo[seq[Id]](rr)
  doAssert refIds.kind == rkReference
  doAssert refIds.reference.path == rpIds

block rfc8620_S3_7_wildcardInPath:
  ## RFC S3.7: The '*' character is a JMAP extension to JSON Pointer for array wildcard.
  doAssert '*' in $rpListIds
  doAssert '*' in $rpAddedIds

block rfc8620_S3_7_resultReferenceTriple:
  ## A ResultReference has all three required fields: resultOf, name, path.
  let rr = makeResultReference(makeMcid("c0"), mnEmailQuery, rpIds)
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == mnEmailQuery
  doAssert rr.path == rpIds

block rfc8620_S3_7_resultReferenceEmptyPath:
  ## RFC 8620 S3.7: parseResultReference validates that path is non-empty.
  ## An empty path is rejected with a ValidationError.
  let rr =
    parseResultReference(resultOf = makeMcid("c0"), name = "Mailbox/get", path = "")
  doAssert rr.isErr
  doAssert "must not be empty" in rr.error.message

block rfc8620_S3_7_resultReferenceRootPath:
  ## RFC 8620 S3.7: the wire-boundary parser stores the path string as-is.
  ## A root JSON Pointer "/" is accepted at Layer 1; semantic validation
  ## is deferred to the server. Non-enum paths round-trip via parseResultReference.
  let rr = parseResultReference(
      resultOf = makeMcid("c0"), name = "Mailbox/get", path = "/"
    )
    .get()
  doAssert rr.rawPath == "/"

block rfc8620_S3_7_resultReferenceDoubleSeparator:
  ## RFC 8620 S3.7: the wire-boundary parser stores the path string as-is.
  ## A double separator "//" is accepted at Layer 1; path syntax validation
  ## is a Layer 3 concern. Non-enum paths round-trip via parseResultReference.
  let rr = parseResultReference(
      resultOf = makeMcid("c0"), name = "Mailbox/get", path = "//"
    )
    .get()
  doAssert rr.rawPath == "//"

# =============================================================================
# S5.3 — SetError (RFC 8620 section 5.3)
# =============================================================================

block rfc8620_S5_3_setErrorTypesRecognised:
  ## All RFC 8620 SetError types must parse correctly.
  doAssert parseSetErrorType("forbidden") == setForbidden
  doAssert parseSetErrorType("overQuota") == setOverQuota
  doAssert parseSetErrorType("tooLarge") == setTooLarge
  doAssert parseSetErrorType("rateLimit") == setRateLimit
  doAssert parseSetErrorType("notFound") == setNotFound
  doAssert parseSetErrorType("invalidPatch") == setInvalidPatch
  doAssert parseSetErrorType("willDestroy") == setWillDestroy
  doAssert parseSetErrorType("invalidProperties") == setInvalidProperties
  doAssert parseSetErrorType("alreadyExists") == setAlreadyExists
  doAssert parseSetErrorType("singleton") == setSingleton

block rfc8620_S5_3_invalidPropertiesMustIncludeProperties:
  ## The invalidProperties error MUST include a properties field listing
  ## the property names that were invalid.
  let se = setErrorInvalidProperties("invalidProperties", @["subject", "from"])
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties.len == 2
  doAssert "subject" in se.properties
  doAssert "from" in se.properties

block rfc8620_S5_3_alreadyExistsMustIncludeExistingId:
  ## The alreadyExists error MUST include an existingId field.
  let existId = makeId("existing42")
  let se = setErrorAlreadyExists("alreadyExists", existId)
  doAssert se.errorType == setAlreadyExists
  doAssert se.existingId == existId

block rfc8620_S5_3_setErrorMayHaveDescription:
  ## RFC S5.3: A SetError MAY include a "description" property.
  let se = setError("forbidden", description = Opt.some("not authorised"))
  doAssert se.description.isSome
  doAssert se.description.get() == "not authorised"

block rfc8620_S5_3_creationIdOmitsHashPrefix:
  ## RFC S5.3: The '#' prefix is wire-format only. CreationId rejects it.
  assertErr parseCreationId("#abc")

block rfc8620_S5_3_creationIdAcceptsPlain:
  ## Plain creation IDs without '#' are valid.
  assertOk parseCreationId("abc")
  assertOk parseCreationId("k0")

# =============================================================================
# S5.4 — /copy Method Errors (RFC 8620 section 5.4)
# =============================================================================

block rfc8620_S5_4_fromAccountNotFoundError:
  ## /copy-specific error: the source account was not found.
  doAssert parseMethodErrorType("fromAccountNotFound") == metFromAccountNotFound

block rfc8620_S5_4_fromAccountNotSupportedError:
  ## /copy-specific error: the source account does not support this method.
  doAssert parseMethodErrorType("fromAccountNotSupportedByMethod") ==
    metFromAccountNotSupportedByMethod

# =============================================================================
# S5.5 — Filter / Comparator (RFC 8620 section 5.5)
# =============================================================================

block rfc8620_S5_5_filterOperators:
  ## FilterOperator enum values match RFC 8620 definitions: AND, OR, NOT.
  doAssert $foAnd == "AND"
  doAssert $foOr == "OR"
  doAssert $foNot == "NOT"

block rfc8620_S5_5_notOperatorSemantics:
  ## NOT means "none of the conditions must match" — it wraps child filters.
  let cond1 = filterCondition("a")
  let cond2 = filterCondition("b")
  let notFilter = filterOperator(foNot, @[cond1, cond2])
  doAssert notFilter.kind == fkOperator
  doAssert notFilter.operator == foNot
  doAssert notFilter.conditions.len == 2

block rfc8620_S5_5_comparatorDefaultAscending:
  ## Comparator isAscending defaults to true per RFC 8620.
  let prop = makePropertyName("receivedAt")
  let cmp = parseComparator(prop)
  doAssert cmp.isAscending == true

block rfc8620_S5_5_comparatorExplicitDescending:
  ## Comparator isAscending can be explicitly set to false.
  let prop = makePropertyName("size")
  let cmp = parseComparator(prop, isAscending = false)
  doAssert cmp.isAscending == false

block rfc8620_S5_5_comparatorCollationRfc4790Format:
  ## RFC 4790 collation identifier in Comparator.
  let prop = makePropertyName("subject")
  let cmp = parseComparator(prop, collation = Opt.some(CollationAsciiCasemap))
  doAssert cmp.collation.isSome
  doAssert cmp.collation.get() == CollationAsciiCasemap

block rfc8620_S5_5_filterDeepNesting:
  ## A 3-level deep filter tree is structurally valid.
  let leaf1 = filterCondition("a")
  let leaf2 = filterCondition("b")
  let leaf3 = filterCondition("c")
  let mid = filterOperator(foAnd, @[leaf1, leaf2])
  let top = filterOperator(foOr, @[mid, filterOperator(foNot, @[leaf3])])
  doAssert top.kind == fkOperator
  doAssert top.conditions[0].kind == fkOperator
  doAssert top.conditions[0].conditions[0].kind == fkCondition

block rfc8620_S5_5_filterNotMultipleChildren:
  ## RFC 8620 S5.5: the NOT operator semantically applies to exactly one
  ## child, but Layer 1 does not enforce this constraint. Multiple children
  ## under NOT are accepted at Layer 1; semantic validation is a Layer 3
  ## concern.
  let cond1 = filterCondition(1)
  let cond2 = filterCondition(2)
  let notFilter = filterOperator(foNot, @[cond1, cond2])
  doAssert notFilter.kind == fkOperator
  doAssert notFilter.operator == foNot
  doAssert notFilter.conditions.len == 2

block rfc8620_S5_5_filterEmptyConditions:
  ## RFC 8620 S5.5: Layer 1 does not validate the conditions list length.
  ## An empty conditions list under AND is accepted at Layer 1; semantic
  ## validation is deferred to Layer 3.
  let f = filterOperator[int](foAnd, @[])
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  doAssert f.conditions.len == 0

block rfc8620_S5_5_comparatorDefaultAscendingTrue:
  ## RFC 8620 S5.5: "If true or not present, sort is ascending."
  ## The parseComparator factory defaults isAscending to true, matching
  ## the RFC's specified default behaviour.
  let prop = makePropertyName("date")
  let cmp = parseComparator(prop)
  doAssert cmp.isAscending == true
  doAssert cmp.collation.isNone

block rfc8620_S5_5_comparatorWithCollation:
  ## RFC 8620 S5.5: a Comparator may include a collation identifier
  ## (RFC 4790 format). "i;ascii-casemap" is a standard collation.
  let prop = makePropertyName("subject")
  let cmp = parseComparator(
    prop, isAscending = true, collation = Opt.some(CollationAsciiCasemap)
  )
  doAssert cmp.property == prop
  doAssert cmp.isAscending == true
  doAssert cmp.collation.isSome
  doAssert cmp.collation.get() == CollationAsciiCasemap

# =============================================================================
# S5.6 — /queryChanges (RFC 8620 section 5.6)
# =============================================================================

block rfc8620_S5_6_addedItemStructure:
  ## AddedItem has id (Id) and index (UnsignedInt).
  let item = makeAddedItem(makeId("id1"), 42'i64)
  doAssert item.id == makeId("id1")
  doAssert item.index == parseUnsignedInt(42).get()

block rfc8620_S5_6_tooManyChangesError:
  ## /queryChanges-specific error type.
  doAssert parseMethodErrorType("tooManyChanges") == metTooManyChanges

# =============================================================================
# S9 — IANA Considerations and Conformance (RFC 8620 section 9)
# =============================================================================

block rfc8620_S9_4_allKnownCapabilitiesUseJmapUrnPrefix:
  ## All IANA-registered JMAP capabilities use the urn:ietf:params:jmap: prefix.
  for kind in CapabilityKind:
    if kind != ckUnknown:
      let uri = capabilityUri(kind)
      doAssert uri.isSome
      doAssert uri.get().startsWith("urn:ietf:params:jmap:")

block rfc8620_S9_4_capabilityKindBijectiveRoundTrip:
  ## For every known kind, parseCapabilityKind(capabilityUri(kind)) == kind.
  for kind in CapabilityKind:
    if kind != ckUnknown:
      let uri = capabilityUri(kind).get()
      doAssert parseCapabilityKind(uri) == kind

block rfc8620_S9_5_allIanaMethodErrorCodesRegistered:
  ## Every RFC 8620 method error type round-trips through parse.
  for met in MethodErrorType:
    if met != metUnknown:
      doAssert parseMethodErrorType($met) == met

block rfc8620_S9_5_allIanaSetErrorCodesRegistered:
  ## Every RFC 8620 set error type round-trips through parse.
  for se in SetErrorType:
    if se != setUnknown:
      doAssert parseSetErrorType($se) == se

block rfc8620_conformance_parseEnumNimIdentNormalize:
  ## Documentation: nimIdentNormalize in parseEnum strips underscores and
  ## case-folds after the first character. This means non-RFC strings like
  ## "server_Fail" match "serverFail". This is a known conformance risk.
  doAssert parseMethodErrorType("server_Fail") == metServerFail
  doAssert parseMethodErrorType("serverfail") == metServerFail
  ## But first-character case sensitivity is preserved:
  doAssert parseMethodErrorType("ServerFail") == metUnknown

block rfc8620_conformance_losslessRoundTripAllErrorTypes:
  ## All error constructors preserve rawType for lossless round-trip.
  ## ``setError`` defensively maps payload-bearing rawType strings without
  ## wire data to ``setUnknown``, so round-trip only holds for the
  ## payload-less variants.
  for met in MethodErrorType:
    if met != metUnknown:
      doAssert methodError($met).rawType == $met
  const PayloadBearing = {
    setInvalidProperties, setAlreadyExists, setBlobNotFound, setInvalidEmail,
    setTooManyRecipients, setInvalidRecipients,
  }
  for se in SetErrorType:
    if se notin PayloadBearing + {setUnknown}:
      doAssert setError($se).rawType == $se
  for re in RequestErrorType:
    if re != retUnknown:
      doAssert requestError($re).rawType == $re

# =============================================================================
# RFC 8621 — JMAP Mail error type classification
# =============================================================================

block rfc8621_setErrorMailboxHasChildClassified:
  ## RFC 8621 §2.3 mailboxHasChild is now a first-class SetErrorType variant.
  doAssert parseSetErrorType("mailboxHasChild") == setMailboxHasChild

block rfc8621_setErrorBlobNotFoundClassified:
  ## RFC 8621 §4.6 blobNotFound is now a first-class payload-bearing variant.
  doAssert parseSetErrorType("blobNotFound") == setBlobNotFound

block rfc8621_submissionErrorsClassified:
  ## RFC 8621 §7.5 submission-specific error types are first-class variants.
  doAssert parseSetErrorType("forbiddenFrom") == setForbiddenFrom
  doAssert parseSetErrorType("forbiddenToSend") == setForbiddenToSend
  doAssert parseSetErrorType("noRecipients") == setNoRecipients

# =============================================================================
# Phase 5 — Priority 1: MUST requirements
# =============================================================================

block rfc8620_S1_2_idRejectsStandardBase64Chars:
  ## RFC 4648 S5: base64url excludes '+' and '/' from standard base64.
  assertErr parseId("abc+def")
  assertErr parseId("abc/def")

block rfc8620_S1_2_lenientRejectsNulDelTab:
  ## Lenient Id parsing still rejects control characters individually.
  assertErr parseIdFromServer("\x00")
  assertErr parseIdFromServer("\x7F")
  assertErr parseIdFromServer("\x09")

block rfc8620_S3_2_responseDuplicateMethodCallId:
  ## RFC 8620 S3.2: a method may return one or more responses, all sharing
  ## the same methodCallId.
  let mcid = makeMcid("c0")
  let inv1 = initInvocation(mnMailboxGet, newJObject(), mcid)
  let inv2 = initInvocation(mnMailboxGet, newJObject(), mcid)
  let resp = makeResponse(methodResponses = @[inv1, inv2])
  doAssert resp.methodResponses.len == 2
  doAssert resp.methodResponses[0].methodCallId == resp.methodResponses[1].methodCallId

block rfc8620_S3_4_responseCreatedIdsMerged:
  ## RFC 8620 S3.4: response createdIds includes both request-passed and
  ## server-added entries.
  let cid1 = makeCreationId("k1")
  let cid2 = makeCreationId("k2")
  let id1 = makeId("server1")
  let id2 = makeId("server2")
  var merged = initTable[CreationId, Id]()
  merged[cid1] = id1
  merged[cid2] = id2
  let resp = makeResponse(createdIds = Opt.some(merged))
  doAssert resp.createdIds.isSome
  let ids = resp.createdIds.get()
  doAssert ids.len == 2
  doAssert ids[cid1] == id1
  doAssert ids[cid2] == id2

block rfc8620_S3_6_1_requestErrorAllRfc7807Fields:
  ## RFC 7807 problem details: all optional fields populated.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    status = Opt.some(400),
    title = Opt.some("Rate Limit"),
    detail = Opt.some("Too many requests"),
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(newJObject()),
  )
  doAssert re.errorType == retLimit
  doAssert re.status.get() == 400
  doAssert re.title.get() == "Rate Limit"
  doAssert re.detail.get() == "Too many requests"
  doAssert re.limit.get() == "maxCallsInRequest"
  doAssert re.extras.isSome

block rfc8620_S3_6_2_methodErrorRawTypeNonEmpty:
  ## rawType is always non-empty for all known MethodErrorType variants.
  const knownTypes = [
    "serverUnavailable", "serverFail", "serverPartialFail", "unknownMethod",
    "invalidArguments", "invalidResultReference", "forbidden", "accountNotFound",
    "accountNotSupportedByMethod", "accountReadOnly", "anchorNotFound",
    "unsupportedSort", "unsupportedFilter", "cannotCalculateChanges", "tooManyChanges",
    "requestTooLarge", "stateMismatch", "fromAccountNotFound",
    "fromAccountNotSupportedByMethod",
  ]
  for rt in knownTypes:
    let me = methodError(rt)
    doAssert me.rawType.len > 0
    doAssert me.rawType == rt

block rfc8620_S5_3_setErrorDefensiveFallback:
  ## Generic setError() defensively maps variant-specific types to setUnknown
  ## when the caller does not provide variant-specific data.
  let seIp = setError("invalidProperties")
  doAssert seIp.errorType == setUnknown
  doAssert seIp.rawType == "invalidProperties"
  let seAe = setError("alreadyExists")
  doAssert seAe.errorType == setUnknown
  doAssert seAe.rawType == "alreadyExists"

# =============================================================================
# Phase 5 — Priority 2: SHOULD requirements and boundary coverage
# =============================================================================

block rfc8620_S2_sessionEmptyUsername:
  ## RFC 8620 S2: username MAY be empty.
  var args = makeSessionArgs()
  args.username = ""
  assertOk parseSessionFromArgs(args)

block rfc8620_S2_sessionEmptyAccounts:
  ## Empty accounts table is valid (server may have no accessible accounts).
  var args = makeSessionArgs()
  args.accounts = initTable[AccountId, Account]()
  args.primaryAccounts = initTable[string, AccountId]()
  assertOk parseSessionFromArgs(args)

block rfc8620_S1_3_jmapIntZero:
  ## Zero is a valid JmapInt.
  assertEq parseJmapInt(0).get(), JmapInt(0)

block rfc8620_S1_4_utcDateWithFractionalSeconds:
  ## UTCDate with fractional seconds and Z suffix.
  assertOk parseUtcDate("2024-01-15T10:30:00.123Z")

block rfc8620_S1_4_dateWithPlusZeroOffset:
  ## Date with +00:00 offset is valid.
  assertOk parseDate("2024-01-15T10:30:00+00:00")

block rfc8620_S5_5_comparatorCollationDefault:
  ## Comparator collation defaults to none when not specified.
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn)
  doAssert c.collation.isNone

block rfc8620_S5_5_filterOperatorEmptyConditions:
  ## Filter operator with empty conditions list.
  let f = filterOperator[int](foAnd, @[])
  doAssert f.kind == fkOperator
  doAssert f.conditions.len == 0

block rfc8620_S3_6_1_requestErrorLimitName:
  ## The "limit" field for retLimit specifies which limit was exceeded.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest")
  )
  doAssert re.errorType == retLimit
  doAssert re.limit.get() == "maxCallsInRequest"

# =============================================================================
# Phase 5 — Priority 3: Cross-RFC references
# =============================================================================

block rfc8620_crossRef_rfc4648_base64urlAlphabetSize:
  ## RFC 4648 S5: base64url alphabet has exactly 64 characters.
  var count = 0
  for c in char.low .. char.high:
    if c in Base64UrlChars:
      inc count
  doAssert count == 64

block rfc8620_crossRef_rfc3339_leapSecond:
  ## RFC 3339 allows leap seconds (second=60). Layer 1 performs structural
  ## validation only (no calendar semantics), so this is accepted.
  assertOk parseDate("2016-12-31T23:59:60Z")

block rfc8620_crossRef_rfc7807_aboutBlank:
  ## RFC 7807: "about:blank" as error type maps to unknown variants.
  doAssert parseRequestErrorType("about:blank") == retUnknown
  doAssert parseMethodErrorType("about:blank") == metUnknown
  doAssert parseSetErrorType("about:blank") == setUnknown

# =============================================================================
# Phase 5 — Documentation-only blocks for out-of-scope requirements
# =============================================================================

block rfc8620_S3_1_iJsonCompliance:
  ## RFC 8620 S3.1: "All data is exchanged as I-JSON (RFC 7493)."
  ## I-JSON compliance is a Layer 2 (serialisation) concern, not Layer 1.
  discard

block rfc8620_S3_1_httpContentType:
  ## RFC 8620 S3.1: "application/json" Content-Type header.
  ## HTTP headers are a Layer 4 (transport) concern, not Layer 1.
  discard

block rfc8620_S3_5_resultReferenceResolution:
  ## RFC 8620 S3.5: result reference path resolution and back-reference
  ## evaluation. This is a Layer 3 (protocol logic) concern, not Layer 1.
  ## Layer 1 only defines the ResultReference type and path constants.
  discard

block rfc8620_S3_7_hashPrefixHandling:
  ## RFC 8620 S3.7: the '#' prefix in property names triggers back-reference
  ## processing. This prefix handling is a Layer 2/3 concern. Layer 1 only
  ## defines CreationId without the '#' prefix.
  discard

# =============================================================================
# Phase 3: downloadUrl individual missing variable tests (RFC 8620 S2)
# =============================================================================

block rfc8620_S2_downloadUrlMissingAccountId:
  ## downloadUrl with {blobId},{type},{name} but NOT {accountId}.
  var args = makeSessionArgs()
  args.downloadUrl =
    parseUriTemplate("https://e.com/{blobId}/{name}?accept={type}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "downloadUrl missing {accountId}",
    "https://e.com/{blobId}/{name}?accept={type}"

block rfc8620_S2_downloadUrlMissingBlobId:
  ## downloadUrl with {accountId},{type},{name} but NOT {blobId}.
  var args = makeSessionArgs()
  args.downloadUrl =
    parseUriTemplate("https://e.com/{accountId}/{name}?accept={type}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "downloadUrl missing {blobId}",
    "https://e.com/{accountId}/{name}?accept={type}"

block rfc8620_S2_downloadUrlMissingType:
  ## downloadUrl with {accountId},{blobId},{name} but NOT {type}.
  var args = makeSessionArgs()
  args.downloadUrl = parseUriTemplate("https://e.com/{accountId}/{blobId}/{name}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session", "downloadUrl missing {type}", "https://e.com/{accountId}/{blobId}/{name}"

block rfc8620_S2_downloadUrlMissingName:
  ## downloadUrl with {accountId},{blobId},{type} but NOT {name}.
  var args = makeSessionArgs()
  args.downloadUrl =
    parseUriTemplate("https://e.com/{accountId}/{blobId}?accept={type}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "downloadUrl missing {name}",
    "https://e.com/{accountId}/{blobId}?accept={type}"

# =============================================================================
# Phase 3: eventSourceUrl individual missing variable tests (RFC 8620 S2)
# =============================================================================

block rfc8620_S2_eventSourceUrlMissingTypes:
  ## eventSourceUrl with {closeafter},{ping} but NOT {types}.
  var args = makeSessionArgs()
  args.eventSourceUrl =
    parseUriTemplate("https://e.com/events?closeafter={closeafter}&ping={ping}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "eventSourceUrl missing {types}",
    "https://e.com/events?closeafter={closeafter}&ping={ping}"

block rfc8620_S2_eventSourceUrlMissingCloseafter:
  ## eventSourceUrl with {types},{ping} but NOT {closeafter}.
  var args = makeSessionArgs()
  args.eventSourceUrl =
    parseUriTemplate("https://e.com/events?types={types}&ping={ping}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "eventSourceUrl missing {closeafter}",
    "https://e.com/events?types={types}&ping={ping}"

block rfc8620_S2_eventSourceUrlMissingPing:
  ## eventSourceUrl with {types},{closeafter} but NOT {ping}.
  var args = makeSessionArgs()
  args.eventSourceUrl =
    parseUriTemplate("https://e.com/events?types={types}&closeafter={closeafter}").get()
  assertErrFields tryParseSessionFromArgs(args),
    "Session",
    "eventSourceUrl missing {ping}",
    "https://e.com/events?types={types}&closeafter={closeafter}"

# =============================================================================
# Phase 6A — Byte-for-byte RFC golden tests (serde round-trip)
# =============================================================================

block rfc8620_S2_goldenSessionToJson:
  ## Construct a Session matching RFC 8620 section 2.1 example values,
  ## serialise with toJson(), and verify key JSON field values match.
  let j = goldenSessionJson()
  let r = Session.fromJson(j).get()
  let session = r
  # Verify structural properties
  assertEq session.username, "john@example.com"
  assertEq session.apiUrl, "https://jmap.example.com/api/"
  assertEq session.state, parseJmapState("75128aab4b1b").get()
  # Serialise and verify key fields in the output JSON
  let outJson = session.toJson()
  assertEq outJson{"username"}.getStr(""), "john@example.com"
  assertEq outJson{"apiUrl"}.getStr(""), "https://jmap.example.com/api/"
  assertEq outJson{"state"}.getStr(""), "75128aab4b1b"
  doAssert outJson{"capabilities"} != nil
  doAssert outJson{"capabilities"}.kind == JObject
  doAssert outJson{"capabilities"}{"urn:ietf:params:jmap:core"} != nil
  doAssert outJson{"accounts"} != nil
  doAssert outJson{"accounts"}.kind == JObject
  doAssert outJson{"primaryAccounts"} != nil
  doAssert outJson{"primaryAccounts"}.kind == JObject
  # Verify download/upload/eventSource URLs
  assertEq outJson{"downloadUrl"}.getStr(""),
    "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}"
  assertEq outJson{"uploadUrl"}.getStr(""),
    "https://jmap.example.com/upload/{accountId}/"
  assertEq outJson{"eventSourceUrl"}.getStr(""),
    "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}"

block rfc8620_S3_3_goldenRequestToJson:
  ## Construct a Request matching RFC 8620 section 3.3.1 example, serialise,
  ## and verify the JSON structure matches.
  let inv1 = parseInvocation(
      "method1", %*{"arg1": "arg1data", "arg2": "arg2data"}, makeMcid("c1")
    )
    .get()
  let inv2 = parseInvocation("method2", %*{"arg1": "arg1data"}, makeMcid("c2")).get()
  let inv3 = parseInvocation("method3", newJObject(), makeMcid("c3")).get()
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[inv1, inv2, inv3],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  let j = req.toJson()
  # Verify using array
  doAssert j{"using"} != nil
  doAssert j{"using"}.kind == JArray
  assertEq j{"using"}.len, 2
  assertEq j{"using"}.getElems(@[])[0].getStr(""), "urn:ietf:params:jmap:core"
  assertEq j{"using"}.getElems(@[])[1].getStr(""), "urn:ietf:params:jmap:mail"
  # Verify methodCalls array
  doAssert j{"methodCalls"} != nil
  doAssert j{"methodCalls"}.kind == JArray
  assertEq j{"methodCalls"}.len, 3
  # First method call: ["method1", {"arg1": "arg1data", "arg2": "arg2data"}, "c1"]
  let mc0 = j{"methodCalls"}.getElems(@[])[0]
  assertEq mc0.getElems(@[])[0].getStr(""), "method1"
  assertEq mc0.getElems(@[])[2].getStr(""), "c1"
  assertEq mc0.getElems(@[])[1]{"arg1"}.getStr(""), "arg1data"
  # createdIds must be absent
  doAssert j{"createdIds"}.isNil

block rfc8620_S3_4_goldenResponseFromJson:
  ## Parse a Response JSON matching RFC 8620 section 3.4.1 example and verify
  ## all typed fields match expected values.
  let j = goldenResponseJson()
  let r = Response.fromJson(j).get()
  let resp = r
  assertEq resp.methodResponses.len, 4
  # First response: ["method1", {"arg1": 3, "arg2": "foo"}, "c1"]
  assertEq resp.methodResponses[0].rawName, "method1"
  assertEq resp.methodResponses[0].methodCallId, makeMcid("c1")
  assertEq resp.methodResponses[0].arguments{"arg1"}.getInt(0), 3
  assertEq resp.methodResponses[0].arguments{"arg2"}.getStr(""), "foo"
  # Second response: ["method2", {"isBlah": true}, "c2"]
  assertEq resp.methodResponses[1].rawName, "method2"
  assertEq resp.methodResponses[1].methodCallId, makeMcid("c2")
  doAssert resp.methodResponses[1].arguments{"isBlah"}.getBool(false) == true
  # Third response: ["anotherResponseFromMethod2", {...}, "c2"]
  assertEq resp.methodResponses[2].rawName, "anotherResponseFromMethod2"
  assertEq resp.methodResponses[2].methodCallId, makeMcid("c2")
  # Fourth response: ["error", {"type": "unknownMethod"}, "c3"]
  assertEq resp.methodResponses[3].rawName, "error"
  assertEq resp.methodResponses[3].methodCallId, makeMcid("c3")
  assertEq resp.methodResponses[3].arguments{"type"}.getStr(""), "unknownMethod"
  # Session state
  assertEq resp.sessionState, parseJmapState("75128aab4b1b").get()
  # createdIds absent
  assertNone resp.createdIds

# =============================================================================
# Phase 6B — Error response golden tests
# =============================================================================

block rfc8620_S3_6_goldenLimitError:
  ## Build a complete RequestError with all RFC 7807 fields: type, status,
  ## title, detail, limit. Round-trip and verify all fields preserved.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:limit",
    status = Opt.some(429),
    title = Opt.some("Too Many Requests"),
    detail = Opt.some("You have exceeded the rate limit"),
    limit = Opt.some("maxObjectsInGet"),
  )
  let j = original.toJson()
  # Verify JSON structure
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:limit"
  assertEq j{"status"}.getBiggestInt(0), 429'i64
  assertEq j{"title"}.getStr(""), "Too Many Requests"
  assertEq j{"detail"}.getStr(""), "You have exceeded the rate limit"
  assertEq j{"limit"}.getStr(""), "maxObjectsInGet"
  # Round-trip
  let rt = RequestError.fromJson(j).get()
  let v = rt
  doAssert v.errorType == retLimit
  assertEq v.rawType, "urn:ietf:params:jmap:error:limit"
  assertSomeEq v.status, 429
  assertSomeEq v.title, "Too Many Requests"
  assertSomeEq v.detail, "You have exceeded the rate limit"
  assertSomeEq v.limit, "maxObjectsInGet"

block rfc8620_S3_6_goldenMethodError:
  ## Build a complete MethodError (serverFail with description). Round-trip
  ## and verify all fields preserved.
  let original =
    methodError(rawType = "serverFail", description = Opt.some("Database timeout"))
  let j = original.toJson()
  # Verify JSON structure
  assertEq j{"type"}.getStr(""), "serverFail"
  assertEq j{"description"}.getStr(""), "Database timeout"
  # Round-trip
  let rt = MethodError.fromJson(j).get()
  let v = rt
  doAssert v.errorType == metServerFail
  assertEq v.rawType, "serverFail"
  assertSomeEq v.description, "Database timeout"

# =============================================================================
# Phase 6C — Interop edge cases
# =============================================================================

block rfc8620_S5_5_comparatorEmptyCollationWireSentinel:
  ## Empty-string collation on the wire is the RFC-default sentinel. The
  ## Layer 1 type (``Opt[CollationAlgorithm]``) makes the absence of a
  ## collation unrepresentable as any string value, so ``fromJson`` maps
  ## ``"collation": ""`` to ``Opt.none``. The stricter interior type
  ## removes the ambiguity the old stringly-typed model carried.
  let j = %*{"property": "subject", "collation": ""}
  let rt = Comparator.fromJson(j).get()
  doAssert rt.collation.isNone

block rfc8620_S1_4_leapSecondWithFractional:
  ## Test parseDate("2024-06-30T23:59:60.123Z").get(). Layer 1 performs structural
  ## validation only and does not check calendar semantics, so second=60
  ## (leap second) with fractional seconds is accepted.
  let r = parseDate("2024-06-30T23:59:60.123Z").get()
  assertOk r

# =============================================================================
# Phase 6A — Request error URI serde compliance (RFC 8620 S3.6.1)
# =============================================================================
# Section-traceable tests for all 4 request error URIs with full JSON
# structure (toJson -> fromJson round-trip).

block rfc8620_S3_6_1_requestErrorUnknownCapability:
  ## RFC 8620 S3.6.1: "urn:ietf:params:jmap:error:unknownCapability"
  ## Full round-trip with RFC 7807 structure.
  let re = requestError(
    "urn:ietf:params:jmap:error:unknownCapability",
    status = Opt.some(400),
    title = Opt.some("Unknown Capability"),
    detail = Opt.some("The requested capability is not supported"),
  )
  doAssert re.errorType == retUnknownCapability
  let j = re.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:unknownCapability"
  assertEq j{"status"}.getBiggestInt(0), 400'i64
  let rt = RequestError.fromJson(j).get()
  doAssert rt.errorType == retUnknownCapability
  assertEq rt.rawType, "urn:ietf:params:jmap:error:unknownCapability"
  assertSomeEq rt.status, 400
  assertSomeEq rt.title, "Unknown Capability"

block rfc8620_S3_6_1_requestErrorNotJSON:
  ## RFC 8620 S3.6.1: "urn:ietf:params:jmap:error:notJSON"
  let re = requestError(
    "urn:ietf:params:jmap:error:notJSON",
    status = Opt.some(400),
    title = Opt.some("Not JSON"),
    detail = Opt.some("The content type was not application/json"),
  )
  doAssert re.errorType == retNotJson
  let j = re.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notJSON"
  let rt = RequestError.fromJson(j).get()
  doAssert rt.errorType == retNotJson
  assertEq rt.rawType, "urn:ietf:params:jmap:error:notJSON"

block rfc8620_S3_6_1_requestErrorNotRequest:
  ## RFC 8620 S3.6.1: "urn:ietf:params:jmap:error:notRequest"
  let re = requestError(
    "urn:ietf:params:jmap:error:notRequest",
    status = Opt.some(400),
    title = Opt.some("Not Request"),
    detail = Opt.some("The JSON was not a valid JMAP request"),
  )
  doAssert re.errorType == retNotRequest
  let j = re.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notRequest"
  let rt = RequestError.fromJson(j).get()
  doAssert rt.errorType == retNotRequest
  assertEq rt.rawType, "urn:ietf:params:jmap:error:notRequest"

block rfc8620_S3_6_1_requestErrorLimit:
  ## RFC 8620 S3.6.1: "urn:ietf:params:jmap:error:limit"
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    status = Opt.some(400),
    title = Opt.some("Limit"),
    detail = Opt.some("Too many method calls"),
    limit = Opt.some("maxCallsInRequest"),
  )
  doAssert re.errorType == retLimit
  let j = re.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:limit"
  assertEq j{"limit"}.getStr(""), "maxCallsInRequest"
  let rt = RequestError.fromJson(j).get()
  doAssert rt.errorType == retLimit
  assertSomeEq rt.limit, "maxCallsInRequest"

# =============================================================================
# Phase 6A — Method error type serde compliance (RFC 8620 S3.6.2)
# =============================================================================
# Section-traceable round-trip tests for all 19 method error types.

block rfc8620_S3_6_2_serdeServerUnavailable:
  ## serverUnavailable round-trip.
  let me = methodError("serverUnavailable", description = Opt.some("maintenance"))
  let j = me.toJson()
  assertEq j{"type"}.getStr(""), "serverUnavailable"
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metServerUnavailable

block rfc8620_S3_6_2_serdeServerFail:
  ## serverFail round-trip.
  let me = methodError("serverFail")
  let j = me.toJson()
  assertEq j{"type"}.getStr(""), "serverFail"
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metServerFail

block rfc8620_S3_6_2_serdeServerPartialFail:
  ## serverPartialFail round-trip.
  let me = methodError("serverPartialFail")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metServerPartialFail

block rfc8620_S3_6_2_serdeUnknownMethod:
  ## unknownMethod round-trip.
  let me = methodError("unknownMethod")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metUnknownMethod

block rfc8620_S3_6_2_serdeInvalidArguments:
  ## invalidArguments round-trip.
  let me = methodError("invalidArguments")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metInvalidArguments

block rfc8620_S3_6_2_serdeInvalidResultReference:
  ## invalidResultReference round-trip.
  let me = methodError("invalidResultReference")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metInvalidResultReference

block rfc8620_S3_6_2_serdeForbidden:
  ## forbidden round-trip.
  let me = methodError("forbidden")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metForbidden

block rfc8620_S3_6_2_serdeAccountNotFound:
  ## accountNotFound round-trip.
  let me = methodError("accountNotFound")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metAccountNotFound

block rfc8620_S3_6_2_serdeAccountNotSupportedByMethod:
  ## accountNotSupportedByMethod round-trip.
  let me = methodError("accountNotSupportedByMethod")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metAccountNotSupportedByMethod

block rfc8620_S3_6_2_serdeAccountReadOnly:
  ## accountReadOnly round-trip.
  let me = methodError("accountReadOnly")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metAccountReadOnly

block rfc8620_S3_6_2_serdeAnchorNotFound:
  ## anchorNotFound round-trip.
  let me = methodError("anchorNotFound")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metAnchorNotFound

block rfc8620_S3_6_2_serdeUnsupportedSort:
  ## unsupportedSort round-trip.
  let me = methodError("unsupportedSort")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metUnsupportedSort

block rfc8620_S3_6_2_serdeUnsupportedFilter:
  ## unsupportedFilter round-trip.
  let me = methodError("unsupportedFilter")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metUnsupportedFilter

block rfc8620_S3_6_2_serdeCannotCalculateChanges:
  ## cannotCalculateChanges round-trip.
  let me = methodError("cannotCalculateChanges")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metCannotCalculateChanges

block rfc8620_S3_6_2_serdeTooManyChanges:
  ## tooManyChanges round-trip.
  let me = methodError("tooManyChanges")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metTooManyChanges

block rfc8620_S3_6_2_serdeRequestTooLarge:
  ## requestTooLarge round-trip.
  let me = methodError("requestTooLarge")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metRequestTooLarge

block rfc8620_S3_6_2_serdeStateMismatch:
  ## stateMismatch round-trip.
  let me = methodError("stateMismatch")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metStateMismatch

block rfc8620_S3_6_2_serdeFromAccountNotFound:
  ## fromAccountNotFound round-trip.
  let me = methodError("fromAccountNotFound")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metFromAccountNotFound

block rfc8620_S3_6_2_serdeFromAccountNotSupportedByMethod:
  ## fromAccountNotSupportedByMethod round-trip.
  let me = methodError("fromAccountNotSupportedByMethod")
  let j = me.toJson()
  let rt = MethodError.fromJson(j).get()
  doAssert rt.errorType == metFromAccountNotSupportedByMethod

# =============================================================================
# Phase 6A — Set error type serde compliance (RFC 8620 S5.3)
# =============================================================================
# Section-traceable round-trip tests for all 10 set error types.

block rfc8620_S5_3_serdeForbidden:
  ## SetError forbidden round-trip.
  let se = setError("forbidden", description = Opt.some("not allowed"))
  let j = se.toJson()
  assertEq j{"type"}.getStr(""), "forbidden"
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setForbidden

block rfc8620_S5_3_serdeOverQuota:
  ## SetError overQuota round-trip.
  let se = setError("overQuota")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setOverQuota

block rfc8620_S5_3_serdeTooLarge:
  ## SetError tooLarge round-trip.
  let se = setError("tooLarge")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setTooLarge

block rfc8620_S5_3_serdeRateLimit:
  ## SetError rateLimit round-trip.
  let se = setError("rateLimit")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setRateLimit

block rfc8620_S5_3_serdeNotFound:
  ## SetError notFound round-trip.
  let se = setError("notFound")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setNotFound

block rfc8620_S5_3_serdeInvalidPatch:
  ## SetError invalidPatch round-trip.
  let se = setError("invalidPatch")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setInvalidPatch

block rfc8620_S5_3_serdeWillDestroy:
  ## SetError willDestroy round-trip.
  let se = setError("willDestroy")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setWillDestroy

block rfc8620_S5_3_serdeInvalidProperties:
  ## SetError invalidProperties round-trip with properties array.
  let se = setErrorInvalidProperties(
    "invalidProperties", @["subject", "from", "to"], Opt.some("bad fields")
  )
  doAssert se.errorType == setInvalidProperties
  let j = se.toJson()
  assertEq j{"type"}.getStr(""), "invalidProperties"
  doAssert j{"properties"} != nil
  doAssert j{"properties"}.kind == JArray
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setInvalidProperties
  assertEq rt.properties.len, 3
  doAssert "subject" in rt.properties
  doAssert "from" in rt.properties
  doAssert "to" in rt.properties

block rfc8620_S5_3_serdeAlreadyExists:
  ## SetError alreadyExists round-trip with existingId.
  let existId = makeId("existingRecord42")
  let se =
    setErrorAlreadyExists("alreadyExists", existId, Opt.some("record already present"))
  doAssert se.errorType == setAlreadyExists
  let j = se.toJson()
  assertEq j{"type"}.getStr(""), "alreadyExists"
  assertEq j{"existingId"}.getStr(""), "existingRecord42"
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setAlreadyExists
  assertEq $rt.existingId, "existingRecord42"

block rfc8620_S5_3_serdeSingleton:
  ## SetError singleton round-trip.
  let se = setError("singleton")
  let j = se.toJson()
  let rt = SetError.fromJson(j).get()
  doAssert rt.errorType == setSingleton

# =============================================================================
# Phase 6C — parseEnum case sensitivity documentation (nimIdentNormalize)
# =============================================================================
# Nim's parseEnum uses nimIdentNormalize which strips underscores (except
# leading) and lowercases everything except the first character. This means
# error type parsing is case-insensitive after the first character and strips
# underscores — deviating from strict RFC case matching but consistent with
# Postel's Law for a client library receiving server responses.

block rfc8620_conformance_methodErrorExactMatch:
  ## Exact RFC string matches the corresponding enum variant.
  doAssert parseMethodErrorType("serverFail") == metServerFail
  doAssert parseMethodErrorType("invalidArguments") == metInvalidArguments
  doAssert parseMethodErrorType("forbidden") == metForbidden

block rfc8620_conformance_methodErrorNimIdentNormalize:
  ## nimIdentNormalize: case-insensitive after first character.
  ## "serverfail" normalises same as "serverFail" -> metServerFail.
  doAssert parseMethodErrorType("serverfail") == metServerFail
  doAssert parseMethodErrorType("serverFAIL") == metServerFail
  doAssert parseMethodErrorType("invalidarguments") == metInvalidArguments

block rfc8620_conformance_methodErrorFirstCharCaseSensitive:
  ## First character IS case-sensitive under nimIdentNormalize.
  ## "SERVERFAIL" starts with 'S' vs 's' in "serverFail" -> metUnknown.
  doAssert parseMethodErrorType("SERVERFAIL") == metUnknown
  doAssert parseMethodErrorType("ServerFail") == metUnknown
  doAssert parseMethodErrorType("Forbidden") == metUnknown

block rfc8620_conformance_methodErrorUnderscoreStripping:
  ## nimIdentNormalize strips underscores (except leading).
  ## "server_Fail" becomes "serverfail" -> matches metServerFail.
  doAssert parseMethodErrorType("server_Fail") == metServerFail
  doAssert parseMethodErrorType("invalid_Arguments") == metInvalidArguments

block rfc8620_conformance_methodErrorLeadingUnderscorePreserved:
  ## Leading underscores are preserved by nimIdentNormalize -> no match.
  doAssert parseMethodErrorType("_serverFail") == metUnknown

block rfc8620_conformance_setErrorExactMatch:
  ## Exact RFC string matches the corresponding SetErrorType variant.
  doAssert parseSetErrorType("forbidden") == setForbidden
  doAssert parseSetErrorType("overQuota") == setOverQuota
  doAssert parseSetErrorType("tooLarge") == setTooLarge

block rfc8620_conformance_setErrorNimIdentNormalize:
  ## nimIdentNormalize: case-insensitive after first character.
  doAssert parseSetErrorType("overquota") == setOverQuota
  doAssert parseSetErrorType("toolarge") == setTooLarge

block rfc8620_conformance_setErrorFirstCharCaseSensitive:
  ## First character IS case-sensitive.
  doAssert parseSetErrorType("Forbidden") == setUnknown
  doAssert parseSetErrorType("OverQuota") == setUnknown

block rfc8620_conformance_requestErrorExactMatch:
  ## Exact RFC URIs match the corresponding RequestErrorType variant.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:unknownCapability") ==
    retUnknownCapability
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notJSON") == retNotJson
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notRequest") ==
    retNotRequest
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:limit") == retLimit

block rfc8620_conformance_requestErrorFirstCharCaseSensitive:
  ## First character IS case-sensitive for URIs too.
  ## 'U' vs 'u' in "urn:" -> retUnknown.
  doAssert parseRequestErrorType("Urn:ietf:params:jmap:error:limit") == retUnknown
