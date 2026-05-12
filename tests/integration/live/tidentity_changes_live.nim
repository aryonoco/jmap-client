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
## ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tidentityChangesLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): Stalwart 0.15.5 implements Identity/{set,
    # changes} fully. James 3.9 binds Identity/changes but
    # ``doc/specs/spec/mail/identity.mdown`` flags it "Not implemented"
    # (response shape is degraded). Cyrus 3.12.2 omits Identity/{set,
    # changes} entirely (``imap/jmap_mail.c:122-123``: "Possibly to be
    # implemented") and returns ``metUnknownMethod``. Each
    # ``assertSuccessOrTypedError`` site exercises the typed-error
    # projection contract uniformly.
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

    # --- Capture baseline state via empty Identity/get ------------------
    let baselineState = captureBaselineState[Identity](client, submissionAccountId)
      .expect("captureBaselineState[Identity][" & $target.kind & "]")

    # --- Mutate: create one Identity ------------------------------------
    let createCid =
      parseCreationId("phaseHStep46").expect("parseCreationId[" & $target.kind & "]")
    # Stalwart only allows Identity create for email addresses that are
    # configured for the account; alice@example.com is Alice's seeded
    # primary, so reusing it here ensures the create succeeds. Multiple
    # Identities can share an email (per ``tidentity_set_crud_live``);
    # the unique ``name`` is what differentiates this test's identity
    # from any pre-existing alice@example.com identity.
    let createIdent = parseIdentityCreate(
        email = "alice@example.com", name = "phase-h step-46"
      )
      .expect("parseIdentityCreate[" & $target.kind & "]")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[createCid] = createIdent
    let (bCreate, createHandle) = addIdentitySet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(createTbl),
    )
    let respCreate = client.send(bCreate.freeze()).expect(
        "send Identity/set create[" & $target.kind & "]"
      )
    let createExtract = respCreate.get(createHandle)
    var identityId: Id
    var createOk = false
    assertSuccessOrTypedError(target, createExtract, {metUnknownMethod}):
      let setResp = success
      setResp.createResults.withValue(createCid, outcome):
        assertOn target,
          outcome.isOk, "Identity/set create must succeed: " & outcome.error.rawType
        identityId = outcome.unsafeValue.id
        createOk = true
      do:
        assertOn target, false, "Identity/set must report a create result"

    # --- Happy path: Identity/changes since baseline --------------------
    if createOk:
      let (bHappy, happyHandle) = addIdentityChanges(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        sinceState = baselineState,
      )
      let respHappy = client.send(bHappy.freeze()).expect(
          "send Identity/changes happy[" & $target.kind & "]"
        )
      let happyExtract = respHappy.get(happyHandle)
      assertSuccessOrTypedError(target, happyExtract, {metUnknownMethod}):
        let cr = success
        assertOn target,
          string(cr.oldState) == string(baselineState),
          "oldState must echo the supplied baseline"
        # James 3.9 binds Identity/changes but reports it "Not
        # implemented" — the response shape is well-formed but the
        # delta is empty. Stalwart correctly surfaces the newly-
        # created identity id. Both are accepted: the wire-shape
        # parse is the universal client-library contract.
        if cr.created.len > 0:
          assertOn target,
            identityId in cr.created,
            "newly created Identity id must surface in cr.created when delta is " &
              "non-empty (got created=" & $cr.created & ")"
        assertOn target, cr.hasMoreChanges == false, "no further changes pending"

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = JmapState("phase-h-46-bogus-state")
    let (bSad, sadHandle) = addIdentityChanges(
      initRequestBuilder(makeBuilderId()), submissionAccountId, sinceState = bogusState
    )
    let respSad = client.send(bSad.freeze()).expect(
        "send Identity/changes bogus[" & $target.kind & "]"
      )
    captureIfRequested(client, "identity-changes-bogus-state-" & $target.kind).expect(
      "captureIfRequested"
    )
    let sadExtract = respSad.get(sadHandle)
    assertOn target,
      sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let getErr = sadExtract.error
    doAssert getErr.kind == gekMethod, "expected gekMethod"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in
        {metCannotCalculateChanges, metInvalidArguments, metUnknownMethod},
      "method error must project as cannotCalculateChanges, invalidArguments, or " &
        "unknownMethod (got rawType=" & methodErr.rawType & ")"

    # --- Cleanup: destroy the test-created Identity ---------------------
    if createOk:
      let (bCleanup, cleanupHandle) = addIdentitySet(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        destroy = directIds(@[identityId]),
      )
      discard client.send(bCleanup.freeze())
      discard cleanupHandle
    client.close()
