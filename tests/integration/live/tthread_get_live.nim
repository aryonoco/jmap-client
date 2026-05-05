# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Thread/get (RFC 8621 §3) against Stalwart.
## Seeds a single Email, reads back its ``threadId`` via ``Email/get``,
## then issues ``Thread/get`` for that id and asserts the thread carries
## the seeded message in its ``emailIds`` list.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
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

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/thread as jthread
import ./mcapture
import ./mconfig
import ./mlive

block tthreadGetLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Seed: resolve inbox + create email ------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let seededId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-b step-8 seed", "seedThread"
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")

    # --- Resolve threadId via Email/get ----------------------------------
    let (b1, emailHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "threadId"]),
    )
    let resp1 = client.send(b1).expect("send Email/get[" & $target.kind & "]")
    let emailResp =
      resp1.get(emailHandle).expect("Email/get extract[" & $target.kind & "]")
    assertOn target, emailResp.list.len == 1, "Email/get must return the seeded message"
    let threadIdNode = emailResp.list[0]{"threadId"}
    assertOn target,
      not threadIdNode.isNil,
      "Email/get must include threadId when requested in properties"
    let threadId = parseIdFromServer(threadIdNode.getStr("")).expect(
        "parseIdFromServer threadId[" & $target.kind & "]"
      )

    # --- Thread/get with bounded retry for async population --------------
    var thread = Opt.none(jthread.Thread)
    for attempt in 0 ..< 5:
      let (b2, threadHandle) = addGet[jthread.Thread](
        initRequestBuilder(), mailAccountId, ids = directIds(@[threadId])
      )
      let resp2 = client.send(b2).expect("send Thread/get[" & $target.kind & "]")
      let threadResp =
        resp2.get(threadHandle).expect("Thread/get extract[" & $target.kind & "]")
      if threadResp.list.len == 1:
        let parsed = jthread.Thread.fromJson(threadResp.list[0])
        if parsed.isOk:
          thread = Opt.some(parsed.get())
          break
      sleep(100)

    assertOn target,
      thread.isSome, "Thread/get must return the seeded thread within 500 ms"
    captureIfRequested(client, "thread-get-" & $target.kind).expect(
      "captureIfRequested[" & $target.kind & "]"
    )
    let t = thread.get()
    assertOn target,
      string(t.id) == string(threadId),
      "returned Thread.id must match the threadId from Email/get"
    assertOn target,
      seededId in t.emailIds, "seeded EmailId must appear in Thread.emailIds"
    client.close()
