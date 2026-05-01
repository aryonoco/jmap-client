# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test scaffolds shared across the Phase A–D suites.
## ``mconfig.nim`` stays single-purpose (env contract); this module owns
## the Stalwart-interaction recipes that would otherwise be inlined
## verbatim across multiple test files: resolving Alice's inbox via
## ``Mailbox/get``, seeding text/plain ``Email`` instances, and seeding
## structured (multipart/alternative, multipart/mixed, message/rfc822)
## emails for the Phase D body-content tests.
##
## Helpers return ``Result[T, string]`` so callers can chain ``.expect``
## with the same ergonomics as ``loadLiveTestConfig``. They take a
## ``var JmapClient`` because ``client.send`` requires it.

{.push raises: [].}

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client

# ---------------------------------------------------------------------------
# Shared blueprint-leaf factory
# ---------------------------------------------------------------------------

type LeafPartSpec* = object
  ## Inputs for ``makeLeafPart``. Carries the variable bits — body bytes,
  ## MIME type, optional attachment name / disposition / cid — and lets
  ## the seed helpers stay free of repetitive ``BlueprintBodyPart``
  ## boilerplate.
  partId*: PartId
  contentType*: string
  body*: string
  name*: Opt[string]
  disposition*: Opt[ContentDisposition]
  cid*: Opt[string]

func makeLeafPart*(spec: LeafPartSpec): BlueprintBodyPart =
  ## Constructs a non-multipart ``BlueprintBodyPart`` from ``spec``.
  ## Pure — every seed helper in this module funnels through it so the
  ## "inline leaf with these knobs" shape lives in one place.
  BlueprintBodyPart(
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: spec.partId,
      value: BlueprintBodyValue(value: spec.body),
    ),
    contentType: spec.contentType,
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    name: spec.name,
    disposition: spec.disposition,
    cid: spec.cid,
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

func buildAliceAddr*(): EmailAddress =
  ## ``alice@example.com`` with display name ``"Alice"`` — Stalwart's
  ## seeded credentials. Smart-constructor invariant: input is RFC-valid
  ## by literal so ``parseEmailAddress`` cannot Err here.
  parseEmailAddress("alice@example.com", Opt.some("Alice")).get()

func buildPartId*(label: string): PartId =
  ## Wraps ``parsePartIdFromServer`` for a server-shaped literal. The
  ## seeds use ``"1"`` for single-part bodies and ``"1"`` / ``"2"`` …
  ## inside multipart trees; every literal in this module is RFC-valid,
  ## so the parser cannot Err.
  parsePartIdFromServer(label).get()

# ---------------------------------------------------------------------------
# Mailbox / Email helpers
# ---------------------------------------------------------------------------

proc resolveInboxId*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string] =
  ## ``Mailbox/get`` → returns the ``Id`` of the mailbox carrying
  ## ``role == roleInbox``. Errors out narratively when the request
  ## fails, the response cannot be extracted, or no inbox-role mailbox
  ## is present.
  let (b, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
  let resp = client.send(b).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.rawType)
  for node in mbResp.list:
    let mb = Mailbox.fromJson(node).valueOr:
      return err("Mailbox parse failed during inbox lookup")
    for role in mb.role:
      if role == roleInbox:
        return ok(mb.id)
  err("no Mailbox with role==Inbox found in account")

proc emailSetCreate(
    client: var JmapClient,
    mailAccountId: AccountId,
    blueprint: EmailBlueprint,
    creationLabel: string,
): Result[Id, string] =
  ## Issues a single-create ``Email/set`` and returns the assigned id.
  ## Private to this module — every seed helper builds a blueprint then
  ## funnels through here so the creation-results unwrap lives in one
  ## place.
  let cid = parseCreationId(creationLabel).valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, EmailBlueprint]()
  createTbl[cid] = blueprint
  let (b, setHandle) =
    addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp = client.send(b).valueOr:
    return err("Email/set send failed: " & error.message)
  let setResp = resp.get(setHandle).valueOr:
    return err("Email/set extract failed: " & error.rawType)
  var seededId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Email/set create rejected: " & error.rawType)
    seededId = item.id
    found = true
  do:
    return err("Email/set returned no result for creationId " & creationLabel)
  doAssert found
  ok(seededId)

