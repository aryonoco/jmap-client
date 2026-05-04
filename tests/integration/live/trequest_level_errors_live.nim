# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``RequestError.fromJson`` projects every wire
## URI Stalwart returns into the closed ``RequestErrorType`` enum
## AND preserves the URI losslessly in ``rawType``.
## ``parseRequestErrorType`` is total: unknown URIs project to
## ``retUnknown`` with the URI captured in ``rawType``.
## ``classifyHttpResponse`` routes request-level JMAP errors into the
## ``cekRequest`` arm of ``ClientError``, distinct from transport-layer
## errors.
##
## Phase J Step 61.  Four sequential ``sendRawHttpForTesting`` calls
## drive Stalwart through four request-level rejection scenarios.
##
## **Library-contract vs server-compliance separation.**  This live
## test asserts the library's projection contract — closed-enum
## membership, rawType preservation, cekRequest arm — without
## hard-coding which specific URI Stalwart returns per scenario.
## Stalwart's empirical URI choices are pinned byte-for-byte by the
## four captured fixtures; the parser-only replay tests under
## ``tests/serde/captured/`` assert the captured bytes round-trip
## back to the same parsed shape.  This separation matters: a
## Stalwart-side change cannot silently break a library-contract
## test, and a library regression cannot be masked by a server-side
## compensation.
##
## **Empirical pin (Stalwart 0.15.5).**  For non-JSON input,
## Stalwart returns ``urn:ietf:params:jmap:error:notRequest`` rather
## than the RFC 8620 §3.6.1-mandated ``notJSON``.  This is a
## Stalwart-side deviation from RFC; the library projects whichever
## URI Stalwart sends.  Sub-test 1 below therefore asserts the
## library's projection contract, not Stalwart's RFC compliance.
## See the captured fixture ``request-error-not-json-stalwart.json``
## for the durable record.

import std/json
import std/strutils

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig

block trequestLevelErrorsLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    discard client.fetchSession().expect("fetchSession")

    # Sub-test 1: non-JSON input.  Strict library-contract assertions:
    # the response must arrive on the cekRequest arm; rawType must be
    # losslessly preserved and shaped as a JMAP error URI; errorType
    # must project into the closed RequestErrorType enum.
    #
    # Stalwart 0.15.5 returns ``notRequest`` rather than the RFC 8620
    # §3.6.1-mandated ``notJSON`` here — that's a Stalwart deviation
    # from RFC.  The captured fixture pins Stalwart's empirical
    # choice; the replay test asserts it byte-for-byte.
    block notJsonCase:
      let res = client.sendRawHttpForTesting("this is not JSON")
      captureIfRequested(client, "request-error-not-json-stalwart").expect(
        "captureIfRequested notJSON"
      )
      doAssert res.isErr, "expected RequestError on non-JSON body"
      let ce = res.error
      doAssert ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      doAssert ce.request.rawType.len > 0,
        "rawType must be losslessly preserved (non-empty)"
      doAssert ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      doAssert ce.request.errorType in
        {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 2: well-formed JSON that does not match the Request
    # type signature.  Top-level array `[1,2,3]` is a hard structural
    # mismatch — RFC 8620 §3.3 mandates a top-level Request object
    # with ``using`` and ``methodCalls`` fields.  A bare object like
    # ``{"foo":"bar"}`` is insufficient: Stalwart 0.15.5 accepts
    # missing ``using``/``methodCalls`` as defaults and returns an
    # empty 200 success.  Top-level array forces structural rejection.
    #
    # Strict library-contract assertions: cekRequest arm; rawType
    # losslessly preserved + URI-shaped; errorType in closed enum.
    block notRequestCase:
      let res = client.sendRawHttpForTesting("[1,2,3]")
      captureIfRequested(client, "request-error-not-request-stalwart").expect(
        "captureIfRequested notRequest"
      )
      doAssert res.isErr, "expected RequestError on top-level-array body"
      let ce = res.error
      doAssert ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      doAssert ce.request.rawType.len > 0,
        "rawType must be losslessly preserved (non-empty)"
      doAssert ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      doAssert ce.request.errorType in
        {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 3: request envelope claiming a capability URI the
    # server does not advertise.  RFC 8620 §3.6.1 mandates
    # ``unknownCapability`` here.  Stalwart 0.15.5 collapses this
    # case to ``notRequest`` along with the other malformed-Request
    # scenarios — another Stalwart deviation from RFC.
    #
    # Strict library-contract assertions only — captured fixture
    # pins Stalwart's empirical URI choice byte-for-byte.
    block unknownCapabilityCase:
      const body = """{"using":["urn:test:phase-j:bogus"],"methodCalls":[]}"""
      let res = client.sendRawHttpForTesting(body)
      captureIfRequested(client, "request-error-unknown-capability-stalwart").expect(
        "captureIfRequested unknownCapability"
      )
      doAssert res.isErr, "expected RequestError on unknown capability URI"
      let ce = res.error
      doAssert ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      doAssert ce.request.rawType.len > 0,
        "rawType must be losslessly preserved (non-empty)"
      doAssert ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      doAssert ce.request.errorType in
        {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 4: oversized request body.  A Core/echo invocation
    # with a 12 MiB ASCII payload, well past Stalwart's 10 MiB
    # maxSizeRequest default.  Strict library-contract assertions
    # only — Stalwart's specific URI choice among the five enum
    # variants is captured but not asserted live; the replay test
    # pins it byte-for-byte.
    block limitCase:
      let blob = "x".repeat(12 * 1024 * 1024)
      const prefix =
        """{"using":["urn:ietf:params:jmap:core"],"methodCalls":[["Core/echo",{"blob":""""
      const suffix = """"},"c0"]]}"""
      let body = prefix & blob & suffix
      let res = client.sendRawHttpForTesting(body)
      captureIfRequested(client, "request-error-limit-stalwart").expect(
        "captureIfRequested limit"
      )
      doAssert res.isErr, "expected RequestError on over-limit body"
      let ce = res.error
      doAssert ce.kind == cekRequest,
        "expected cekRequest on over-limit, got " & $ce.kind & ": " & ce.message
      doAssert ce.request.rawType.len > 0,
        "rawType must be losslessly preserved (non-empty)"
      doAssert ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      doAssert ce.request.errorType in
        {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    client.close()
