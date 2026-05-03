# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Identity/changes (RFC 8621 §6.2) against
## Stalwart. Phase H Step 46 — first wire test of
## ``addIdentityChanges``. Identity carries the
## ``urn:ietf:params:jmap:submission`` capability URI per
## ``mail/mail_entities.nim``; the helper auto-registers it so the
## ``using`` array is correct.
##
## Two paths:
##  1. **Happy path** — capture baseline ``state`` via
##     ``captureBaselineState[Identity]`` (mlive H0); create one
##     Identity via ``Identity/set``; ``Identity/changes`` since
##     baseline. Assert ``oldState`` echoes the baseline, the
##     created id surfaces in ``cr.created``, and
##     ``hasMoreChanges == false``.
##  2. **Sad path** — bogus ``sinceState``; assert the §5.5 method
##     error projects as ``cannotCalculateChanges`` or
##     ``invalidArguments`` (set-membership; Phase B Step 11
##     precedent at ``temail_changes_live.nim:96-98``).
##
## Cleanup: destroy the test-created Identity at the end so
## subsequent runs re-create rather than accumulate. No assertion on
## the destroy outcome — best-effort idempotency hygiene.
##
## Capture: ``identity-changes-bogus-state-stalwart`` after the sad-
## path send. Listed in ``tests/testament_skip.txt`` so ``just test``
## skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on
## ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tidentityChangesLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")

    # --- Capture baseline state via empty Identity/get ------------------
    let baselineState = captureBaselineState[Identity](client, submissionAccountId)
      .expect("captureBaselineState[Identity]")

    # --- Mutate: create one Identity ------------------------------------
    let createCid = parseCreationId("phaseHStep46").expect("parseCreationId")
    # Stalwart only allows Identity create for email addresses that are
    # configured for the account; alice@example.com is Alice's seeded
    # primary, so reusing it here ensures the create succeeds. Multiple
    # Identities can share an email (per ``tidentity_set_crud_live``);
    # the unique ``name`` is what differentiates this test's identity
    # from any pre-existing alice@example.com identity.
    let createIdent = parseIdentityCreate(
        email = "alice@example.com", name = "phase-h step-46"
      )
      .expect("parseIdentityCreate")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[createCid] = createIdent
    let (bCreate, createHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(createTbl)
    )
    let respCreate = client.send(bCreate).expect("send Identity/set create")
    let setResp = respCreate.get(createHandle).expect("Identity/set create extract")
    var identityId: Id
    var createOk = false
    setResp.createResults.withValue(createCid, outcome):
      doAssert outcome.isOk,
        "Identity/set create must succeed: " & outcome.error.rawType
      identityId = outcome.unsafeValue.id
      createOk = true
    do:
      doAssert false, "Identity/set must report a create result"
    doAssert createOk

    # --- Happy path: Identity/changes since baseline --------------------
    let (bHappy, happyHandle) = addIdentityChanges(
      initRequestBuilder(), submissionAccountId, sinceState = baselineState
    )
    let respHappy = client.send(bHappy).expect("send Identity/changes happy")
    let cr = respHappy.get(happyHandle).expect("Identity/changes happy extract")
    doAssert string(cr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    doAssert identityId in cr.created,
      "newly created Identity id must surface in cr.created (got created=" & $cr.created &
        ")"
    doAssert cr.hasMoreChanges == false, "no further changes pending"

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = JmapState("phase-h-46-bogus-state")
    let (bSad, sadHandle) = addIdentityChanges(
      initRequestBuilder(), submissionAccountId, sinceState = bogusState
    )
    let respSad = client.send(bSad).expect("send Identity/changes bogus")
    captureIfRequested(client, "identity-changes-bogus-state-stalwart").expect(
      "captureIfRequested"
    )
    let sadExtract = respSad.get(sadHandle)
    doAssert sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = sadExtract.error
    doAssert methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"

    # --- Cleanup: destroy the test-created Identity ---------------------
    let (bCleanup, cleanupHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, destroy = directIds(@[identityId])
    )
    discard client.send(bCleanup)
    discard cleanupHandle
    client.close()
