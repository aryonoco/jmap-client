# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for transport, request, client, method, and set error constructors.

import std/json
import std/strutils

import results

import jmap_client/primitives
import jmap_client/errors

import ./massertions

# --- parseRequestErrorType ---

block parseRequestErrorTypeAllKnown:
  ## Table-driven: every known request error URI maps to its expected variant.
  const cases = [
    ("urn:ietf:params:jmap:error:unknownCapability", retUnknownCapability),
    ("urn:ietf:params:jmap:error:notJSON", retNotJson),
    ("urn:ietf:params:jmap:error:notRequest", retNotRequest),
    ("urn:ietf:params:jmap:error:limit", retLimit),
  ]
  for (uri, expected) in cases:
    assertEq parseRequestErrorType(uri), expected

block parseRequestErrorTypeVendorUri:
  doAssert parseRequestErrorType("urn:vendor:custom:error") == retUnknown

block parseRequestErrorTypeEmpty:
  doAssert parseRequestErrorType("") == retUnknown

# --- parseMethodErrorType ---

block parseMethodErrorTypeAllKnown:
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

block parseMethodErrorTypeUnknown:
  doAssert parseMethodErrorType("customError") == metUnknown

block parseMethodErrorTypeEmpty:
  doAssert parseMethodErrorType("") == metUnknown

# --- parseSetErrorType ---

block parseSetErrorTypeAllKnown:
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

block parseSetErrorTypeVendorSpecific:
  doAssert parseSetErrorType("vendorSpecific") == setUnknown

block parseSetErrorTypeEmpty:
  doAssert parseSetErrorType("") == setUnknown

# --- TransportError constructors ---

block transportErrorTimeout:
  let e = transportError(tekTimeout, "timed out")
  doAssert e.kind == tekTimeout
  doAssert e.message == "timed out"

block transportErrorNetwork:
  let e = transportError(tekNetwork, "refused")
  doAssert e.kind == tekNetwork
  doAssert e.message == "refused"

block transportErrorTls:
  let e = transportError(tekTls, "certificate verify failed")
  doAssert e.kind == tekTls
  doAssert e.message == "certificate verify failed"

block httpStatusError502:
  let e = httpStatusError(502, "Bad Gateway")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 502
  doAssert e.message == "Bad Gateway"

# --- RequestError constructor ---

block requestErrorLimit:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit", limit = Opt.some("maxCallsInRequest")
  )
  doAssert e.errorType == retLimit
  doAssert e.rawType == "urn:ietf:params:jmap:error:limit"
  doAssert e.limit.isSome
  doAssert e.limit.unsafeGet == "maxCallsInRequest"
  doAssert e.status.isNone
  doAssert e.title.isNone
  doAssert e.detail.isNone
  doAssert e.extras.isNone

block requestErrorLimitWithExtras:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit",
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(%*{"requestId": "abc"}),
  )
  doAssert e.extras.isSome

block requestErrorUnknown:
  let e = requestError("urn:vendor:custom")
  doAssert e.errorType == retUnknown
  doAssert e.rawType == "urn:vendor:custom"

block requestErrorKnownRawTypePreserved:
  let e = requestError("urn:ietf:params:jmap:error:notJSON")
  doAssert e.errorType == retNotJson
  doAssert e.rawType == "urn:ietf:params:jmap:error:notJSON"

# --- ClientError constructors + message accessor ---

block clientErrorTransport:
  let ce = clientError(transportError(tekNetwork, "refused"))
  doAssert ce.kind == cekTransport

block clientErrorRequest:
  let ce = clientError(requestError("urn:ietf:params:jmap:error:notJSON"))
  doAssert ce.kind == cekRequest

block messageTransport:
  let ce = clientError(transportError(tekTimeout, "timed out"))
  doAssert ce.message == "timed out"

block messageRequestWithDetail:
  let ce = clientError(
    requestError(
      "urn:ietf:params:jmap:error:limit", detail = Opt.some("Too many calls")
    )
  )
  doAssert ce.message == "Too many calls"

block messageRequestDetailPreferredOverTitle:
  let ce = clientError(
    requestError(
      "urn:ietf:params:jmap:error:limit",
      title = Opt.some("Limit Exceeded"),
      detail = Opt.some("Too many calls"),
    )
  )
  doAssert ce.message == "Too many calls"

block messageRequestWithTitleOnly:
  let ce = clientError(
    requestError("urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded"))
  )
  doAssert ce.message == "Limit Exceeded"

block messageRequestFallbackToRawType:
  let ce = clientError(requestError("urn:ietf:params:jmap:error:limit"))
  doAssert ce.message == "urn:ietf:params:jmap:error:limit"

# --- MethodError constructor ---

