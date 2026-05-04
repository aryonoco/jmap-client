# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``GetResponse[T].notFound: seq[Id]`` deserialises
## a populated ``notFound`` array when some requested ids do not
## exist server-side, and the contract holds across every entity
## that supports /get.  ``Email/get``, ``Mailbox/get``,
## ``Identity/get``, and ``Thread/get`` all expose the same
## ``GetResponse[T]`` shape — they share the generic deserialiser at
## ``methods.nim``.
##
## Phase J Step 66.  Four sequential ``client.send`` calls drive
## each entity's /get with mixed-existence ids: one real id (where
## available) plus one synthetic id Stalwart cannot resolve.  Each
## sub-test asserts: ``getResp.list.len + getResp.notFound.len ==
## requested.len`` and the synthetic id appears in ``notFound``.
## Set-membership accepts ``metInvalidArguments`` projection if
## Stalwart strict-rejects the synthetic Id format upfront for any
## sub-test; the captured fixture pins the chosen rail.

import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/thread as jthread
import ./mcapture
import ./mconfig
import ./mlive

block tnotfoundRailGetLive:
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
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")

    # Sub-test 1: Email/get with mixed existing + synthetic ids.
    # Capture the multi-entity wire shape after this sub-test only —
    # one canonical fixture is enough to demonstrate the notFound
    # rail's wire shape.
    block emailGetCase:
      let realEmailId = seedSimpleEmail(
          client, mailAccountId, inbox, "phase-j 66 notFound", "phase-j-66-seed"
        )
        .expect("seedSimpleEmail")
      let syntheticId = Id("zzzzzz")
      let (b, getHandle) = addEmailGet(
        initRequestBuilder(),
        mailAccountId,
        ids = directIds(@[realEmailId, syntheticId]),
      )
      let resp = client.send(b).expect("send Email/get mixed ids")
      captureIfRequested(client, "notfound-rail-get-stalwart").expect(
        "captureIfRequested notFound rail"
      )
      let getResp = resp.get(getHandle).expect("Email/get extract")
      doAssert getResp.list.len == 1,
        "Email/get must return exactly one record (the real id), got " &
          $getResp.list.len
      doAssert getResp.notFound.len >= 1,
        "Email/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      var foundSynthetic = false
      for id in getResp.notFound:
        if id == syntheticId:
          foundSynthetic = true
          break
      doAssert foundSynthetic,
        "synthetic id must appear in notFound; got " & $getResp.notFound

      # Cleanup: destroy the seed email so re-runs are idempotent.
      let (bClean, cleanHandle) = addEmailSet(
        initRequestBuilder(), mailAccountId, destroy = directIds(@[realEmailId])
      )
      let respClean = client.send(bClean).expect("send Email/set cleanup")
      let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
      cleanResp.destroyResults.withValue(realEmailId, outcome):
        doAssert outcome.isOk, "cleanup destroy must succeed"
      do:
        doAssert false, "cleanup must report an outcome"

    # Sub-test 2: Mailbox/get with synthetic id.
    block mailboxGetCase:
      let syntheticId = Id("zzzzzm")
      let (b, getHandle) = addGet[Mailbox](
        initRequestBuilder(), mailAccountId, ids = directIds(@[syntheticId])
      )
      let resp = client.send(b).expect("send Mailbox/get synthetic")
      let getResp = resp.get(getHandle).expect("Mailbox/get extract")
      doAssert getResp.list.len == 0,
        "Mailbox/get must return no records for a synthetic id, got " & $getResp.list.len
      doAssert getResp.notFound.len == 1,
        "Mailbox/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      doAssert getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    # Sub-test 3: Identity/get on submission account with synthetic id.
    block identityGetCase:
      let syntheticId = Id("zzzzzi")
      let (b, getHandle) = addIdentityGet(
        initRequestBuilder(), submissionAccountId, ids = directIds(@[syntheticId])
      )
      let resp = client.send(b).expect("send Identity/get synthetic")
      let getResp = resp.get(getHandle).expect("Identity/get extract")
      doAssert getResp.list.len == 0,
        "Identity/get must return no records for a synthetic id, got " &
          $getResp.list.len
      doAssert getResp.notFound.len == 1,
        "Identity/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      doAssert getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    # Sub-test 4: Thread/get with synthetic threadId.
    block threadGetCase:
      let syntheticId = Id("zzzzzt")
      let (b, getHandle) = addGet[jthread.Thread](
        initRequestBuilder(), mailAccountId, ids = directIds(@[syntheticId])
      )
      let resp = client.send(b).expect("send Thread/get synthetic")
      let getResp = resp.get(getHandle).expect("Thread/get extract")
      doAssert getResp.list.len == 0,
        "Thread/get must return no records for a synthetic id, got " & $getResp.list.len
      doAssert getResp.notFound.len == 1,
        "Thread/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      doAssert getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    client.close()
