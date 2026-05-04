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

const LargeBodyLen = 4096

proc seedLargeEmail(
    client: var JmapClient,
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
  let (b, setHandle) =
    addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp = client.send(b).expect("send Email/set large")
  let setResp = resp.get(setHandle).expect("Email/set large extract")
  var seededId = Id("")
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
    client: var JmapClient,
    mailAccountId: AccountId,
    archiveId: Id,
    archiveSeed: Id,
    inboxSeeds: openArray[Id],
) =
  ## Sub-test A: filter inMailbox=archiveId surfaces archive seed
  ## and excludes the inbox seeds.
  let filter = filterCondition(EmailFilterCondition(inMailbox: Opt.some(archiveId)))
  let (b, h) =
    addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
  let resp = client.send(b).expect("send Email/query inMailbox")
  let qr = resp.get(h).expect("Email/query inMailbox extract")
  var foundArchive = false
  for id in qr.ids:
    if id == archiveSeed:
      foundArchive = true
    for inboxId in inboxSeeds:
      doAssert id != inboxId,
        "inMailbox=archive must not surface any inbox-only emails (got " & string(id) &
          ")"
  doAssert foundArchive, "archive seed must surface under inMailbox=archiveId"

proc assertInMailboxOtherThanMinSize(
    client: var JmapClient,
    mailAccountId: AccountId,
    archiveId: Id,
    largeId: Id,
    smallIds: openArray[Id],
) =
  ## Sub-test B: AND of inMailboxOtherThan=[archive] and
  ## minSize=1000 surfaces the large email and excludes small ones.
  let filter = filterCondition(
    EmailFilterCondition(
      inMailboxOtherThan: Opt.some(@[archiveId]), minSize: Opt.some(UnsignedInt(1000))
    )
  )
  let (b, h) =
    addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
  let resp = client.send(b).expect("send Email/query minSize")
  let qr = resp.get(h).expect("Email/query minSize extract")
  var foundLarge = false
  for id in qr.ids:
    if id == largeId:
      foundLarge = true
    for smallId in smallIds:
      doAssert id != smallId,
        "minSize=1000 must not surface small emails (got " & string(id) & ")"
  doAssert foundLarge, "large 4 KB email must surface under minSize=1000 filter"

proc assertHasAttachment(
    client: var JmapClient, mailAccountId: AccountId, attachId: Id
) =
  ## Sub-test C: hasAttachment=true plus before=<future date>
  ## surfaces at least the attachment-bearing seed.  Captures the
  ## wire response.
  let future = parseUtcDate("2099-01-01T00:00:00Z").expect("parseUtcDate future")
  let filter = filterCondition(
    EmailFilterCondition(hasAttachment: Opt.some(true), before: Opt.some(future))
  )
  let (b, h) =
    addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
  let resp = client.send(b).expect("send Email/query hasAttachment")
  captureIfRequested(client, "email-query-advanced-filter-stalwart").expect(
    "captureIfRequested"
  )
  let qr = resp.get(h).expect("Email/query hasAttachment extract")
  var foundAttach = false
  for id in qr.ids:
    if id == attachId:
      foundAttach = true
      break
  doAssert foundAttach,
    "attachment-bearing email must surface under hasAttachment=true + before=future"

block temailQueryAdvancedFilterLive:
  forEachLiveTarget(target):
    # James 3.9 fails this test for two independent reasons:
    #   1. ``seedMixedEmail`` (Sub-test C) uses inline-bodyValues
    #      attachments which James rejects (requires blob upload via
    #      RFC 8620 §6.1 ``/upload`` — the library scope deferral).
    #   2. ``inMailboxOtherThan`` (Sub-test B) is rejected by James
    #      when nested inside a FilterOperator AND can't combine with
    #      ``minSize`` because James only allows top-level
    #      ``inMailboxOtherThan`` (``doc/specs/spec/mail/message.mdown``).
    # Captured ``-stalwart`` fixtures preserve replay coverage.
    if target.kind == ltkJames:
      continue
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
    let attachId = seedMixedEmail(
        client, mailAccountId, inbox, "phase-i 55 attached", "phase-i 55 inline body",
        "phase-i-55-attach.txt", "text/plain", "phase-i 55 attachment payload",
        "phase-i-55-attach",
      )
      .expect("seedMixedEmail attached[" & $target.kind & "]")
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
    assertHasAttachment(client, mailAccountId, attachId)

    client.close()