block methodErrorKnown:
  let e = methodError("unknownMethod")
  doAssert e.errorType == metUnknownMethod
  doAssert e.rawType == "unknownMethod"
  doAssert e.description.isNone
  doAssert e.extras.isNone

block methodErrorUnknownWithExtras:
  let e = methodError("custom", extras = Opt.some(%*{"hint": "retry"}))
  doAssert e.errorType == metUnknown
  doAssert e.rawType == "custom"
  doAssert e.extras.isSome

block methodErrorWithDescription:
  let e = methodError("serverFail", description = Opt.some("internal error"))
  doAssert e.errorType == metServerFail
  doAssert e.description.isSome
  doAssert e.description.unsafeGet == "internal error"

# --- SetError constructors ---

block setErrorForbidden:
  let e = setError("forbidden")
  doAssert e.errorType == setForbidden
  doAssert e.rawType == "forbidden"

block setErrorWithDescriptionAndExtras:
  let e = setError(
    "overQuota",
    description = Opt.some("quota exceeded"),
    extras = Opt.some(%*{"limit": 100}),
  )
  doAssert e.errorType == setOverQuota
  doAssert e.description.isSome
  doAssert e.description.unsafeGet == "quota exceeded"
  doAssert e.extras.isSome

block setErrorInvalidPropertiesVariant:
  let e = setErrorInvalidProperties("invalidProperties", @["name"])
  doAssert e.errorType == setInvalidProperties
  doAssert e.properties == @["name"]
  doAssert e.rawType == "invalidProperties"
  doAssert e.description.isNone

block setErrorAlreadyExistsVariant:
  let someId = parseIdFromServer("existing-123").get()
  let e = setErrorAlreadyExists("alreadyExists", someId)
  doAssert e.errorType == setAlreadyExists
  doAssert e.existingId == someId
  doAssert e.rawType == "alreadyExists"
  doAssert e.description.isNone

block setErrorDefensiveFallbackInvalidProperties:
  let e = setError("invalidProperties")
  doAssert e.errorType == setUnknown
  doAssert e.rawType == "invalidProperties"

block setErrorDefensiveFallbackAlreadyExists:
  let e = setError("alreadyExists")
  doAssert e.errorType == setUnknown
  doAssert e.rawType == "alreadyExists"

# --- RFC conformance: string backing ---

block requestErrorTypeStringBacking:
  doAssert $retUnknownCapability == "urn:ietf:params:jmap:error:unknownCapability"
  doAssert $retNotJson == "urn:ietf:params:jmap:error:notJSON"
  doAssert $retNotRequest == "urn:ietf:params:jmap:error:notRequest"
  doAssert $retLimit == "urn:ietf:params:jmap:error:limit"

block methodErrorTypeStringBacking:
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

block setErrorTypeStringBacking:
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

block enumParserCaseSensitivity:
  doAssert parseMethodErrorType("ServerFail") == metUnknown
  doAssert parseSetErrorType("Forbidden") == setUnknown
  ## parseEnum uses nimIdentNormalize: first-char case-sensitive, rest insensitive.
  ## "urn:..." and "urn:..." share the same first char, so "notJson" matches "notJSON".
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notJson") == retNotJson

block parseRequestErrorTypeIdempotent:
  doAssert parseRequestErrorType($retUnknownCapability) == retUnknownCapability
  doAssert parseRequestErrorType($retNotJson) == retNotJson
  doAssert parseRequestErrorType($retNotRequest) == retNotRequest
  doAssert parseRequestErrorType($retLimit) == retLimit

block parseMethodErrorTypeIdempotent:
  doAssert parseMethodErrorType($metServerFail) == metServerFail
  doAssert parseMethodErrorType($metInvalidArguments) == metInvalidArguments
  doAssert parseMethodErrorType($metForbidden) == metForbidden
  doAssert parseMethodErrorType($metStateMismatch) == metStateMismatch

block parseSetErrorTypeIdempotent:
  doAssert parseSetErrorType($setForbidden) == setForbidden
  doAssert parseSetErrorType($setInvalidProperties) == setInvalidProperties
  doAssert parseSetErrorType($setSingleton) == setSingleton

block requestErrorRawTypeAllVariants:
  for uri in [
    "urn:ietf:params:jmap:error:unknownCapability",
    "urn:ietf:params:jmap:error:notJSON", "urn:ietf:params:jmap:error:notRequest",
    "urn:ietf:params:jmap:error:limit", "urn:vendor:custom",
  ]:
    doAssert requestError(uri).rawType == uri

block methodErrorRawTypeAllVariants:
  for s in ["serverFail", "unknownMethod", "forbidden", "customVendorError"]:
    doAssert methodError(s).rawType == s

