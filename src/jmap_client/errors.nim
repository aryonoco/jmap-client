# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Three-railway error hierarchy mapping JMAP's failure modes: transport
## (network/TLS/HTTP), request-level (RFC 7807 problem details), and
## per-invocation method and set errors. All error types are plain objects
## (not exceptions) for use with Railway-Oriented Programming via
## nim-results.

import std/strutils
from std/json import JsonNode

import results

when defined(ssl):
  from std/net import TimeoutError, SslError
else:
  from std/net import TimeoutError

from ./validation import ValidationError
import ./primitives

{.push raises: [].}

type TransportErrorKind* = enum
  ## Failure mode before any JMAP-level processing occurs.
  tekNetwork
  tekTls
  tekTimeout
  tekHttpStatus

type TransportError* = object
  ## Pre-JMAP failure with an HTTP status code when applicable.
  message*: string ## human-readable error description
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard

func transportError*(kind: TransportErrorKind, message: string): TransportError =
  ## For non-HTTP-status transport errors.
  TransportError(kind: kind, message: message)

func httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  TransportError(kind: tekHttpStatus, message: message, httpStatus: status)

type RequestErrorType* = enum
  ## Request-level error types from the JMAP problem details response (RFC 8620 §3.6.1).
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

func parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  strutils.parseEnum[RequestErrorType](raw, retUnknown)

type RequestError* = object
  ## RFC 7807 problem details returned when the entire request is rejected.
  ##
  ## ``errorType`` is module-private — always derived from ``rawType`` via
  ## ``parseRequestErrorType``. This seals the consistency invariant:
  ## ``errorType`` and ``rawType`` cannot diverge.
  errorType: RequestErrorType ## module-private; derived from rawType
  rawType*: string ## always populated — lossless round-trip
  status*: Opt[int] ## RFC 7807 "status" field
  title*: Opt[string] ## RFC 7807 "title" field
  detail*: Opt[string] ## RFC 7807 "detail" field
  limit*: Opt[string] ## which limit was exceeded (retLimit only)
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation

func errorType*(re: RequestError): RequestErrorType =
  ## Returns the parsed error type variant.
  re.errorType

func message*(re: RequestError): string =
  ## Human-readable message via cascade: detail > title > rawType.
  re.detail.valueOr:
    re.title.valueOr:
      re.rawType

func requestError*(
    rawType: string,
    status: Opt[int] = Opt.none(int),
    title: Opt[string] = Opt.none(string),
    detail: Opt[string] = Opt.none(string),
    limit: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): RequestError =
  ## Auto-parses rawType string to the corresponding enum variant via parseRequestErrorType.
  let re = RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )
  doAssert re.rawType == rawType
  return re

type ClientErrorKind* = enum
  ## Discriminator for the outer railway: transport failure or request rejection.
  cekTransport
  cekRequest

type ClientError* = object
  ## Outer railway error: either a transport failure or a JMAP request rejection.
  case kind*: ClientErrorKind
  of cekTransport:
    transport*: TransportError
  of cekRequest:
    request*: RequestError

func clientError*(transport: TransportError): ClientError =
  ## Lifts a transport failure into the outer railway.
  ClientError(kind: cekTransport, transport: transport)

func clientError*(request: RequestError): ClientError =
  ## Lifts a request rejection into the outer railway.
  ClientError(kind: cekRequest, request: request)

func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport: err.transport.message
  of cekRequest: err.request.message

func validationToClientError*(ve: ValidationError): ClientError =
  ## Bridges the construction railway (ValidationError) to the outer railway
  ## (ClientError). For use with ``mapErr`` when a Layer 1 validation failure
  ## must be surfaced as a transport error.
  clientError(transportError(tekNetwork, ve.message))

func validationToClientErrorCtx*(ve: ValidationError, context: string): ClientError =
  ## Bridges with a context prefix prepended to the error message.
  clientError(transportError(tekNetwork, context & ve.message))

