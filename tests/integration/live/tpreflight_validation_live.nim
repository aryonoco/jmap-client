# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``client.send(req: Request)`` rejects requests
## that exceed the session-advertised core capability caps BEFORE
## issuing any HTTP request. Two distinct pre-flight code paths:
## ``validateLimits`` (``client.nim:486-494``) checks
## ``maxCallsInRequest`` / ``maxObjectsInGet`` / ``maxObjectsInSet``
## per-invocation; the post-serialisation Step-4 size check
## (``client.nim:657-665``) compares the serialised JSON length
## against ``maxSizeRequest``.  Each violation surfaces as a
## ``Result.err(ClientError)`` carrying a diagnostic that names the
## breached cap.
##
## Phase J Step 64.  Four sub-tests, one per cap. No fixtures
## captured: the assertion is purely client-side (no HTTP fires).

import std/json
import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tpreflightValidationLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let caps = session.coreCapabilities()
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # Each sub-test captures lastRawResponseBody.len immediately
    # before the failing send and asserts the length is unchanged
    # afterwards — proving no HTTP request fired (the body buffer
    # is overwritten by classifyHttpResponse on every successful or
    # failed HTTP response).  Capturing the length per sub-test
    # tolerates intervening HTTP traffic from setup helpers like
    # ``resolveInboxId``.

    # Sub-test 1: maxObjectsInGet — Mailbox/get carrying ids one over
    # the cap.  ``buildOversizedRequest`` from mlive funnels through
    # ``addGet[Mailbox]``.
    block maxObjectsInGetCase:
      let idCount = int(caps.maxObjectsInGet) + 1
      let builder = buildOversizedRequest(mailAccountId, idCount)
      let bufBefore = client.lastRawResponseBody.len
      let res = client.send(builder.freeze())
      assertOn target, res.isErr, "validateLimits must reject oversize Mailbox/get ids"
      assertOn target,
        "maxObjectsInGet" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        client.lastRawResponseBody.len == bufBefore,
        "no HTTP must fire — response body buffer length must be unchanged"

    # Sub-test 2: maxCallsInRequest — N+1 Core/echo invocations
    # assembled via repeated ``addEcho``.
    block maxCallsInRequestCase:
      var b = initRequestBuilder(makeBuilderId())
      let callCount = int(caps.maxCallsInRequest) + 1
      let echoArgs = %*{"phase-j-64": "preflight"}
      for _ in 0 ..< callCount:
        let (newB, _) = b.addEcho(echoArgs)
        b = newB
      let req = b.freeze()
      let bufBefore = client.lastRawResponseBody.len
      let res = client.send(req)
      assertOn target, res.isErr, "validateLimits must reject oversize methodCalls list"
      assertOn target,
        "maxCallsInRequest" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        client.lastRawResponseBody.len == bufBefore,
        "no HTTP must fire — response body buffer length must be unchanged"

    # Sub-test 3: maxObjectsInSet — Email/set carrying N+1 create
    # entries (combined create/update/destroy total).  Use raw JSON
    # via the typed builder's ``addEmailSet`` would require a
    # NonEmptyEmailBlueprintMap which is gated to ``<= caps`` at
    # construction; bypass via constructing the create map directly.
    block maxObjectsInSetCase:
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
          "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
        )
      let aliceAddr = buildAliceAddr()
      let textPart = makeLeafPart(
        LeafPartSpec(
          partId: buildPartId("1"),
          contentType: "text/plain",
          body: "phase-j-64 preflight maxObjectsInSet",
          name: Opt.none(string),
          disposition: Opt.none(ContentDisposition),
          cid: Opt.none(string),
        )
      )
      let createCount = int(caps.maxObjectsInSet) + 1
      var createTbl = initTable[CreationId, EmailBlueprint]()
      for i in 0 ..< createCount:
        let blueprint = parseEmailBlueprint(
            mailboxIds = mailboxIds,
            body = flatBody(textBody = Opt.some(textPart)),
            fromAddr = Opt.some(@[aliceAddr]),
            to = Opt.some(@[aliceAddr]),
            subject = Opt.some("phase-j-64 oversize " & $i),
          )
          .expect("parseEmailBlueprint[" & $target.kind & "]")
        let cid = parseCreationId("phaseJ64-" & $i).expect(
            "parseCreationId[" & $target.kind & "]"
          )
        createTbl[cid] = blueprint
      let (b, _) = addEmailSet(
        initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
      )
      let bufBefore = client.lastRawResponseBody.len
      let res = client.send(b.freeze())
      assertOn target,
        res.isErr, "validateLimits must reject oversize Email/set creates"
      assertOn target,
        "maxObjectsInSet" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        client.lastRawResponseBody.len == bufBefore,
        "no HTTP must fire — response body buffer length must be unchanged"

    # Sub-test 4: maxSizeRequest — single Email/set create whose
    # serialised JSON exceeds caps.maxSizeRequest.  This trips the
    # post-serialisation Step-4 check in send (``client.nim:657``),
    # not validateLimits — the diagnostic still names the cap.
    block maxSizeRequestCase:
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
          "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
        )
      let aliceAddr = buildAliceAddr()
      let oversizeSubject = "x".repeat(int(caps.maxSizeRequest) + 1024)
      let textPart = makeLeafPart(
        LeafPartSpec(
          partId: buildPartId("1"),
          contentType: "text/plain",
          body: "phase-j-64 oversize body filler",
          name: Opt.none(string),
          disposition: Opt.none(ContentDisposition),
          cid: Opt.none(string),
        )
      )
      let blueprint = parseEmailBlueprint(
          mailboxIds = mailboxIds,
          body = flatBody(textBody = Opt.some(textPart)),
          fromAddr = Opt.some(@[aliceAddr]),
          to = Opt.some(@[aliceAddr]),
          subject = Opt.some(oversizeSubject),
        )
        .expect("parseEmailBlueprint[" & $target.kind & "]")
      let cid =
        parseCreationId("phaseJ64size").expect("parseCreationId[" & $target.kind & "]")
      var createTbl = initTable[CreationId, EmailBlueprint]()
      createTbl[cid] = blueprint
      let (b, _) = addEmailSet(
        initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
      )
      let req = b.freeze()
      let bufBefore = client.lastRawResponseBody.len
      let res = client.send(req)
      assertOn target,
        res.isErr, "Step-4 size check must reject oversize serialised body"
      assertOn target,
        "maxSizeRequest" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        client.lastRawResponseBody.len == bufBefore,
        "no HTTP must fire — response body buffer length must be unchanged"

    client.close()
