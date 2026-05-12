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
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/mail/identity as jidentity
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

proc resolveOrCreateSecondaryAliceIdentity(
    client: var JmapClient, submissionAccountId: AccountId, displayName: string
): Result[Id, string] =
  ## Sibling of ``resolveOrCreateAliceIdentity`` that targets a
  ## distinct display name on the same email address — the corpus
  ## needs two identities to make the ``identityIds`` filter
  ## discriminating.  Idempotent across runs: the lookup precedes
  ## every create.
  let (b1, getHandle) =
    addIdentityGet(initRequestBuilder(makeBuilderId()), submissionAccountId)
  let resp1 = client.send(b1.freeze()).valueOr:
    return err("Identity/get send failed: " & error.message)
  let getResp = resp1.get(getHandle).valueOr:
    return err("Identity/get extract failed: " & error.message)
  for ident in getResp.list:
    if ident.email == "alice@example.com" and ident.name == displayName:
      return ok(ident.id)
  let createIdent = parseIdentityCreate(email = "alice@example.com", name = displayName).valueOr:
    return err("parseIdentityCreate secondary failed: " & error.message)
  let cid = parseCreationId("phaseISecondaryIdent").valueOr:
    return err("parseCreationId secondary failed: " & error.message)
  var createTbl = initTable[CreationId, IdentityCreate]()
  createTbl[cid] = createIdent
  let (b2, setHandle) = addIdentitySet(
    initRequestBuilder(makeBuilderId()),
    submissionAccountId,
    create = Opt.some(createTbl),
  )
  let resp2 = client.send(b2.freeze()).valueOr:
    return err("Identity/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Identity/set extract failed: " & error.message)
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

testCase temailSubmissionFilterSortLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises EmailSubmission/{query,queryChanges}
    # filter + sort. Stalwart 0.15.5 and Cyrus 3.12.2 implement both;
    # James 3.9 stores no submission records and the surface returns
    # typed errors. Each extract uses ``assertSuccessOrTypedError``;
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
        "resolveOrCreateAliceIdentity primary"
      )
    # Cyrus 3.12.2 has no ``Identity/set`` (``imap/jmap_mail.c:122-123``)
    # so the secondary identity cannot be provisioned. Skip the
    # dependent corpus seed when the secondary lookup errs; the wire-
    # shape parsing of the primary EmailSubmission/query baseline above
    # is the universal client-library contract.
    let secondaryRes = resolveOrCreateSecondaryAliceIdentity(
      client, submissionAccountId, "phase-i 60 secondary"
    )
    if secondaryRes.isErr:
      client.close()
      continue
    let secondaryId = secondaryRes.unsafeValue

    # Baseline EmailSubmission/query queryState (no filter).
    let (bBase, baseHandle) =
      addEmailSubmissionQuery(initRequestBuilder(makeBuilderId()), submissionAccountId)
    let respBase = client.send(bBase.freeze()).expect(
        "send baseline EmailSubmission/query[" & $target.kind & "]"
      )
    let baseExtract = respBase.get(baseHandle)
    if baseExtract.isErr:
      client.close()
      continue
    let qrBase = baseExtract.unsafeValue
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
    let submissionIdsRes = seedSubmissionCorpus(
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
    if submissionIdsRes.isErr:
      client.close()
      continue
    let submissionIds = submissionIdsRes.unsafeValue
    assertOn target,
      submissionIds.len == 2,
      "two submissions expected (got " & $submissionIds.len & ")"
    let primarySubmissions = @[submissionIds[0]]
    let secondarySubmissions = @[submissionIds[1]]

    # Sub-test A: filter by identityIds = [primary].
    let primaryIdSeq = parseNonEmptyIdSeq(@[primaryId]).expect(
        "parseNonEmptyIdSeq primary[" & $target.kind & "]"
      )
    let identityFilter = filterCondition(
      EmailSubmissionFilterCondition(identityIds: Opt.some(primaryIdSeq))
    )
    let (bA, hA) = addEmailSubmissionQuery(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      filter = Opt.some(identityFilter),
    )
    let respA = client.send(bA.freeze()).expect(
        "send Email Submission/query identity filter[" & $target.kind & "]"
      )
    let qrA = respA.get(hA).expect("identity filter extract[" & $target.kind & "]")
    for primSub in primarySubmissions:
      var found = false
      for id in qrA.ids:
        if id == primSub:
          found = true
          break
      assertOn target,
        found,
        "primary-identity submission " & string(primSub) &
          " must surface under identityIds=[primary] filter"
    for secSub in secondarySubmissions:
      for id in qrA.ids:
        assertOn target,
          id != secSub,
          "secondary-identity submission " & string(secSub) &
            " must NOT surface under identityIds=[primary] filter"

    # Sub-test B: sort by sentAt ascending.
    let comparator = parseEmailSubmissionComparator(
        rawProperty = "sentAt", isAscending = true
      )
      .expect("parseEmailSubmissionComparator sentAt[" & $target.kind & "]")
    let (bB, hB) = addEmailSubmissionQuery(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      sort = Opt.some(@[comparator]),
    )
    let respB = client.send(bB.freeze()).expect(
        "send EmailSubmission/query sort sentAt asc[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-submission-query-filter-sort-" & $target.kind)
      .expect("captureIfRequested filter+sort")
    let qrB = respB.get(hB).expect("sort sentAt extract[" & $target.kind & "]")
    for sId in submissionIds:
      var found = false
      for id in qrB.ids:
        if id == sId:
          found = true
          break
      assertOn target,
        found,
        "every seeded submission must surface under sentAt-asc sort (missing " &
          string(sId) & ")"

    # Sub-test C: EmailSubmission/queryChanges with calculateTotal.
    let (bC, hC) = addEmailSubmissionQueryChanges(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      sinceQueryState = baselineQueryState,
      calculateTotal = true,
    )
    let respC = client.send(bC.freeze()).expect(
        "send EmailSubmission/queryChanges[" & $target.kind & "]"
      )
    captureIfRequested(
      client, "email-submission-query-changes-with-filter-" & $target.kind
    )
      .expect("captureIfRequested queryChanges[" & $target.kind & "]")
    let qcr = respC.get(hC).expect("queryChanges extract[" & $target.kind & "]")
    assertOn target,
      string(qcr.oldQueryState) == string(baselineQueryState),
      "oldQueryState must echo the supplied baseline"
    assertOn target, qcr.total.isSome, "calculateTotal=true must surface total"
    assertOn target,
      int64(qcr.total.unsafeGet) >= 2,
      "total must reflect at least the two new submissions (got " & $qcr.total.unsafeGet &
        ")"

    client.close()
