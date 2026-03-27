# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/json

import pkg/results

import jmap_client/primitives
import jmap_client/errors

# --- parseRequestErrorType ---

block parseRequestErrorTypeUnknownCapability:
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:unknownCapability") ==
    retUnknownCapability

block parseRequestErrorTypeNotJson:
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notJSON") == retNotJson

block parseRequestErrorTypeNotRequest:
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:notRequest") ==
    retNotRequest

block parseRequestErrorTypeLimit:
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:limit") == retLimit

block parseRequestErrorTypeVendorUri:
  doAssert parseRequestErrorType("urn:vendor:custom:error") == retUnknown

block parseRequestErrorTypeEmpty:
  doAssert parseRequestErrorType("") == retUnknown

# --- parseMethodErrorType ---

block parseMethodErrorTypeAllKnown:
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

block parseMethodErrorTypeUnknown:
  doAssert parseMethodErrorType("customError") == metUnknown

block parseMethodErrorTypeEmpty:
  doAssert parseMethodErrorType("") == metUnknown

# --- parseSetErrorType ---

block parseSetErrorTypeAllKnown:
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
  doAssert e.existingId.isSome
  doAssert e.existingId.unsafeGet == someId
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
