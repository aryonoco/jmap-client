# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for transport, request, client, method, and set error constructors.

import std/json
import std/strutils

import jmap_client/internal/types/primitives
import jmap_client/internal/types/errors
import jmap_client/internal/types/validation

import ../massertions
import ../mtestblock

# --- parseRequestErrorType ---

testCase parseRequestErrorTypeAllKnown:
  ## Table-driven: every known request error URI maps to its expected variant.
  const cases = [
    ("urn:ietf:params:jmap:error:unknownCapability", retUnknownCapability),
    ("urn:ietf:params:jmap:error:notJSON", retNotJson),
    ("urn:ietf:params:jmap:error:notRequest", retNotRequest),
    ("urn:ietf:params:jmap:error:limit", retLimit),
  ]
  for (uri, expected) in cases:
    assertEq parseRequestErrorType(uri), expected

testCase parseRequestErrorTypeVendorUri:
  doAssert parseRequestErrorType("urn:vendor:custom:error") == retUnknown

testCase parseRequestErrorTypeEmpty:
  doAssert parseRequestErrorType("") == retUnknown

# --- parseMethodErrorType ---

testCase parseMethodErrorTypeAllKnown:
  ## Table-driven: every known method error string maps to its expected variant.
  const cases = [
    ("serverUnavailable", metServerUnavailable),
    ("serverFail", metServerFail),
    ("serverPartialFail", metServerPartialFail),
    ("unknownMethod", metUnknownMethod),
    ("invalidArguments", metInvalidArguments),
    ("invalidResultReference", metInvalidResultReference),
    ("forbidden", metForbidden),
    ("accountNotFound", metAccountNotFound),
    ("accountNotSupportedByMethod", metAccountNotSupportedByMethod),
    ("accountReadOnly", metAccountReadOnly),
    ("anchorNotFound", metAnchorNotFound),
    ("unsupportedSort", metUnsupportedSort),
    ("unsupportedFilter", metUnsupportedFilter),
    ("cannotCalculateChanges", metCannotCalculateChanges),
    ("tooManyChanges", metTooManyChanges),
    ("requestTooLarge", metRequestTooLarge),
    ("stateMismatch", metStateMismatch),
    ("fromAccountNotFound", metFromAccountNotFound),
    ("fromAccountNotSupportedByMethod", metFromAccountNotSupportedByMethod),
  ]
  for (rawType, expected) in cases:
    assertEq parseMethodErrorType(rawType), expected

testCase parseMethodErrorTypeUnknown:
  doAssert parseMethodErrorType("customError") == metUnknown

testCase parseMethodErrorTypeEmpty:
  doAssert parseMethodErrorType("") == metUnknown

# --- parseSetErrorType ---

testCase parseSetErrorTypeAllKnown:
  ## Table-driven: every known set error string maps to its expected variant.
  const cases = [
    ("forbidden", setForbidden),
    ("overQuota", setOverQuota),
    ("tooLarge", setTooLarge),
    ("rateLimit", setRateLimit),
    ("notFound", setNotFound),
    ("invalidPatch", setInvalidPatch),
    ("willDestroy", setWillDestroy),
    ("invalidProperties", setInvalidProperties),
    ("alreadyExists", setAlreadyExists),
    ("singleton", setSingleton),
  ]
  for (rawType, expected) in cases:
    assertEq parseSetErrorType(rawType), expected

testCase parseSetErrorTypeVendorSpecific:
  doAssert parseSetErrorType("vendorSpecific") == setUnknown

testCase parseSetErrorTypeEmpty:
  doAssert parseSetErrorType("") == setUnknown

# --- TransportError constructors ---

testCase transportErrorTimeout:
  let e = transportError(tekTimeout, "timed out")
  doAssert e.kind == tekTimeout
  doAssert e.message == "timed out"

testCase transportErrorNetwork:
  let e = transportError(tekNetwork, "refused")
  doAssert e.kind == tekNetwork
  doAssert e.message == "refused"

