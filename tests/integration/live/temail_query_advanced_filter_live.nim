# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 55 — wire test of ``Email/query`` exercising the
## ``EmailFilterCondition`` arms not covered by Phases C13/C14:
## ``inMailbox``, ``inMailboxOtherThan``, ``before`` / ``after``,
## ``minSize`` / ``maxSize``, and ``hasAttachment``.  Phase J's
## adversarial scope owns the thread-keyword and substring-text
## arms (per the plan-doc retrospective on adversarial corpus).
##
## Workflow:
##
##  1. Resolve mail account and inbox; resolve / create the
##     ``phase-i 55 archive`` child mailbox via
##     ``resolveOrCreateMailbox``.
##  2. Seed corpus:
##       * 1 small text/plain email into Inbox via
##         ``seedEmailsWithSubjects`` (subject ``phase-i 55 small``).
##       * 1 large text/plain email into Inbox (4 KB body) via
##         ``parseEmailBlueprint`` directly.
##       * 1 multipart/mixed email with attachment into Inbox via
##         ``seedMixedEmail``.
##       * 1 small email into the archive via
##         ``seedEmailsIntoMailbox``.
##  3. Sub-test A: ``inMailbox = archiveId`` — assert the archive
##     entry surfaces and the inbox entries do not.
##  4. Sub-test B: ``inMailboxOtherThan = [archiveId]`` AND
##     ``minSize = 1000`` — assert at least the large email
##     surfaces and the small + archive entries do not.
##  5. Sub-test C: ``hasAttachment = true`` AND ``before = <UTC
##     date in the future>`` — assert at least the attachment-
##     bearing email surfaces.  Capture the wire response on this
##     leg.
##
## Capture: ``email-query-advanced-filter-stalwart``.
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

const LargeBodyLen = 4096

proc seedLargeEmail(
    client: JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject, creationLabel: string,
): Id =
  ## Inline blueprint with a 4 KB text/plain body so ``minSize`` /
  ## ``maxSize`` filtering has a deterministic discriminator.
  let mailboxIds =
    parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet large")
  let aliceAddr = buildAliceAddr()
  let bigBody = repeat('p', LargeBodyLen)
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
      subject = Opt.some(subject),
    )
    .expect("parseEmailBlueprint large")
  let cid = parseCreationId(creationLabel).expect("parseCreationId large")
  var createTbl = initTable[CreationId, EmailBlueprint]()
  createTbl[cid] = blueprint
  let (b, setHandle) = addEmailSet(
    initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
  )
  let resp = client.send(b.freeze()).expect("send Email/set large")
  let setResp = resp.get(setHandle).expect("Email/set large extract")
  var seededId = parseIdFromServer("placeholder").get()
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.expect("Email/set create large")
    seededId = item.id
    found = true
  do:
    doAssert false, "Email/set returned no result for large"
  doAssert found
  seededId

proc assertInMailbox(
    client: JmapClient,
    mailAccountId: AccountId,
    archiveId: Id,
    archiveSeed: Id,
    inboxSeeds: openArray[Id],
) =
  ## Sub-test A: filter inMailbox=archiveId surfaces archive seed
  ## and excludes the inbox seeds.
  let filter = filterCondition(EmailFilterCondition(inMailbox: Opt.some(archiveId)))
  let (b, h) = addEmailQuery(
    initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
  )
  let resp = client.send(b.freeze()).expect("send Email/query inMailbox")
  let qr = resp.get(h).expect("Email/query inMailbox extract")
  var foundArchive = false
  for id in qr.ids:
    if id == archiveSeed:
      foundArchive = true
    for inboxId in inboxSeeds:
      doAssert id != inboxId,
        "inMailbox=archive must not surface any inbox-only emails (got " & $id & ")"
  doAssert foundArchive, "archive seed must surface under inMailbox=archiveId"

proc assertInMailboxOtherThanMinSize(
    client: JmapClient,
    mailAccountId: AccountId,
    archiveId: Id,
    largeId: Id,
    smallIds: openArray[Id],
) =
  ## Sub-test B: AND of inMailboxOtherThan=[archive] and
  ## minSize=1000 surfaces the large email and excludes small ones
  ## when the server accepts the FilterOperator shape; otherwise the
  ## typed error is acceptable.
  let filter = filterCondition(
    EmailFilterCondition(
      inMailboxOtherThan: Opt.some(@[archiveId]),
      minSize: Opt.some(parseUnsignedInt(1000).get()),
    )
  )
  let (b, h) = addEmailQuery(
    initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
  )
  let resp = client.send(b.freeze()).expect("send Email/query minSize")
  let qrExtract = resp.get(h)
  if qrExtract.isOk:
    let qr = qrExtract.unsafeValue
    var foundLarge = false
    for id in qr.ids:
      if id == largeId:
        foundLarge = true
      for smallId in smallIds:
        doAssert id != smallId,
          "minSize=1000 must not surface small emails (got " & $id & ")"
    doAssert foundLarge, "large 4 KB email must surface under minSize=1000 filter"
  else:
    # Cat-B error arm — server rejected the nested FilterOperator
    # shape.
    let getErr = qrExtract.unsafeError
    doAssert getErr.kind == gekMethod,
      "filter rejection must surface as gekMethod, not gekHandleMismatch"
    let methodErr = getErr.methodErr
    doAssert methodErr.errorType in
      {metInvalidArguments, metUnsupportedFilter, metUnknownMethod},
      "method error must be in allowed set (got rawType=" & methodErr.rawType & ")"

