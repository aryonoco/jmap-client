# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## The single consumer-facing error rail (P13). ``JmapError`` is a flat
## six-arm sum covering every way a JMAP *call* can fail at the call level:
## invalid client input, transport failure, whole-request rejection, an
## absent session capability, consumer misuse, or a malformed server
## response. The whole ``freeze -> send -> get`` pipeline returns this one
## type, so it composes under a single ``?``.
##
## The arms fold the five former call-path rails: ``jeValidation`` (was
## ``ValidationError`` / ``seq[ValidationError]`` / ``EmailBlueprintErrors``),
## ``jeTransport`` / ``jeRequest`` (was ``ClientError``), and ``jeMisuse`` /
## ``jeProtocol`` (was ``GetError`` plus the dispatch-side synthetic faults).
## ``jeSession`` is new — it gives the capability/primary-account preflight a
## named home so the eventual ``connect`` threads on one ``?``.
##
## A method-level error (RFC 8620 §3.6.2) and a per-item ``/set`` error
## (§5.3) are **response data**, not rail errors: they ride the ok branch via
## ``MethodOutcome[T]`` and ``SetResponse`` respectively, so a method erroring
## never discards its successful siblings. Mirrors SQLite's row-status code vs
## column data, and libcurl's perform code vs per-transfer ``CURLMsg``.
##
## L1 smart constructors stay on their pure ``ValidationError`` rail; the leaf
## rails fold into ``JmapError`` once, at the boundary, via ``toJmapError`` and
## the ``lift`` helper (``?`` cannot auto-convert and ``converter``s are
## forbidden). This is the libcurl ``CURLMcode`` / ``CURLUcode`` shape — a few
## honest sub-system leaf rails lifting into the one rail consumers thread —
## not OpenSSL-style fragmentation.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils

import results

import ../types/validation
import ../types/primitives
import ../types/identifiers
import ../types/capabilities
import ../types/errors
import ../serialisation/serde
import ../serialisation/serde_diagnostics

# =============================================================================
# Sub-faults — each arm carries one typed payload (its own discriminator, so
# strictCaseObjects Rule 4 never bites at the JmapError level)
# =============================================================================

type SessionFaultKind* = enum
  ## Why a capability/account preflight failed against the live session.
  sfCapabilityAbsent ## the session does not advertise the required capability
  sfPrimaryAccountAbsent ## no primary account exists for the required capability

type SessionFault* = object
  ## ``jeSession`` payload. ``capability`` is the URN the consumer required;
  ## ``CapabilityKind`` is used rather than a raw string so the failure is a
  ## named value an FFI layer can project to one code.
  kind*: SessionFaultKind
  capability*: CapabilityKind

func sessionFault*(kind: SessionFaultKind, capability: CapabilityKind): SessionFault =
  ## Constructs a ``SessionFault``.
  SessionFault(kind: kind, capability: capability)

func message*(sf: SessionFault): string =
  ## Human-readable diagnostic. Renders the registered URI when known, else
  ## the enum's symbolic name (``ckUnknown``).
  let uri = sf.capability.capabilityUri.valueOr:
    $sf.capability
  case sf.kind
  of sfCapabilityAbsent:
    "session does not advertise the " & uri & " capability"
  of sfPrimaryAccountAbsent:
    "no primary account for the " & uri & " capability"

func `$`*(sf: SessionFault): string =
  ## Delegates to ``message`` for the single canonical projection.
  sf.message

type Misuse* = object
  ## ``jeMisuse`` payload — a programming bug (A6): a handle issued by one
  ## builder was applied to another builder's ``DispatchedResponse``.
  ## Category-distinct from a server fault, exactly as SQLite separates
  ## ``SQLITE_MISUSE`` from ``SQLITE_IOERR``. ``expected`` is the brand carried
  ## by the ``DispatchedResponse`` (the truth source); ``actual`` is the
  ## misapplied handle's brand.
  expected*: BuilderId
  actual*: BuilderId
  callId*: MethodCallId

func misuse*(expected, actual: BuilderId, callId: MethodCallId): Misuse =
  ## Constructs a ``Misuse``.
  Misuse(expected: expected, actual: actual, callId: callId)

func message*(m: Misuse): string =
  ## Human-readable diagnostic — reads "expected X, got Y".
  "handle from a different builder (expected " & $m.expected & "; got " & $m.actual &
    "; callId=" & $m.callId & ")"

func `$`*(m: Misuse): string =
  ## Delegates to ``message`` for the single canonical projection.
  m.message

