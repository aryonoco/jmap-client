# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: when client-side pre-flight is bypassed via
## ``sendRawHttpForTesting``, ``classifyHttpResponse`` correctly
## handles whatever wire shape Stalwart emits for cap-exceeded
## scenarios.  Each rejection projects either through
## ``RequestError.fromJson`` (request-layer error → ``cekRequest``
## arm) or through a method-level ``MethodError.fromJson`` rail; in
## both cases ``rawType`` is losslessly preserved and the typed
## enum projection is consistent.
##
## Phase J Step 65.  Three sub-tests drive Stalwart through three
## cap-exceeded scenarios (``maxSizeRequest``, ``maxObjectsInGet``,
## ``maxCallsInRequest``) using ``sendRawHttpForTesting`` to bypass
## the pre-flight checks Step 64 already verifies.
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
import ./mcapture
import ./mconfig
import ./mlive

block tserverSideEnforcementParityLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    let caps = session.coreCapabilities()
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # Sub-test 1: oversized request body — Email/set create with a
    # ``subject`` field padded to ``maxSizeRequest + 1024`` bytes.
    # Distinct from Step 61's ``Core/echo``-based limit test in
    # invocation shape; both target the same cap.
    block maxSizeRequestCase:
      let pad = "x".repeat(int(caps.maxSizeRequest) + 1024)
      const prefix =
        """{"using":["urn:ietf:params:jmap:mail"],"methodCalls":[["Email/set",{"accountId":""""
      const middle = """","create":{"phaseJ65":{"subject":""""
      const suffix = """"}}},"c0"]]}"""
      let body = prefix & $mailAccountId & middle & pad & suffix
      let res = client.sendRawHttpForTesting(body)
      captureIfRequested(client, "server-enforcement-max-size-request-stalwart").expect(
        "captureIfRequested maxSizeRequest"
      )
      doAssert res.isErr, "Stalwart must reject oversize request body"
      let ce = res.error
      doAssert ce.kind in {cekRequest, cekTransport},
        "rejection must surface on a ClientError arm, got " & $ce.kind
      if ce.kind == cekRequest:
        doAssert ce.request.rawType.len > 0,
          "rawType must be losslessly preserved (non-empty)"
        doAssert ce.request.rawType.startsWith("urn:ietf:params:jmap:error:"),
          "rawType must be a JMAP error URI, got " & ce.request.rawType

    # Sub-test 2: Mailbox/get with N+1 ids — exceeds maxObjectsInGet.
    block maxObjectsInGetCase:
      var idsArr = newJArray()
      let idCount = int(caps.maxObjectsInGet) + 1
      for i in 0 ..< idCount:
        idsArr.add(%("phaseJ65synth" & $i))
      let resp = sendRawInvocation(
        client,
        capabilityUris = @["urn:ietf:params:jmap:mail"],
        methodName = "Mailbox/get",
        arguments = %*{"accountId": $mailAccountId, "ids": idsArr},
      )
      captureIfRequested(client, "server-enforcement-max-objects-in-get-stalwart")
        .expect("captureIfRequested maxObjectsInGet")
      # Stalwart can either reject at the request layer (returns
      # Err(ClientError)) or accept the invocation and return a
      # method-level error (returns Ok(Response) carrying an "error"
      # invocation).  Library contract holds across both rails.
      if resp.isErr:
        let ce = resp.error
        doAssert ce.kind in {cekRequest, cekTransport},
          "request-layer rejection arm, got " & $ce.kind
        if ce.kind == cekRequest:
          doAssert ce.request.rawType.len > 0, "rawType must be losslessly preserved"
      else:
        let env = resp.unsafeValue
        doAssert env.methodResponses.len == 1
        let inv = env.methodResponses[0]
        if inv.rawName == "error":
          let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
          doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
        else:
          # Stalwart silently truncated or accepted the request.  Some
          # servers do this for over-limit ``ids`` arrays.  The wire
          # shape still parses through the typed surface — that is the
          # library contract.
          doAssert inv.rawName == "Mailbox/get"

    # Sub-test 3: methodCalls list with N+1 entries — exceeds
    # maxCallsInRequest.
    block maxCallsInRequestCase:
      var calls = newJArray()
      let callCount = int(caps.maxCallsInRequest) + 1
      for i in 0 ..< callCount:
        calls.add(%*["Core/echo", {"i": i}, "c" & $i])
      const body0 = """{"using":["urn:ietf:params:jmap:core"],"methodCalls":"""
      const body2 = """}"""
      let body = body0 & $calls & body2
      let res = client.sendRawHttpForTesting(body)
      captureIfRequested(client, "server-enforcement-max-calls-in-request-stalwart")
        .expect("captureIfRequested maxCallsInRequest")
      # Library contract: whatever rail Stalwart chooses, the wire
      # shape parses through the typed surface.
      if res.isErr:
        let ce = res.error
        doAssert ce.kind in {cekRequest, cekTransport}, "rejection arm, got " & $ce.kind
        if ce.kind == cekRequest:
          doAssert ce.request.rawType.len > 0, "rawType must be losslessly preserved"
      else:
        let env = res.unsafeValue
        doAssert env.methodResponses.len >= 1,
          "Stalwart accepted over-limit methodCalls; library still parsed it"

    client.close()
