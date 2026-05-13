# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared transport-related test helpers. Composes ONLY the public
## ``newTransport(send, close)`` API — no library backdoors. Tests are
## an application, not privileged consumers; this module proves it.

{.push raises: [].}

import std/json

import results

import jmap_client
import jmap_client/client
import jmap_client/transport

import jmap_client/internal/types/capabilities
import jmap_client/internal/types/errors
import jmap_client/internal/serialisation/serde_session

import ./mfixtures

type RecordingTransportState* = ref object
  ## Observer state captured by ``newRecordingTransport``. Counts
  ## ``sendImpl`` invocations, captures the most recent ``HttpRequest``,
  ## and snapshots the body of each successful ``HttpResponse``.
  sendCount*: int
  lastResponseBody*: string
  lastRequest*: HttpRequest

proc newRecordingTransport*(inner: Transport): (Transport, RecordingTransportState) =
  ## Wraps ``inner`` in a Transport that records every send call. The
  ## closure captures both ``inner`` and the returned state ref so the
  ## test can inspect post-hoc. ``closeImpl`` forwards to
  ## ``inner.closeImpl`` via ref-counting — when the wrapper drops, ARC
  ## drops the inner ref too.
  # nimalyzer 0.12.2's varUplevel rule operates on parse-only AST and
  # therefore sees a nil ``n.typ`` on the ``RecordingTransportState(...)``
  # ObjConstr — its ``isDeepConstExpr`` short-circuits to ``true``
  # (`compiler/trees.nim:114`) for typeless nodes and flags this let
  # as "can be const". The actual type is ``tyRef`` and
  # ``isDeepConstExpr`` would return false with full sema — this is a
  # nimalyzer false positive on ref-object construction. The pragma
  # below disables that single rule on this single declaration.
  let state {.ruleOff: "varUplevel".} = RecordingTransportState(sendCount: 0)
  let innerRef = inner
  let stateRef = state
  let sendImpl: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    stateRef.sendCount += 1
    stateRef.lastRequest = req
    let res = innerRef.send(req)
    if res.isOk:
      stateRef.lastResponseBody = res.unsafeValue.body
    res
  let closeImpl: CloseProc = proc() {.closure, raises: [].} =
    discard innerRef
  let t = newTransport(sendImpl, closeImpl).get()
  (t, state)

proc newCannedTransport*(sessionJson, responseJson: string): Transport =
  ## Returns a Transport whose ``sendImpl`` returns canned bodies:
  ## ``hmGet`` → 200 + ``sessionJson``; ``hmPost`` → 200 +
  ## ``responseJson``. ``Content-Type`` is always
  ## ``application/json`` so the classify pipeline accepts it.
  let session = sessionJson
  let response = responseJson
  let sendImpl: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    case req.httpMethod
    of hmGet:
      ok(HttpResponse(statusCode: 200, contentType: "application/json", body: session))
    of hmPost:
      ok(HttpResponse(statusCode: 200, contentType: "application/json", body: response))
  let closeImpl: CloseProc = proc() {.closure, raises: [].} =
    discard
  newTransport(sendImpl, closeImpl).get()

proc newAlwaysFailTransport*(message: string): Transport =
  ## Returns a Transport whose ``sendImpl`` always returns
  ## ``err(transportError(tekNetwork, message))``. Useful for testing
  ## error-rail propagation through the JMAP layer.
  let msg = message
  let sendImpl: SendProc = proc(
      req: HttpRequest
  ): Result[HttpResponse, TransportError] {.closure, raises: [].} =
    discard req
    err(transportError(tekNetwork, msg))
  let closeImpl: CloseProc = proc() {.closure, raises: [].} =
    discard
  newTransport(sendImpl, closeImpl).get()

proc makeDefaultSessionJson*(): string =
  ## Returns the serialised JSON of a Session built from
  ## ``makeSessionArgs()``. Used by accessor-replacement tests that
  ## don't care about the precise caps shape.
  $parseSessionFromArgs(makeSessionArgs()).toJson()

proc makeSessionJsonWithCoreCaps*(caps: CoreCapabilities): string =
  ## Returns serialised JSON of a Session whose core capability
  ## advertises ``caps``. Byte-fidelity round trip via
  ## ``parseSessionFromArgs`` then ``Session.toJson``.
  $parseSessionFromArgs(makeSessionArgsWithCoreCaps(caps)).toJson()

const DefaultPostResponseJson* = """{"methodResponses":[],"sessionState":"s1"}"""
  ## Empty methodResponses with the same sessionState as
  ## ``makeSessionArgs``'s default. Parses successfully through
  ## ``parseJmapResponse`` and produces an Ok ``DispatchedResponse``.

proc newClientWithSessionCaps*(
    caps: CoreCapabilities, responseJson: string = DefaultPostResponseJson
): JmapClient =
  ## Builds a JmapClient with a cached Session carrying ``caps``.
  ## Internally constructs a canned Transport returning the session
  ## JSON on GET and ``responseJson`` on POST, then primes the cache
  ## via ``fetchSession``.
  let transport = newCannedTransport(makeSessionJsonWithCoreCaps(caps), responseJson)
  let client = initJmapClient(
      transport = transport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "test-token",
    )
    .get()
  discard client.fetchSession().get()
  client
