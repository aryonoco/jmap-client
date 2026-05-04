# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 59 — wire test of ``Identity/set update`` with all
## five ``IdentityUpdate`` arms (``setName``, ``setReplyTo``,
## ``setBcc``, ``setTextSignature``, ``setHtmlSignature``) packed
## into one update, followed by ``Identity/changes`` from a
## captured baseline.  Closes Phase F31's "no full update arm-set
## inside a changes window" gap and Phase H46's "no full update
## combination" gap.
##
## Workflow:
##
##  1. Resolve submission account; resolve / create alice's
##     identity via ``resolveOrCreateAliceIdentity``.
##  2. Capture baseline state via
##     ``captureBaselineState[Identity]``.
##  3. ``Identity/set update`` packed with all five typed update
##     arms.  Capture the wire response.
##  4. ``Identity/changes`` from the baseline — assert the
##     identity id surfaces in the union of ``created`` /
##     ``updated`` (Stalwart's same-state-window collapse per
##     Phase H46).
##  5. ``Identity/get`` round-trip — assert all five fields
##     parse correctly.
##  6. Cleanup: revert name to a benign default, clear the
##     other four arms.
##
## Capture: ``identity-changes-with-updates-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/identity as jidentity
import ./mcapture
import ./mconfig
import ./mlive

block tidentityChangesWithUpdatesLive:
  forEachLiveTarget(target):
    # James 3.9 compatibility: skipped on James.
    # Reason: Same — Identity/changes is documented as not implemented on James 3.9.
    # When James adds support, remove this guard.
    if target.kind == ltkJames:
      continue
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    let identityId = resolveOrCreateAliceIdentity(client, submissionAccountId).expect(
        "resolveOrCreateAliceIdentity"
      )

    let baselineState = captureBaselineState[Identity](client, submissionAccountId)
      .expect("captureBaselineState[Identity][" & $target.kind & "]")

    let replyAddr = parseEmailAddress("alice+reply@example.com", Opt.none(string))
      .expect("parseEmailAddress reply[" & $target.kind & "]")
    let bccAddr = parseEmailAddress("alice+bcc@example.com", Opt.none(string)).expect(
        "parseEmailAddress bcc"
      )
    const renamedName = "phase-i 59 renamed"
    const textSig = "phase-i 59 text sig"
    const htmlSig = "<p>phase-i 59 html sig</p>"

    let updateSet = initIdentityUpdateSet(
        @[
          jidentity.setName(renamedName),
          setReplyTo(Opt.some(@[replyAddr])),
          setBcc(Opt.some(@[bccAddr])),
          setTextSignature(textSig),
          setHtmlSignature(htmlSig),
        ]
      )
      .expect("initIdentityUpdateSet five arms[" & $target.kind & "]")
    let updates = parseNonEmptyIdentityUpdates(@[(identityId, updateSet)]).expect(
        "parseNonEmptyIdentityUpdates"
      )
    let (bU, updateHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(updates)
    )
    let respU =
      client.send(bU).expect("send Identity/set five-arm update[" & $target.kind & "]")
    captureIfRequested(client, "identity-changes-with-updates-" & $target.kind).expect(
      "captureIfRequested"
    )
    let setRespU = respU.get(updateHandle).expect(
        "Identity/set five-arm extract[" & $target.kind & "]"
      )
    var updateOk = false
    setRespU.updateResults.withValue(identityId, outcome):
      assertOn target,
        outcome.isOk,
        "Identity/set five-arm update must succeed: " & outcome.error.rawType
      updateOk = true
    do:
      assertOn target, false, "Identity/set must report an update outcome"
    assertOn target, updateOk

    # Identity/changes from the baseline state.
    let (bC, changesHandle) = addIdentityChanges(
      initRequestBuilder(), submissionAccountId, sinceState = baselineState
    )
    let respC = client.send(bC).expect("send Identity/changes[" & $target.kind & "]")
    let cr =
      respC.get(changesHandle).expect("Identity/changes extract[" & $target.kind & "]")
    let allDelta = cr.created.toHashSet + cr.updated.toHashSet
    assertOn target,
      identityId in allDelta,
      "identity id must surface in created ∪ updated of the changes delta"

    # Read-back via Identity/get — verify all five fields.
    let (bG, getHandle) = addIdentityGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[identityId])
    )
    let respG =
      client.send(bG).expect("send Identity/get round-trip[" & $target.kind & "]")
    let getResp = respG.get(getHandle).expect(
        "Identity/get round-trip extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp.list.len == 1, "Identity/get must return exactly one record"
    let updated =
      Identity.fromJson(getResp.list[0]).expect("parse Identity[" & $target.kind & "]")
    assertOn target,
      updated.name == renamedName,
      "name must reflect setName update (got " & updated.name & ")"
    assertOn target,
      updated.replyTo.isSome and updated.replyTo.unsafeGet.len == 1 and
        updated.replyTo.unsafeGet[0].email == "alice+reply@example.com",
      "replyTo must round-trip the supplied address"
    assertOn target,
      updated.bcc.isSome and updated.bcc.unsafeGet.len == 1 and
        updated.bcc.unsafeGet[0].email == "alice+bcc@example.com",
      "bcc must round-trip the supplied address"
    assertOn target,
      updated.textSignature == textSig,
      "textSignature must reflect setTextSignature update"
    assertOn target,
      updated.htmlSignature == htmlSig,
      "htmlSignature must reflect setHtmlSignature update"

    # Cleanup — revert name + clear the other four arms.
    let cleanupSet = initIdentityUpdateSet(
        @[
          jidentity.setName("Alice"),
          setReplyTo(Opt.none(seq[EmailAddress])),
          setBcc(Opt.none(seq[EmailAddress])),
          setTextSignature(""),
          setHtmlSignature(""),
        ]
      )
      .expect("initIdentityUpdateSet cleanup[" & $target.kind & "]")
    let cleanupUpdates = parseNonEmptyIdentityUpdates(@[(identityId, cleanupSet)])
      .expect("parseNonEmptyIdentityUpdates cleanup[" & $target.kind & "]")
    let (bX, _) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, update = Opt.some(cleanupUpdates)
    )
    discard client.send(bX).expect("send Identity/set cleanup[" & $target.kind & "]")
    client.close()
