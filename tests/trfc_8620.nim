# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## RFC 8620 compliance tests. Each block verifies a normative requirement
## traceable to a specific section of RFC 8620. Block names follow the
## convention rfc8620_S<section>_<description>.

import std/json
import std/sets
import std/strutils
import std/tables

import pkg/results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors

import ./massertions
import ./mfixtures

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
  let res = parseSession(
    noCore, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertErr res
  assertErrContains res, "urn:ietf:params:jmap:core"

block rfc8620_S2_sessionApiUrlNonEmpty:
  ## apiUrl MUST be non-empty.
  let args = makeSessionArgs()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, "",
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertErr res
  assertErrContains res, "apiUrl"

block rfc8620_S2_sessionDownloadUrlVariables:
  ## downloadUrl MUST contain {accountId}, {blobId}, {type}, {name}.
  let args = makeSessionArgs()
  # A URL missing required template variables must be rejected.
  let badDl = parseUriTemplate("https://example.com/download/").get()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    badDl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertErr res
  assertErrContains res, "downloadUrl"

block rfc8620_S2_sessionUploadUrlVariable:
  ## uploadUrl MUST contain {accountId}.
  let args = makeSessionArgs()
  let badUp = parseUriTemplate("https://example.com/upload/").get()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, badUp, args.eventSourceUrl, args.state,
  )
  assertErr res
  assertErrContains res, "uploadUrl"

block rfc8620_S2_sessionEventSourceUrlVariables:
  ## eventSourceUrl MUST contain {types}, {closeafter}, {ping}.
  let args = makeSessionArgs()
  let badEs = parseUriTemplate("https://example.com/events/").get()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, badEs, args.state,
  )
  assertErr res
  assertErrContains res, "eventSourceUrl"

