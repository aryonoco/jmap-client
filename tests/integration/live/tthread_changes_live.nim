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
## ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/os
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tthreadChangesLive:
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

    # --- Resolve inbox + capture baseline ------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let baselineState = captureBaselineState[jmap_client.Thread](client, mailAccountId)
      .expect("captureBaselineState[Thread]")

    # --- Mutate: seed two threaded emails ------------------------------
    let seedIds = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-h step-45 root", "phase-h step-45 reply"],
        rootMessageId = "<phase-h-step-45-root@example.com>",
      )
      .expect("seedThreadedEmails")
    doAssert seedIds.len == 2, "seedThreadedEmails must return two ids"

    # --- Happy path: Thread/changes with bounded re-fetch loop ---------
    var converged = false
    var lastCr: ChangesResponse[jmap_client.Thread]
    for attempt in 0 ..< 5:
      let (b, h) = addChanges[jmap_client.Thread](
        initRequestBuilder(), mailAccountId, sinceState = baselineState
      )
      let resp = client.send(b).expect("send Thread/changes happy")
      let cr = resp.get(h).expect("Thread/changes happy extract")
      if cr.created.len + cr.updated.len >= 1:
        lastCr = cr
        converged = true
        break
      sleep(200)
    doAssert converged,
      "Stalwart Thread/changes did not converge within 1 s — extend re-fetch budget " &
        "or investigate Stalwart 0.15.5 threading pipeline"
    doAssert string(lastCr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    doAssert lastCr.destroyed.len == 0, "no Thread destroys issued"
    doAssert lastCr.hasMoreChanges == false, "no further changes pending"

    # --- Sad path: bogus sinceState ------------------------------------
    let bogusState = JmapState("phase-h-45-bogus-state")
    let (bSad, sadHandle) = addChanges[jmap_client.Thread](
      initRequestBuilder(), mailAccountId, sinceState = bogusState
    )
    let respSad = client.send(bSad).expect("send Thread/changes bogus")
    captureIfRequested(client, "thread-changes-bogus-state-stalwart").expect(
      "captureIfRequested"
    )
    let sadExtract = respSad.get(sadHandle)
    doAssert sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = sadExtract.error
    doAssert methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"
    client.close()
