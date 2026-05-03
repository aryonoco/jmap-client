# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 52 — wire test of ``Email/get`` with the
## ``EmailBodyFetchOptions.maxBodyValueBytes`` cap forcing
## ``EmailBodyValue.isTruncated == true`` per RFC 8621 §4.1.4.
## Closes Phase D catalogue §6 deferral — that section flagged the
## truncation marker as unverified against any server.
##
## Workflow:
##
##  1. Seed a single email whose text/plain body is 2048 bytes of
##     repeated ASCII.  The body is constructed inline rather than
##     via ``seedSimpleEmail`` so the size knob is explicit.
##  2. ``Email/get`` with ``properties = ["id", "bodyValues",
##     "textBody"]`` and ``EmailBodyFetchOptions(fetchBodyValues =
##     bvsText, maxBodyValueBytes = Opt.some(UnsignedInt(64)))``.
##     Capture the wire response.
##  3. Assert exactly one bodyValues entry whose ``value.len <= 64``
##     AND ``isTruncated == true``.
##
## Capture: ``email-get-max-body-value-bytes-truncated-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

const SeedBodyLen = 2048
const TruncationCap = 64

block temailGetMaxBodyValueBytesLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let mailboxIds =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet")
    let aliceAddr = buildAliceAddr()
    let bigBody = repeat('a', SeedBodyLen)
    let textPart = makeLeafPart(
      LeafPartSpec(
        partId: buildPartId("1"),
        contentType: "text/plain",
        body: bigBody,
        name: Opt.none(string),
        disposition: Opt.none(ContentDisposition),
        cid: Opt.none(string),
      )
    )
    let blueprint = parseEmailBlueprint(
        mailboxIds = mailboxIds,
        body = flatBody(textBody = Opt.some(textPart)),
        fromAddr = Opt.some(@[aliceAddr]),
        to = Opt.some(@[aliceAddr]),
        subject = Opt.some("phase-i 52 truncation"),
      )
      .expect("parseEmailBlueprint")
    let cid = parseCreationId("phase-i-52-seed").expect("parseCreationId")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprint
    let (bSeed, seedHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
    let seedResp = client.send(bSeed).expect("send Email/set big body")
    let seedSet = seedResp.get(seedHandle).expect("Email/set big body extract")
    var seededId: Id
    var found = false
    seedSet.createResults.withValue(cid, outcome):
      let item = outcome.expect("Email/set create big body")
      seededId = item.id
      found = true
    do:
      doAssert false, "Email/set returned no result"
    doAssert found

    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "bodyValues", "textBody"]),
      bodyFetchOptions = EmailBodyFetchOptions(
        fetchBodyValues: bvsText,
        maxBodyValueBytes: Opt.some(UnsignedInt(TruncationCap)),
      ),
    )
    let resp = client.send(bGet).expect("send Email/get truncation")
    captureIfRequested(client, "email-get-max-body-value-bytes-truncated-stalwart")
      .expect("captureIfRequested")
    let getResp = resp.get(getHandle).expect("Email/get truncation extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"
    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.bodyValues.len >= 1,
      "fetchBodyValues=bvsText must populate at least the text leaf"
    var anyTruncated = false
    for partId, bv in email.bodyValues.pairs:
      doAssert bv.value.len <= TruncationCap,
        "bodyValue under maxBodyValueBytes=" & $TruncationCap & " must satisfy " &
          "value.len <= cap (got " & $bv.value.len & " for partId=" & string(partId) &
          ")"
      if bv.isTruncated:
        anyTruncated = true
    doAssert anyTruncated,
      "at least one bodyValue must carry isTruncated=true under a 2 KB body and " &
        "a 64-byte cap"

    client.close()
