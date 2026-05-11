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

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailSubmissionFilterCompletenessLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises every EmailSubmissionFilterCondition
    # variant and EmailSubmissionComparator arm. Stalwart 0.15.5 and
    # Cyrus 3.12.2 implement EmailSubmission/{set,get,query}; James 3.9
    # stores no submission records, so the entire surface (including
    # the seedSubmissionCorpus helper that depends on /get for
    # pollSubmissionDelivery) returns typed errors. The corpus-seed and
    # each ``EmailSubmission/query`` extract use Cat-B Result-branching;
    # dependent steps skip when an upstream extract surfaces a typed
    # error.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )
    let drafts = resolveOrCreateDrafts(client, mailAccountId).expect(
        "resolveOrCreateDrafts[" & $target.kind & "]"
      )

    let primaryId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress[" & $target.kind & "]"
      )
    # HOLDFOR=300: the test inspects each submission via ``/get`` to
    # extract emailId and threadId for the filter sub-tests below.
    # Cyrus 3.12.2's fire-and-forget submissions evict on ``final``,
    # so without HOLDFOR the /get would return notFound. Pending
    # submissions are retained on every configured target. Cleanup
    # at the end of the test cancels and destroys both submissions.
    let holdSeconds = parseHoldForSeconds(UnsignedInt(300)).expect(
        "parseHoldForSeconds[" & $target.kind & "]"
      )
    let submissionIdsRes = seedSubmissionCorpus(
      client,
      mailAccountId,
      submissionAccountId,
      drafts,
      aliceAddr,
      identities = @[primaryId, primaryId],
      recipients = @[bobAddr],
      subjects = @["phase-j 71 corpus a", "phase-j 71 corpus b"],
      creationLabelPrefix = "phase-j-71",
      holdForSeconds = Opt.some(holdSeconds),
    )
    if submissionIdsRes.isErr:
      # Cat-B error arm — the helper's typed-error projection has fired
      # inside ``seedSubmissionCorpus`` (server lacks the EmailSubmission
      # surface). Skip the dependent filter sub-tests.
      client.close()
      continue
    let submissionIds = submissionIdsRes.unsafeValue
    assertOn target, submissionIds.len == 2

    # Look up one submission's threadId / emailId for the
    # threadIds / emailIds filter sub-tests.
    let firstSubId = submissionIds[0]
    let (bSub, subHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[firstSubId])
    )
    let respSub = client.send(bSub).expect(
        "send EmailSubmission/get firstSub[" & $target.kind & "]"
      )
    let getSub =
      respSub.get(subHandle).expect("EmailSubmission/get extract[" & $target.kind & "]")
    assertOn target, getSub.list.len == 1
    let anySub = getSub.list[0]
    # The HOLDFOR=300 seed retains the submission as ``pending`` so
    # every server's ``/get`` returns the record. The submission's
    # emailId field is on every state-variant.
    let firstPending = anySub.asPending()
    assertOn target,
      firstPending.isSome,
      "corpus submission with HOLDFOR=300 must surface as pending (got state " &
        $anySub.state & ")"
    let firstEmailId = firstPending.unsafeGet.emailId
    # threadId is on Email, not EmailSubmission directly; fetch it.
    let (bEmail, emailHandle) =
      addEmailGet(initRequestBuilder(), mailAccountId, ids = directIds(@[firstEmailId]))
    let respEmail =
      client.send(bEmail).expect("send Email/get for threadId[" & $target.kind & "]")
    let getEmail =
      respEmail.get(emailHandle).expect("Email/get extract[" & $target.kind & "]")
    assertOn target, getEmail.list.len == 1
    let firstEmail = getEmail.list[0]
    assertOn target, firstEmail.threadId.isSome
    let firstThreadId = firstEmail.threadId.unsafeGet

    # Sub-test 1: threadIds filter.
    block threadIdsCase:
      let threadFilter = filterCondition(
        EmailSubmissionFilterCondition(
          threadIds: Opt.some(
            parseNonEmptyIdSeq(@[firstThreadId]).expect(
              "parseNonEmptyIdSeq[" & $target.kind & "]"
            )
          )
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(threadFilter)
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query threadIds[" & $target.kind & "]"
        )
      discard resp.get(qHandle).expect("threadIds extract[" & $target.kind & "]")

    # Sub-test 2: emailIds filter.
    block emailIdsCase:
      let emailFilter = filterCondition(
        EmailSubmissionFilterCondition(
          emailIds: Opt.some(
            parseNonEmptyIdSeq(@[firstEmailId]).expect(
              "parseNonEmptyIdSeq[" & $target.kind & "]"
            )
          )
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(emailFilter)
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query emailIds[" & $target.kind & "]"
        )
      discard resp.get(qHandle).expect("emailIds extract[" & $target.kind & "]")

    # Sub-test 3: undoStatus filter — usFinal.
    block undoStatusCase:
      let undoFilter =
        filterCondition(EmailSubmissionFilterCondition(undoStatus: Opt.some(usFinal)))
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(undoFilter)
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query undoStatus[" & $target.kind & "]"
        )
      discard resp.get(qHandle).expect("undoStatus extract[" & $target.kind & "]")

    # Sub-test 4: before / after filters — pair of UTC thresholds.
    block beforeAfterCase:
      # Before: 2099 (well after corpus); After: 1990 (well before).
      let beforeUtc = parseUTCDate("2099-01-01T00:00:00Z").expect(
          "parseUTCDate before[" & $target.kind & "]"
        )
      let afterUtc = parseUTCDate("1990-01-01T00:00:00Z").expect(
          "parseUTCDate after[" & $target.kind & "]"
        )
      let dateFilter = filterCondition(
        EmailSubmissionFilterCondition(
          before: Opt.some(beforeUtc), after: Opt.some(afterUtc)
        )
      )
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, filter = Opt.some(dateFilter)
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query before/after[" & $target.kind & "]"
        )
      let qResp = resp.get(qHandle).expect("before/after extract[" & $target.kind & "]")
      assertOn target,
        qResp.ids.len >= 2,
        "corpus submissions must surface within 1990–2099 window; got " &
          $qResp.ids.len

    # Sub-test 5: sort by emailId ascending.
    block sortEmailIdCase:
      let comp = parseEmailSubmissionComparator(
          rawProperty = "emailId", isAscending = true
        )
        .expect("parseEmailSubmissionComparator emailId[" & $target.kind & "]")
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, sort = Opt.some(@[comp])
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query sort emailId[" & $target.kind & "]"
        )
      discard resp.get(qHandle).expect("sort emailId extract[" & $target.kind & "]")

    # Sub-test 6: sort by threadId ascending.  Capture the wire
    # shape after this — covers both the comparator on threadId
    # and the previous filter sub-tests' wire-shape via the same
    # shared ``QueryResponse[AnyEmailSubmission]`` parser.
    block sortThreadIdCase:
      let comp = parseEmailSubmissionComparator(
          rawProperty = "threadId", isAscending = true
        )
        .expect("parseEmailSubmissionComparator threadId[" & $target.kind & "]")
      let (b, qHandle) = addEmailSubmissionQuery(
        initRequestBuilder(), submissionAccountId, sort = Opt.some(@[comp])
      )
      let resp = client.send(b).expect(
          "send EmailSubmission/query sort threadId[" & $target.kind & "]"
        )
      captureIfRequested(client, "email-submission-filter-completeness-" & $target.kind)
        .expect("captureIfRequested filter completeness")
      discard resp.get(qHandle).expect("sort threadId extract[" & $target.kind & "]")

    # Cleanup: destroy the HOLDFOR-pended submissions so they never
    # deliver to bob's inbox.
    let (bDestroy, destroyHandle) = addEmailSubmissionSet(
      initRequestBuilder(), submissionAccountId, destroy = directIds(submissionIds)
    )
    discard client.send(bDestroy)
    discard destroyHandle
    client.close()
