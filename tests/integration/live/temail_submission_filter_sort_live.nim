# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 60 (capstone) — wire test of
## ``EmailSubmission/query`` and ``EmailSubmission/queryChanges``
## with ``EmailSubmissionFilterCondition`` and
## ``EmailSubmissionComparator`` against a multi-identity corpus.
## Visibly-harder capstone (mirrors A7 / B12 / C18 / D24 / E30 /
## F36 / G42 / H48): builds two identities, two submissions, and
## chains ``/query`` → ``/queryChanges`` from a captured baseline.
##
## Workflow:
##
##  1. Resolve mail and submission accounts; resolve / create
##     drafts mailbox; resolve / create alice's primary identity.
##  2. Resolve / create a second identity sharing
##     ``alice@example.com`` but with a distinct display name
##     (``"phase-i 60 secondary"``).  Idempotent across runs via
##     a get-then-create lookup.
##  3. Capture baseline ``queryState`` from
##     ``EmailSubmission/query``.
##  4. ``seedSubmissionCorpus`` with two identities (one each),
##     alice→bob recipient, and two distinct subject suffixes.
##     Polls each to ``usFinal``.
##  5. Sub-test A: filter ``identityIds = [primary]`` — assert
##     the primary submission surfaces and the secondary
##     submission does not.
##  6. Sub-test B: sort by ``sentAt`` ascending — assert both
##     submissions surface.  Capture the wire response.
##  7. Sub-test C: ``EmailSubmission/queryChanges`` from the
##     baseline with ``calculateTotal: true``.  Capture the wire
##     response; assert total advanced by at least two.
##
## **Stalwart 0.15.5 empirical pin.** ``identityIds``,
## ``threadIds``, ``emailIds`` filter list semantics permit empty
## input rejected at construction time (NonEmptyIdSeq); at the
## wire layer the filter list intersection is membership-based per
## RFC 8621 §7.3.
##
## Captures: ``email-submission-query-filter-sort-stalwart``
## (after sub-test B) and
## ``email-submission-query-changes-with-filter-stalwart``
## (after sub-test C).
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/identity as jidentity
import ./mcapture
import ./mconfig
import ./mlive

proc resolveOrCreateSecondaryAliceIdentity(
    client: var JmapClient, submissionAccountId: AccountId, displayName: string
): Result[Id, string] =
  ## Sibling of ``resolveOrCreateAliceIdentity`` that targets a
  ## distinct display name on the same email address — the corpus
  ## needs two identities to make the ``identityIds`` filter
  ## discriminating.  Idempotent across runs: the lookup precedes
  ## every create.
  let (b1, getHandle) = addIdentityGet(initRequestBuilder(), submissionAccountId)
  let resp1 = client.send(b1).valueOr:
    return err("Identity/get send failed: " & error.message)
  let getResp = resp1.get(getHandle).valueOr:
    return err("Identity/get extract failed: " & error.rawType)
  for node in getResp.list:
    let ident = jidentity.Identity.fromJson(node).valueOr:
      return err("Identity parse failed during secondary lookup")
    if ident.email == "alice@example.com" and ident.name == displayName:
      return ok(ident.id)
  let createIdent = parseIdentityCreate(email = "alice@example.com", name = displayName).valueOr:
    return err("parseIdentityCreate secondary failed: " & error.message)
  let cid = parseCreationId("phaseISecondaryIdent").valueOr:
    return err("parseCreationId secondary failed: " & error.message)
  var createTbl = initTable[CreationId, IdentityCreate]()
  createTbl[cid] = createIdent
  let (b2, setHandle) = addIdentitySet(
    initRequestBuilder(), submissionAccountId, create = Opt.some(createTbl)
  )
  let resp2 = client.send(b2).valueOr:
    return err("Identity/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Identity/set extract failed: " & error.rawType)
  var createdId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Identity/set create rejected: " & error.rawType)
    createdId = item.id
    found = true
  do:
    return err("Identity/set returned no result for secondary identity")
  doAssert found
  ok(createdId)

