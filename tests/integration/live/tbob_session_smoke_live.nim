# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test exercising the second seeded principal's
## bearer token end-to-end. First non-alice authentication in the
## campaign (Phase A–F all ran exclusively as alice). Validates that
## ``JMAP_TEST_BOB_TOKEN`` round-trips through ``initJmapClient``, that
## bob's session payload deserialises, that bob's primary mail account
## is genuinely his (not a shared view onto alice's), and that bob's
## inbox-role mailbox surfaces via ``Mailbox/get``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tBobSessionSmokeLive:
  forEachLiveTarget(target):
    var bobClient = initBobClient(target).expect("initBobClient[" & $target.kind & "]")
    let session = bobClient.fetchSession().expect("fetchSession[" & $target.kind & "]")
    captureIfRequested(bobClient, "bob-session-" & $target.kind).expect(
      "captureIfRequested[" & $target.kind & "]"
    )
    assertOn target,
      session.accounts.len >= 1,
      "bob's session must advertise at least one account (got " & $session.accounts.len &
        ")"

    let bobMailAccountId = resolveMailAccountId(session).expect(
        "resolveMailAccountId bob[" & $target.kind & "]"
      )

    let bobAccount = session.findAccount(bobMailAccountId)
    assertOn target,
      bobAccount.isSome, "bob's primary mail accountId must resolve in session.accounts"
    let acc = bobAccount.unsafeGet
    assertOn target,
      acc.isPersonal, "bob's primary mail account must be marked isPersonal=true"
    assertOn target,
      not acc.isReadOnly,
      "bob's primary mail account must not be read-only (got isReadOnly=true)"

    let (b1, mbHandle) =
      addMailboxGet(initRequestBuilder(makeBuilderId()), bobMailAccountId)
    let resp =
      bobClient.send(b1.freeze()).expect("send Mailbox/get[" & $target.kind & "]")
    let gr = resp.get(mbHandle).expect("Mailbox/get extract[" & $target.kind & "]")
    assertOn target,
      gr.list.len >= 1,
      "bob's account must have at least one mailbox (got " & $gr.list.len & ")"
    var sawInbox = false
    for mb in gr.list:
      for role in mb.role:
        if role == roleInbox:
          sawInbox = true
    assertOn target, sawInbox, "bob's account must include an inbox-role mailbox"
    bobClient.close()
