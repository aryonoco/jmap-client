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
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tnotfoundRailGetLive:
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
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # Sub-test 1: Email/get with mixed existing + synthetic ids.
    # Capture the multi-entity wire shape after this sub-test only —
    # one canonical fixture is enough to demonstrate the notFound
    # rail's wire shape.
    block emailGetCase:
      let realEmailId = seedSimpleEmail(
          client, mailAccountId, inbox, "phase-j 66 notFound", "phase-j-66-seed"
        )
        .expect("seedSimpleEmail[" & $target.kind & "]")
      let syntheticId = Id("zzzzzz")
      let (b, getHandle) = addEmailGet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        ids = directIds(@[realEmailId, syntheticId]),
      )
      let resp =
        client.send(b.freeze()).expect("send Email/get mixed ids[" & $target.kind & "]")
      captureIfRequested(client, "notfound-rail-get-" & $target.kind).expect(
        "captureIfRequested notFound rail"
      )
      let getResp =
        resp.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 1,
        "Email/get must return exactly one record (the real id), got " &
          $getResp.list.len
      assertOn target,
        getResp.notFound.len >= 1,
        "Email/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      var foundSynthetic = false
      for id in getResp.notFound:
        if id == syntheticId:
          foundSynthetic = true
          break
      assertOn target,
        foundSynthetic, "synthetic id must appear in notFound; got " & $getResp.notFound

      # Cleanup: destroy the seed email so re-runs are idempotent.
      let (bClean, cleanHandle) = addEmailSet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        destroy = directIds(@[realEmailId]),
      )
      let respClean = client.send(bClean.freeze()).expect(
          "send Email/set cleanup[" & $target.kind & "]"
        )
      let cleanResp = respClean.get(cleanHandle).expect(
          "Email/set cleanup extract[" & $target.kind & "]"
        )
      cleanResp.destroyResults.withValue(realEmailId, outcome):
        assertOn target, outcome.isOk, "cleanup destroy must succeed"
      do:
        assertOn target, false, "cleanup must report an outcome"

    # Sub-test 2: Mailbox/get with synthetic id.
    block mailboxGetCase:
      let syntheticId = Id("zzzzzm")
      let (b, getHandle) = addMailboxGet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        ids = directIds(@[syntheticId]),
      )
      let resp = client.send(b.freeze()).expect(
          "send Mailbox/get synthetic[" & $target.kind & "]"
        )
      let getResp =
        resp.get(getHandle).expect("Mailbox/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 0,
        "Mailbox/get must return no records for a synthetic id, got " & $getResp.list.len
      assertOn target,
        getResp.notFound.len == 1,
        "Mailbox/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      assertOn target,
        getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    # Sub-test 3: Identity/get on submission account with synthetic id.
    block identityGetCase:
      let syntheticId = Id("zzzzzi")
      let (b, getHandle) = addIdentityGet(
        initRequestBuilder(makeBuilderId()),
        submissionAccountId,
        ids = directIds(@[syntheticId]),
      )
      let resp = client.send(b.freeze()).expect(
          "send Identity/get synthetic[" & $target.kind & "]"
        )
      let getResp =
        resp.get(getHandle).expect("Identity/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 0,
        "Identity/get must return no records for a synthetic id, got " &
          $getResp.list.len
      assertOn target,
        getResp.notFound.len == 1,
        "Identity/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      assertOn target,
        getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    # Sub-test 4: Thread/get with synthetic threadId.
    block threadGetCase:
      let syntheticId = Id("zzzzzt")
      let (b, getHandle) = addThreadGet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        ids = directIds(@[syntheticId]),
      )
      let resp = client.send(b.freeze()).expect(
          "send Thread/get synthetic[" & $target.kind & "]"
        )
      let getResp =
        resp.get(getHandle).expect("Thread/get extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 0,
        "Thread/get must return no records for a synthetic id, got " & $getResp.list.len
      assertOn target,
        getResp.notFound.len == 1,
        "Thread/get must report the synthetic id in notFound, got " &
          $getResp.notFound.len
      assertOn target,
        getResp.notFound[0] == syntheticId,
        "synthetic id must appear in notFound; got " & $getResp.notFound

    client.close()