testCase transportErrorTls:
  let e = transportError(tekTls, "certificate verify failed")
  doAssert e.kind == tekTls
  doAssert e.message == "certificate verify failed"

testCase httpStatusError502:
  let e = httpStatusError(502, "Bad Gateway")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 502
  doAssert e.message == "Bad Gateway"

# --- RequestError constructor ---

testCase requestErrorLimit:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest")
  )
  doAssert e.errorType == retLimit
  doAssert e.rawType == "urn:ietf:params:jmap:error:limit"
  doAssert e.limit.isSome
  doAssert e.limit.get() == "maxCallsInRequest"
  doAssert e.status.isNone
  doAssert e.title.isNone
  doAssert e.detail.isNone
  doAssert e.extras.isNone

testCase requestErrorLimitWithExtras:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit",
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(%*{"requestId": "abc"}),
  )
  doAssert e.extras.isSome

testCase requestErrorUnknown:
  let e = requestError("urn:vendor:custom")
  doAssert e.errorType == retUnknown
  doAssert e.rawType == "urn:vendor:custom"

testCase requestErrorKnownRawTypePreserved:
  let e = requestError("urn:ietf:params:jmap:error:notJSON")
  doAssert e.errorType == retNotJson
  doAssert e.rawType == "urn:ietf:params:jmap:error:notJSON"

# --- ClientError constructors + message accessor ---

testCase clientErrorTransport:
  let ce = clientError(transportError(tekNetwork, "refused"))
  doAssert ce.kind == cekTransport

testCase clientErrorRequest:
  let ce = clientError(requestError("urn:ietf:params:jmap:error:notJSON"))
  doAssert ce.kind == cekRequest

testCase messageTransport:
  let ce = clientError(transportError(tekTimeout, "timed out"))
  doAssert errors.message(ce) == "timed out"

testCase messageRequestWithDetail:
  let ce = clientError(
    requestError(
      "urn:ietf:params:jmap:error:limit", detail = Opt.some("Too many calls")
    )
  )
  doAssert errors.message(ce) == "Too many calls"

testCase messageRequestDetailPreferredOverTitle:
  let ce = clientError(
    requestError(
      "urn:ietf:params:jmap:error:limit",
      title = Opt.some("Limit Exceeded"),
      detail = Opt.some("Too many calls"),
    )
  )
  doAssert errors.message(ce) == "Too many calls"

testCase messageRequestWithTitleOnly:
  let ce = clientError(
    requestError("urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded"))
  )
  doAssert errors.message(ce) == "Limit Exceeded"

testCase messageRequestFallbackToRawType:
  let ce = clientError(requestError("urn:ietf:params:jmap:error:limit"))
  doAssert errors.message(ce) == "urn:ietf:params:jmap:error:limit"

# --- MethodError constructor ---

testCase methodErrorKnown:
  let e = methodError("unknownMethod")
  doAssert e.errorType == metUnknownMethod
  doAssert e.rawType == "unknownMethod"
  doAssert e.description.isNone
  doAssert e.extras.isNone

testCase methodErrorUnknownWithExtras:
  let e = methodError("custom", extras = Opt.some(%*{"hint": "retry"}))
  doAssert e.errorType == metUnknown
  doAssert e.rawType == "custom"
  doAssert e.extras.isSome

testCase methodErrorWithDescription:
  let e = methodError("serverFail", description = Opt.some("internal error"))
  doAssert e.errorType == metServerFail
  doAssert e.description.isSome
  doAssert e.description.get() == "internal error"

# --- SetError constructors ---

testCase setErrorForbidden:
  let e = setError("forbidden")
  doAssert e.errorType == setForbidden
  doAssert e.rawType == "forbidden"

testCase setErrorWithDescriptionAndExtras:
  let e = setError(
    "overQuota",
    description = Opt.some("quota exceeded"),
    extras = Opt.some(%*{"limit": 100}),
  )
  doAssert e.errorType == setOverQuota
  doAssert e.description.isSome
  doAssert e.description.get() == "quota exceeded"
  doAssert e.extras.isSome

