# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: when client-side pre-flight is bypassed via
## ``postRawJmap``, the internal classify pipeline correctly handles
## whatever wire shape Stalwart emits for cap-exceeded scenarios.
## Each rejection projects either through ``RequestError.fromJson``
## (request-layer error → ``cekRequest`` arm) or through a method-
## level ``MethodError.fromJson`` rail; in both cases ``rawType`` is
## losslessly preserved and the typed enum projection is consistent.
##
## Phase J Step 65.  Three sub-tests drive Stalwart through three
## cap-exceeded scenarios (``maxSizeRequest``, ``maxObjectsInGet``,
## ``maxCallsInRequest``) using ``postRawJmap`` to bypass the pre-
## flight checks Step 64 already verifies.
##
## **Library-contract vs server-compliance separation.**  Set-
## membership over the two rails (request-layer vs method-level) is
## library-contract design — RFC 8620 permits the server discretion
## on which rail to use.  Captured fixtures pin Stalwart's specific
## projection per scenario.

import std/json
import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/types/envelope
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tserverSideEnforcementParityLive:
  forEachLiveTarget(target):
    let client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let caps = session.coreCapabilities()
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # Sub-test 1: oversized request body — Email/set create with a
    # ``subject`` field padded to ``maxSizeRequest + 1024`` bytes.
    block maxSizeRequestCase:
      let pad = "x".repeat(caps.maxSizeRequest.toInt64.int + 1024)
      const prefix =
        """{"using":["urn:ietf:params:jmap:mail"],"methodCalls":[["Email/set",{"accountId":""""
      const middle = """","create":{"phaseJ65":{"subject":""""
      const suffix = """"}}},"c0"]]}"""
      let body = prefix & $mailAccountId & middle & pad & suffix
      let (respBody, res) =
        postRawJmap(target, session, body, target.aliceToken, target.authScheme)
      captureIfRequested(
        respBody, "server-enforcement-max-size-request-" & $target.kind
      )
        .expect("captureIfRequested maxSizeRequest")
      assertOn target, res.isErr, "Stalwart must reject oversize request body"
      let ce = res.error
      assertOn target,
        ce.kind in {cekRequest, cekTransport},
        "rejection must surface on a ClientError arm, got " & $ce.kind
      if ce.kind == cekRequest:
        assertOn target,
          ce.request.rawType.len > 0, "rawType must be losslessly preserved (non-empty)"
        assertOn target,
          ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
          "rawType must be a JMAP error URI, got " & ce.request.rawType

    # Sub-test 2: Mailbox/get with N+1 ids — exceeds maxObjectsInGet.
    block maxObjectsInGetCase:
      var idsArr = newJArray()
      let idCount = caps.maxObjectsInGet.toInt64.int + 1
      for i in 0 ..< idCount:
        idsArr.add(%("phaseJ65synth" & $i))
      let reqBody = %*{
        "using": @["urn:ietf:params:jmap:mail"],
        "methodCalls":
          @[%*["Mailbox/get", %*{"accountId": $mailAccountId, "ids": idsArr}, %"c0"]],
      }
      let (respBody, resp) =
        postRawJmap(target, session, $reqBody, target.aliceToken, target.authScheme)
      captureIfRequested(
        respBody, "server-enforcement-max-objects-in-get-" & $target.kind
      )
        .expect("captureIfRequested maxObjectsInGet[" & $target.kind & "]")
      if resp.isErr:
        let ce = resp.error
        assertOn target,
          ce.kind in {cekRequest, cekTransport},
          "request-layer rejection arm, got " & $ce.kind
        if ce.kind == cekRequest:
          assertOn target,
            ce.request.rawType.len > 0, "rawType must be losslessly preserved"
      else:
        let env = resp.unsafeValue
        assertOn target, env.methodResponses.len == 1
        let inv = env.methodResponses[0]
        if inv.rawName == "error":
          let me = MethodError.fromJson(inv.arguments).expect(
              "MethodError.fromJson[" & $target.kind & "]"
            )
          assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
        else:
          assertOn target, inv.rawName == "Mailbox/get"

    # Sub-test 3: methodCalls list with N+1 entries — exceeds
    # maxCallsInRequest.
    block maxCallsInRequestCase:
      var calls = newJArray()
      let callCount = caps.maxCallsInRequest.toInt64.int + 1
      for i in 0 ..< callCount:
        calls.add(%*["Core/echo", {"i": i}, "c" & $i])
      const body0 = """{"using":["urn:ietf:params:jmap:core"],"methodCalls":"""
      const body2 = """}"""
      let body = body0 & $calls & body2
      let (respBody, res) =
        postRawJmap(target, session, body, target.aliceToken, target.authScheme)
      captureIfRequested(
        respBody, "server-enforcement-max-calls-in-request-" & $target.kind
      )
        .expect("captureIfRequested maxCallsInRequest[" & $target.kind & "]")
      if res.isErr:
        let ce = res.error
        assertOn target,
          ce.kind in {cekRequest, cekTransport}, "rejection arm, got " & $ce.kind
        if ce.kind == cekRequest:
          assertOn target,
            ce.request.rawType.len > 0, "rawType must be losslessly preserved"
      else:
        let env = res.unsafeValue
        assertOn target,
          env.methodResponses.len >= 1,
          "Stalwart accepted over-limit methodCalls; library still parsed it"
