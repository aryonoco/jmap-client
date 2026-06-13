# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Three-railway error hierarchy mapping JMAP's failure modes: transport
## (network/TLS/HTTP), request-level (RFC 7807 problem details), and
## per-invocation method and set errors. All error types are plain objects
## (not exceptions) for use with Railway-Oriented Programming via
## nim-results.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils
from std/json import JsonNode

import results

when defined(ssl):
  from std/net import TimeoutError, SslError
else:
  from std/net import TimeoutError

from ./validation import ValidationError, message
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
  detail*: string ## wire/exception text; composed with kind into ``message``
  case kind*: TransportErrorKind
  of tekHttpStatus:
    httpStatus*: int
  of tekNetwork, tekTls, tekTimeout:
    discard

func transportError*(kind: TransportErrorKind, detail: string): TransportError =
  ## For non-HTTP-status transport errors.
  return TransportError(kind: kind, detail: detail)

func httpStatusError*(status: int, detail: string): TransportError =
  ## For HTTP-level failures without a JMAP problem details body.
  return TransportError(kind: tekHttpStatus, detail: detail, httpStatus: status)

func message*(te: TransportError): string =
  ## Canonical diagnostic: HTTP arm prefixes the status code; the other
  ## arms surface the detail string verbatim.
  case te.kind
  of tekHttpStatus:
    "HTTP " & $te.httpStatus & ": " & te.detail
  of tekNetwork, tekTls, tekTimeout:
    te.detail

func `$`*(te: TransportError): string =
  ## Delegates to ``message`` for the single canonical projection.
  te.message

type RequestErrorKind* = enum
  ## Request-level error types from the JMAP problem details response (RFC 8620 §3.6.1).
  retUnknownCapability = "urn:ietf:params:jmap:error:unknownCapability"
  retNotJson = "urn:ietf:params:jmap:error:notJSON"
  retNotRequest = "urn:ietf:params:jmap:error:notRequest"
  retLimit = "urn:ietf:params:jmap:error:limit"
  retUnknown

func parseRequestErrorKind*(raw: string): RequestErrorKind =
  ## Total function: always succeeds. Unknown URIs map to retUnknown.
  return strutils.parseEnum[RequestErrorKind](raw, retUnknown)

type RequestError* = object
  ## RFC 7807 problem details returned when the entire request is rejected.
  ##
  ## ``kind`` is module-private — always derived from ``rawType`` via
  ## ``parseRequestErrorKind``. This seals the consistency invariant:
  ## ``kind`` and ``rawType`` cannot diverge.
  kind: RequestErrorKind ## module-private; derived from rawType
  rawType*: string ## always populated — lossless round-trip
  status*: Opt[int] ## RFC 7807 "status" field
  title*: Opt[string] ## RFC 7807 "title" field
  detail*: Opt[string] ## RFC 7807 "detail" field
  limit*: Opt[string] ## which limit was exceeded (retLimit only)
  extras*: Opt[JsonNode] ## non-standard fields, lossless preservation

func kind*(re: RequestError): RequestErrorKind =
  ## Returns the parsed error kind variant.
  return re.kind

func message*(re: RequestError): string =
  ## Human-readable message via cascade: detail > title > rawType.
  return re.detail.valueOr:
    re.title.valueOr:
      re.rawType

func `$`*(re: RequestError): string =
  ## Delegates to ``message`` for the single canonical projection.
  re.message