type ProtocolFaultKind* = enum
  ## How the server's response failed to conform to what the request expected.
  pfMissingCall ## no invocation in methodResponses for the expected call ID
  pfMalformedError ## an "error" invocation whose arguments do not parse as MethodError
  pfDecode ## a normal invocation whose arguments failed typed decoding

type ProtocolFault* = object
  ## ``jeProtocol`` payload. ``callId`` is always populated. ``pfDecode``
  ## preserves the structured ``SerdeViolation`` (RFC 6901 JsonPath + the
  ## typed failure mode), so the diagnostic locates the violation inside the
  ## wire tree rather than flattening to a string.
  callId*: MethodCallId
  case kind*: ProtocolFaultKind
  of pfDecode:
    violation*: SerdeViolation
  of pfMissingCall, pfMalformedError:
    discard

func protocolMissingCall*(callId: MethodCallId): ProtocolFault =
  ## No invocation matched the expected call ID.
  ProtocolFault(kind: pfMissingCall, callId: callId)

func protocolMalformedError*(callId: MethodCallId): ProtocolFault =
  ## An "error" invocation was present but its arguments did not parse as a
  ## ``MethodError`` — a server/protocol fault, distinct from a real
  ## method-level error (which is data on the ok branch).
  ProtocolFault(kind: pfMalformedError, callId: callId)

func protocolDecode*(callId: MethodCallId, violation: SerdeViolation): ProtocolFault =
  ## A normal invocation's arguments failed typed decoding; the
  ## ``SerdeViolation`` carries the structured location and reason.
  ProtocolFault(kind: pfDecode, callId: callId, violation: violation)

func message*(p: ProtocolFault): string =
  ## Human-readable diagnostic. The decode arm reuses the canonical
  ## ``SerdeViolation`` -> ``ValidationError`` translator (with a "response"
  ## root) so the JsonPath and reason surface without duplicating the renderer.
  case p.kind
  of pfMissingCall:
    "no response for call ID " & $p.callId
  of pfMalformedError:
    "malformed error response for call ID " & $p.callId
  of pfDecode:
    "malformed response for call ID " & $p.callId & ": " &
      toValidationError(p.violation, "response").message

func `$`*(p: ProtocolFault): string =
  ## Delegates to ``message`` for the single canonical projection.
  p.message

# =============================================================================
# JmapError — the one consumer rail
# =============================================================================

type JmapErrorKind* = enum
  ## Discriminator for ``JmapError`` — the six ways a JMAP call fails at the
  ## call level. Additive: a new arm forces a compile error at every
  ## exhaustive ``case`` (here and in any FFI projection), never a silent gap.
  jeValidation ## client-supplied input was invalid (construction)
  jeTransport ## network / TLS / timeout / HTTP status, before any JMAP processing
  jeRequest ## the whole request was rejected (RFC 7807 problem details)
  jeSession ## an expected capability or primary account is absent
  jeMisuse ## a programming bug — a handle from a different builder was applied
  jeProtocol ## the server's response was malformed or did not conform

type JmapError* = object
  ## The single error rail for the public pipeline. Flat top-level arms (not a
  ## nested ``ClientError``) so the sum maps isomorphically to one gapped C
  ## enum and ``case err.kind`` is one level deep. ``MethodError`` / ``SetError``
  ## are deliberately absent — they are response data, not rail errors.
  case kind*: JmapErrorKind
  of jeValidation:
    validation*: NonEmptySeq[ValidationError]
  of jeTransport:
    transport*: TransportError
  of jeRequest:
    request*: RequestError
  of jeSession:
    session*: SessionFault
  of jeMisuse:
    misuse*: Misuse
  of jeProtocol:
    protocol*: ProtocolFault

func jmapValidation*(violation: ValidationError): JmapError =
  ## Lifts a single construction failure onto the rail. ``@[violation]`` has
  ## length 1, so ``parseNonEmptySeq`` cannot ``Err`` here.
  JmapError(kind: jeValidation, validation: parseNonEmptySeq(@[violation]).get())

func jmapValidation*(violations: NonEmptySeq[ValidationError]): JmapError =
  ## Lifts an accumulated, non-empty set of construction failures onto the
  ## rail (the "report all violations" path from the accumulating validators).
  JmapError(kind: jeValidation, validation: violations)

func jmapTransport*(transport: TransportError): JmapError =
  ## Lifts a transport failure onto the rail.
  JmapError(kind: jeTransport, transport: transport)