testCase setErrorInvalidPropertiesVariant:
  let e = setErrorInvalidProperties("invalidProperties", @["name"])
  doAssert e.errorType == setInvalidProperties
  doAssert e.properties == @["name"]
  doAssert e.rawType == "invalidProperties"
  doAssert e.description.isNone

testCase setErrorAlreadyExistsVariant:
  let someId = parseIdFromServer("existing-123").get()
  let e = setErrorAlreadyExists("alreadyExists", someId)
  doAssert e.errorType == setAlreadyExists
  doAssert e.existingId == someId
  doAssert e.rawType == "alreadyExists"
  doAssert e.description.isNone

testCase setErrorDefensiveFallbackInvalidProperties:
  let e = setError("invalidProperties")
  doAssert e.errorType == setUnknown
  doAssert e.rawType == "invalidProperties"

testCase setErrorDefensiveFallbackAlreadyExists:
  let e = setError("alreadyExists")
  doAssert e.errorType == setUnknown
  doAssert e.rawType == "alreadyExists"

# --- RFC conformance: string backing ---

testCase requestErrorTypeStringBacking:
  doAssert $retUnknownCapability == "urn:ietf:params:jmap:error:unknownCapability"
  doAssert $retNotJson == "urn:ietf:params:jmap:error:notJSON"
  doAssert $retNotRequest == "urn:ietf:params:jmap:error:notRequest"
  doAssert $retLimit == "urn:ietf:params:jmap:error:limit"

testCase methodErrorTypeStringBacking:
  doAssert $metServerUnavailable == "serverUnavailable"
  doAssert $metServerFail == "serverFail"
  doAssert $metServerPartialFail == "serverPartialFail"
  doAssert $metUnknownMethod == "unknownMethod"
  doAssert $metInvalidArguments == "invalidArguments"
  doAssert $metInvalidResultReference == "invalidResultReference"
  doAssert $metForbidden == "forbidden"
  doAssert $metAccountNotFound == "accountNotFound"
  doAssert $metAccountNotSupportedByMethod == "accountNotSupportedByMethod"
  doAssert $metAccountReadOnly == "accountReadOnly"
  doAssert $metAnchorNotFound == "anchorNotFound"
  doAssert $metUnsupportedSort == "unsupportedSort"
  doAssert $metUnsupportedFilter == "unsupportedFilter"
  doAssert $metCannotCalculateChanges == "cannotCalculateChanges"
  doAssert $metTooManyChanges == "tooManyChanges"
  doAssert $metRequestTooLarge == "requestTooLarge"
  doAssert $metStateMismatch == "stateMismatch"
  doAssert $metFromAccountNotFound == "fromAccountNotFound"
  doAssert $metFromAccountNotSupportedByMethod == "fromAccountNotSupportedByMethod"

testCase setErrorTypeStringBacking:
  doAssert $setForbidden == "forbidden"
  doAssert $setOverQuota == "overQuota"
  doAssert $setTooLarge == "tooLarge"
  doAssert $setRateLimit == "rateLimit"
  doAssert $setNotFound == "notFound"
  doAssert $setInvalidPatch == "invalidPatch"
  doAssert $setWillDestroy == "willDestroy"
  doAssert $setInvalidProperties == "invalidProperties"
  doAssert $setAlreadyExists == "alreadyExists"
  doAssert $setSingleton == "singleton"

testCase enumParserCaseSensitivity:
  doAssert parseMethodErrorType("ServerFail") == metUnknown
  doAssert parseSetErrorType("Forbidden") == setUnknown
  ## parseEnum uses nimIdentNormalize: first-char case-sensitive, rest insensitive.
  ## Same first char ('u') with different case in the rest still resolves.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notJson") == retNotJson

testCase parseRequestErrorTypeIdempotent:
  doAssert parseRequestErrorType($retUnknownCapability) == retUnknownCapability
  doAssert parseRequestErrorType($retNotJson) == retNotJson
  doAssert parseRequestErrorType($retNotRequest) == retNotRequest
  doAssert parseRequestErrorType($retLimit) == retLimit