func requestError*(
    rawType: string,
    status: Opt[int] = Opt.none(int),
    title: Opt[string] = Opt.none(string),
    detail: Opt[string] = Opt.none(string),
    limit: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): RequestError =
  ## Auto-parses rawType string to the corresponding enum variant via parseRequestErrorKind.
  return RequestError(
    kind: parseRequestErrorKind(rawType),
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

func `$`*(ce: ClientError): string =
  ## Delegates to ``message`` for the single canonical projection.
  ce.message

func validationToClientError*(ve: ValidationError): ClientError =
  ## Bridges the construction railway (ValidationError) to the outer railway
  ## (ClientError). For use with ``mapErr`` when a Layer 1 validation failure
  ## must be surfaced as a transport error.
  return clientError(transportError(tekNetwork, ve.message))

func validationToClientErrorCtx*(ve: ValidationError, context: string): ClientError =
  ## Bridges with a context prefix prepended to the error message.
  return clientError(transportError(tekNetwork, context & ve.message))

func isTlsRelatedMsg(msg: string): bool =
  ## Heuristic: checks whether an OSError message indicates a TLS failure.
  ## OpenSSL surfaces TLS errors as OSError with keywords in the message
  ## (D4.5). False positives are harmless — the error is still a transport
  ## failure and ``msg`` carries the actual underlying error.
  let lower = msg.toLowerAscii
  return "ssl" in lower or "tls" in lower or "certificate" in lower

func classifyTransportException*(e: ref CatchableError): TransportError =
  ## Maps ``std/httpclient`` exceptions to ``TransportError``. Pure: no
  ## IO, no side effects. Exhaustive over known exception types. Called
  ## by the default HTTP transport closure; ``classifyException`` lifts
  ## the result into the outer railway for JMAP-layer callers.
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

func classifyException*(e: ref CatchableError): ClientError =
  ## Maps ``std/httpclient`` exceptions to ``ClientError(cekTransport)``.
  ## Pure: no IO, no side effects. Lifts ``classifyTransportException``
  ## into the outer railway.
  clientError(classifyTransportException(e))

func sizeLimitExceeded*(what: string, actual, limit: int): TransportError =
  ## Constructs a ``TransportError`` for a size-limit violation. Shared
  ## by body-length and Content-Length enforcement inside the default
  ## HTTP transport.
  transportError(
    tekNetwork,
    what & " exceeds limit: " & $actual & " bytes > " & $limit & " byte limit",
  )

func enforceBodySizeLimit*(
    maxResponseBytes: int, body: string
): Result[void, TransportError] =
  ## Phase 2 body size enforcement: post-read rejection via actual body
  ## length. No-op when ``maxResponseBytes == 0`` (no limit). Pure.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    return err(sizeLimitExceeded("response body", body.len, maxResponseBytes))
  ok()

type MethodErrorKind* = enum
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

func parseMethodErrorKind*(raw: string): MethodErrorKind =
  ## Total function: always succeeds. Unknown types map to metUnknown.
  return strutils.parseEnum[MethodErrorKind](raw, metUnknown)

type MethodError* = object
  ## Inner railway error for a single method invocation within a batch response.
  ##
  ## ``kind`` is module-private — always derived from ``rawType`` via
  ## ``parseMethodErrorKind``. This seals the consistency invariant.
  kind: MethodErrorKind ## module-private; derived from rawType
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## RFC "description" field
  extras*: Opt[JsonNode]
    ## non-standard fields, lossless preservation. P19 exception (A22b): forward-compatibility for unknown server fields.

func kind*(me: MethodError): MethodErrorKind =
  ## Returns the parsed error kind variant.
  return me.kind

func methodError*(
    rawType: string,
    description: Opt[string] = Opt.none(string),
    extras: Opt[JsonNode] = Opt.none(JsonNode),
): MethodError =
  ## Auto-parses rawType string to the corresponding enum variant via parseMethodErrorKind.
  return MethodError(
    kind: parseMethodErrorKind(rawType),
    rawType: rawType,
    description: description,
    extras: extras,
  )

func message*(me: MethodError): string =
  ## RFC 8620 §3.6.2 composition: ``"<rawType>: <description>"`` when a
  ## description is present and non-empty, else ``"<rawType>"`` alone.
  let desc = me.description.valueOr:
    ""
  if desc.len > 0:
    me.rawType & ": " & desc
  else:
    me.rawType

func `$`*(me: MethodError): string =
  ## Delegates to ``message`` for the single canonical projection.
  me.message

type SetErrorKind* = enum
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

func parseSetErrorKind*(raw: string): SetErrorKind =
  ## Total function: always succeeds. Unknown types map to setUnknown.
  return strutils.parseEnum[SetErrorKind](raw, setUnknown)

type SetError* = object
  ## Per-item error from a ``/set`` response. Five payload-bearing arms
  ## match the RFC-mandated data: ``setInvalidProperties`` /
  ## ``setAlreadyExists`` (RFC 8620 §5.3 / §5.4), ``setBlobNotFound`` /
  ## ``setInvalidEmail`` / ``setTooManyRecipients`` /
  ## ``setInvalidRecipients`` (RFC 8621 §4.6 / §7.5), and ``setTooLarge``
  ## augmented with ``maxSize`` (RFC 8621 §7.5 SHOULD).
  ##
  ## ``kind*`` is the public discriminator. Nim's case-object
  ## construction rule already prevents payload-bearing variants from
  ## being constructed without their payloads — strict's flow-analysis
  ## needs direct access to the discriminator field (not an accessor
  ## func), so exposing it lets external consumers ``case se.kind of
  ## setX: se.variantField`` under strictCaseObjects. The variant-
  ## specific smart constructors (``setErrorInvalidProperties`` etc.)
  ## remain the preferred construction path; generic ``setError`` is
  ## reserved for payload-less variants and defensively maps payload-
  ## bearing rawType strings without wire data to ``setUnknown``.
  rawType*: string ## always populated — lossless round-trip
  description*: Opt[string] ## optional human-readable description
  extras*: Opt[JsonNode]
    ## non-standard fields, lossless preservation. P19 exception (A22b): forward-compatibility for unknown server fields.
  case kind*: SetErrorKind
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

template seFieldsPlain(lit: untyped): SetError =
  ## Builds a payload-less SetError with a literal discriminator. Expanded
  ## inline at each ``of X: seFieldsPlain(X)`` call site in ``setError``
  ## below — the literal substitution satisfies Nim's case-object
  ## construction rule (Pattern 4: no runtime discriminator allowed).
  SetError(kind: lit, rawType: rawType, description: description, extras: extras)

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
  let kind = parseSetErrorKind(rawType)
  case kind
  of setInvalidProperties, setAlreadyExists, setBlobNotFound, setInvalidEmail,
      setTooManyRecipients, setInvalidRecipients:
    seFieldsPlain(setUnknown)
  of setTooLarge:
    SetError(
      kind: setTooLarge,
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
    kind: setInvalidProperties,
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
    kind: setAlreadyExists,
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
    kind: setBlobNotFound,
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
    kind: setInvalidEmail,
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
    kind: setTooManyRecipients,
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
    kind: setInvalidRecipients,
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
    kind: setTooLarge,
    rawType: rawType,
    description: description,
    extras: extras,
    maxSizeOctets: maxSize,
  )

func message*(se: SetError): string =
  ## RFC-aligned per-variant composition. Exhaustive over ``SetErrorKind``;
  ## adding a variant forces a compile error here.
  case se.kind
  of setInvalidProperties:
    se.rawType & ": " & se.properties.join(", ")
  of setAlreadyExists:
    se.rawType & ": " & $se.existingId
  of setBlobNotFound:
    var ids: seq[string] = @[]
    for b in se.notFound:
      ids.add($b)
    se.rawType & ": " & ids.join(", ")
  of setInvalidEmail:
    se.rawType & ": " & se.invalidEmailPropertyNames.join(", ")
  of setTooManyRecipients:
    se.rawType & ": max=" & $se.maxRecipientCount
  of setInvalidRecipients:
    se.rawType & ": " & se.invalidRecipients.join(", ")
  of setTooLarge:
    let cap = se.maxSizeOctets
    case cap.isOk
    of true:
      se.rawType & ": maxSize=" & $cap.unsafeValue & " octets"
    of false:
      let desc = se.description.valueOr:
        ""
      if desc.len > 0:
        se.rawType & ": " & desc
      else:
        se.rawType
  of setForbidden, setOverQuota, setRateLimit, setNotFound, setInvalidPatch,
      setWillDestroy, setSingleton, setMailboxHasChild, setMailboxHasEmail,
      setTooManyKeywords, setTooManyMailboxes, setNoRecipients, setForbiddenMailFrom,
      setForbiddenFrom, setForbiddenToSend, setCannotUnsend, setUnknown:
    let desc = se.description.valueOr:
      ""
    if desc.len > 0:
      se.rawType & ": " & desc
    else:
      se.rawType

func `$`*(se: SetError): string =
  ## Delegates to ``message`` for the single canonical projection.
  se.message

type GetErrorKind* = enum
  ## Discriminator for ``GetError``. Two arms cover the inner railway:
  ## server-reported method-level failures, and client-side handle misuse.
  gekMethod
  gekHandleMismatch

type GetError* = object
  ## Inner-railway error returned by ``handle.get(dr)`` and
  ## ``getBoth(handles, dr)``. Two arms (P13 named variants, no
  ## string collapsing; P18 sum types over flag bitmaps):
  ##
  ## - ``gekMethod`` — server returned an ``"error"`` invocation or the
  ##   typed parse failed at the dispatch boundary. The original
  ##   ``MethodError`` is preserved verbatim under ``methodErr``.
  ## - ``gekHandleMismatch`` — the handle's ``builderId`` did not match
  ##   the ``DispatchedResponse``'s ``builderId``. The cross-builder /
  ##   cross-client bug A6 is designed to catch.
  case kind*: GetErrorKind
  of gekMethod:
    methodErr*: MethodError
  of gekHandleMismatch:
    expected*: BuilderId ## brand carried by the DispatchedResponse
    actual*: BuilderId ## brand carried by the handle
    callId*: MethodCallId ## handle's callId, for diagnostic context

func getErrorMethod*(me: MethodError): GetError =
  ## Lifts a method-level error into the inner-railway sum.
  GetError(kind: gekMethod, methodErr: me)

func getErrorHandleMismatch*(
    expected, actual: BuilderId, callId: MethodCallId
): GetError =
  ## Constructs the handle-mismatch variant. Convention: ``expected``
  ## = the brand carried by the ``DispatchedResponse`` (truth source);
  ## ``actual`` = the brand carried by the handle being applied. The
  ## error message reads "expected X, got Y".
  GetError(kind: gekHandleMismatch, expected: expected, actual: actual, callId: callId)

func message*(ge: GetError): string =
  ## Human-readable diagnostic message. Exhaustive ``case`` over the
  ## discriminator — adding a new variant forces a compile error here.
  case ge.kind
  of gekMethod:
    ge.methodErr.message
  of gekHandleMismatch:
    "handle from a different builder (expected " & $ge.expected & "; got " & $ge.actual &
      "; callId=" & $ge.callId & ")"

func `$`*(ge: GetError): string =
  ## String representation — delegates to ``message`` for a
  ## human-readable diagnostic.
  ge.message