func jmapRequest*(request: RequestError): JmapError =
  ## Lifts a whole-request rejection (RFC 7807) onto the rail.
  JmapError(kind: jeRequest, request: request)

func jmapSession*(session: SessionFault): JmapError =
  ## Lifts a capability/account preflight failure onto the rail.
  JmapError(kind: jeSession, session: session)

func jmapMisuse*(expected, actual: BuilderId, callId: MethodCallId): JmapError =
  ## Constructs the misuse arm directly from the brand-check operands.
  JmapError(kind: jeMisuse, misuse: misuse(expected, actual, callId))

func jmapProtocol*(protocol: ProtocolFault): JmapError =
  ## Lifts a malformed-response fault onto the rail.
  JmapError(kind: jeProtocol, protocol: protocol)

func message*(err: JmapError): string =
  ## Canonical human-readable diagnostic. Exhaustive over ``JmapErrorKind`` —
  ## adding an arm forces a compile error here. The validation arm joins every
  ## accumulated violation so the "report all" detail is not lost.
  case err.kind
  of jeValidation:
    var parts: seq[string] = @[]
    for ve in asSeq(err.validation):
      parts.add(ve.message)
    parts.join("; ")
  of jeTransport:
    err.transport.message
  of jeRequest:
    err.request.message
  of jeSession:
    err.session.message
  of jeMisuse:
    err.misuse.message
  of jeProtocol:
    err.protocol.message

func `$`*(err: JmapError): string =
  ## Delegates to ``message`` for the single canonical projection.
  err.message

type JmapResult*[T] = Result[T, JmapError]
  ## The canonical result alias for the public pipeline. Relocated from the L1
  ## ``types`` hub: ``JmapError`` references the L2 ``SerdeViolation`` (the
  ## ``pfDecode`` arm), so it — and this alias — live at L3.

# =============================================================================
# Boundary lifts — fold the leaf rails into JmapError exactly once
# =============================================================================

func toJmapError*(violation: ValidationError): JmapError =
  ## Leaf lift: a single ``ValidationError`` from an L1 smart constructor.
  jmapValidation(violation)

func toJmapError*(violations: NonEmptySeq[ValidationError]): JmapError =
  ## Leaf lift: an accumulated ``NonEmptySeq[ValidationError]``.
  jmapValidation(violations)

func toJmapError*(transport: TransportError): JmapError =
  ## Leaf lift: the pluggable-transport plug-in contract's error type.
  jmapTransport(transport)

func toJmapError*(request: RequestError): JmapError =
  ## Leaf lift: an RFC 7807 request rejection.
  jmapRequest(request)

func toJmapError*(session: SessionFault): JmapError =
  ## Leaf lift: a session preflight failure.
  jmapSession(session)

func lift*[T, E](r: Result[T, E]): Result[T, JmapError] {.inline.} =
  ## Sanctioned boundary lift: ``mapErr(toJmapError)`` under one greppable
  ## token. ``?`` cannot auto-convert ``E`` to ``JmapError`` and ``converter``s
  ## are forbidden, so a construction call composes into a JmapError-returning
  ## function as ``?parseAccountId(s).lift``. There is deliberately no
  ## ``SerdeViolation`` overload: a decode failure needs the call ID for its
  ## ``pfDecode`` arm, which only ``dispatch.get`` holds, so that conversion is
  ## built there, not lifted context-free here.
  mixin toJmapError
  r.mapErr(toJmapError)

# =============================================================================
# MethodOutcome[T] — a single method's per-call result as DATA (RFC 8620
# §3.6.2). Rides the ok branch of get's Result so a batch's successful
# siblings survive when one method errors.
# =============================================================================

type MethodOutcomeKind* = enum
  mokValue ## the method returned its typed result
  mokMethodError ## the server ran the method and reported a domain-level error

type MethodOutcome*[T] = object
  ## The outcome of extracting one method's response: either the typed value,
  ## or the server's ``MethodError`` carried as data (never on the rail).
  case kind*: MethodOutcomeKind
  of mokValue:
    value*: T
  of mokMethodError:
    error*: MethodError

func methodValue*[T](value: T): MethodOutcome[T] =
  ## The method succeeded and produced ``value``.
  MethodOutcome[T](kind: mokValue, value: value)

func methodFailure*[T](error: MethodError): MethodOutcome[T] =
  ## The server reported a method-level error; preserved verbatim as data.
  MethodOutcome[T](kind: mokMethodError, error: error)
