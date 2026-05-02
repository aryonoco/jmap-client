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
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/json
import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tEmailSubmissionOnSuccessUpdateLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")

    let draftsId =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")
    let sentId =
      resolveOrCreateSent(client, mailAccountId).expect("resolveOrCreateSent")

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # --- Seed draft ---------------------------------------------------
    let aliceAddr = buildAliceAddr()
    let bobAddr = parseEmailAddress("bob@example.com", Opt.some("Bob")).expect(
        "parseEmailAddress bob"
      )
    let envelope =
      buildEnvelope("alice@example.com", "bob@example.com").expect("buildEnvelope")
    let draftId = seedDraftEmail(
        client, mailAccountId, draftsId, aliceAddr, bobAddr, "phase-f step-34",
        "Submission with onSuccessUpdateEmail patch.", "draft34",
      )
      .expect("seedDraftEmail")

    # --- Build EmailUpdateSet patch + onSuccessUpdateEmail map ----------
    let draftKw = parseKeyword("$draft").expect("parseKeyword $draft")
    let seenKw = parseKeyword("$seen").expect("parseKeyword $seen")
    let patch = initEmailUpdateSet(
        @[
          removeFromMailbox(draftsId),
          addToMailbox(sentId),
          removeKeyword(draftKw),
          addKeyword(seenKw),
        ]
      )
      .expect("initEmailUpdateSet")
    let onSuccess = parseNonEmptyOnSuccessUpdateEmail(@[(directRef(draftId), patch)])
      .expect("parseNonEmptyOnSuccessUpdateEmail")

    # --- Build blueprint + compound submission ---------------------------
    let blueprint = parseEmailSubmissionBlueprint(
        identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
      )
      .expect("parseEmailSubmissionBlueprint")
    let subCid = parseCreationId("sub34").expect("parseCreationId sub34")
    var subTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    subTbl[subCid] = blueprint
    let (b3, handles) = addEmailSubmissionAndEmailSet(
      initRequestBuilder(),
      submissionAccountId,
      create = Opt.some(subTbl),
      onSuccessUpdateEmail = Opt.some(onSuccess),
    )
    let resp3 = client.send(b3).expect("send EmailSubmission/set+Email/set")
    captureIfRequested(client, "email-submission-on-success-update-stalwart").expect(
      "captureIfRequested"
    )
    let pair = resp3.getBoth(handles).expect("getBoth(EmailSubmissionHandles)")
    var submissionId: Id
    pair.primary.createResults.withValue(subCid, outcome):
      doAssert outcome.isOk,
        "EmailSubmission/set create must succeed: " & outcome.error.rawType
      submissionId = outcome.unsafeValue.id
    do:
      doAssert false, "EmailSubmission/set must report a create outcome"
    pair.implicit.updateResults.withValue(draftId, outcome):
      doAssert outcome.isOk,
        "implicit Email/set update must succeed: " & outcome.error.rawType
    do:
      doAssert false, "implicit Email/set must report an update outcome for draftId"

    # --- Poll until usFinal -----------------------------------------------
    discard pollSubmissionDelivery(client, submissionAccountId, submissionId).expect(
        "pollSubmissionDelivery"
      )

    # --- Read-back via Email/get to verify mailbox + keyword changes -----
    let (b4, emailGetHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[draftId]),
      properties = Opt.some(@["mailboxIds", "keywords"]),
    )
    let resp4 = client.send(b4).expect("send Email/get post-submit")
    let getResp = resp4.get(emailGetHandle).expect("Email/get post-submit extract")
    doAssert getResp.list.len == 1,
      "Email/get must return one entry for the patched draft"
    # Email/get with restricted properties returns a partial entity, so the
    # strict ``emailFromJson`` parser does not apply (Email requires every
    # field). Parse mailboxIds and keywords directly via their typed
    # ``fromJson`` granularities.
    let entity = getResp.list[0]
    let mbIdsNode = entity{"mailboxIds"}
    doAssert not mbIdsNode.isNil, "Email/get must include mailboxIds"
    let mbIdsTyped = MailboxIdSet.fromJson(mbIdsNode).expect("parse MailboxIdSet")
    let mbIds = HashSet[Id](mbIdsTyped)
    doAssert sentId in mbIds,
      "after onSuccessUpdateEmail, draft must be in Sent (mailboxIds=" & $mbIds & ")"
    doAssert draftsId notin mbIds,
      "after onSuccessUpdateEmail, draft must no longer be in Drafts"
    let kwNode = entity{"keywords"}
    doAssert not kwNode.isNil, "Email/get must include keywords"
    let kwTyped = KeywordSet.fromJson(kwNode).expect("parse KeywordSet")
    let kwSet = HashSet[Keyword](kwTyped)
    doAssert seenKw in kwSet, "after patch, $seen must be present"
    doAssert draftKw notin kwSet, "after patch, $draft must be absent"
    client.close()