proc seedSimpleEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    creationLabel: string,
): Result[Id, string] =
  ## ``Email/set create`` for a minimal text/plain message addressed
  ## from alice@example.com to herself, filed in ``inbox``. Returns the
  ## server-assigned ``EmailId``. Caller supplies a unique
  ## ``creationLabel`` per seed in the same test (e.g., ``"seedA"``) so
  ## multiple seeds in one ``Email/set`` would not collide — even though
  ## each helper call issues its own request, the label still flows
  ## through ``CreationId`` validation.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  let textPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("1"),
      contentType: "text/plain",
      body: "Live-test seed body.",
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
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

proc seedEmailsWithSubjects*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subjects: openArray[string],
): Result[seq[Id], string] =
  ## Seeds N minimal text/plain emails differentiated only by subject.
  ## Wraps ``seedSimpleEmail`` per element of ``subjects``; returns the
  ## server-assigned ids in the same order. The ``creationLabel`` is
  ## derived as ``"seed-N"`` from the index — test bodies only consume
  ## the returned ids, never the label.
  ##
  ## Short-circuits on the first ``Err`` per the railway pattern, so a
  ## partial failure does not silently swallow earlier successes.
  var ids: seq[Id] = @[]
  for i, subject in subjects:
    let id = seedSimpleEmail(client, mailAccountId, inbox, subject, "seed-" & $i).valueOr:
      return err("seedEmailsWithSubjects[" & $i & "]: " & error)
    ids.add(id)
  ok(ids)

proc seedThreadedEmails*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subjects: openArray[string],
    rootMessageId: string,
): Result[seq[Id], string] =
  ## Seeds N text/plain emails with RFC 5322 In-Reply-To / References
  ## headers wired so a server's threading pipeline groups them into a
  ## single Thread. The first email gets ``messageId = @[rootMessageId]``;
  ## each subsequent email gets ``inReplyTo = @[rootMessageId]`` and
  ## ``references = @[rootMessageId]``.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  var ids: seq[Id] = @[]
  for i, subject in subjects:
    let textPart = makeLeafPart(
      LeafPartSpec(
        partId: buildPartId("1"),
        contentType: "text/plain",
        body: "Live-test threaded seed body.",
        name: Opt.none(string),
        disposition: Opt.none(ContentDisposition),
        cid: Opt.none(string),
      )
    )
    let messageId =
      if i == 0:
        Opt.some(@[rootMessageId])
      else:
        Opt.none(seq[string])
    let inReplyTo =
      if i == 0:
        Opt.none(seq[string])
      else:
        Opt.some(@[rootMessageId])
    let references =
      if i == 0:
        Opt.none(seq[string])
      else:
        Opt.some(@[rootMessageId])
    let blueprint = parseEmailBlueprint(
      mailboxIds = mailboxIds,
      body = flatBody(textBody = Opt.some(textPart)),
      fromAddr = Opt.some(@[aliceAddr]),
      to = Opt.some(@[aliceAddr]),
      subject = Opt.some(subject),
      messageId = messageId,
      inReplyTo = inReplyTo,
      references = references,
    ).valueOr:
      return err("parseEmailBlueprint failed: " & $error)
    let id = emailSetCreate(client, mailAccountId, blueprint, "thread-" & $i).valueOr:
      return err("seedThreadedEmails[" & $i & "]: " & error)
    ids.add(id)
  ok(ids)

# ---------------------------------------------------------------------------
# Phase D structured-body seeds
# ---------------------------------------------------------------------------

