# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: thread-keyword ``EmailFilterCondition``
## variants (``allInThreadHaveKeyword``, ``someInThreadHaveKeyword``,
## ``noneInThreadHaveKeyword``) emit valid wire shapes via
## ``filterCondition``, and Stalwart accepts each.  The ``upToId``
## parameter on ``Email/queryChanges`` (RFC 8620 §5.6 /
## ``mail_builders.nim:241``) round-trips correctly.
##
## Phase J Step 72.  Five sub-tests:
## 1. ``someInThreadHaveKeyword`` filter wire-emission.
## 2. ``allInThreadHaveKeyword`` filter wire-emission.
## 3. ``noneInThreadHaveKeyword`` filter wire-emission (capture).
## 4. ``upToId`` parameter on ``Email/queryChanges`` (capture).
##
## **Library-contract.**  Each sub-test asserts the wire-emission +
## response-parse pipeline; the actual id sets returned are
## incidental.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tthreadKeywordFilterAndUpToIdLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises thread-keyword EmailFilterCondition
    # variants and ``upToId`` on Email/queryChanges. Stalwart 0.15.5
    # and Cyrus 3.12.2 implement all four filter variants and
    # queryChanges fully (`imap/jmap_mail_query.c:1071-1140`); James
    # 3.9 does not advertise them. Each ``Email/query`` and
    # ``Email/queryChanges`` extract uses Cat-B Result-branching.
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # Seed two emails into the same thread; flag exactly one.
    let seedIds = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-j 72 thread alpha", "phase-j 72 thread beta"],
        rootMessageId = "phase-j-72@example.com",
      )
      .expect("seedThreadedEmails[" & $target.kind & "]")
    assertOn target, seedIds.len == 2

    # Flag the first email via Email/set update markFlagged.
    let flagUpdate = markFlagged()
    let flagSet = initEmailUpdateSet(@[flagUpdate]).expect(
        "initEmailUpdateSet[" & $target.kind & "]"
      )
    let flagUpdates = parseNonEmptyEmailUpdates(@[(seedIds[0], flagSet)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (bFlag, flagHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, update = Opt.some(flagUpdates)
    )
    let respFlag = client.send(bFlag.freeze()).expect(
        "send Email/set markFlagged[" & $target.kind & "]"
      )
    let setResp =
      respFlag.get(flagHandle).expect("Email/set extract[" & $target.kind & "]")
    setResp.updateResults.withValue(seedIds[0], outcome):
      assertOn target, outcome.isOk, "flag update must succeed"
    do:
      assertOn target, false, "Email/set must report an outcome for the flagged seed"

    # Capture baseline queryState before further state changes.
    let (bBase, baseHandle) =
      addEmailQuery(initRequestBuilder(makeBuilderId()), mailAccountId)
    let respBase = client.send(bBase.freeze()).expect(
        "send Email/query baseline[" & $target.kind & "]"
      )
    let qrBase =
      respBase.get(baseHandle).expect("baseline extract[" & $target.kind & "]")
    let baselineState = qrBase.queryState

    let flaggedKw =
      parseKeyword("$flagged").expect("parseKeyword[" & $target.kind & "]")

    # Sub-test 1: someInThreadHaveKeyword filter.
    block someCase:
      let f = filterCondition(
        EmailFilterCondition(someInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) = addEmailQuery(
        initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(f)
      )
      let resp = client.send(b.freeze()).expect(
          "send Email/query someInThreadHaveKeyword[" & $target.kind & "]"
        )
      let extract = resp.get(h)
      assertSuccessOrTypedError(
        target, extract, {metUnsupportedFilter, metUnknownMethod}
      ):
        discard success

    # Sub-test 2: allInThreadHaveKeyword filter.
    block allCase:
      let f = filterCondition(
        EmailFilterCondition(allInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) = addEmailQuery(
        initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(f)
      )
      let resp = client.send(b.freeze()).expect(
          "send Email/query allInThreadHaveKeyword[" & $target.kind & "]"
        )
      let extract = resp.get(h)
      assertSuccessOrTypedError(
        target, extract, {metUnsupportedFilter, metUnknownMethod}
      ):
        discard success

    # Sub-test 3: noneInThreadHaveKeyword filter — capture.
    block noneCase:
      let f = filterCondition(
        EmailFilterCondition(noneInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) = addEmailQuery(
        initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(f)
      )
      let resp = client.send(b.freeze()).expect(
          "send Email/query noneInThreadHaveKeyword[" & $target.kind & "]"
        )
      captureIfRequested(
        recorder.lastResponseBody, "thread-keyword-filter-" & $target.kind
      )
        .expect("captureIfRequested noneInThreadHaveKeyword")
      let extract = resp.get(h)
      assertSuccessOrTypedError(
        target, extract, {metUnsupportedFilter, metUnknownMethod}
      ):
        discard success

    # Sub-test 4: upToId parameter on Email/queryChanges. Capture.
    block upToIdCase:
      let (b, h) = addEmailQueryChanges(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        sinceQueryState = baselineState,
        upToId = Opt.some(seedIds[0]),
      )
      let resp = client.send(b.freeze()).expect(
          "send Email/queryChanges upToId[" & $target.kind & "]"
        )
      captureIfRequested(
        recorder.lastResponseBody, "email-querychanges-up-to-id-" & $target.kind
      )
        .expect("captureIfRequested upToId")
      let extract = resp.get(h)
      assertSuccessOrTypedError(
        target, extract, {metCannotCalculateChanges, metUnknownMethod}
      ):
        discard success

    # Cleanup: destroy the seed emails so re-runs are idempotent.
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, destroy = directIds(seedIds)
    )
    let respClean = client.send(bClean.freeze()).expect(
        "send Email/set cleanup[" & $target.kind & "]"
      )
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    for id in seedIds:
      cleanResp.destroyResults.withValue(id, outcome):
        assertOn target, outcome.isOk, "cleanup destroy must succeed"
      do:
        assertOn target, false, "cleanup must report an outcome for each seed id"
