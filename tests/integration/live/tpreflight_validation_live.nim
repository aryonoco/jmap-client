# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``client.send(req: Request)`` rejects requests
## that exceed the session-advertised core capability caps BEFORE
## issuing any HTTP request. Two distinct pre-flight code paths: the
## internal ``validateLimits`` checks ``maxCallsInRequest`` /
## ``maxObjectsInGet`` / ``maxObjectsInSet`` per-invocation; the
## post-serialisation size check compares the serialised JSON length
## against ``maxSizeRequest``. Each violation surfaces as a
## ``Result.err(ClientError)`` carrying a diagnostic that names the
## breached cap.
##
## Phase J Step 64. Four sub-tests, one per cap. The "no HTTP fired"
## assertion is now driven through a ``RecordingTransport`` wrapper:
## ``recorder.sendCount`` is observed to be unchanged across the
## failing send.

import std/json
import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/transport
import ./mconfig
import ./mlive
import ../../mtestblock
import ../../mtransport

testCase tpreflightValidationLive:
  forEachLiveTarget(target):
    let httpTransport =
      newHttpTransport().expect("newHttpTransport[" & $target.kind & "]")
    let (recordingTransport, recorder) = newRecordingTransport(httpTransport)
    let client = initJmapClient(
        transport = recordingTransport,
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let caps = session.coreCapabilities()
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # Each sub-test captures recorder.sendCount immediately before the
    # failing send and asserts the count is unchanged afterwards —
    # proving no HTTP request fired.

    # Sub-test 1: maxObjectsInGet — Mailbox/get carrying ids one over
    # the cap. ``buildOversizedRequest`` from mlive funnels through
    # ``addGet[Mailbox]``.
    block maxObjectsInGetCase:
      let idCount = caps.maxObjectsInGet.toInt64.int + 1
      let builder = buildOversizedRequest(mailAccountId, idCount)
      let countBefore = recorder.sendCount
      let res = client.send(builder.freeze())
      assertOn target, res.isErr, "validateLimits must reject oversize Mailbox/get ids"
      assertOn target,
        "maxObjectsInGet" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        recorder.sendCount == countBefore,
        "no HTTP must fire — recorder.sendCount must be unchanged"

    # Sub-test 2: maxCallsInRequest — N+1 Core/echo invocations
    # assembled via repeated ``addEcho``.
    block maxCallsInRequestCase:
      var b = initRequestBuilder(makeBuilderId())
      let callCount = caps.maxCallsInRequest.toInt64.int + 1
      let echoArgs = %*{"phase-j-64": "preflight"}
      for _ in 0 ..< callCount:
        let (newB, _) = b.addEcho(echoArgs)
        b = newB
      let req = b.freeze()
      let countBefore = recorder.sendCount
      let res = client.send(req)
      assertOn target, res.isErr, "validateLimits must reject oversize methodCalls list"
      assertOn target,
        "maxCallsInRequest" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        recorder.sendCount == countBefore,
        "no HTTP must fire — recorder.sendCount must be unchanged"

    # Sub-test 3: maxObjectsInSet — Email/set carrying N+1 create
    # entries.
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
      let createCount = caps.maxObjectsInSet.toInt64.int + 1
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
      let countBefore = recorder.sendCount
      let res = client.send(b.freeze())
      assertOn target,
        res.isErr, "validateLimits must reject oversize Email/set creates"
      assertOn target,
        "maxObjectsInSet" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        recorder.sendCount == countBefore,
        "no HTTP must fire — recorder.sendCount must be unchanged"

    # Sub-test 4: maxSizeRequest — single Email/set create whose
    # serialised JSON exceeds caps.maxSizeRequest.
    block maxSizeRequestCase:
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
          "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
        )
      let aliceAddr = buildAliceAddr()
      let oversizeSubject = "x".repeat(caps.maxSizeRequest.toInt64.int + 1024)
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
      let countBefore = recorder.sendCount
      let res = client.send(req)
      assertOn target,
        res.isErr, "Step-4 size check must reject oversize serialised body"
      assertOn target,
        "maxSizeRequest" in res.error.message,
        "diagnostic must name the breached cap, got " & res.error.message
      assertOn target,
        recorder.sendCount == countBefore,
        "no HTTP must fire — recorder.sendCount must be unchanged"
