# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Mailbox/get with ``ids: null`` (RFC 8621
## §2.4) against Stalwart. Fetches every mailbox in Alice's account and
## asserts the seeded inbox is among them with sensible ``myRights``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tmailboxGetAllLive:
  forEachLiveTarget(target):
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let (b1, mbHandle) =
      addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
    let resp = client.send(b1.freeze()).expect("send[" & $target.kind & "]")
    captureIfRequested(recorder.lastResponseBody, "mailbox-get-all-" & $target.kind)
      .expect("captureIfRequested[" & $target.kind & "]")
    let gr = resp.get(mbHandle).expect("Mailbox/get extract[" & $target.kind & "]")
    assertOn target, gr.list.len >= 1, "alice's account must have at least one mailbox"
    var sawInbox = false
    for mb in gr.list:
      assertOn target, mb.name.len > 0, "every mailbox must have a non-empty name"
      assertOn target,
        mb.myRights.mayReadItems, "alice must have read rights on her own mailbox"
      for role in mb.role:
        if role == roleInbox:
          sawInbox = true
    assertOn target, sawInbox, "alice's account must include an inbox-role mailbox"
