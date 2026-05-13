# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: typed update arms (``IdentityUpdate.setX`` /
## ``MailboxUpdate.setX``) emit flat JSON keys correctly:
## ``Opt.none → null``, signature-clear via empty string, parentId
## set-to-null, and similar.  Deep-path PatchObject expressions
## (``replyTo/0/name``) and JSON-Pointer escape sequences
## (``~0`` / ``~1``) are NOT exposed via the typed surface — they
## go through ``sendRawInvocation`` with hand-rolled JSON.
##
## Phase J Step 70.  Four sub-tests:
## A. typed-arm flat patch on Identity (``setName`` + signature
##    clear via empty string).
## B. typed-arm flat patch on Mailbox (``setParentId(Opt.none)``).
## C. deep-path patch via raw JSON (``replyTo/0/name`` on Identity).
## D. JSON-Pointer escape via raw JSON (``keywords/$tag~1with~1slash``).
##
## **Library-contract vs server-compliance separation.**  Sub-tests
## A and B verify the typed builder's wire emission directly via
## read-back.  Sub-tests C and D drive Stalwart through patch
## shapes the typed surface does not generate; the captured
## fixture pins Stalwart's empirical projection (success or
## ``setInvalidPatch`` / ``setInvalidProperties``).

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/mail/identity as jidentity
import jmap_client/internal/mail/mailbox as jmailbox
import jmap_client/internal/types/envelope
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tpatchObjectDeepPathsLive:
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

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    # Sub-test A: typed-arm flat patch on Identity.
    block typedIdentityPatchCase:
      # Cat-B: Cyrus 3.12.2 has no ``Identity/set`` (returns
      # ``metUnknownMethod``); Stalwart and James implement it. The
      # success arm verifies the typed-arm flat-patch round-trip; the
      # error arm verifies the typed-error projection.
      let setNameUpdate = jidentity.setName("phase-j 70 renamed")
      let setSigUpdate = setTextSignature("")
      let updateSet = initIdentityUpdateSet(@[setNameUpdate, setSigUpdate]).expect(
          "initIdentityUpdateSet"
        )
      let updates = parseNonEmptyIdentityUpdates(@[(identityId, updateSet)]).expect(
          "parseNonEmptyIdentityUpdates"
        )
      let (b, setHandle) = addIdentitySet(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        update = Opt.some(updates),
      )
      let resp = client.send(b.freeze()).expect(
          "send Identity/set typed flat patch[" & $target.kind & "]"
        )
      let setExtract = resp.get(setHandle)
      var identityUpdateOk = false
      if setExtract.isOk:
        let setResp = setExtract.unsafeValue
        setResp.updateResults.withValue(identityId, outcome):
          if outcome.isOk:
            identityUpdateOk = true
        do:
          assertOn target, false, "Identity/set must report an outcome"
      else:
        let getErr = setExtract.unsafeError
        doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
        let methodErr = getErr.methodErr
        assertOn target,
          methodErr.errorType == metUnknownMethod,
          "Identity/set must surface as metUnknownMethod when unimplemented (got " &
            methodErr.rawType & ")"

      # Read back via Identity/get to verify the flat-key wire emission
      # — only when the upstream update succeeded.
      if identityUpdateOk:
        let (b2, getHandle) = addIdentityGet(
          initRequestBuilder(makeBuilderId()),
          submissionAccountId,
          ids = directIds(@[identityId]),
        )
        let resp2 = client.send(b2.freeze()).expect(
            "send Identity/get readback[" & $target.kind & "]"
          )
        let getResp =
          resp2.get(getHandle).expect("Identity/get extract[" & $target.kind & "]")
        assertOn target, getResp.list.len == 1
        let ident = getResp.list[0]
        assertOn target,
          ident.name == "phase-j 70 renamed",
          "name update must round-trip; got " & ident.name
        assertOn target,
          ident.textSignature == "",
          "textSignature clear via empty string must round-trip; got " &
            ident.textSignature

    # Sub-test B: typed-arm flat patch on Mailbox — setParentId(none).
    # Set up a child mailbox first so the parentId field is non-null
    # before the test patches it to null.
    block typedMailboxPatchCase:
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let childId = resolveOrCreateMailbox(client, mailAccountId, "phase-j-70-child")
        .expect("resolveOrCreateMailbox[" & $target.kind & "]")
      assertOn target, $childId != $inbox

      let setParent = jmailbox.setParentId(Opt.none(Id))
      let mUpdateSet = initMailboxUpdateSet(@[setParent]).expect(
          "initMailboxUpdateSet[" & $target.kind & "]"
        )
      let mUpdates = parseNonEmptyMailboxUpdates(@[(childId, mUpdateSet)]).expect(
          "parseNonEmptyMailboxUpdates"
        )
      let (b, setHandle) = addMailboxSet(
        initRequestBuilder(makeBuilderId()), mailAccountId, update = Opt.some(mUpdates)
      )
      let resp = client.send(b.freeze()).expect(
          "send Mailbox/set typed flat patch[" & $target.kind & "]"
        )
      let setResp =
        resp.get(setHandle).expect("Mailbox/set extract[" & $target.kind & "]")
      setResp.updateResults.withValue(childId, outcome):
        assertOn target,
          outcome.isOk,
          "Mailbox/set typed flat patch must succeed; got " & outcome.error.rawType
      do:
        assertOn target, false, "Mailbox/set must report an outcome"

      # Read back to verify parentId is now null.
      let (b2, getHandle) = addMailboxGet(
        initRequestBuilder(makeBuilderId()), mailAccountId, ids = directIds(@[childId])
      )
      let resp2 = client.send(b2.freeze()).expect(
          "send Mailbox/get readback[" & $target.kind & "]"
        )
      let getResp =
        resp2.get(getHandle).expect("Mailbox/get extract[" & $target.kind & "]")
      assertOn target, getResp.list.len == 1
      let mb = getResp.list[0]
      assertOn target,
        mb.parentId.isNone, "parentId set-to-null must round-trip as Opt.none"

      # Cleanup: destroy the child mailbox.
      let (bDestroy, destroyHandle) = addMailboxSet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        destroy = directIds(@[childId]),
      )
      let respDestroy = client.send(bDestroy.freeze()).expect(
          "send Mailbox/set destroy[" & $target.kind & "]"
        )
      let destroyResp = respDestroy.get(destroyHandle).expect(
          "Mailbox/set extract[" & $target.kind & "]"
        )
      destroyResp.destroyResults.withValue(childId, outcome):
        assertOn target, outcome.isOk, "child mailbox cleanup destroy must succeed"
      do:
        assertOn target, false, "Mailbox/set must report destroy outcome"

    # Sub-test C: deep-path patch via raw JSON.  Stalwart's
    # PatchObject support varies — set-membership accepts success
    # (deep patch applied) OR rejection (setInvalidPatch /
    # setInvalidProperties).  Captured fixture pins the choice.
    block deepPathPatchCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:submission"],
          methodName = "Identity/set",
          arguments = %*{
            "accountId": $submissionAccountId,
            "update": {$identityId: {"replyTo/0/name": "phase-j 70 deep"}},
          },
        )
        .expect("sendRawInvocation deepPath[" & $target.kind & "]")
      captureIfRequested(client, "patch-object-deep-paths-" & $target.kind).expect(
        "captureIfRequested deepPath"
      )
      assertOn target, resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      assertOn target,
        inv.rawName == "Identity/set" or inv.rawName == "error",
        "expected Identity/set or error, got " & inv.rawName
      if inv.rawName == "Identity/set":
        let setResp = SetResponse[IdentityCreatedItem, PartialIdentity]
          .fromJson(inv.arguments)
          .expect("SetResponse[IdentityCreatedItem, PartialIdentity].fromJson")
        setResp.updateResults.withValue(identityId, outcome):
          assertOn target,
            outcome.isErr, "deep-path patch must surface as Err on updateResults rail"
          let se = outcome.error
          assertOn target, se.rawType.len > 0
          assertOn target,
            se.errorType in
              {setInvalidPatch, setInvalidProperties, setForbidden, setUnknown},
            "errorType must project into the closed enum, got " & $se.errorType
        do:
          assertOn target,
            false, "Identity/set must report an outcome for the patched id"

    # Sub-test D: JSON-Pointer escape ``~1`` for ``/`` in keyword
    # name.  Same set-membership contract as sub-test C.
    block jsonPointerEscapeCase:
      let inbox = resolveInboxId(client, mailAccountId).expect(
          "resolveInboxId[" & $target.kind & "]"
        )
      let seedId = seedSimpleEmail(
          client, mailAccountId, inbox, "phase-j 70 escape seed", "phase-j-70-escape"
        )
        .expect("seedSimpleEmail[" & $target.kind & "]")
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/set",
          arguments = %*{
            "accountId": $mailAccountId,
            "update": {$seedId: {"keywords/$tag~1with~1slash": true}},
          },
        )
        .expect("sendRawInvocation jsonPointerEscape[" & $target.kind & "]")
      assertOn target, resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      assertOn target,
        inv.rawName == "Email/set" or inv.rawName == "error",
        "expected Email/set or error, got " & inv.rawName
      if inv.rawName == "Email/set":
        # Stalwart's response shape varies — could be success
        # (updated) or rejection (notUpdated).  Library contract
        # holds for both at the raw JSON level.
        let notUpdated = inv.arguments{"notUpdated"}
        let updated = inv.arguments{"updated"}
        let hasResolution = (not notUpdated.isNil) or (not updated.isNil)
        assertOn target,
          hasResolution,
          "Stalwart must report some resolution for the patch; got " & $inv.arguments

      # Cleanup: destroy the seed email.
      let (bClean, cleanHandle) = addEmailSet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        destroy = directIds(@[seedId]),
      )
      let respClean = client.send(bClean.freeze()).expect(
          "send Email/set cleanup[" & $target.kind & "]"
        )
      let cleanResp = respClean.get(cleanHandle).expect(
          "Email/set cleanup extract[" & $target.kind & "]"
        )
      cleanResp.destroyResults.withValue(seedId, outcome):
        assertOn target, outcome.isOk, "cleanup destroy must succeed"
      do:
        assertOn target, false, "cleanup must report an outcome"

    client.close()
