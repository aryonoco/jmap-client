# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 54 — wire test of ``Email/get`` with the
## ``EmailBodyFetchOptions.bodyProperties`` array (RFC 8621 §4.2
## narrows which ``EmailBodyPart`` fields the server returns) AND
## the ``bvsAll`` body-value scope (full-tree value fetch).
##
## Workflow:
##
##  1. Seed a multipart/mixed email via ``seedMixedEmail`` — text/plain
##     body plus a small ``text/plain`` attachment (Phase E precedent).
##  2. ``Email/get`` with ``bodyProperties = ["partId", "blobId",
##     "type", "name", "size"]`` and ``EmailBodyFetchOptions(
##     fetchBodyValues = bvsAll)``.  Capture the wire response.
##  3. Assert ``bodyStructure`` parses with the multipart shape, the
##     subParts cover both the text body and the attachment, and
##     ``bodyValues`` carries at least one entry (the text body).
##
## **Stalwart 0.15.5 empirical pin.** ``bvsAll`` does NOT include
## the text/plain attachment leaf in ``bodyValues`` even though the
## RFC 8621 §4.1.4 contract permits it for text/* parts.  The
## response carries exactly one bodyValue (the textBody leaf at
## partId "1"); the attachment (partId "2") is omitted.  The
## anticipated divergence in plan-doc §6 anticipated this — RFC
## 8621 §4.1.4 makes attachment bodyValue inclusion server-defined
## even for text-typed leaves.
##
## Capture: ``email-get-body-properties-all-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailGetBodyPropertiesAllLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let seededId = seedMixedEmail(
        client, mailAccountId, inbox, "phase-i 54 mixed", "phase-i 54 text body",
        "phase-i-54.txt", "text/plain", "phase-i 54 attachment payload (32B sentinel)",
        "phase-i-54-seed",
      )
      .expect("seedMixedEmail")

    let bodyProperties = @[
      parsePropertyName("partId").expect("partId"),
      parsePropertyName("blobId").expect("blobId"),
      parsePropertyName("type").expect("type"),
      parsePropertyName("name").expect("name"),
      parsePropertyName("size").expect("size"),
    ]
    let (b, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "bodyStructure", "bodyValues"]),
      bodyFetchOptions = EmailBodyFetchOptions(
        fetchBodyValues: bvsAll, bodyProperties: Opt.some(bodyProperties)
      ),
    )
    let resp = client.send(b).expect("send Email/get bodyProperties+bvsAll")
    captureIfRequested(client, "email-get-body-properties-all-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp.get(getHandle).expect("Email/get bodyProperties+bvsAll extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"
    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.bodyStructure.isSome,
      "bodyStructure must be present when explicitly requested"
    let bs = email.bodyStructure.unsafeGet
    doAssert bs.isMultipart,
      "multipart/mixed seed must produce a multipart bodyStructure root"
    doAssert bs.subParts.len >= 2,
      "multipart/mixed seed must yield at least text + attachment subParts (got " &
        $bs.subParts.len & ")"
    doAssert email.bodyValues.len >= 1,
      "bvsAll must yield at least the textBody bodyValue (got " & $email.bodyValues.len &
        " — Stalwart 0.15.5 omits attachment bodyValues even for text/* leaves)"
    for partId, bv in email.bodyValues.pairs:
      doAssert string(partId).len > 0, "every bodyValues key must be non-empty"
      doAssert bv.value.len > 0, "bvsAll-emitted bodyValue must carry decoded content"

    client.close()