testCase parseMethodErrorTypeIdempotent:
  doAssert parseMethodErrorType($metServerFail) == metServerFail
  doAssert parseMethodErrorType($metInvalidArguments) == metInvalidArguments
  doAssert parseMethodErrorType($metForbidden) == metForbidden
  doAssert parseMethodErrorType($metStateMismatch) == metStateMismatch

testCase parseSetErrorTypeIdempotent:
  doAssert parseSetErrorType($setForbidden) == setForbidden
  doAssert parseSetErrorType($setInvalidProperties) == setInvalidProperties
  doAssert parseSetErrorType($setSingleton) == setSingleton

testCase requestErrorRawTypeAllVariants:
  for uri in [
    "urn:ietf:params:jmap:error:unknownCapability",
    "urn:ietf:params:jmap:error:notJSON", "urn:ietf:params:jmap:error:notRequest",
    "urn:ietf:params:jmap:error:limit", "urn:vendor:custom",
  ]:
    doAssert requestError(uri).rawType == uri

testCase methodErrorRawTypeAllVariants:
  for s in ["serverFail", "unknownMethod", "forbidden", "customVendorError"]:
    doAssert methodError(s).rawType == s

testCase setErrorRawTypeAllVariants:
  for s in [
    "forbidden", "overQuota", "tooLarge", "rateLimit", "notFound", "invalidPatch",
    "willDestroy", "singleton", "vendorCustom",
  ]:
    doAssert setError(s).rawType == s

testCase methodErrorRfc8621FallThrough:
  doAssert parseMethodErrorType("mailboxHasChild") == metUnknown
  doAssert parseMethodErrorType("mailboxHasEmail") == metUnknown
  doAssert parseMethodErrorType("tooManyKeywords") == metUnknown

# --- Missing error paths ---

testCase httpStatusError404:
  let e = httpStatusError(404, "Not Found")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 404

testCase httpStatusError500:
  let e = httpStatusError(500, "Internal Server Error")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 500

testCase httpStatusErrorZero:
  let e = httpStatusError(0, "zero")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 0

testCase setErrorAllElseBranch:
  doAssert setError("tooLarge").errorType == setTooLarge
  doAssert setError("rateLimit").errorType == setRateLimit
  doAssert setError("notFound").errorType == setNotFound
  doAssert setError("invalidPatch").errorType == setInvalidPatch
  doAssert setError("willDestroy").errorType == setWillDestroy
  doAssert setError("singleton").errorType == setSingleton

testCase requestErrorAllFieldsPopulated:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit",
    status = Opt.some(400),
    title = Opt.some("Request Limit"),
    detail = Opt.some("Too many calls"),
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(%*{"requestId": "abc"}),
  )
  doAssert e.status.isSome
  doAssert e.status.get() == 400
  doAssert e.title.isSome
  doAssert e.detail.isSome
  doAssert e.limit.isSome
  doAssert e.extras.isSome

testCase methodErrorRawTypePreserved:
  doAssert methodError("vendorSpecific").rawType == "vendorSpecific"
  doAssert methodError("vendorSpecific").errorType == metUnknown

# --- nimIdentNormalize documentation tests ---

testCase parseMethodErrorTypeAllLowercase:
  # nimIdentNormalize: case-insensitive after first char
  # "serverfail" has same first char 's' as "serverFail" -> matches
  doAssert parseMethodErrorType("serverfail") == metServerFail

testCase parseMethodErrorTypeUnderscore:
  # nimIdentNormalize strips underscores -> "server_Fail" matches "serverFail"
  doAssert parseMethodErrorType("server_Fail") == metServerFail

testCase parseSetErrorTypeUnderscore:
  doAssert parseSetErrorType("over_Quota") == setOverQuota

