# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 51 — wire test of ``Email/queryChanges`` with a
## filter that differs from the original ``Email/query``'s filter.
## RFC 8620 §5.6: "If the filter or sort includes a property the
## client does not understand, OR if the filter/sort has changed
## since the previous queryState, the server MAY return a
## ``cannotCalculateChanges`` error."  Closes Phase C12 deferral.
##
## **RFC ambiguity → set-membership assertion.** RFC 8620 §5.6 uses
## "MAY" — Stalwart is free to either reject the call or silently
## recompute the delta against the new filter.  This test asserts
## set membership: either ``Err`` projects to one of
## ``metCannotCalculateChanges`` / ``metInvalidArguments``, or
## ``Ok`` carries a structurally valid ``QueryChangesResponse[Email]``
## with a non-empty ``oldQueryState`` matching the supplied baseline.
## Both outcomes are RFC-conformant; capturing whichever Stalwart
## emits at this version pins the empirical pin for Phase J's
## divergences catalogue.
##
## Workflow:
##
##  1. Seed three emails with subjects ``phase-i 51 alpha`` /
##     ``bravo`` / ``charlie`` so a substring-on-prefix filter
##     matches all three and a substring-on-distinctive-token
##     matches one.
##  2. Original ``Email/query`` with ``filter = subject "phase-i
##     51"``.  Capture ``queryState``.
##  3. Mismatched ``Email/queryChanges`` with ``sinceQueryState =
##     queryState`` and ``filter = subject "phase-i 51 alpha"``.
##     Capture the wire response and assert RFC-conformant outcome
##     (Err on a permitted MethodErrorType, or Ok carrying a valid
##     QueryChangesResponse).
##
## Capture: ``email-query-changes-filter-mismatch-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailQueryChangesFilterMismatchLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): test asserts on client behaviour, not on
    # specific server implementations. Stalwart 0.15.5 and Cyrus 3.12.2
    # implement Email/queryChanges; James 3.9 emits a typed JMAP error
    # (Email/queryChanges unregistered). The success arm verifies the
    # RFC 8620 §5.6 set-membership outcome; the error arm verifies the
    # client's typed-error projection across configured targets.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let seededIds = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @["phase-i 51 alpha", "phase-i 51 bravo", "phase-i 51 charlie"],
      )
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target,
      seededIds.len == 3, "three seeded ids expected (got " & $seededIds.len & ")"

    let filterA = filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 51")))
    let (b1, h1) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filterA)
    )
    let resp1 =
      client.send(b1.freeze()).expect("send Email/query baseline[" & $target.kind & "]")
    let qResp1 =
      resp1.get(h1).expect("Email/query baseline extract[" & $target.kind & "]")
    let queryStateA = qResp1.queryState

    let filterB =
      filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 51 alpha")))
    let (b2, h2) = addEmailQueryChanges(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      sinceQueryState = queryStateA,
      filter = Opt.some(filterB),
    )
    let resp2 = client.send(b2.freeze()).expect(
        "send Email/queryChanges mismatched filter[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-query-changes-filter-mismatch-" & $target.kind)
      .expect("captureIfRequested")
    let extract = resp2.get(h2)
    assertSuccessOrTypedError(
      target,
      extract,
      {metCannotCalculateChanges, metInvalidArguments, metUnknownMethod},
    ):
      let qcr = success
      assertOn target,
        string(qcr.oldQueryState) == string(queryStateA),
        "success arm: oldQueryState must echo the supplied baseline"

    client.close()
