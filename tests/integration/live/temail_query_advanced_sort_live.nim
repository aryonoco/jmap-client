# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 56 — wire test of ``Email/query`` exercising the
## ``EmailComparator`` arms not covered by Phase C15 (Phase C15
## covered ``pspSubject`` ascending and descending only).  This
## step adds:
##
##  * ``pspSize`` ascending — distinct body sizes give a
##    deterministic ordering.
##  * ``pspSubject`` descending — compatible with C15's coverage
##    but here against this phase's seed.
##  * ``eckKeyword`` — sort by has-keyword via
##    ``keywordComparator(kspHasKeyword, kwFlagged, isAscending =
##    true)`` after marking one seed with ``$flagged``.
##
## **Stalwart 0.15.5 empirical pin.**  The ``isAscending`` semantics
## for boolean ``hasKeyword`` sorts on Stalwart treat *present*
## keyword as "earlier" under ``isAscending = true`` (flagged
## first), and *missing* keyword as "earlier" under
## ``isAscending = false``.  RFC 8620 §5.5 does not pin the boolean
## true/false numeric mapping, so either direction is conformant.
## This test asserts the direction Stalwart actually produces;
## reversing the direction on a future server requires only
## flipping ``isAscending``.
##
## Workflow:
##
##  1. Resolve mail account, inbox.
##  2. Seed three emails with distinct body sizes via
##     ``parseEmailBlueprint`` directly (smaller, medium, larger).
##  3. Sub-test A: sort by size ascending — assert smaller < medium
##     < larger by position.
##  4. Sub-test B: sort by subject descending — assert subject
##     ordering is reverse-alphabetic among the seeded subjects.
##  5. Mark the medium seed with ``$flagged`` via
##     ``Email/set update``.
##  6. Sub-test C: sort by ``hasKeyword: $flagged`` ascending —
##     under Stalwart 0.15.5 the flagged seed must appear before
##     the unflagged seeds in the result list (empirical pin —
##     see header).  Capture the wire response on this leg.
##
## Capture: ``email-query-advanced-sort-stalwart``.
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

proc seedSizedEmail(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    bodyLen: int,
    creationLabel: string,
): Id =
  ## Seeds an email whose body is ``bodyLen`` bytes — distinctive
  ## sizes give a deterministic pspSize ordering.
  let mailboxIds =
    parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet sized")
  let aliceAddr = buildAliceAddr()
  let body = repeat('q', bodyLen)
  let textPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("1"),
      contentType: "text/plain",
      body: body,
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
    .expect("parseEmailBlueprint sized")
  let cid = parseCreationId(creationLabel).expect("parseCreationId sized")
  var createTbl = initTable[CreationId, EmailBlueprint]()
  createTbl[cid] = blueprint
  let (b, setHandle) =
    addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp = client.send(b).expect("send Email/set sized")
  let setResp = resp.get(setHandle).expect("Email/set sized extract")
  var seededId = Id("")
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.expect("Email/set create sized")
    seededId = item.id
    found = true
  do:
    doAssert false, "Email/set returned no result for sized"
  doAssert found
  seededId

proc positionsOf(qr: QueryResponse[Email], ids: openArray[Id]): seq[int] =
  ## Returns the position of each id within ``qr.ids``; -1 if absent.
  result = newSeq[int](ids.len)
  for i in 0 ..< ids.len:
    result[i] = -1
  for i, id in qr.ids:
    for j, target in ids:
      if id == target:
        result[j] = i

proc assertSizeAscending(
    client: var JmapClient, mailAccountId: AccountId, smallId, mediumId, largeId: Id
) =
  ## Sub-test A: sort by size ascending; small < medium < large.
  let filter = filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 56")))
  let comparator = @[plainComparator(pspSize, isAscending = Opt.some(true))]
  let (b, h) = addEmailQuery(
    initRequestBuilder(),
    mailAccountId,
    filter = Opt.some(filter),
    sort = Opt.some(comparator),
  )
  let resp = client.send(b).expect("send Email/query size asc")
  let qr = resp.get(h).expect("Email/query size asc extract")
  let positions = positionsOf(qr, @[smallId, mediumId, largeId])
  for i, pos in positions:
    doAssert pos >= 0, "all three sized seeds must surface (missing index " & $i & ")"
  doAssert positions[0] < positions[1] and positions[1] < positions[2],
    "size ascending must yield small (" & $positions[0] & ") < medium (" & $positions[1] &
      ") < large (" & $positions[2] & ")"

