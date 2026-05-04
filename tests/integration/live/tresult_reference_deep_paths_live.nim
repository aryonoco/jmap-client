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
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tresultReferenceDeepPathsLive:
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
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")

    let seedIds = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-j 67 ref deep alpha", "phase-j 67 ref deep beta",
          "phase-j 67 ref deep gamma",
        ],
      )
      .expect("seedEmailsWithSubjects")
    doAssert seedIds.len == 3

    # Sub-test 1: simple two-leg chain — Email/query → Email/get.
    # Regression-only.
    block simpleRefCase:
      let (b1, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
      let queryRef = initResultReference(callId(queryHandle), mnEmailQuery, rpIds)
      let (b2, getHandle) = addEmailGetByRef(b1, mailAccountId, idsRef = queryRef)
      let resp = client.send(b2).expect("send Email/query → Email/get")
      let queryResp = resp.get(queryHandle).expect("Email/query extract")
      let getResp = resp.get(getHandle).expect("Email/get extract")
      doAssert queryResp.ids.len >= 3,
        "Email/query must surface at least the seeded ids, got " & $queryResp.ids.len
      doAssert getResp.list.len >= 3,
        "Email/get-by-ref must return matching list, got " & $getResp.list.len

    # Sub-test 2: three-leg deep chain via rpListThreadId.
    # Email/query → Email/get(props=[id, threadId]) → Thread/get
    block deepRefCase:
      let (b1, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
      let queryRef = initResultReference(callId(queryHandle), mnEmailQuery, rpIds)
      let (b2, getHandle) = addEmailGetByRef(
        b1, mailAccountId, idsRef = queryRef, properties = Opt.some(@["id", "threadId"])
      )
      let getThreadIdRef =
        initResultReference(callId(getHandle), mnEmailGet, rpListThreadId)
      let (b3, threadHandle) =
        addThreadGetByRef(b2, mailAccountId, idsRef = getThreadIdRef)
      let resp = client.send(b3).expect("send Email/query → Email/get → Thread/get")
      captureIfRequested(client, "result-reference-deep-path-stalwart").expect(
        "captureIfRequested deep ref"
      )
      let queryResp = resp.get(queryHandle).expect("Email/query extract")
      let getResp = resp.get(getHandle).expect("Email/get extract")
      let threadResp = resp.get(threadHandle).expect("Thread/get extract")
      doAssert queryResp.ids.len >= 3,
        "Email/query must surface seeded emails, got " & $queryResp.ids.len
      doAssert getResp.list.len >= 3,
        "Email/get must surface email records, got " & $getResp.list.len
      doAssert threadResp.list.len >= 1,
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
      let (b1, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
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
      let mcid = parseMethodCallId("c" & $combinedCalls.len).expect("parseMethodCallId")
      let brokenInv =
        parseInvocation("Email/get", getArgsRef, mcid).expect("parseInvocation")
      combinedCalls.add(brokenInv)
      let combined = Request(
        `using`: req1.`using` & @["urn:ietf:params:jmap:mail"],
        methodCalls: combinedCalls,
        createdIds: Opt.none(Table[CreationId, Id]),
      )
      let resp = client.send(combined).expect("send query+broken-get envelope")
      doAssert resp.methodResponses.len == 2,
        "envelope must carry two responses, got " & $resp.methodResponses.len
      let brokenInvResp = resp.methodResponses[1]
      doAssert brokenInvResp.rawName == "error",
        "broken back-reference must surface as 'error', got " & brokenInvResp.rawName
      let me =
        MethodError.fromJson(brokenInvResp.arguments).expect("MethodError.fromJson")
      doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
      doAssert me.errorType in
        {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown},
        "errorType must project into the closed enum, got " & $me.errorType

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