block temailSubmissionFilterSortLive:
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
        "resolveOrCreateAliceIdentity primary"
      )
    let secondaryId = resolveOrCreateSecondaryAliceIdentity(
        client, submissionAccountId, "phase-i 60 secondary"
      )
      .expect("resolveOrCreateSecondaryAliceIdentity")

    # Baseline EmailSubmission/query queryState (no filter).
    let (bBase, baseHandle) =
      addEmailSubmissionQuery(initRequestBuilder(), submissionAccountId)
    let respBase = client.send(bBase).expect("send baseline EmailSubmission/query")
    let qrBase = respBase.get(baseHandle).expect("baseline query extract")
    let baselineQueryState = qrBase.queryState

    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    # Two submissions — one per identity — exercise the
    # identityIds filter (membership), the sentAt sort (ordering
    # over the full corpus), and queryChanges counting.  A larger
    # corpus stressed Stalwart's SMTP queue when the broader
    # submission suite ran back-to-back and surfaced
    # pollSubmissionDelivery budget timeouts in unrelated tests
    # downstream of this capstone's seeds.
    let submissionIds = seedSubmissionCorpus(
        client,
        mailAccountId,
        submissionAccountId,
        drafts,
        aliceAddr,
        identities = @[primaryId, secondaryId],
        recipients = @[bobAddr],
        subjects = @["phase-i 60 sub-a", "phase-i 60 sub-b"],
        creationLabelPrefix = "phase-i-60",
      )
      .expect("seedSubmissionCorpus")
    doAssert submissionIds.len == 2,
      "two submissions expected (got " & $submissionIds.len & ")"
    let primarySubmissions = @[submissionIds[0]]
    let secondarySubmissions = @[submissionIds[1]]

    # Sub-test A: filter by identityIds = [primary].
    let primaryIdSeq =
      parseNonEmptyIdSeq(@[primaryId]).expect("parseNonEmptyIdSeq primary")
    let identityFilter = filterCondition(
      EmailSubmissionFilterCondition(identityIds: Opt.some(primaryIdSeq))
    )
    let (bA, hA) = addEmailSubmissionQuery(
      initRequestBuilder(), submissionAccountId, filter = Opt.some(identityFilter)
    )
    let respA = client.send(bA).expect("send Email Submission/query identity filter")
    let qrA = respA.get(hA).expect("identity filter extract")
    for primSub in primarySubmissions:
      var found = false
      for id in qrA.ids:
        if id == primSub:
          found = true
          break
      doAssert found,
        "primary-identity submission " & string(primSub) &
          " must surface under identityIds=[primary] filter"
    for secSub in secondarySubmissions:
      for id in qrA.ids:
        doAssert id != secSub,
          "secondary-identity submission " & string(secSub) &
            " must NOT surface under identityIds=[primary] filter"

    # Sub-test B: sort by sentAt ascending.
    let comparator = parseEmailSubmissionComparator(
        rawProperty = "sentAt", isAscending = true
      )
      .expect("parseEmailSubmissionComparator sentAt")
    let (bB, hB) = addEmailSubmissionQuery(
      initRequestBuilder(), submissionAccountId, sort = Opt.some(@[comparator])
    )
    let respB = client.send(bB).expect("send EmailSubmission/query sort sentAt asc")
    captureIfRequested(client, "email-submission-query-filter-sort-stalwart").expect(
      "captureIfRequested filter+sort"
    )
    let qrB = respB.get(hB).expect("sort sentAt extract")
    for sId in submissionIds:
      var found = false
      for id in qrB.ids:
        if id == sId:
          found = true
          break
      doAssert found,
        "every seeded submission must surface under sentAt-asc sort (missing " &
          string(sId) & ")"

    # Sub-test C: EmailSubmission/queryChanges with calculateTotal.
    let (bC, hC) = addEmailSubmissionQueryChanges(
      initRequestBuilder(),
      submissionAccountId,
      sinceQueryState = baselineQueryState,
      calculateTotal = true,
    )
    let respC = client.send(bC).expect("send EmailSubmission/queryChanges")
    captureIfRequested(client, "email-submission-query-changes-with-filter-stalwart")
      .expect("captureIfRequested queryChanges")
    let qcr = respC.get(hC).expect("queryChanges extract")
    doAssert string(qcr.oldQueryState) == string(baselineQueryState),
      "oldQueryState must echo the supplied baseline"
    doAssert qcr.total.isSome, "calculateTotal=true must surface total"
    doAssert int64(qcr.total.unsafeGet) >= 2,
      "total must reflect at least the two new submissions (got " & $qcr.total.unsafeGet &
        ")"

    client.close()