block setErrorRawTypeAllVariants:
  for s in [
    "forbidden", "overQuota", "tooLarge", "rateLimit", "notFound", "invalidPatch",
    "willDestroy", "singleton", "vendorCustom",
  ]:
    doAssert setError(s).rawType == s

block methodErrorRfc8621FallThrough:
  doAssert parseMethodErrorType("mailboxHasChild") == metUnknown
  doAssert parseMethodErrorType("mailboxHasEmail") == metUnknown
  doAssert parseMethodErrorType("tooManyKeywords") == metUnknown

# --- Missing error paths ---

block httpStatusError404:
  let e = httpStatusError(404, "Not Found")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 404

block httpStatusError500:
  let e = httpStatusError(500, "Internal Server Error")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 500

block httpStatusErrorZero:
  let e = httpStatusError(0, "zero")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 0

block setErrorAllElseBranch:
  doAssert setError("tooLarge").errorType == setTooLarge
  doAssert setError("rateLimit").errorType == setRateLimit
  doAssert setError("notFound").errorType == setNotFound
  doAssert setError("invalidPatch").errorType == setInvalidPatch
  doAssert setError("willDestroy").errorType == setWillDestroy
  doAssert setError("singleton").errorType == setSingleton

block requestErrorAllFieldsPopulated:
  let e = requestError(
    "urn:ietf:params:jmap:error:limit",
    status = Opt.some(400),
    title = Opt.some("Request Limit"),
    detail = Opt.some("Too many calls"),
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(%*{"requestId": "abc"}),
  )
  doAssert e.status.isSome
  doAssert e.status.unsafeGet == 400
  doAssert e.title.isSome
  doAssert e.detail.isSome
  doAssert e.limit.isSome
  doAssert e.extras.isSome

block methodErrorRawTypePreserved:
  doAssert methodError("vendorSpecific").rawType == "vendorSpecific"
  doAssert methodError("vendorSpecific").errorType == metUnknown

# --- nimIdentNormalize documentation tests ---

block parseMethodErrorTypeAllLowercase:
  # nimIdentNormalize: case-insensitive after first char
  # "serverfail" has same first char 's' as "serverFail" -> matches
  doAssert parseMethodErrorType("serverfail") == metServerFail

block parseMethodErrorTypeUnderscore:
  # nimIdentNormalize strips underscores -> "server_Fail" matches "serverFail"
  doAssert parseMethodErrorType("server_Fail") == metServerFail

block parseSetErrorTypeUnderscore:
  doAssert parseSetErrorType("over_Quota") == setOverQuota

block parseRequestErrorTypeUnderscore:
  # nimIdentNormalize strips underscores in URI-style error types too.
  # "urn:ietf:params:jmap:error:not_JSON" normalises the same as
  # "urn:ietf:params:jmap:error:notJSON" (underscore removed, case-folded).
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:not_JSON") == retNotJson

# --- SetError multi-element properties ---

block setErrorInvalidPropertiesMultiple:
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

block setErrorAllVariantsThroughGenericConstructor:
  # Every SetErrorType variant through setError() must not crash
  # and must preserve rawType
  for variant in SetErrorType:
    let rawType = $variant
    let se = setError(rawType, Opt.none(string), Opt.none(JsonNode))
    doAssert se.rawType == rawType

# --- ClientError message cascade ---

block clientErrorMessageCascadeDetail:
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
  assertEq ce.message, "Too many requests"

block clientErrorMessageCascadeTitle:
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
  assertEq ce.message, "Rate Limited"

block clientErrorMessageCascadeRawType:
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
  assertEq ce.message, "urn:ietf:params:jmap:error:limit"

# --- SetError variant constructor edge cases ---

block setErrorInvalidPropertiesEmptyList:
  # Empty property list is structurally valid
  let se = setErrorInvalidProperties("invalidProperties", @[])
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties.len == 0
  doAssert se.rawType == "invalidProperties"

block setErrorInvalidPropertiesAllFields:
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
  doAssert se.description.unsafeGet == "bad properties"
  doAssert se.extras.isSome

block setErrorAlreadyExistsAllFields:
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
  doAssert se.description.unsafeGet == "duplicate detected"
  doAssert se.extras.isSome

block setErrorDefensiveFallbackInvalidProperties:
  # Generic constructor maps invalidProperties to setUnknown defensively
  let se = setError("invalidProperties")
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "invalidProperties"

block setErrorDefensiveFallbackAlreadyExists:
  # Generic constructor maps alreadyExists to setUnknown defensively
  let se = setError("alreadyExists")
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "alreadyExists"

# --- Phase 4: Error constructor mutation resistance ---

block transportErrorEmptyMessage:
  ## Empty message string is valid — no restriction on message content.
  let te = transportError(tekNetwork, "")
  assertEq te.message, ""

