# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/changes (RFC 8620 §5.2) against
## Stalwart. Two paths exercised in one test:
##
## 1. **Happy path** — capture a baseline ``state`` from an empty
##    Email/get, seed two new Emails via mlive helpers, then issue
##    Email/changes with ``sinceState=baseline``. Asserts both seeded
##    ids surface in ``created`` and that ``oldState`` matches the
##    baseline.
## 2. **Sad path** — issue Email/changes with a synthetic bogus
##    ``sinceState``. RFC 8620 §5.2 permits the server to respond with
##    either ``cannotCalculateChanges`` or ``invalidArguments``; the
##    test accepts both, asserting the projected ``MethodErrorType``
##    against that pair.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailChangesLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    # --- Capture baseline state via an empty Email/get -------------------
    let (b1, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[]),
      properties = Opt.some(@["id"]),
    )
    let resp1 = client.send(b1).expect("send Email/get baseline")
    let getResp = resp1.get(getHandle).expect("Email/get baseline extract")
    let baselineState = getResp.state

    # --- Seed two emails via mlive --------------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let idA = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-11 a", "seedA"
      )
      .expect("seedSimpleEmail A")
    let idB = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-11 b", "seedB"
      )
      .expect("seedSimpleEmail B")

    # --- Happy path: Email/changes since baseline -----------------------
    let (b2, changesHandle) =
      addChanges[Email](initRequestBuilder(), mailAccountId, sinceState = baselineState)
    let resp2 = client.send(b2).expect("send Email/changes happy")
    let cr = resp2.get(changesHandle).expect("Email/changes happy extract")
    doAssert string(cr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    doAssert cr.created.len == 2,
      "two seeds must surface as two created entries (got " & $cr.created.len & ")"
    doAssert cr.updated.len == 0, "no updates issued — updated must be empty"
    doAssert cr.destroyed.len == 0, "no destroys issued — destroyed must be empty"
    doAssert idA in cr.created, "seed A must appear in created"
    doAssert idB in cr.created, "seed B must appear in created"

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = JmapState("phase-b-bogus-state")
    let (b3, sadHandle) =
      addChanges[Email](initRequestBuilder(), mailAccountId, sinceState = bogusState)
    let resp3 = client.send(b3).expect("send Email/changes bogus")
    captureIfRequested(client, "email-changes-bogus-state-stalwart").expect(
      "captureIfRequested"
    )
    let sadExtract = resp3.get(sadHandle)
    doAssert sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = sadExtract.error
    doAssert methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"
    client.close()
