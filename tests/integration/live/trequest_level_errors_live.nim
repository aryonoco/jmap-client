# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``RequestError.fromJson`` projects every wire
## URI Stalwart returns into the closed ``RequestErrorType`` enum
## AND preserves the URI losslessly in ``rawType``.
## ``parseRequestErrorType`` is total: unknown URIs project to
## ``retUnknown`` with the URI captured in ``rawType``.
## The internal classify pipeline routes request-level JMAP errors
## into the ``cekRequest`` arm of ``ClientError``, distinct from
## transport-layer errors.
##
## Phase J Step 61.  Four sequential adversarial POSTs drive Stalwart
## through four request-level rejection scenarios via the test-side
## ``postRawJmap`` helper, which composes only the public Transport
## API and the H10-permitted internal classify helper.
##
## **Library-contract vs server-compliance separation.**  This live
## test asserts the library's projection contract — closed-enum
## membership, rawType preservation, cekRequest arm — without
## hard-coding which specific URI Stalwart returns per scenario.
## Stalwart's empirical URI choices are pinned byte-for-byte by the
## four captured fixtures; the parser-only replay tests under
## ``tests/serde/captured/`` assert the captured bytes round-trip
## back to the same parsed shape.
##
## **Empirical pin (Stalwart 0.15.5).**  For non-JSON input,
## Stalwart returns ``urn:ietf:params:jmap:error:notRequest`` rather
## than the RFC 8620 §3.6.1-mandated ``notJSON``.  This is a
## Stalwart-side deviation from RFC; the library projects whichever
## URI Stalwart sends.

import std/strutils

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase trequestLevelErrorsLive:
  forEachLiveTarget(target):
    let client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")

    # Sub-test 1: non-JSON input.  Strict library-contract assertions:
    # the response must arrive on the cekRequest arm; rawType must be
    # losslessly preserved and shaped as a JMAP error URI; errorType
    # must project into the closed RequestErrorType enum.
    block notJsonCase:
      let (respBody, res) = postRawJmap(
        target, session, "this is not JSON", target.aliceToken, target.authScheme
      )
      captureIfRequested(respBody, "request-error-not-json-" & $target.kind).expect(
        "captureIfRequested notJSON"
      )
      assertOn target, res.isErr, "expected RequestError on non-JSON body"
      let ce = res.error
      assertOn target,
        ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      assertOn target,
        ce.request.rawType.len > 0, "rawType must be losslessly preserved (non-empty)"
      assertOn target,
        ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      assertOn target,
        ce.request.errorType in
          {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 2: well-formed JSON that does not match the Request
    # type signature.
    block notRequestCase:
      let (respBody, res) =
        postRawJmap(target, session, "[1,2,3]", target.aliceToken, target.authScheme)
      captureIfRequested(respBody, "request-error-not-request-" & $target.kind).expect(
        "captureIfRequested notRequest"
      )
      assertOn target, res.isErr, "expected RequestError on top-level-array body"
      let ce = res.error
      assertOn target,
        ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      assertOn target,
        ce.request.rawType.len > 0, "rawType must be losslessly preserved (non-empty)"
      assertOn target,
        ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      assertOn target,
        ce.request.errorType in
          {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 3: request envelope claiming a capability URI the
    # server does not advertise.
    block unknownCapabilityCase:
      const body = """{"using":["urn:test:phase-j:bogus"],"methodCalls":[]}"""
      let (respBody, res) =
        postRawJmap(target, session, body, target.aliceToken, target.authScheme)
      captureIfRequested(respBody, "request-error-unknown-capability-" & $target.kind)
        .expect("captureIfRequested unknownCapability")
      assertOn target, res.isErr, "expected RequestError on unknown capability URI"
      let ce = res.error
      assertOn target,
        ce.kind == cekRequest,
        "expected cekRequest, got " & $ce.kind & ": " & ce.message
      assertOn target,
        ce.request.rawType.len > 0, "rawType must be losslessly preserved (non-empty)"
      assertOn target,
        ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      assertOn target,
        ce.request.errorType in
          {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType

    # Sub-test 4: oversized request body — exceeds server's advertised
    # ``maxSizeRequest``.
    block limitCase:
      let maxSize = session.coreCapabilities().maxSizeRequest.toInt64.int
      let oversize = maxSize + 1024
      let blob = "x".repeat(oversize)
      const prefix =
        """{"using":["urn:ietf:params:jmap:core"],"methodCalls":[["Core/echo",{"blob":""""
      const suffix = """"},"c0"]]}"""
      let body = prefix & blob & suffix
      let (respBody, res) =
        postRawJmap(target, session, body, target.aliceToken, target.authScheme)
      captureIfRequested(respBody, "request-error-limit-" & $target.kind).expect(
        "captureIfRequested limit"
      )
      assertOn target, res.isErr, "expected RequestError on over-limit body"
      let ce = res.error
      assertOn target,
        ce.kind == cekRequest,
        "expected cekRequest on over-limit, got " & $ce.kind & ": " & ce.message
      assertOn target,
        ce.request.rawType.len > 0, "rawType must be losslessly preserved (non-empty)"
      assertOn target,
        ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
        "rawType must be a JMAP error URI, got " & ce.request.rawType
      assertOn target,
        ce.request.errorType in
          {retUnknownCapability, retNotJson, retNotRequest, retLimit, retUnknown},
        "errorType must project into the closed RequestErrorType enum, got " &
          $ce.request.errorType