block setErrorInvalidPropertiesEmptyListVariant:
  ## Empty properties list is valid (semantically odd but structurally correct).
  let se = setErrorInvalidProperties("invalidProperties", @[])
  assertEq se.errorType, setInvalidProperties
  assertLen se.properties, 0

block setErrorAlreadyExistsMaxLengthId:
  ## alreadyExists with maximum-length Id (255 bytes).
  let id = parseId("A".repeat(255)).get()
  let se = setErrorAlreadyExists("alreadyExists", id)
  assertEq se.errorType, setAlreadyExists
  assertEq se.existingId, id

block requestErrorLimitFieldNonLimitType:
  ## Limit field populated for a non-retLimit error type.
  let re =
    requestError("urn:ietf:params:jmap:error:notJSON", limit = Opt.some("maxSize"))
  assertEq re.errorType, retNotJson
  assertSome re.limit

block clientErrorMessageAllNone:
  ## When all optional fields are None, message falls back to rawType.
  let re = requestError("urn:ietf:params:jmap:error:notJSON")
  let ce = clientError(re)
  assertEq message(ce), "urn:ietf:params:jmap:error:notJSON"

block httpStatusErrorLargeStatus:
  ## Very large or unusual HTTP status codes.
  let te = httpStatusError(999, "unusual")
  assertEq te.httpStatus, 999
  let te0 = httpStatusError(0, "zero status")
  assertEq te0.httpStatus, 0

# --- Phase 2: Error constructor zero-coverage gaps ---

block clientErrorFromTransport:
  ## clientError(transport) lifts a transport error into ClientError.
  let te = transportError(tekNetwork, "connection refused")
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekNetwork
  doAssert ce.transport.message == "connection refused"

block clientErrorFromRequest:
  ## clientError(request) lifts a request error into ClientError.
  let re = requestError("urn:ietf:params:jmap:error:notJSON")
  let ce = clientError(re)
  doAssert ce.kind == cekRequest
  doAssert ce.request.errorType == retNotJson

block transportErrorAllKindsNetwork:
  ## transportError with tekNetwork variant.
  let e = transportError(tekNetwork, "host unreachable")
  doAssert e.kind == tekNetwork
  doAssert e.message == "host unreachable"

block transportErrorAllKindsTls:
  ## transportError with tekTls variant.
  let e = transportError(tekTls, "handshake failed")
  doAssert e.kind == tekTls
  doAssert e.message == "handshake failed"

block transportErrorAllKindsTimeout:
  ## transportError with tekTimeout variant.
  let e = transportError(tekTimeout, "request timed out after 30s")
  doAssert e.kind == tekTimeout
  doAssert e.message == "request timed out after 30s"

block transportErrorAllKindsHttpStatus:
  ## httpStatusError constructs a tekHttpStatus variant.
  let e = httpStatusError(503, "Service Unavailable")
  doAssert e.kind == tekHttpStatus
  doAssert e.httpStatus == 503
  doAssert e.message == "Service Unavailable"

block httpStatusErrorFieldAccess:
  ## httpStatusError provides access to both httpStatus and message.
  let e = httpStatusError(429, "Too Many Requests")
  assertEq e.kind, tekHttpStatus
  assertEq e.httpStatus, 429
  assertEq e.message, "Too Many Requests"

block messageClientErrorTransportPath:
  ## message(ClientError) for cekTransport returns transport.message.
  let ce = clientError(transportError(tekTls, "expired certificate"))
  assertEq message(ce), "expired certificate"

block messageClientErrorRequestWithDetail:
  ## message(ClientError) for cekRequest prefers detail over title.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    title = Opt.some("Limit"),
    detail = Opt.some("Too many objects in request"),
  )
  let ce = clientError(re)
  assertEq message(ce), "Too many objects in request"

block messageClientErrorRequestWithTitleOnly:
  ## message(ClientError) for cekRequest uses title when detail is absent.
  let re = requestError(
    "urn:ietf:params:jmap:error:notRequest", title = Opt.some("Not a JMAP Request")
  )
  let ce = clientError(re)
  assertEq message(ce), "Not a JMAP Request"

block messageClientErrorRequestRawTypeFallback:
  ## message(ClientError) for cekRequest falls back to rawType.
  let re = requestError("urn:ietf:params:jmap:error:unknownCapability")
  let ce = clientError(re)
  assertEq message(ce), "urn:ietf:params:jmap:error:unknownCapability"

# --- Phase 3: SetError empty rawType ---

block setErrorEmptyRawType:
  ## setError with empty rawType — still constructs, rawType preserved.
  let se = setError("")
  doAssert se.rawType == ""
  doAssert se.errorType == setUnknown