type RequestContext* = enum
  ## Identifies the JMAP endpoint being processed. Used in error messages
  ## by size-limit and HTTP-response classification functions.
  rcSession = "session"
  rcApi = "api"

func isTlsRelatedMsg(msg: string): bool =
  ## Heuristic: checks whether an OSError message indicates a TLS failure.
  ## OpenSSL surfaces TLS errors as OSError with keywords in the message
  ## (D4.5). False positives are harmless — the error is still a transport
  ## failure and ``msg`` carries the actual underlying error.
  let lower = msg.toLowerAscii
  "ssl" in lower or "tls" in lower or "certificate" in lower

func classifyException*(e: ref CatchableError): ClientError =
  ## Maps ``std/httpclient`` exceptions to ``ClientError(cekTransport)``.
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  var te: TransportError
  if e of ref TimeoutError:
    te = transportError(tekTimeout, e.msg)
  elif (when defined(ssl): e of ref SslError else: false):
    te = transportError(tekTls, e.msg)
  elif e of ref OSError:
    te =
      if isTlsRelatedMsg(e.msg):
        transportError(tekTls, e.msg)
      else:
        transportError(tekNetwork, e.msg)
  elif e of ref IOError:
    te = transportError(tekNetwork, e.msg)
  elif e of ref ValueError:
    te = transportError(tekNetwork, "protocol error: " & e.msg)
  else:
    te = transportError(tekNetwork, "unexpected error: " & e.msg)
  clientError(te)

func sizeLimitExceeded*(
    context: RequestContext, what: string, actual, limit: int
): ClientError =
  ## Constructs a ``ClientError`` for a size-limit violation. Shared by
  ## body-length and Content-Length enforcement.
  clientError(
    transportError(
      tekNetwork,
      $context & " " & what & " exceeds limit: " & $actual & " bytes > " & $limit &
        " byte limit",
    )
  )

func enforceBodySizeLimit*(
    maxResponseBytes: int, body: string, context: RequestContext
): Result[void, ClientError] =
  ## Phase 2 body size enforcement: post-read rejection via actual body
  ## length. No-op when ``maxResponseBytes == 0`` (no limit). Pure.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    return err(sizeLimitExceeded(context, "response body", body.len, maxResponseBytes))
  ok()

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

func parseMethodErrorType*(raw: string): MethodErrorType =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  strutils.parseEnum[MethodErrorType](raw, metUnknown)

type MethodError* = object
  ## Inner railway error for a single method invocation within a batch response.
  ##
  ## ``errorType`` is module-private — always derived from ``rawType`` via
  ## ``parseMethodErrorType``. This seals the consistency invariant.
  errorType: MethodErrorType ## module-private; derived from rawType
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## RFC "description" field
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation

func errorType*(me: MethodError): MethodErrorType =
  ## Returns the parsed error type variant.
  me.errorType

func methodError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  ## Auto-parses rawType string to the corresponding enum variant via parseMethodErrorType.
  let me = MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )
  doAssert me.rawType == rawType
  return me

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

func parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  strutils.parseEnum[SetErrorType](raw, setUnknown)

type SetError* = object
  ## Per-item error from a /set response. Variant-specific fields for invalidProperties and alreadyExists.
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## optional human-readable description
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation
  case errorType*: SetErrorType
  of setInvalidProperties:
    properties*: seq[string] ## invalid property names (§5.3)
  of setAlreadyExists:
    existingId*: Id ## the existing record's ID (§5.4)
  else:
    discard

func setError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
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

func setErrorInvalidProperties*(
    rawType: string,
    properties: seq[string],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for the invalidProperties variant, carrying the list of invalid property names.
  SetError(
    errorType: setInvalidProperties,
    rawType: rawType,
    description: description,
    extras: extras,
    properties: properties,
  )

func setErrorAlreadyExists*(
    rawType: string,
    existingId: Id,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for the alreadyExists variant, carrying the ID of the existing record.
  SetError(
    errorType: setAlreadyExists,
    rawType: rawType,
    description: description,
    extras: extras,
    existingId: existingId,
  )
