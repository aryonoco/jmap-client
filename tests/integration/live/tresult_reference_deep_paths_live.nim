# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``ResultReference.toJson`` emits JSON-Pointer
## paths Stalwart accepts at depth ≥ 3 through the typed ``RefPath``
## enum (``methods_enum.nim:69-80``).  ``addGet[T]`` routes
## ``rkReference`` variants to the ``#ids`` wire key.  The parser
## tolerates a broken back-reference's error projection on the same
## envelope as a successful chain — error and success invocations
## coexist in ``methodResponses`` without one contaminating the
## other.
##
## Phase J Step 67.  Three sub-tests:
## 1. Two-leg back-reference chain (``Email/query`` → ``Email/get``)
##    using the ``rpIds`` typed enum path.  Regression-only: this is
##    the canonical chain.
## 2. Three-leg deep chain (``Email/query`` → ``Email/get`` →
##    ``Thread/get``) using the ``rpListThreadId`` typed enum path
##    with depth-3 JSON Pointer ``/list/*/threadId``.  Captures the
##    wire shape.
## 3. Adversarial broken back-reference using ``sendRawInvocation``
##    with a hand-rolled JSON-Pointer path that does not resolve.

import std/json
import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/types/envelope
import ./mcapture
import ./mconfig
import ./mlive

block tresultReferenceDeepPathsLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    let seedIds = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @["phasej67refdeep alpha", "phasej67refdeep beta", "phasej67refdeep gamma"],
      )
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target, seedIds.len == 3

    # Wait for every seed to surface in the index so the chained
    # Email/query → Email/get back-reference resolves on every
    # server. Cyrus 3.12.2's Xapian rolling indexer settles
    # asynchronously; ``pollEmailQueryIndexed`` opens a fresh client
    # per iteration to bypass Cyrus's per-session index cache.
    let preFilter =
      filterCondition(EmailFilterCondition(subject: Opt.some("phasej67refdeep")))
    discard pollEmailQueryIndexed(target, mailAccountId, preFilter, seedIds.toHashSet)
      .expect("pollEmailQueryIndexed[" & $target.kind & "]")
    reconnectClient(target, client)

    # Sub-test 1: simple two-leg chain — Email/query → Email/get.
    # Regression-only.
    block simpleRefCase:
      # Filter the back-referenced Email/query to the seeded discriminator
      # so the downstream Email/get's #ids result reference does not pull
      # an unbounded slice of inbox-wide ids. James 3.9 caps Email/get at
      # 5 items when fetching full properties (no per-property override
      # in the memory image) and rejects with ``requestTooLarge`` when the
      # back-reference resolves to more. Stalwart accepts arbitrary sizes
      # but tightening the chain doesn't change its result.
      let chainFilter =
        filterCondition(EmailFilterCondition(subject: Opt.some("phasej67refdeep")))
      let (b1, queryHandle) = addEmailQuery(
        initRequestBuilder(), mailAccountId, filter = Opt.some(chainFilter)
      )
      let queryRef = initResultReference(callId(queryHandle), mnEmailQuery, rpIds)
      let (b2, getHandle) = addEmailGetByRef(b1, mailAccountId, idsRef = queryRef)
      let resp =
        client.send(b2).expect("send Email/query → Email/get[" & $target.kind & "]")
      let queryResp =
        resp.get(queryHandle).expect("Email/query extract[" & $target.kind & "]")
      let getResp =
        resp.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
      assertOn target,
        queryResp.ids.len >= 3,
        "Email/query must surface at least the seeded ids, got " & $queryResp.ids.len
      assertOn target,
        getResp.list.len >= 3,
        "Email/get-by-ref must return matching list, got " & $getResp.list.len

    # Sub-test 2: three-leg deep chain via rpListThreadId.
    # Email/query → Email/get(props=[id, threadId]) → Thread/get
    block deepRefCase:
      # Filter the back-referenced Email/query to the seeded discriminator
      # so the downstream Email/get's #ids result reference does not pull
      # an unbounded slice of inbox-wide ids. James 3.9 caps Email/get at
      # 5 items when fetching full properties (no per-property override
      # in the memory image) and rejects with ``requestTooLarge`` when the
      # back-reference resolves to more. Stalwart accepts arbitrary sizes
      # but tightening the chain doesn't change its result.
      let chainFilter =
        filterCondition(EmailFilterCondition(subject: Opt.some("phasej67refdeep")))
      let (b1, queryHandle) = addEmailQuery(
        initRequestBuilder(), mailAccountId, filter = Opt.some(chainFilter)
      )
      let queryRef = initResultReference(callId(queryHandle), mnEmailQuery, rpIds)
      let (b2, getHandle) = addEmailGetByRef(
        b1, mailAccountId, idsRef = queryRef, properties = Opt.some(@["id", "threadId"])
      )
      let getThreadIdRef =
        initResultReference(callId(getHandle), mnEmailGet, rpListThreadId)
      let (b3, threadHandle) =
        addThreadGetByRef(b2, mailAccountId, idsRef = getThreadIdRef)
      let resp = client.send(b3).expect(
          "send Email/query → Email/get → Thread/get[" & $target.kind & "]"
        )
      captureIfRequested(client, "result-reference-deep-path-" & $target.kind).expect(
        "captureIfRequested deep ref"
      )
      let queryResp =
        resp.get(queryHandle).expect("Email/query extract[" & $target.kind & "]")
      let getResp =
        resp.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
      let threadResp =
        resp.get(threadHandle).expect("Thread/get extract[" & $target.kind & "]")
      assertOn target,
        queryResp.ids.len >= 3,
        "Email/query must surface seeded emails, got " & $queryResp.ids.len
      assertOn target,
        getResp.list.len >= 3,
        "Email/get must surface email records, got " & $getResp.list.len
      assertOn target,
        threadResp.list.len >= 1,
        "Thread/get-by-deep-ref must return at least one Thread, got " &
          $threadResp.list.len

    # Sub-test 3: adversarial broken back-reference path.
    # Email/get with a #ids ref pointing at a path that does not
    # resolve in the prior invocation's response.  Stalwart must
    # surface this as an "error" invocation rather than treating
    # the chain as successful.
    block brokenRefCase:
      # First fire an Email/query so c0 carries ids; the broken ref
      # then names a deep path that does not exist in c0's response.
      # Filter the back-referenced Email/query to the seeded discriminator
      # so the downstream Email/get's #ids result reference does not pull
      # an unbounded slice of inbox-wide ids. James 3.9 caps Email/get at
      # 5 items when fetching full properties (no per-property override
      # in the memory image) and rejects with ``requestTooLarge`` when the
      # back-reference resolves to more. Stalwart accepts arbitrary sizes
      # but tightening the chain doesn't change its result.
      let chainFilter =
        filterCondition(EmailFilterCondition(subject: Opt.some("phasej67refdeep")))
      let (b1, queryHandle) = addEmailQuery(
        initRequestBuilder(), mailAccountId, filter = Opt.some(chainFilter)
      )
      discard queryHandle
      let getArgs = %*{"accountId": $mailAccountId}
      let getArgsRef = injectBrokenBackReference(
        getArgs,
        refField = "ids",
        refPath = "/list/99/threadId",
        refName = "Email/query",
      )
      let req1 = b1.build()
      var combinedCalls = req1.methodCalls
      let mcid = parseMethodCallId("c" & $combinedCalls.len).expect(
          "parseMethodCallId[" & $target.kind & "]"
        )
      let brokenInv = parseInvocation("Email/get", getArgsRef, mcid).expect(
          "parseInvocation[" & $target.kind & "]"
        )
      combinedCalls.add(brokenInv)
      let combined = Request(
        `using`: req1.`using` & @["urn:ietf:params:jmap:mail"],
        methodCalls: combinedCalls,
        createdIds: Opt.none(Table[CreationId, Id]),
      )
      let resp = client.send(combined).expect(
          "send query+broken-get envelope[" & $target.kind & "]"
        )
      assertOn target,
        resp.methodResponses.len == 2,
        "envelope must carry two responses, got " & $resp.methodResponses.len
      let brokenInvResp = resp.methodResponses[1]
      assertOn target,
        brokenInvResp.rawName == "error",
        "broken back-reference must surface as 'error', got " & brokenInvResp.rawName
      let me = MethodError.fromJson(brokenInvResp.arguments).expect(
          "MethodError.fromJson[" & $target.kind & "]"
        )
      assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
      assertOn target,
        me.errorType in
          {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown},
        "errorType must project into the closed enum, got " & $me.errorType

    # Cleanup: destroy the seed emails so re-runs are idempotent.
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(seedIds))
    let respClean =
      client.send(bClean).expect("send Email/set cleanup[" & $target.kind & "]")
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    for id in seedIds:
      cleanResp.destroyResults.withValue(id, outcome):
        assertOn target, outcome.isOk, "cleanup destroy must succeed"
      do:
        assertOn target, false, "cleanup must report an outcome for each seed id"

    client.close()
