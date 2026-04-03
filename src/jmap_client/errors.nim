# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Three-railway error hierarchy mapping JMAP's failure modes: transport
## (network/TLS/HTTP), request-level (RFC 7807 problem details), and
## per-invocation method and set errors.

import std/options
import std/strutils
from std/json import JsonNode

import ./primitives

type TransportErrorKind* = enum
  ## Failure mode before any JMAP-level processing occurs.
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus

type TransportError* = object of CatchableError
  ## Pre-JMAP failure with an HTTP status code when applicable.
  ## The inherited ``msg`` field carries the human-readable message.
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard

proc transportError*(kind: TransportErrorKind, message: string): TransportError =
  ## For non-HTTP-status transport errors.
  TransportError(kind: kind, msg: message)

proc httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  TransportError(kind: tekHttpStatus, msg: message, httpStatus: status)

type RequestErrorType* = enum
  ## Request-level error types from the JMAP problem details response (RFC 8620 §3.6.1).
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

proc parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  strutils.parseEnum[RequestErrorType](raw, retUnknown)

type RequestError* = object of CatchableError
  ## RFC 7807 problem details returned when the entire request is rejected.
  errorType*: RequestErrorType ## parsed enum variant
  rawType*: string ## always populated — lossless round-trip
  status*: Option[int] ## RFC 7807 "status" field
  title*: Option[string] ## RFC 7807 "title" field
  detail*: Option[string] ## RFC 7807 "detail" field
  limit*: Option[string] ## which limit was exceeded (retLimit only)
  extras*: Option[JsonNode] ## non-standard fields, lossless preservation

proc requestError*(
    rawType: string,
    status: Option[int] = none(int),
    title: Option[string] = none(string),
    detail: Option[string] = none(string),
    limit: Option[string] = none(string),
    extras: Option[JsonNode] = none(JsonNode),
): RequestError =
  ## Auto-parses rawType string to the corresponding enum variant via parseRequestErrorType.
  result = RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )
  doAssert result.rawType == rawType

type ClientErrorKind* = enum
  ## Discriminator for the outer railway: transport failure or request rejection.
  cekTransport
  cekRequest

type ClientError* = object of CatchableError
  ## Outer railway error: either a transport failure or a JMAP request rejection.
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError

proc clientError*(transport: TransportError): ClientError =
  ## Lifts a transport failure into the outer railway.
  ClientError(kind: cekTransport, transport: transport)

proc clientError*(request: RequestError): ClientError =
  ## Lifts a request rejection into the outer railway.
  ClientError(kind: cekRequest, request: request)

proc message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport:
    err.transport.msg
  of cekRequest:
    if err.request.detail.isSome:
      err.request.detail.get()
    elif err.request.title.isSome:
      err.request.title.get()
    else:
      err.request.rawType

type MethodErrorType* = enum
  ## Per-invocation error types from the inner railway (RFC 8620 §3.6.2).
  metServerUnavailable = "serverUnavailable"
  metServerFail = "serverFail"
  metServerPartialFail = "serverPartialFail"
  metUnknownMethod = "unknownMethod"
  metInvalidArguments = "invalidArguments"
  metInvalidResultReference = "invalidResultReference"
  metForbidden = "forbidden"
  metAccountNotFound = "accountNotFound"
  metAccountNotSupportedByMethod = "accountNotSupportedByMethod"
  metAccountReadOnly = "accountReadOnly"
  metAnchorNotFound = "anchorNotFound"
  metUnsupportedSort = "unsupportedSort"
  metUnsupportedFilter = "unsupportedFilter"
  metCannotCalculateChanges = "cannotCalculateChanges"
  metTooManyChanges = "tooManyChanges"
  metRequestTooLarge = "requestTooLarge"
  metStateMismatch = "stateMismatch"
  metFromAccountNotFound = "fromAccountNotFound"
  metFromAccountNotSupportedByMethod = "fromAccountNotSupportedByMethod"
  metUnknown

proc parseMethodErrorType*(raw: string): MethodErrorType =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  strutils.parseEnum[MethodErrorType](raw, metUnknown)

type MethodError* = object
  ## Inner railway error for a single method invocation within a batch response.
  errorType*: MethodErrorType ## parsed enum variant
  rawType*: string ## always populated — lossless round-trip
  description*: Option[string] ## RFC "description" field
  extras*: Option[JsonNode] ## non-standard fields, lossless preservation

proc methodError*(
    rawType: string,
    description: Option[string] = none(string),
    extras: Option[JsonNode] = none(JsonNode),
): MethodError =
  ## Auto-parses rawType string to the corresponding enum variant via parseMethodErrorType.
  result = MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )
  doAssert result.rawType == rawType

type SetErrorType* = enum
  ## Per-item error types within a /set response (RFC 8620 §5.3).
  setForbidden = "forbidden"
  setOverQuota = "overQuota"
  setTooLarge = "tooLarge"
  setRateLimit = "rateLimit"
  setNotFound = "notFound"
  setInvalidPatch = "invalidPatch"
  setWillDestroy = "willDestroy"
  setInvalidProperties = "invalidProperties"
  setAlreadyExists = "alreadyExists"
  setSingleton = "singleton"
  setUnknown

proc parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  strutils.parseEnum[SetErrorType](raw, setUnknown)

type SetError* = object
  ## Per-item error from a /set response. Variant-specific fields for invalidProperties and alreadyExists.
  rawType*: string ## always populated — lossless round-trip
  description*: Option[string] ## optional human-readable description
  extras*: Option[JsonNode] ## non-standard fields, lossless preservation
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string] ## invalid property names (§5.3)
  of setAlreadyExists:
    existingId*: Id ## the existing record's ID (§5.4)
  else:
    discard

proc setError*(
    rawType: string,
    description: Option[string] = none(string),
    extras: Option[JsonNode] = none(JsonNode),
): SetError =
  ## For non-variant-specific set errors.
  ## Defensively maps invalidProperties/alreadyExists to setUnknown when
  ## variant-specific data is absent.
  let errorType = parseSetErrorType(rawType)
  let safeType =
    if errorType in {setInvalidProperties, setAlreadyExists}: setUnknown else: errorType
  SetError(
    errorType: safeType, rawType: rawType, description: description, extras: extras
  )

proc setErrorInvalidProperties*(
    rawType: string,
    properties: seq[string],
    description: Option[string] = none(string),
    extras: Option[JsonNode] = none(JsonNode),
): SetError =
  ## Constructor for the invalidProperties variant, carrying the list of invalid property names.
  SetError(
    errorType: setInvalidProperties,
    rawType: rawType,
    description: description,
    extras: extras,
    properties: properties,
  )

proc setErrorAlreadyExists*(
    rawType: string,
    existingId: Id,
    description: Option[string] = none(string),
    extras: Option[JsonNode] = none(JsonNode),
): SetError =
  ## Constructor for the alreadyExists variant, carrying the ID of the existing record.
  SetError(
    errorType: setAlreadyExists,
    rawType: rawType,
    description: description,
    extras: extras,
    existingId: existingId,
  )
