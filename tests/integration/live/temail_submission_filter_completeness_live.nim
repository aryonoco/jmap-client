# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: every variant of
## ``EmailSubmissionFilterCondition`` (six fields per RFC 8621 §7.3:
## ``identityIds``, ``emailIds``, ``threadIds``, ``undoStatus``,
## ``before``, ``after``) and every arm of
## ``EmailSubmissionComparator`` (``emailId``, ``threadId``,
## ``sentAt``) serialises to a wire shape Stalwart accepts and the
## response parses cleanly through ``QueryResponse[AnyEmailSubmission]``.
##
## Phase J Step 71.  Phase I60 already covered ``identityIds`` and
## ``sentAt``; this step closes the remaining four filter variants
## and the two unexercised comparator arms.
##
## **Library-contract.**  Each sub-test exercises a typed filter or
## comparator and asserts the response parses without error; the
## set of returned ids is incidental — we are testing the wire-
## emission and parse pipeline, not Stalwart's filter semantics.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailSubmissionFilterCompletenessLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")
    let drafts =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")

    let primaryId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )
    let aliceAddr = buildAliceAddr()
    let bobAddr =
      parseEmailAddress("bob@example.com", Opt.some("Bob")).expect("parseEmailAddress")
    let submissionIds = seedSubmissionCorpus(
        client,
        mailAccountId,
        submissionAccountId,
        drafts,
        aliceAddr,
        identities = @[primaryId, primaryId],
        recipients = @[bobAddr],
        subjects = @["phase-j 71 corpus a", "phase-j 71 corpus b"],
        creationLabelPrefix = "phase-j-71",
      )
      .expect("seedSubmissionCorpus")
    doAssert submissionIds.len == 2

    # Look up one submission's threadId / emailId for the
    # threadIds / emailIds filter sub-tests.
    let firstSubId = submissionIds[0]
    let (bSub, subHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[firstSubId])
    )
    let respSub = client.send(bSub).expect("send EmailSubmission/get firstSub")
    let getSub = respSub.get(subHandle).expect("EmailSubmission/get extract")
    doAssert getSub.list.len == 1
    let anySub =
      AnyEmailSubmission.fromJson(getSub.list[0]).expect("AnyEmailSubmission.fromJson")
    let firstFinal = anySub.asFinal()
    doAssert firstFinal.isSome,
      "corpus submission must have settled to usFinal before filter tests"
    let firstEmailId = firstFinal.unsafeGet.emailId
    # threadId is on Email, not EmailSubmission directly; fetch it.
    let (bEmail, emailHandle) =
      addEmailGet(initRequestBuilder(), mailAccountId, ids = directIds(@[firstEmailId]))
    let respEmail = client.send(bEmail).expect("send Email/get for threadId")
    let getEmail = respEmail.get(emailHandle).expect("Email/get extract")
    doAssert getEmail.list.len == 1
    let firstEmail = Email.fromJson(getEmail.list[0]).expect("Email.fromJson")
    doAssert firstEmail.threadId.isSome
    let firstThreadId = firstEmail.threadId.unsafeGet

    # Sub-test 1: threadIds filter.
    block threadIdsCase:
      let threadFilter = filterCondition(
        EmailSubmissionFilterCondition(
          threadIds:
            Opt.some(parseNonEmptyIdSeq(@[firstThreadId]).expect("parseNonEmptyIdSeq"))
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(threadFilter)
      )
      let resp = client.send(b).expect("send EmailSubmission/query threadIds")
      discard resp.get(qHandle).expect("threadIds extract")

    # Sub-test 2: emailIds filter.
    block emailIdsCase:
      let emailFilter = filterCondition(
        EmailSubmissionFilterCondition(
          emailIds:
            Opt.some(parseNonEmptyIdSeq(@[firstEmailId]).expect("parseNonEmptyIdSeq"))
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(emailFilter)
      )
      let resp = client.send(b).expect("send EmailSubmission/query emailIds")
      discard resp.get(qHandle).expect("emailIds extract")

    # Sub-test 3: undoStatus filter — usFinal.
    block undoStatusCase:
      let undoFilter =
        filterCondition(EmailSubmissionFilterCondition(undoStatus: Opt.some(usFinal)))
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(undoFilter)
      )
      let resp = client.send(b).expect("send EmailSubmission/query undoStatus")
      discard resp.get(qHandle).expect("undoStatus extract")

    # Sub-test 4: before / after filters — pair of UTC thresholds.
    block beforeAfterCase:
      # Before: 2099 (well after corpus); After: 1990 (well before).
      let beforeUtc = parseUTCDate("2099-01-01T00:00:00Z").expect("parseUTCDate before")
      let afterUtc = parseUTCDate("1990-01-01T00:00:00Z").expect("parseUTCDate after")
      let dateFilter = filterCondition(
        EmailSubmissionFilterCondition(
          before: Opt.some(beforeUtc), after: Opt.some(afterUtc)
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(dateFilter)
      )
      let resp = client.send(b).expect("send EmailSubmission/query before/after")
      let qResp = resp.get(qHandle).expect("before/after extract")
      doAssert qResp.ids.len >= 2,
        "corpus submissions must surface within 1990–2099 window; got " &
          $qResp.ids.len

    # Sub-test 5: sort by emailId ascending.
    block sortEmailIdCase:
      let comp = parseEmailSubmissionComparator(
          rawProperty = "emailId", isAscending = true
        )
        .expect("parseEmailSubmissionComparator emailId")
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, sort = Opt.some(@[comp])
      )
      let resp = client.send(b).expect("send EmailSubmission/query sort emailId")
      discard resp.get(qHandle).expect("sort emailId extract")

    # Sub-test 6: sort by threadId ascending.  Capture the wire
    # shape after this — covers both the comparator on threadId
    # and the previous filter sub-tests' wire-shape via the same
    # shared ``QueryResponse[AnyEmailSubmission]`` parser.
    block sortThreadIdCase:
      let comp = parseEmailSubmissionComparator(
          rawProperty = "threadId", isAscending = true
        )
        .expect("parseEmailSubmissionComparator threadId")
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, sort = Opt.some(@[comp])
      )
      let resp = client.send(b).expect("send EmailSubmission/query sort threadId")
      captureIfRequested(client, "email-submission-filter-completeness-stalwart").expect(
        "captureIfRequested filter completeness"
      )
      discard resp.get(qHandle).expect("sort threadId extract")

    client.close()