proc seedAlternativeEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    textBody: string,
    htmlBody: string,
    creationLabel: string,
): Result[Id, string] =
  ## Seeds a multipart/alternative email — text/plain + text/html siblings
  ## that the server wraps as a single MIME message. The returned id
  ## resolves through ``Email/get`` with ``bodyValueScope = bvsTextAndHtml``
  ## to verify both leaves and their bodyValues map entries.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  let textPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("1"),
      contentType: "text/plain",
      body: textBody,
      name: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
    )
  )
  let htmlPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("2"),
      contentType: "text/html",
      body: htmlBody,
      name: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
    )
  )
  let blueprint = parseEmailBlueprint(
    mailboxIds = mailboxIds,
    body = flatBody(textBody = Opt.some(textPart), htmlBody = Opt.some(htmlPart)),
    fromAddr = Opt.some(@[aliceAddr]),
    to = Opt.some(@[aliceAddr]),
    subject = Opt.some(subject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

proc seedMixedEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    textBody: string,
    attachmentName: string,
    attachmentMimeType: string,
    attachmentBytes: string,
    creationLabel: string,
): Result[Id, string] =
  ## Seeds a multipart/mixed email — text/plain body + one attachment.
  ## ``attachmentBytes`` is sent inline; callers should pass JSON-safe
  ## bytes (high-bit-clean ASCII or UTF-8). For binary attachments the
  ## production path is to upload via blob first, but the live test only
  ## needs to verify the structural attachment shape on read-back.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  let textPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("1"),
      contentType: "text/plain",
      body: textBody,
      name: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
    )
  )
  let attachPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("2"),
      contentType: attachmentMimeType,
      body: attachmentBytes,
      name: Opt.some(attachmentName),
      disposition: Opt.some(dispositionAttachment),
      cid: Opt.none(string),
    )
  )
  let blueprint = parseEmailBlueprint(
    mailboxIds = mailboxIds,
    body = flatBody(textBody = Opt.some(textPart), attachments = @[attachPart]),
    fromAddr = Opt.some(@[aliceAddr]),
    to = Opt.some(@[aliceAddr]),
    subject = Opt.some(subject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

func buildInnerRfc822Message(
    innerSubject: string, innerFrom: EmailAddress, innerBody: string
): string =
  ## Constructs a minimal RFC 5322 message string for use as a
  ## message/rfc822 attachment payload. The exact byte sequence is
  ## ``From: <name> <addr>\r\nTo: <self>\r\nSubject: <subj>\r\n
  ## MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n
  ## \r\n<body>``. Stalwart parses it on receive and exposes the parsed
  ## form via ``Email/parse``.
  let fromName = innerFrom.name.valueOr:
    ""
  let fromHeader =
    if fromName.len > 0:
      fromName & " <" & innerFrom.email & ">"
    else:
      "<" & innerFrom.email & ">"
  "From: " & fromHeader & "\r\n" & "To: <alice@example.com>\r\n" & "Subject: " &
    innerSubject & "\r\n" & "MIME-Version: 1.0\r\n" &
    "Content-Type: text/plain; charset=utf-8\r\n" & "\r\n" & innerBody

proc seedForwardedEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    outerSubject: string,
    innerSubject: string,
    innerFrom: EmailAddress,
    innerBody: string,
    creationLabel: string,
): Result[Id, string] =
  ## Seeds a multipart/mixed email — text/plain body + a message/rfc822
  ## attachment containing a constructed inner email. Used by Phase D
  ## Step 24 to exercise ``Email/parse`` on the attached blob.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  let textPart = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("1"),
      contentType: "text/plain",
      body: "Forwarded message follows.",
      name: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
    )
  )
  let innerMessage = buildInnerRfc822Message(innerSubject, innerFrom, innerBody)
  let rfc822Part = makeLeafPart(
    LeafPartSpec(
      partId: buildPartId("2"),
      contentType: "message/rfc822",
      body: innerMessage,
      name: Opt.some("forwarded.eml"),
      disposition: Opt.some(dispositionAttachment),
      cid: Opt.none(string),
    )
  )
  let blueprint = parseEmailBlueprint(
    mailboxIds = mailboxIds,
    body = flatBody(textBody = Opt.some(textPart), attachments = @[rfc822Part]),
    fromAddr = Opt.some(@[aliceAddr]),
    to = Opt.some(@[aliceAddr]),
    subject = Opt.some(outerSubject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func resolveCollationAlgorithms*(session: Session): HashSet[CollationAlgorithm] =
  ## Convenience: returns the ``CollationAlgorithm`` set advertised by the
  ## server's core capabilities. Pure — no IO. Exists as a named helper for
  ## symmetry with the seed helpers and to keep test bodies free of
  ## capability-traversal boilerplate.
  session.coreCapabilities.collationAlgorithms