proc assertHasAttachment(
    client: JmapClient,
    recorder: RecordingTransportState,
    mailAccountId: AccountId,
    attachId: Id,
    targetSuffix: string,
) =
  ## Sub-test C: hasAttachment=true plus before=<future date> surfaces
  ## the attachment-bearing seed.
  ##
  ## Cat-E on Cyrus only — Cyrus 3.12.2 does NOT classify inline-
  ## bodyValues parts (even with ``Content-Disposition: attachment``)
  ## as attachments for the ``hasAttachment`` filter
  ## (``imap/jmap_mail.c`` accepts inline text/* parts at seed time
  ## but never flags them in the per-email attachment-presence
  ## annotation). RFC 8621 §4.4 leaves the classification up to the
  ## server's reasonable interpretation; both Cyrus's choice (inline-
  ## bodyValues are not "attachments") and Stalwart/James's choice
  ## (they are) are conformant. Testing this assertion on Cyrus
  ## requires a real binary attachment via the JMAP ``/upload``
  ## endpoint (RFC 8620 §6.1) — that surface is deliberately
  ## deferred from Phase L. When ``/upload`` lands, this sub-test
  ## runs on Cyrus too.
  if targetSuffix == "cyrus":
    return
  let future = parseUtcDate("2099-01-01T00:00:00Z").expect("parseUtcDate future")
  let filter = filterCondition(
    EmailFilterCondition(hasAttachment: Opt.some(true), before: Opt.some(future))
  )
  let (b, h) = addEmailQuery(
    initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
  )
  let resp = client.send(b.freeze()).expect("send Email/query hasAttachment")
  captureIfRequested(
    recorder.lastResponseBody, "email-query-advanced-filter-" & targetSuffix
  )
    .expect("captureIfRequested")
  let qr = resp.get(h).expect("Email/query hasAttachment extract")
  var foundAttach = false
  for id in qr.ids:
    if id == attachId:
      foundAttach = true
      break
  doAssert foundAttach,
    "attachment-bearing email must surface under hasAttachment=true + before=future"

testCase temailQueryAdvancedFilterLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises advanced EmailFilterCondition
    # variants. Stalwart 0.15.5 and Cyrus 3.12.2 accept the full
    # surface (`imap/jmap_mail_query.c:1071-1140`). James 3.9 rejects
    # ``inMailboxOtherThan`` nested in FilterOperator and ``hasAttachment``
    # inline-bodyValues attachments — typed errors surface in either
    # the seed step (inline-bodyValues) or the filter extract.
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let archive = resolveOrCreateMailbox(client, mailAccountId, "phase-i 55 archive")
      .expect("resolveOrCreateMailbox archive[" & $target.kind & "]")
    let smallInbox = seedEmailsWithSubjects(
        client, mailAccountId, inbox, @["phase-i 55 small a"]
      )
      .expect("seedEmailsWithSubjects inbox small[" & $target.kind & "]")
    assertOn target, smallInbox.len == 1
    let largeId = seedLargeEmail(
      client, mailAccountId, inbox, "phase-i 55 large", "phase-i-55-large"
    )
    let attachRes = seedMixedEmail(
      client, mailAccountId, inbox, "phase-i 55 attached", "phase-i 55 inline body",
      "phase-i-55-attach.txt", "text/plain", "phase-i 55 attachment payload",
      "phase-i-55-attach",
    )
    if attachRes.isErr:
      # Cat-B error arm: server (e.g. James) rejected the inline-
      # bodyValues attachment. The typed-error projection has fired
      # inside ``seedMixedEmail`` — skip the dependent sub-tests.
      continue
    let attachId = attachRes.unsafeValue
    let archiveSeeds = seedEmailsIntoMailbox(
        client, mailAccountId, archive, @["phase-i 55 archived"]
      )
      .expect("seedEmailsIntoMailbox archive[" & $target.kind & "]")
    assertOn target, archiveSeeds.len == 1
    let archiveSeed = archiveSeeds[0]

    assertInMailbox(client, mailAccountId, archive, archiveSeed, smallInbox)
    assertInMailboxOtherThanMinSize(
      client, mailAccountId, archive, largeId, smallInbox & @[archiveSeed]
    )
    assertHasAttachment(client, recorder, mailAccountId, attachId, $target.kind)
