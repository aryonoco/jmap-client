# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Mailbox/get with ``ids: null`` (RFC 8621
## §2.4) against Stalwart. Fetches every mailbox in Alice's account and
## asserts the seeded inbox is among them with sensible ``myRights``.
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

block tmailboxGetAllLive:
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
    let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
    let resp = client.send(b1).expect("send")
    captureIfRequested(client, "mailbox-get-all-stalwart").expect("captureIfRequested")
    let gr = resp.get(mbHandle).expect("Mailbox/get extract")
    doAssert gr.list.len >= 1, "alice's account must have at least one mailbox"
    var sawInbox = false
    for node in gr.list:
      let mb = Mailbox.fromJson(node).expect("parse Mailbox")
      doAssert mb.name.len > 0, "every mailbox must have a non-empty name"
      doAssert mb.myRights.mayReadItems,
        "alice must have read rights on her own mailbox"
      for role in mb.role:
        if role == roleInbox:
          sawInbox = true
    doAssert sawInbox, "alice's account must include an inbox-role mailbox"
    client.close()
