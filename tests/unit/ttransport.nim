# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for the public Transport surface: ``newTransport`` strict
## nil-checks, ``newHttpTransport`` configuration validation, and ARC
## ``=destroy`` invocation of ``closeImpl`` on ref-count drop.

import results

import jmap_client
import jmap_client/internal/types/errors
import jmap_client/internal/types/validation # in-scope ``ruleOff`` pragma

import ../massertions
import ../mtestblock

# --- newTransport ---

testCase newTransportNilSendImpl:
  ## sendImpl must not be nil.
  let validClose: CloseProc = proc() {.closure, raises: [].} =
    discard
  let res = newTransport(nil, validClose)
  doAssert res.isErr, "expected Err for nil sendImpl"
  doAssert res.error.typeName == "Transport"
  doAssert res.error.message == "sendImpl must not be nil"

testCase newTransportNilCloseImpl:
  ## closeImpl must not be nil.
  let validSend: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    discard req
    err(transportError(tekNetwork, "noop"))
  let res = newTransport(validSend, nil)
  doAssert res.isErr, "expected Err for nil closeImpl"
  doAssert res.error.typeName == "Transport"
  doAssert res.error.message == "closeImpl must not be nil"

testCase newTransportValid:
  ## Both closures supplied — construction succeeds.
  let validSend: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    discard req
    err(transportError(tekNetwork, "noop"))
  let validClose: CloseProc = proc() {.closure, raises: [].} =
    discard
  assertOk newTransport(validSend, validClose)

# --- newHttpTransport ---

testCase newHttpTransportDefaults:
  ## Default arguments — succeeds.
  assertOk newHttpTransport()

testCase newHttpTransportTimeoutNoLimit:
  ## timeout = -1 (no timeout) is valid.
  assertOk newHttpTransport(timeout = -1)

testCase newHttpTransportTimeoutInvalid:
  ## timeout = -2 rejected.
  assertErrFields newHttpTransport(timeout = -2),
    "HttpTransport", "timeout must be >= -1", "-2"

testCase newHttpTransportTimeoutZero:
  ## timeout = 0 ("return immediately") is valid.
  assertOk newHttpTransport(timeout = 0)

testCase newHttpTransportMaxRedirectsZero:
  ## maxRedirects = 0 (no redirects) is valid.
  assertOk newHttpTransport(maxRedirects = 0)

testCase newHttpTransportMaxRedirectsNegative:
  ## Negative maxRedirects rejected (prevents RangeDefect on Natural field).
  assertErrFields newHttpTransport(maxRedirects = -1),
    "HttpTransport", "maxRedirects must be >= 0", "-1"

testCase newHttpTransportMaxResponseBytesZero:
  ## maxResponseBytes = 0 (no limit) is valid.
  assertOk newHttpTransport(maxResponseBytes = 0)

testCase newHttpTransportMaxResponseBytesNegative:
  ## Negative maxResponseBytes rejected.
  assertErrFields newHttpTransport(maxResponseBytes = -1),
    "HttpTransport", "maxResponseBytes must be >= 0", "-1"

testCase newHttpTransportAllEdgeLimits:
  ## All optional limits at their edge values.
  assertOk newHttpTransport(timeout = 0, maxRedirects = 0, maxResponseBytes = 0)

# --- ARC =destroy ---

# Sealed Pattern-A handle for the destructor-fires-once test —
# private fields are deliberate (the test mutates via field
# assignment; outside callers have no business reaching in).
# Inline ``{.ruleOff: "objects".}`` form (push/pop at block scope
# is rejected by the Nim compiler as "invalid pragma"; the inline
# attribute on the type is the supported shape).
type CloseCounter {.ruleOff: "objects".} = ref object
  count: int

testCase destroyInvokesCloseImpl:
  ## When the last reference to a Transport drops, ARC invokes
  ## closeImpl exactly once.
  # See mtransport.nim's identical note: nimalyzer's varUplevel
  # misfires on ref-object construction expressions because parse-
  # only AST has nil ``n.typ``. Single-declaration suppression.
  let counter {.ruleOff: "varUplevel".} = CloseCounter(count: 0)
  block:
    let counterRef = counter
    let sendImpl: SendProc = proc(
        req: HttpRequest
    ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
      discard req
      err(transportError(tekNetwork, "noop"))
    let closeImpl: CloseProc = proc() {.closure, raises: [].} =
      counterRef.count += 1
    let t {.used.} = newTransport(sendImpl, closeImpl).get()
    discard t
  doAssert counter.count == 1,
    "closeImpl should fire once on ref drop, got " & $counter.count

testCase destroyIdempotentAcrossCopies:
  ## Copying the ref to a second binding still drops closeImpl exactly
  ## once when both bindings go out of scope.
  # Same nimalyzer parse-only-vs-typed varUplevel mismatch as above:
  # ref-object constructors are not deep-const, but nimalyzer's
  # type-less AST misses that.
  let counter {.ruleOff: "varUplevel".} = CloseCounter(count: 0)
  block:
    let counterRef = counter
    let sendImpl: SendProc = proc(
        req: HttpRequest
    ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
      discard req
      err(transportError(tekNetwork, "noop"))
    let closeImpl: CloseProc = proc() {.closure, raises: [].} =
      counterRef.count += 1
    let t1 = newTransport(sendImpl, closeImpl).get()
    let t2 {.used.} = t1
    discard t1
    discard t2
  doAssert counter.count == 1,
    "closeImpl should fire exactly once across two refs, got " & $counter.count