block rfc8620_S2_sessionValidConstructionSucceeds:
  ## A Session with all required fields and core capability succeeds.
  let args = makeSessionArgs()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertOk res

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
  let res = parseSession(
    args.capabilities, args.accounts, pa, args.username, args.apiUrl, args.downloadUrl,
    args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertOk res

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
  doAssert caps.hasCollation("i;ascii-casemap")
  doAssert caps.hasCollation("i;unicode-casemap")
  doAssert not caps.hasCollation("i;nonexistent")

# =============================================================================
# S3.2 — Invocation (RFC 8620 section 3.2)
# =============================================================================

block rfc8620_S3_2_invocationStructure:
  ## An Invocation has three elements: name, arguments, methodCallId.
  let mcid = makeMcid("call0")
  let inv = Invocation(name: "Foo/get", arguments: newJObject(), methodCallId: mcid)
  doAssert inv.name == "Foo/get"
  doAssert inv.arguments.kind == JObject
  doAssert inv.methodCallId == mcid

block rfc8620_S3_2_methodCallIdCorrelation:
  ## methodCallId correlates a request invocation to its response.
  let mcid1 = makeMcid("c1")
  let mcid2 = makeMcid("c2")
  doAssert mcid1 != mcid2
  let inv1 = Invocation(name: "A/get", arguments: newJObject(), methodCallId: mcid1)
  let inv2 = Invocation(name: "B/get", arguments: newJObject(), methodCallId: mcid2)
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
  doAssert req.methodCalls[0].name == "A/get"
  doAssert req.methodCalls[1].name == "B/get"
  doAssert req.methodCalls[2].name == "C/get"

block rfc8620_S3_3_requestCreatedIdsOptional:
  ## createdIds is optional; Opt.none is valid.
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
  doAssert resp.methodResponses[0].name == "A/get"
  doAssert resp.methodResponses[1].name == "B/get"

block rfc8620_S3_4_responseSessionStateMandatory:
  ## sessionState is always present in a Response.
  let resp = makeResponse()
  doAssert resp.sessionState == makeState("rs1")

block rfc8620_S3_4_responseCreatedIdsOnlyIfRequested:
  ## createdIds in response is present only if given in the request.
  let resp = makeResponse()
  doAssert resp.createdIds.isNone

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
  let errInv = Invocation(
    name: "error",
    arguments: %*{"type": "invalidArguments"},
    methodCallId: makeMcid("c0"),
  )
  doAssert errInv.name == "error"

# =============================================================================
# S3.7 — ResultReference (RFC 8620 section 3.7)
# =============================================================================

block rfc8620_S3_7_resultReferencePathConstants:
  ## The spec defines standard JSON Pointer paths for result references.
  doAssert RefPathIds == "/ids"
  doAssert RefPathListIds == "/list/*/id"
  doAssert RefPathAddedIds == "/added/*/id"
  doAssert RefPathCreated == "/created"
  doAssert RefPathUpdated == "/updated"
  doAssert RefPathUpdatedProperties == "/updatedProperties"

block rfc8620_S3_7_resultReferenceConstruction:
  ## A ResultReference ties a back-reference to a previous call's result.
  let mcid = makeMcid("c0")
  let rr = ResultReference(resultOf: mcid, name: "Mailbox/get", path: RefPathIds)
  doAssert rr.resultOf == mcid
  doAssert rr.name == "Mailbox/get"
  doAssert rr.path == "/ids"

block rfc8620_S3_7_referencableVariants:
  ## Referencable[T] is either a direct value or a result reference.
  let directIds = direct(@[makeId("id1")])
  doAssert directIds.kind == rkDirect

  let mcid = makeMcid("c0")
  let rr = ResultReference(resultOf: mcid, name: "Mailbox/query", path: RefPathIds)
  let refIds = referenceTo[seq[Id]](rr)
  doAssert refIds.kind == rkReference
  doAssert refIds.reference.path == "/ids"

block rfc8620_S3_7_wildcardInPath:
  ## RFC S3.7: The '*' character is a JMAP extension to JSON Pointer for array wildcard.
  doAssert '*' in RefPathListIds
  doAssert '*' in RefPathAddedIds

block rfc8620_S3_7_resultReferenceTriple:
  ## A ResultReference has all three required fields: resultOf, name, path.
  let rr = makeResultReference(makeMcid("c0"), "Email/query", RefPathIds)
  doAssert rr.resultOf == makeMcid("c0")
  doAssert rr.name == "Email/query"
  doAssert rr.path == "/ids"

# =============================================================================
# S5.3 — PatchObject and SetError (RFC 8620 section 5.3)
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

block rfc8620_S5_3_patchObjectSetAndDelete:
  ## PatchObject supports setting values and deleting (setting to null).
  let p0 = emptyPatch()
  doAssert p0.len == 0
  let p1 = p0.setProp("subject", %"hello").get()
  doAssert p1.len == 1
  let p2 = p1.deleteProp("keywords/$seen").get()
  doAssert p2.len == 2

block rfc8620_S5_3_patchObjectPathImplicitLeadingSlash:
  ## RFC S5.3: Paths have an implicit leading '/'. "subject" means "/subject".
  let p = emptyPatch().setProp("subject", %"hello").get()
  doAssert p.len == 1
  doAssert p.getKey("subject").isSome

block rfc8620_S5_3_patchObjectNestedPath:
  ## Nested paths like "mailboxIds/mb1" are accepted (implicit "/mailboxIds/mb1").
  let p = emptyPatch().setProp("mailboxIds/mb1", %true).get()
  doAssert p.getKey("mailboxIds/mb1").isSome

block rfc8620_S5_3_patchObjectNullMeansDelete:
  ## RFC S5.3: Setting to null means delete/reset. deleteProp produces a null value.
  let p = emptyPatch().deleteProp("keywords/$seen").get()
  doAssert p.getKey("keywords/$seen").isSome
  doAssert p.getKey("keywords/$seen").get().kind == JNull

block rfc8620_S5_3_patchObjectTildeEscaping:
  ## RFC 6901 tilde escaping: ~0 encodes '~', ~1 encodes '/'. Stored as-is.
  assertOk emptyPatch().setProp("a~0b", %"val")
  assertOk emptyPatch().setProp("a~1b", %"val")

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
  let cmp = parseComparator(prop).get()
  doAssert cmp.isAscending == true

block rfc8620_S5_5_comparatorExplicitDescending:
  ## Comparator isAscending can be explicitly set to false.
  let prop = makePropertyName("size")
  let cmp = parseComparator(prop, isAscending = false).get()
  doAssert cmp.isAscending == false

block rfc8620_S5_5_comparatorCollationRfc4790Format:
  ## RFC 4790 collation identifier in Comparator.
  let prop = makePropertyName("subject")
  let cmp = parseComparator(prop, collation = Opt.some("i;ascii-casemap")).get()
  doAssert cmp.collation.isSome
  doAssert cmp.collation.get() == "i;ascii-casemap"

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

# =============================================================================
# S5.6 — /queryChanges (RFC 8620 section 5.6)
# =============================================================================

block rfc8620_S5_6_addedItemStructure:
  ## AddedItem has id (Id) and index (UnsignedInt).
  let item = AddedItem(id: makeId("id1"), index: parseUnsignedInt(42).get())
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
  for met in MethodErrorType:
    if met != metUnknown:
      doAssert methodError($met).rawType == $met
  for se in SetErrorType:
    if se notin {setUnknown, setInvalidProperties, setAlreadyExists}:
      doAssert setError($se).rawType == $se
  for re in RequestErrorType:
    if re != retUnknown:
      doAssert requestError($re).rawType == $re

# =============================================================================
# RFC 8621 — JMAP Mail error type fallthrough
# =============================================================================

block rfc8621_setErrorMailboxHasChildFallsThrough:
  ## RFC 8621 set error types are not modelled in Layer 1; they fall to setUnknown.
  doAssert parseSetErrorType("mailboxHasChild") == setUnknown

block rfc8621_setErrorBlobNotFoundFallsThrough:
  doAssert parseSetErrorType("blobNotFound") == setUnknown

block rfc8621_submissionErrorsFallThrough:
  ## RFC 8621 S7 submission-specific error types fall to setUnknown.
  doAssert parseSetErrorType("forbiddenFrom") == setUnknown
  doAssert parseSetErrorType("forbiddenToSend") == setUnknown
  doAssert parseSetErrorType("noRecipients") == setUnknown