testCase parseRequestErrorTypeUnderscore:
  # nimIdentNormalize strips underscores in URI-style error types too.
  # "urn:ietf:params:jmap:error:not_JSON" normalises the same as
  # "urn:ietf:params:jmap:error:notJSON" (underscore removed, case-folded).
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:not_JSON") == retNotJson

# --- SetError multi-element properties ---

testCase setErrorInvalidPropertiesMultiple:
  let se = setErrorInvalidProperties(
    "invalidProperties",
    @["from", "to", "subject"],
    Opt.none(string),
    Opt.none(JsonNode),
  )
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties.len == 3
  doAssert se.properties[0] == "from"
  doAssert se.properties[2] == "subject"

# --- SetError exhaustive variant iteration ---

testCase setErrorAllVariantsThroughGenericConstructor:
  # Every SetErrorType variant through setError() must not crash
  # and must preserve rawType
  for variant in SetErrorType:
    let rawType = $variant
    let se = setError(rawType, Opt.none(string), Opt.none(JsonNode))
    doAssert se.rawType == rawType

# --- ClientError message cascade ---

testCase clientErrorMessageCascadeDetail:
  # When detail is present, message returns detail
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    Opt.some(429),
    Opt.some("Rate Limited"),
    Opt.some("Too many requests"),
    Opt.some("maxCallsInRequest"),
    Opt.none(JsonNode),
  )
  let ce = clientError(re)
  assertEq errors.message(ce), "Too many requests"

testCase clientErrorMessageCascadeTitle:
  # When detail is absent, message returns title
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    Opt.some(429),
    Opt.some("Rate Limited"),
    Opt.none(string),
    Opt.none(string),
    Opt.none(JsonNode),
  )
  let ce = clientError(re)
  assertEq errors.message(ce), "Rate Limited"

testCase clientErrorMessageCascadeRawType:
  # When both detail and title absent, message returns rawType
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    Opt.none(int),
    Opt.none(string),
    Opt.none(string),
    Opt.none(string),
    Opt.none(JsonNode),
  )
  let ce = clientError(re)
  assertEq errors.message(ce), "urn:ietf:params:jmap:error:limit"

# --- SetError variant constructor edge cases ---

testCase setErrorInvalidPropertiesEmptyList:
  # Empty property list is structurally valid
  let se = setErrorInvalidProperties("invalidProperties", @[])
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties.len == 0
  doAssert se.rawType == "invalidProperties"

testCase setErrorInvalidPropertiesAllFields:
  # All optional fields populated
  let se = setErrorInvalidProperties(
    "invalidProperties",
    @["from", "to"],
    description = Opt.some("bad properties"),
    extras = Opt.some(%*{"hint": "check format"}),
  )
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties == @["from", "to"]
  doAssert se.description.isSome
  doAssert se.description.get() == "bad properties"
  doAssert se.extras.isSome

testCase setErrorAlreadyExistsAllFields:
  # All optional fields populated
  let existId = parseIdFromServer("existing-456").get()
  let se = setErrorAlreadyExists(
    "alreadyExists",
    existId,
    description = Opt.some("duplicate detected"),
    extras = Opt.some(%*{"server": "info"}),
  )
  doAssert se.errorType == setAlreadyExists
  doAssert se.existingId == existId
  doAssert se.description.isSome
  doAssert se.description.get() == "duplicate detected"
  doAssert se.extras.isSome

# --- Phase 4: Error constructor mutation resistance ---

testCase transportErrorEmptyMessage:
  ## Empty message string is valid — no restriction on message content.
  let te = transportError(tekNetwork, "")
  assertEq te.message, ""

testCase setErrorAlreadyExistsMaxLengthId:
  ## alreadyExists with maximum-length Id (255 bytes).
  let id = parseId("A".repeat(255)).get()
  let se = setErrorAlreadyExists("alreadyExists", id)
  assertEq se.errorType, setAlreadyExists
  assertEq se.existingId, id

