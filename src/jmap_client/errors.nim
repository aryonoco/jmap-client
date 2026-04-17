# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Three-railway error hierarchy mapping JMAP's failure modes: transport
## (network/TLS/HTTP), request-level (RFC 7807 problem details), and
## per-invocation method and set errors. All error types are plain objects
## (not exceptions) for use with Railway-Oriented Programming via
## nim-results.

{.push raises: [], noSideEffect.}

import std/strutils
from std/json import JsonNode

import results

when defined(ssl):
  from std/net import TimeoutError, SslError
else:
  from std/net import TimeoutError

from ./validation import ValidationError
import ./primitives
import ./identifiers

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
  return TransportError(kind: kind, message: message)

func httpStatusError*(status: int, message: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  return TransportError(kind: tekHttpStatus, message: message, httpStatus: status)

type RequestErrorType* = enum
  ## Request-level error types from the JMAP problem details response (RFC 8620 §3.6.1).
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

func parseRequestErrorType*(raw: string): RequestErrorType =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  return strutils.parseEnum[RequestErrorType](raw, retUnknown)

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
  return re.errorType

func message*(re: RequestError): string =
  ## Human-readable message via cascade: detail > title > rawType.
  return re.detail.valueOr:
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
  return RequestError(
    errorType: parseRequestErrorType(rawType),
    rawType: rawType,
    status: status,
    title: title,
    detail: detail,
    limit: limit,
    extras: extras,
  )

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
  return ClientError(kind: cekTransport, transport: transport)

func clientError*(request: RequestError): ClientError =
  ## Lifts a request rejection into the outer railway.
  return ClientError(kind: cekRequest, request: request)

func message*(err: ClientError): string =
  ## Human-readable message for any ClientError variant.
  case err.kind
  of cekTransport:
    return err.transport.message
  of cekRequest:
    return err.request.message

func validationToClientError*(ve: ValidationError): ClientError =
  ## Bridges the construction railway (ValidationError) to the outer railway
  ## (ClientError). For use with ``mapErr`` when a Layer 1 validation failure
  ## must be surfaced as a transport error.
  return clientError(transportError(tekNetwork, ve.message))

func validationToClientErrorCtx*(ve: ValidationError, context: string): ClientError =
  ## Bridges with a context prefix prepended to the error message.
  return clientError(transportError(tekNetwork, context & ve.message))

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
  return "ssl" in lower or "tls" in lower or "certificate" in lower

func classifyException*(e: ref CatchableError): ClientError =
  ## Maps ``std/httpclient`` exceptions to ``ClientError(cekTransport)``.
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  let te =
    if e of ref TimeoutError:
      transportError(tekTimeout, e.msg)
    elif (when defined(ssl): e of ref SslError else: false):
      transportError(tekTls, e.msg)
    elif e of ref OSError:
      if isTlsRelatedMsg(e.msg):
        transportError(tekTls, e.msg)
      else:
        transportError(tekNetwork, e.msg)
    elif e of ref IOError:
      transportError(tekNetwork, e.msg)
    elif e of ref ValueError:
      transportError(tekNetwork, "protocol error: " & e.msg)
    else:
      transportError(tekNetwork, "unexpected error: " & e.msg)
  return clientError(te)

func sizeLimitExceeded*(
    context: RequestContext, what: string, actual, limit: int
): ClientError =
  ## Constructs a ``ClientError`` for a size-limit violation. Shared by
  ## body-length and Content-Length enforcement.
  return clientError(
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
  return ok()

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
  return strutils.parseEnum[MethodErrorType](raw, metUnknown)

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
  return me.errorType

func methodError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  ## Auto-parses rawType string to the corresponding enum variant via parseMethodErrorType.
  return MethodError(
    errorType: parseMethodErrorType(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )

type SetErrorType* = enum
  ## Per-item error types within a ``/set`` response. Covers RFC 8620 §5.3
  ## core variants plus the RFC 8621 §2.3 / §4.6 / §6 / §7.5 mail-specific
  ## variants. The ``"forbiddenFrom"`` wire string is shared between
  ## ``Identity/set`` (§6) and ``EmailSubmission/set`` (§7.5); a single
  ## enum variant ``setForbiddenFrom`` covers both contexts — the calling
  ## method determines which SHOULD-semantic applies.
  # RFC 8620 §5.3 / §5.4 — core
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
  # RFC 8621 §2.3 — Mailbox/set
  setMailboxHasChild = "mailboxHasChild"
  setMailboxHasEmail = "mailboxHasEmail"
  # RFC 8621 §4.6 — Email/set
  setBlobNotFound = "blobNotFound"
  setTooManyKeywords = "tooManyKeywords"
  setTooManyMailboxes = "tooManyMailboxes"
  # RFC 8621 §7.5 — EmailSubmission/set (and §6 Identity/set)
  setInvalidEmail = "invalidEmail"
  setTooManyRecipients = "tooManyRecipients"
  setNoRecipients = "noRecipients"
  setInvalidRecipients = "invalidRecipients"
  setForbiddenMailFrom = "forbiddenMailFrom"
  setForbiddenFrom = "forbiddenFrom"
  setForbiddenToSend = "forbiddenToSend"
  setCannotUnsend = "cannotUnsend"
  setUnknown

func parseSetErrorType*(raw: string): SetErrorType =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  return strutils.parseEnum[SetErrorType](raw, setUnknown)

type SetError* = object
  ## Per-item error from a ``/set`` response. Five payload-bearing arms
  ## match the RFC-mandated data: ``setInvalidProperties`` /
  ## ``setAlreadyExists`` (RFC 8620 §5.3 / §5.4), ``setBlobNotFound`` /
  ## ``setInvalidEmail`` / ``setTooManyRecipients`` /
  ## ``setInvalidRecipients`` (RFC 8621 §4.6 / §7.5), and ``setTooLarge``
  ## augmented with ``maxSize`` (RFC 8621 §7.5 SHOULD).
  ##
  ## ``rawErrorType`` is module-private — the public ``errorType*``
  ## accessor returns the discriminator so pattern-matching continues to
  ## work via UFCS, but literal construction of payload-bearing variants
  ## without their payloads is rejected at compile time (Pattern A). Use
  ## the variant-specific smart constructors (``setErrorInvalidProperties``
  ## etc.); generic ``setError`` is reserved for payload-less variants
  ## and defensively maps payload-bearing rawType strings without wire
  ## data to ``setUnknown``.
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## optional human-readable description
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation
  case rawErrorType: SetErrorType
  of setInvalidProperties:
    properties*: seq[string] ## RFC 8620 §5.3 SHOULD: invalid property names
  of setAlreadyExists:
    existingId*: Id ## RFC 8620 §5.4 MUST: the existing record's ID
  of setBlobNotFound:
    notFound*: seq[BlobId] ## RFC 8621 §4.6 MUST: unresolved blob IDs
  of setInvalidEmail:
    invalidEmailPropertyNames*: seq[string]
      ## RFC 8621 §7.5 SHOULD: invalid Email property names. Field name
      ## avoids collision with mail-layer accessor ``invalidEmailProperties``.
  of setTooManyRecipients:
    maxRecipientCount*: UnsignedInt
      ## RFC 8621 §7.5 MUST: server's recipient cap. Field name avoids
      ## collision with mail-layer accessor ``maxRecipients``.
  of setInvalidRecipients:
    invalidRecipients*: seq[string]
      ## RFC 8621 §7.5 MUST: recipient addresses that failed validation.
  of setTooLarge:
    maxSizeOctets*: Opt[UnsignedInt]
      ## RFC 8621 §7.5 SHOULD: server's size cap (octets). Field name
      ## avoids collision with mail-layer accessor ``maxSize``.
  else:
    discard

func errorType*(se: SetError): SetErrorType =
  ## Returns the parsed discriminator variant. Accessor preserves the
  ## previous field-level API surface after sealing ``rawErrorType``.
  return se.rawErrorType

template seFieldsPlain(lit: untyped): SetError =
  ## Builds a payload-less SetError with a literal discriminator. Expanded
  ## inline at each ``of X: seFieldsPlain(X)`` call site in ``setError``
  ## below — the literal substitution satisfies Nim's case-object
  ## construction rule (Pattern 4: no runtime discriminator allowed).
  SetError(
    rawErrorType: lit, rawType: rawType, description: description, extras: extras
  )

func setError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## For non-variant-specific set errors. Defensively maps the six
  ## required-payload variants (invalidProperties, alreadyExists,
  ## blobNotFound, invalidEmail, tooManyRecipients, invalidRecipients)
  ## to ``setUnknown`` when variant-specific data is absent — use the
  ## ``setErrorXyz`` smart constructors to supply the payload.
  ## ``setTooLarge`` admits an absent ``maxSize`` (RFC 8621 §7.5 SHOULD,
  ## not MUST), so it is constructed with ``Opt.none`` here.
  let errorType = parseSetErrorType(rawType)
  case errorType
  of setInvalidProperties, setAlreadyExists, setBlobNotFound, setInvalidEmail,
      setTooManyRecipients, setInvalidRecipients:
    seFieldsPlain(setUnknown)
  of setTooLarge:
    SetError(
      rawErrorType: setTooLarge,
      rawType: rawType,
      description: description,
      extras: extras,
      maxSizeOctets: Opt.none(UnsignedInt),
    )
  of setForbidden:
    seFieldsPlain(setForbidden)
  of setOverQuota:
    seFieldsPlain(setOverQuota)
  of setRateLimit:
    seFieldsPlain(setRateLimit)
  of setNotFound:
    seFieldsPlain(setNotFound)
  of setInvalidPatch:
    seFieldsPlain(setInvalidPatch)
  of setWillDestroy:
    seFieldsPlain(setWillDestroy)
  of setSingleton:
    seFieldsPlain(setSingleton)
  of setMailboxHasChild:
    seFieldsPlain(setMailboxHasChild)
  of setMailboxHasEmail:
    seFieldsPlain(setMailboxHasEmail)
  of setTooManyKeywords:
    seFieldsPlain(setTooManyKeywords)
  of setTooManyMailboxes:
    seFieldsPlain(setTooManyMailboxes)
  of setNoRecipients:
    seFieldsPlain(setNoRecipients)
  of setForbiddenMailFrom:
    seFieldsPlain(setForbiddenMailFrom)
  of setForbiddenFrom:
    seFieldsPlain(setForbiddenFrom)
  of setForbiddenToSend:
    seFieldsPlain(setForbiddenToSend)
  of setCannotUnsend:
    seFieldsPlain(setCannotUnsend)
  of setUnknown:
    seFieldsPlain(setUnknown)

func setErrorInvalidProperties*(
    rawType: string,
    properties: seq[string],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setInvalidProperties`` — carries the invalid property names (RFC 8620 §5.3).
  return SetError(
    rawErrorType: setInvalidProperties,
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
  ## Constructor for ``setAlreadyExists`` — carries the existing record's ID (RFC 8620 §5.4).
  return SetError(
    rawErrorType: setAlreadyExists,
    rawType: rawType,
    description: description,
    extras: extras,
    existingId: existingId,
  )

func setErrorBlobNotFound*(
    rawType: string,
    notFound: seq[BlobId],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setBlobNotFound`` — carries the unresolved blob
  ## IDs (RFC 8621 §4.6 MUST).
  return SetError(
    rawErrorType: setBlobNotFound,
    rawType: rawType,
    description: description,
    extras: extras,
    notFound: notFound,
  )

func setErrorInvalidEmail*(
    rawType: string,
    propertyNames: seq[string],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setInvalidEmail`` — carries the names of invalid
  ## Email properties (RFC 8621 §7.5 SHOULD).
  return SetError(
    rawErrorType: setInvalidEmail,
    rawType: rawType,
    description: description,
    extras: extras,
    invalidEmailPropertyNames: propertyNames,
  )

func setErrorTooManyRecipients*(
    rawType: string,
    cap: UnsignedInt,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setTooManyRecipients`` — carries the server's
  ## recipient cap (RFC 8621 §7.5 MUST).
  return SetError(
    rawErrorType: setTooManyRecipients,
    rawType: rawType,
    description: description,
    extras: extras,
    maxRecipientCount: cap,
  )

func setErrorInvalidRecipients*(
    rawType: string,
    addresses: seq[string],
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setInvalidRecipients`` — carries the recipient
  ## addresses that failed validation (RFC 8621 §7.5 MUST).
  return SetError(
    rawErrorType: setInvalidRecipients,
    rawType: rawType,
    description: description,
    extras: extras,
    invalidRecipients: addresses,
  )

func setErrorTooLarge*(
    rawType: string,
    maxSize: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): SetError =
  ## Constructor for ``setTooLarge`` — carries the server's optional size
  ## cap (RFC 8621 §7.5 SHOULD). ``maxSize`` defaults to ``Opt.none`` so
  ## the RFC 8620 §5.3 core use of tooLarge without a cap is expressible.
  return SetError(
    rawErrorType: setTooLarge,
    rawType: rawType,
    description: description,
    extras: extras,
    maxSizeOctets: maxSize,
  )
