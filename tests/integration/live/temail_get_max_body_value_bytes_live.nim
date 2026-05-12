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
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file
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
import ../../mtestblock

const SeedBodyLen = 2048
const TruncationCap = 64

testCase temailGetMaxBodyValueBytesLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
      )
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
      .expect("parseEmailBlueprint[" & $target.kind & "]")
    let cid =
      parseCreationId("phase-i-52-seed").expect("parseCreationId[" & $target.kind & "]")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprint
    let (bSeed, seedHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
    )
    let seedResp = client.send(bSeed.freeze()).expect(
        "send Email/set big body[" & $target.kind & "]"
      )
    let seedSet = seedResp.get(seedHandle).expect(
        "Email/set big body extract[" & $target.kind & "]"
      )
    var seededId: Id
    var found = false
    seedSet.createResults.withValue(cid, outcome):
      let item = outcome.expect("Email/set create big body[" & $target.kind & "]")
      seededId = item.id
      found = true
    do:
      assertOn target, false, "Email/set returned no result"
    assertOn target, found

    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "bodyValues", "textBody"]),
      bodyFetchOptions = EmailBodyFetchOptions(
        fetchBodyValues: bvsText,
        maxBodyValueBytes: Opt.some(UnsignedInt(TruncationCap)),
      ),
    )
    let resp = client.send(bGet.freeze()).expect(
        "send Email/get truncation[" & $target.kind & "]"
      )
    captureIfRequested(
      client, "email-get-max-body-value-bytes-truncated-" & $target.kind
    )
      .expect("captureIfRequested[" & $target.kind & "]")
    let getResp =
      resp.get(getHandle).expect("Email/get truncation extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1, "Email/get must return the seeded message"
    let email = getResp.list[0]
    assertOn target,
      email.bodyValues.len >= 1,
      "fetchBodyValues=bvsText must populate at least the text leaf"
    var anyTruncated = false
    for partId, bv in email.bodyValues.pairs:
      assertOn target,
        bv.value.len <= TruncationCap,
        "bodyValue under maxBodyValueBytes=" & $TruncationCap & " must satisfy " &
          "value.len <= cap (got " & $bv.value.len & " for partId=" & string(partId) &
          ")"
      if bv.isTruncated:
        anyTruncated = true
    assertOn target,
      anyTruncated,
      "at least one bodyValue must carry isTruncated=true under a 2 KB body and " &
        "a 64-byte cap"

    client.close()