testCase requestErrorLimitFieldNonLimitType:
  ## Limit field populated for a non-retLimit error type.
  let re =
    requestError("urn:ietf:params:jmap:error:notJSON", limit = Opt.some("maxSize"))
  assertEq re.errorType, retNotJson
  assertSome re.limit

testCase clientErrorMessageAllNone:
  ## When all optional fields are None, message falls back to rawType.
  let re = requestError("urn:ietf:params:jmap:error:notJSON")
  let ce = clientError(re)
  assertEq message(ce), "urn:ietf:params:jmap:error:notJSON"

testCase httpStatusErrorLargeStatus:
  ## Very large or unusual HTTP status codes.
  let te = httpStatusError(999, "unusual")
  assertEq te.httpStatus, 999
  let te0 = httpStatusError(0, "zero status")
  assertEq te0.httpStatus, 0

# --- Phase 2: Error constructor zero-coverage gaps ---

testCase clientErrorFromTransport:
  ## clientError(transport) lifts a transport error into ClientError.
  let te = transportError(tekNetwork, "connection refused")
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekNetwork
  doAssert ce.transport.message == "connection refused"

testCase clientErrorFromRequest:
  ## clientError(request) lifts a request error into ClientError.
  let re = requestError("urn:ietf:params:jmap:error:notJSON")
  let ce = clientError(re)
  doAssert ce.kind == cekRequest
  doAssert ce.request.errorType == retNotJson

testCase transportErrorAllKindsNetwork:
  ## transportError with tekNetwork variant.
  let e = transportError(tekNetwork, "host unreachable")
  doAssert e.kind == tekNetwork
  doAssert e.message == "host unreachable"

testCase transportErrorAllKindsTls:
  ## transportError with tekTls variant.
  let e = transportError(tekTls, "handshake failed")
  doAssert e.kind == tekTls
  doAssert e.message == "handshake failed"

testCase transportErrorAllKindsTimeout:
  ## transportError with tekTimeout variant.
  let e = transportError(tekTimeout, "request timed out after 30s")
  doAssert e.kind == tekTimeout
  doAssert e.message == "request timed out after 30s"

testCase transportErrorAllKindsHttpStatus:
  ## httpStatusError constructs a tekHttpStatus variant.
  let e = httpStatusError(503, "Service Unavailable")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 503
  doAssert e.message == "Service Unavailable"

testCase httpStatusErrorFieldAccess:
  ## httpStatusError provides access to both httpStatus and message.
  let e = httpStatusError(429, "Too Many Requests")
  assertEq e.kind, tekHttpStatus
  assertEq e.httpStatus, 429
  assertEq e.message, "Too Many Requests"

testCase messageClientErrorTransportPath:
  ## message(ClientError) for cekTransport returns transport.msg.
  let ce = clientError(transportError(tekTls, "expired certificate"))
  assertEq message(ce), "expired certificate"

testCase messageClientErrorRequestWithDetail:
  ## message(ClientError) for cekRequest prefers detail over title.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    title = Opt.some("Limit"),
    detail = Opt.some("Too many objects in request"),
  )
  let ce = clientError(re)
  assertEq message(ce), "Too many objects in request"

testCase messageClientErrorRequestWithTitleOnly:
  ## message(ClientError) for cekRequest uses title when detail is absent.
  let re = requestError(
    "urn:ietf:params:jmap:error:notRequest", title = Opt.some("Not a JMAP Request")
  )
  let ce = clientError(re)
  assertEq message(ce), "Not a JMAP Request"

testCase messageClientErrorRequestRawTypeFallback:
  ## message(ClientError) for cekRequest falls back to rawType.
  let re = requestError("urn:ietf:params:jmap:error:unknownCapability")
  let ce = clientError(re)
  assertEq message(ce), "urn:ietf:params:jmap:error:unknownCapability"

# --- Phase 3: SetError empty rawType ---

testCase setErrorEmptyRawType:
  ## setError with empty rawType — still constructs, rawType preserved.
  let se = setError("")
  doAssert se.rawType == ""
  doAssert se.errorType == setUnknown