proc assertSubjectDescending(
    client: var JmapClient, mailAccountId: AccountId, smallId, mediumId, largeId: Id
) =
  ## Sub-test B: sort by subject descending.  Seed subjects use
  ## suffixes "alpha"/"bravo"/"charlie" so descending yields
  ## charlie → bravo → alpha.
  let filter = filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 56")))
  let comparator = @[plainComparator(pspSubject, isAscending = Opt.some(false))]
  let (b, h) = addEmailQuery(
    initRequestBuilder(),
    mailAccountId,
    filter = Opt.some(filter),
    sort = Opt.some(comparator),
  )
  let resp = client.send(b).expect("send Email/query subject desc")
  let qr = resp.get(h).expect("Email/query subject desc extract")
  # smallId carries "alpha", mediumId carries "bravo", largeId carries "charlie"
  let positions = positionsOf(qr, @[smallId, mediumId, largeId])
  for i, pos in positions:
    doAssert pos >= 0, "all three subject seeds must surface (missing index " & $i & ")"
  doAssert positions[2] < positions[1] and positions[1] < positions[0],
    "subject descending must yield charlie (large=" & $positions[2] &
      ") < bravo (medium=" & $positions[1] & ") < alpha (small=" & $positions[0] & ")"

proc flagMediumEmail(client: var JmapClient, mailAccountId: AccountId, mediumId: Id) =
  ## Email/set update marking the medium seed with ``$flagged``.
  let updateSet = initEmailUpdateSet(@[markFlagged()]).expect("initEmailUpdateSet")
  let updates = parseNonEmptyEmailUpdates(@[(mediumId, updateSet)]).expect(
      "parseNonEmptyEmailUpdates"
    )
  let (b, h) =
    addEmailSet(initRequestBuilder(), mailAccountId, update = Opt.some(updates))
  let resp = client.send(b).expect("send Email/set markFlagged")
  discard resp.get(h).expect("Email/set markFlagged extract")

proc assertKeywordSortAscending(
    client: var JmapClient, mailAccountId: AccountId, smallId, mediumId, largeId: Id
) =
  ## Sub-test C: sort by hasKeyword:$flagged ascending — Stalwart
  ## 0.15.5 emits unflagged emails first and the flagged seed last
  ## (empirical pin documented in the file docstring).
  let filter = filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 56")))
  let flaggedKw = parseKeyword("$flagged").expect("parseKeyword $flagged")
  let comparator =
    @[keywordComparator(kspHasKeyword, flaggedKw, isAscending = Opt.some(true))]
  let (b, h) = addEmailQuery(
    initRequestBuilder(),
    mailAccountId,
    filter = Opt.some(filter),
    sort = Opt.some(comparator),
  )
  let resp = client.send(b).expect("send Email/query keyword asc")
  captureIfRequested(client, "email-query-advanced-sort-stalwart").expect(
    "captureIfRequested"
  )
  let qr = resp.get(h).expect("Email/query keyword asc extract")
  let positions = positionsOf(qr, @[smallId, mediumId, largeId])
  for i, pos in positions:
    doAssert pos >= 0, "all three seeds must surface (missing index " & $i & ")"
  let mediumPos = positions[1]
  let smallPos = positions[0]
  let largePos = positions[2]
  doAssert mediumPos < smallPos and mediumPos < largePos,
    "flagged seed (medium=" & $mediumPos & ") must precede unflagged seeds (small=" &
      $smallPos & ", large=" & $largePos &
      ") under hasKeyword:$flagged ascending — Stalwart 0.15.5 empirical pin"

block temailQueryAdvancedSortLive:
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
    let smallId = seedSizedEmail(
      client, mailAccountId, inbox, "phase-i 56 alpha", 200, "phase-i-56-s"
    )
    let mediumId = seedSizedEmail(
      client, mailAccountId, inbox, "phase-i 56 bravo", 1024, "phase-i-56-m"
    )
    let largeId = seedSizedEmail(
      client, mailAccountId, inbox, "phase-i 56 charlie", 4096, "phase-i-56-l"
    )

    assertSizeAscending(client, mailAccountId, smallId, mediumId, largeId)
    assertSubjectDescending(client, mailAccountId, smallId, mediumId, largeId)
    flagMediumEmail(client, mailAccountId, mediumId)
    assertKeywordSortAscending(client, mailAccountId, smallId, mediumId, largeId)

    client.close()
