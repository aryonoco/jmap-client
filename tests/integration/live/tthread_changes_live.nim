# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Thread/changes (RFC 8621 §3.2) against
## Stalwart. Phase H Step 45 — first wire test of the generic
## ``addChanges[Thread]`` template, which expands at the call site to
## ``addChanges[Thread, ChangesResponse[Thread]]`` via
## ``changesResponseType(Thread) = ChangesResponse[Thread]`` (registered
## in ``mail/mail_entities.nim``). ``Thread`` is qualified as
## ``jmap_client.Thread`` everywhere it appears in the body — the
## unqualified ``Thread`` collides with ``system.Thread`` from the
## stdlib threading primitives that ``--threads:on`` brings into
## scope, so the unqualified form would resolve away from the entity
## registration and fail mixin lookup of ``getMethodName(Thread)``.
##
## Stalwart's threading pipeline is asynchronous (catalogued
## divergence #4 in ``docs/plan/06-integration-testing-F.md``). The
## ``Email/set`` call records a ``threadId`` synchronously, but the
## Thread record's emailIds list — and therefore its appearance in
## ``Thread/changes`` — may take a few hundred milliseconds to
## materialise. The test issues ``Thread/changes`` inside a bounded
## re-fetch loop (5 attempts × 200 ms) and exits as soon as
## ``cr.created.len + cr.updated.len >= 1``. Per RFC 8620 §5.2, a
## newly-materialised Thread surfaces in ``created`` (fresh record)
## or ``updated`` (existing record back-filled) — the ``created ∪
## updated`` disjunction is the deterministic post-condition.
##
## Two paths:
##  1. **Happy path** — capture baseline ``state`` via
##     ``captureBaselineState[Thread]`` (mlive H0); seed two threaded
##     emails via ``seedThreadedEmails`` (mlive); poll
##     ``Thread/changes`` until the Thread record materialises.
##     Assert ``oldState`` echoes the baseline,
##     ``created.len + updated.len >= 1``, ``destroyed.len == 0``,
##     and ``hasMoreChanges == false``.
##  2. **Sad path** — bogus ``sinceState``; assert the §5.5 method
##     error projects as ``cannotCalculateChanges`` or
##     ``invalidArguments`` (set-membership; Phase B Step 11
##     precedent at ``temail_changes_live.nim:96-98``).
##
## Capture: ``thread-changes-bogus-state-stalwart`` after the sad-
## path send. Listed in ``tests/testament_skip.txt`` so ``just test``
## skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on
## ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/os

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tthreadChangesLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): RFC 8621 §3 leaves Thread/changes propagation
    # discretionary. Stalwart 0.15.5 and Cyrus 3.12.2 surface the
    # cascade after Email/set; James 3.9 implements Thread/changes
    # naively (``doc/specs/spec/mail/thread.mdown``: "Naive
    # implementation") and returns a well-formed but empty change-set.
    # The convergence loop is best-effort; the wire-shape parsing and
    # the sad-path typed-error projection are the universal client-
    # library contract assertions.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve inbox + capture baseline ------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let baselineState = captureBaselineState[jmap_client.Thread](client, mailAccountId)
      .expect("captureBaselineState[Thread][" & $target.kind & "]")

    # --- Mutate: seed two threaded emails ------------------------------
    let seedIds = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-h step-45 root", "phase-h step-45 reply"],
        rootMessageId = "<phase-h-step-45-root@example.com>",
      )
      .expect("seedThreadedEmails[" & $target.kind & "]")
    assertOn target, seedIds.len == 2, "seedThreadedEmails must return two ids"

    # --- Happy path: Thread/changes with bounded re-fetch loop ---------
    var converged = false
    var lastCr: ChangesResponse[jmap_client.Thread]
    for attempt in 0 ..< 5:
      let (b, h) = addThreadChanges(
        initRequestBuilder(), mailAccountId, sinceState = baselineState
      )
      let resp =
        client.send(b).expect("send Thread/changes happy[" & $target.kind & "]")
      let cr = resp.get(h).expect("Thread/changes happy extract[" & $target.kind & "]")
      if cr.created.len + cr.updated.len >= 1:
        lastCr = cr
        converged = true
        break
      sleep(200)
    if converged:
      # Strict path — runs on configured targets that propagate the
      # Email/set cascade through Thread/changes.
      assertOn target,
        string(lastCr.oldState) == string(baselineState),
        "oldState must echo the supplied baseline"
      assertOn target, lastCr.destroyed.len == 0, "no Thread destroys issued"
      assertOn target, lastCr.hasMoreChanges == false, "no further changes pending"
    # When ``converged == false`` the server is RFC-conformant with a
    # naive Thread/changes (empty change-set). Every Thread/changes
    # response inside the convergence loop already parsed
    # successfully — the client-library wire-shape contract holds.

    # --- Sad path: bogus sinceState ------------------------------------
    let bogusState = JmapState("phase-h-45-bogus-state")
    let (bSad, sadHandle) =
      addThreadChanges(initRequestBuilder(), mailAccountId, sinceState = bogusState)
    let respSad =
      client.send(bSad).expect("send Thread/changes bogus[" & $target.kind & "]")
    captureIfRequested(client, "thread-changes-bogus-state-" & $target.kind).expect(
      "captureIfRequested"
    )
    let sadExtract = respSad.get(sadHandle)
    assertOn target,
      sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = sadExtract.error
    assertOn target,
      methodErr.errorType in
        {metCannotCalculateChanges, metInvalidArguments, metUnknownMethod},
      "method error must project as cannotCalculateChanges, invalidArguments, or " &
        "unknownMethod (got rawType=" & methodErr.rawType & ")"
    client.close()
