# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Thread/get (RFC 8621 §3) against Stalwart.
## Seeds a single Email, reads back its ``threadId`` via ``Email/get``,
## then issues ``Thread/get`` for that id and asserts the thread carries
## the seeded message in its ``emailIds`` list.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Stalwart's threading pipeline is asynchronous — the ``threadId`` is
## assigned synchronously by Email/set, but the Thread record itself
## may be populated a few hundred milliseconds later. The test retries
## ``Thread/get`` up to five times with a 100 ms backoff; the parser
## invariant (``parseThread`` requires non-empty ``emailIds``) is
## preserved per RFC 8621 §3 — the retry loop accommodates server
## asynchrony, not a parser limitation.

import std/json
import std/os
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/thread as jthread
import ./mcapture
import ./mconfig
import ./mlive

block tthreadGetLive:
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

    # --- Seed: resolve inbox + create email ------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let seededId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-8 seed", "seedThread"
      )
      .expect("seedSimpleEmail")

    # --- Resolve threadId via Email/get ----------------------------------
    let (b1, emailHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "threadId"]),
    )
    let resp1 = client.send(b1).expect("send Email/get")
    let emailResp = resp1.get(emailHandle).expect("Email/get extract")
    doAssert emailResp.list.len == 1, "Email/get must return the seeded message"
    let threadIdNode = emailResp.list[0]{"threadId"}
    doAssert not threadIdNode.isNil,
      "Email/get must include threadId when requested in properties"
    let threadId =
      parseIdFromServer(threadIdNode.getStr("")).expect("parseIdFromServer threadId")

    # --- Thread/get with bounded retry for async population --------------
    var thread = Opt.none(jthread.Thread)
    for attempt in 0 ..< 5:
      let (b2, threadHandle) = addGet[jthread.Thread](
        initRequestBuilder(), mailAccountId, ids = directIds(@[threadId])
      )
      let resp2 = client.send(b2).expect("send Thread/get")
      let threadResp = resp2.get(threadHandle).expect("Thread/get extract")
      if threadResp.list.len == 1:
        let parsed = jthread.Thread.fromJson(threadResp.list[0])
        if parsed.isOk:
          thread = Opt.some(parsed.get())
          break
      sleep(100)

    doAssert thread.isSome, "Thread/get must return the seeded thread within 500 ms"
    captureIfRequested(client, "thread-get-stalwart").expect("captureIfRequested")
    let t = thread.get()
    doAssert string(t.id) == string(threadId),
      "returned Thread.id must match the threadId from Email/get"
    doAssert seededId in t.emailIds, "seeded EmailId must appear in Thread.emailIds"
    client.close()
