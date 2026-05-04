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

block tthreadKeywordFilterAndUpToIdLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")

    # Seed two emails into the same thread; flag exactly one.
    let seedIds = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-j 72 thread alpha", "phase-j 72 thread beta"],
        rootMessageId = "phase-j-72@example.com",
      )
      .expect("seedThreadedEmails")
    doAssert seedIds.len == 2

    # Flag the first email via Email/set update markFlagged.
    let flagUpdate = markFlagged()
    let flagSet = initEmailUpdateSet(@[flagUpdate]).expect("initEmailUpdateSet")
    let flagUpdates = parseNonEmptyEmailUpdates(@[(seedIds[0], flagSet)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (bFlag, flagHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, update = Opt.some(flagUpdates))
    let respFlag = client.send(bFlag).expect("send Email/set markFlagged")
    let setResp = respFlag.get(flagHandle).expect("Email/set extract")
    setResp.updateResults.withValue(seedIds[0], outcome):
      doAssert outcome.isOk, "flag update must succeed"
    do:
      doAssert false, "Email/set must report an outcome for the flagged seed"

    # Capture baseline queryState before further state changes.
    let (bBase, baseHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
    let respBase = client.send(bBase).expect("send Email/query baseline")
    let qrBase = respBase.get(baseHandle).expect("baseline extract")
    let baselineState = qrBase.queryState

    let flaggedKw = parseKeyword("$flagged").expect("parseKeyword")

    # Sub-test 1: someInThreadHaveKeyword filter.
    block someCase:
      let f = filterCondition(
        EmailFilterCondition(someInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) =
        addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(f))
      let resp = client.send(b).expect("send Email/query someInThreadHaveKeyword")
      discard resp.get(h).expect("someInThreadHaveKeyword extract")

    # Sub-test 2: allInThreadHaveKeyword filter.
    block allCase:
      let f = filterCondition(
        EmailFilterCondition(allInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) =
        addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(f))
      let resp = client.send(b).expect("send Email/query allInThreadHaveKeyword")
      discard resp.get(h).expect("allInThreadHaveKeyword extract")

    # Sub-test 3: noneInThreadHaveKeyword filter — capture.
    block noneCase:
      let f = filterCondition(
        EmailFilterCondition(noneInThreadHaveKeyword: Opt.some(flaggedKw))
      )
      let (b, h) =
        addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(f))
      let resp = client.send(b).expect("send Email/query noneInThreadHaveKeyword")
      captureIfRequested(client, "thread-keyword-filter-stalwart").expect(
        "captureIfRequested noneInThreadHaveKeyword"
      )
      discard resp.get(h).expect("noneInThreadHaveKeyword extract")

    # Sub-test 4: upToId parameter on Email/queryChanges.  Capture.
    block upToIdCase:
      let (b, h) = addEmailQueryChanges(
        initRequestBuilder(),
        mailAccountId,
        sinceQueryState = baselineState,
        upToId = Opt.some(seedIds[0]),
      )
      let resp = client.send(b).expect("send Email/queryChanges upToId")
      captureIfRequested(client, "email-querychanges-up-to-id-stalwart").expect(
        "captureIfRequested upToId"
      )
      discard resp.get(h).expect("upToId extract")

    # Cleanup: destroy the seed emails so re-runs are idempotent.
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(seedIds))
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    for id in seedIds:
      cleanResp.destroyResults.withValue(id, outcome):
        doAssert outcome.isOk, "cleanup destroy must succeed"
      do:
        doAssert false, "cleanup must report an outcome for each seed id"

    client.close()
