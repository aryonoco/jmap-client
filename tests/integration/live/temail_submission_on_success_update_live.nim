# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for the compound EmailSubmission/set with
## ``onSuccessUpdateEmail`` (RFC 8621 §7.5 ¶3) against Stalwart. First
## wire exercise of ``addEmailSubmissionAndEmailSet`` — a single JMAP
## invocation that triggers a server-emitted implicit Email/set
## response sharing the parent call id (RFC 8620 §5.4). On a
## successful submission the patch moves the draft out of Drafts into
## Sent and flips the IANA ``$draft`` keyword to ``$seen``, exactly
## the production "Send -> Sent" mail-UI flow.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailSubmissionOnSuccessUpdateLive:
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
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    let draftsId = resolveOrCreateDrafts(client, mailAccountId).expect(
        "resolveOrCreateDrafts[" & $target.kind & "]"
      )
    let sentId = resolveOrCreateSent(client, mailAccountId).expect(
        "resolveOrCreateSent[" & $target.kind & "]"
      )

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # --- Seed draft ---------------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope = buildEnvelope("alice@example.com", "bob@example.com").expect(
        "buildEnvelope[" & $target.kind & "]"
      )
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-34",
        "Submission with onSuccessUpdateEmail patch.", "draft34",
      )
      .expect("seedDraftEmail[" & $target.kind & "]")

    # --- Build EmailUpdateSet patch + onSuccessUpdateEmail map ----------
    let draftKw =
      parseKeyword("$draft").expect("parseKeyword $draft[" & $target.kind & "]")
    let seenKw =
      parseKeyword("$seen").expect("parseKeyword $seen[" & $target.kind & "]")
    let patch = initEmailUpdateSet(
        @[
          removeFromMailbox(draftsId),
          addToMailbox(sentId),
          removeKeyword(draftKw),
          addKeyword(seenKw),
        ]
      )
      .expect("initEmailUpdateSet[" & $target.kind & "]")
    let subCid =
      parseCreationId("sub34").expect("parseCreationId sub34[" & $target.kind & "]")
    # Reference the in-request submission via its creation id (RFC 8621
    # §7.5 ¶3 — ``"#" + creationId`` resolves against the sibling create
    # in the same /set call). James 3.9 supports only ``#cid`` references
    # for ``onSuccessUpdateEmail`` (direct ``Id`` references against the
    # submission's persisted id are rejected because James does not
    # store EmailSubmissions). The ``creationRef`` form is RFC-canonical
    # and works on both servers.
    let onSuccess = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(subCid), patch)])
      .expect("parseNonEmptyOnSuccessUpdateEmail[" & $target.kind & "]")

    # --- Build blueprint + compound submission ---------------------------
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint[" & $target.kind & "]")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, handles) = addEmailSubmissionAndEmailSet(
      initRequestBuilder(),
      submissionAccountId,
      create = Opt.some(subTbl),
      onSuccessUpdateEmail = Opt.some(onSuccess),
    )
    let resp3 =
      client.send(b3).expect("send EmailSubmission/set+Email/set[" & $target.kind & "]")
    captureIfRequested(client, "email-submission-on-success-update-" & $target.kind)
      .expect("captureIfRequested")
    let pairExtract = resp3.getBoth(handles)
    # Cat-B: Cyrus 3.12.2 rejects ``onSuccessUpdateEmail`` with
    # ``invalidArguments``. Stalwart and James implement the compound
    # submit-and-update.
    var submissionId: Id
    var compoundOk = false
    if pairExtract.isOk:
      let pair = pairExtract.unsafeValue
      pair.primary.createResults.withValue(subCid, outcome):
        if outcome.isOk:
          submissionId = outcome.unsafeValue.id
          compoundOk = true
      do:
        assertOn target, false, "EmailSubmission/set must report a create outcome"
      pair.implicit.updateResults.withValue(draftId, outcome):
        assertOn target,
          outcome.isOk,
          "implicit Email/set update must succeed: " & outcome.error.rawType
      do:
        assertOn target,
          false, "implicit Email/set must report an update outcome for draftId"
    else:
      let methodErr = pairExtract.unsafeError
      assertOn target,
        methodErr.errorType in {metInvalidArguments, metUnknownMethod},
        "compound EmailSubmission/set + onSuccessUpdateEmail must surface " &
          "metInvalidArguments or metUnknownMethod when unimplemented (got " &
          methodErr.rawType & ")"
      client.close()
      continue
    if not compoundOk:
      client.close()
      continue

    # --- Verification leg: divergent observation surface --------------
    case target.kind
    of ltkStalwart:
      # Stalwart implements EmailSubmission/get; poll until ``usFinal``
      # before reading back the email so the SMTP queue is drained and
      # the mailbox/keyword patch is observable. Discards the polled
      # ``Opt[EmailSubmission[usFinal]]`` — the caller only needs the
      # delivery barrier.
      discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
          "pollSubmissionDelivery[stalwart]"
        )
    of ltkJames, ltkCyrus:
      # James 3.9 has no ``EmailSubmission/get``; Cyrus 3.12.2's
      # ``deliveryStatus`` is hardcoded null. Verify delivery via
      # inbox arrival on bob; ``onSuccessUpdateEmail`` is processed
      # synchronously per RFC 8621 §7.5 ¶3, so the mailbox/keyword
      # patch is already observable.
      var bobClient =
        initBobClient(target).expect("initBobClient[" & $target.kind & "]")
      let bobSession =
        bobClient.fetchSession().expect("fetchSession bob[" & $target.kind & "]")
      let bobMailAccountId = resolveMailAccountId(bobSession).expect(
          "resolveMailAccountId bob[" & $target.kind & "]"
        )
      let bobInbox = resolveInboxId(bobClient, bobMailAccountId).expect(
          "resolveInboxId bob[" & $target.kind & "]"
        )
      let budget = (if target.kind == ltkCyrus: 30000 else: 5000) * liveBudgetMul
      discard pollEmailDeliveryToInbox(
          bobClient,
          bobMailAccountId,
          bobInbox,
          subject = "phase-f step-34",
          budgetMs = budget,
        )
        .expect("pollEmailDeliveryToInbox bob[" & $target.kind & "]")
      bobClient.close()

    # --- Read-back via Email/get to verify mailbox + keyword changes -----
    let (b4, emailGetHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[draftId]),
      properties = Opt.some(@["mailboxIds", "keywords"]),
    )
    let resp4 =
      client.send(b4).expect("send Email/get post-submit[" & $target.kind & "]")
    let getResp = resp4.get(emailGetHandle).expect(
        "Email/get post-submit extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp.list.len == 1, "Email/get must return one entry for the patched draft"
    let email = getResp.list[0]
    assertOn target, email.mailboxIds.isSome, "Email/get must include mailboxIds"
    let mbIds = HashSet[Id](email.mailboxIds.unsafeGet)
    assertOn target,
      sentId in mbIds,
      "after onSuccessUpdateEmail, draft must be in Sent (mailboxIds=" & $mbIds & ")"
    assertOn target,
      draftsId notin mbIds,
      "after onSuccessUpdateEmail, draft must no longer be in Drafts"
    assertOn target, email.keywords.isSome, "Email/get must include keywords"
    let kwSet = HashSet[Keyword](email.keywords.unsafeGet)
    assertOn target, seenKw in kwSet, "after patch, $seen must be present"
    assertOn target, draftKw notin kwSet, "after patch, $draft must be absent"
    client.close()
