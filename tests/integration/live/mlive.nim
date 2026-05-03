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

import std/os
import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig

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

# ---------------------------------------------------------------------------
# Phase E — additional Mailbox / Email helpers
# ---------------------------------------------------------------------------

proc resolveOrCreateMailbox*(
    client: var JmapClient, mailAccountId: AccountId, name: string
): Result[Id, string] =
  ## ``Mailbox/get`` → scan for a mailbox whose ``name`` matches ``name``.
  ## When present, returns its ``Id``. When absent, creates the mailbox as
  ## a child of the inbox-role mailbox via ``Mailbox/set create`` and
  ## returns the newly assigned id. Phase E supports re-runnability: on a
  ## second run the same name resolves to the previously created mailbox.
  let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
  let resp1 = client.send(b1).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp1.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.rawType)
  for node in mbResp.list:
    let mb = Mailbox.fromJson(node).valueOr:
      return err("Mailbox parse failed during resolveOrCreateMailbox")
    if mb.name == name:
      return ok(mb.id)
  let inbox = ?resolveInboxId(client, mailAccountId)
  let create = parseMailboxCreate(name = name, parentId = Opt.some(inbox)).valueOr:
    return err("parseMailboxCreate failed: " & error.message)
  let cid = parseCreationId("phaseEMailbox").valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, MailboxCreate]()
  createTbl[cid] = create
  let (b2, setHandle) =
    addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp2 = client.send(b2).valueOr:
    return err("Mailbox/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Mailbox/set extract failed: " & error.rawType)
  var createdId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Mailbox/set create rejected: " & error.rawType)
    createdId = item.id
    found = true
  do:
    return err("Mailbox/set returned no result for creationId phaseEMailbox")
  doAssert found
  ok(createdId)

proc seedEmailsIntoMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    mailbox: Id,
    subjects: openArray[string],
): Result[seq[Id], string] =
  ## Variant of ``seedEmailsWithSubjects`` parametrised on the destination
  ## mailbox rather than always seeding into the inbox. Funnels through the
  ## same ``Email/set`` blueprint pipeline; returns the server-assigned ids
  ## in the order of ``subjects``. Short-circuits on the first ``Err`` per
  ## the railway pattern.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[mailbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = buildAliceAddr()
  var ids: seq[Id] = @[]
  for i, subject in subjects:
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
    let id = emailSetCreate(client, mailAccountId, blueprint, "mbseed-" & $i).valueOr:
      return err("seedEmailsIntoMailbox[" & $i & "]: " & error)
    ids.add(id)
  ok(ids)

proc getFirstAttachmentBlobId*(
    client: var JmapClient, mailAccountId: AccountId, emailId: Id
): Result[BlobId, string] =
  ## Issues ``Email/get`` for ``emailId`` requesting only ``id`` and
  ## ``attachments``, then returns the ``blobId`` of ``attachments[0]``
  ## from the typed ``Email`` shape. Used by the Phase E import tests
  ## to bridge a seeded email to a freshly uploaded-like blob without
  ## going through a separate upload endpoint.
  let (b, getHandle) = addEmailGet(
    initRequestBuilder(),
    mailAccountId,
    ids = directIds(@[emailId]),
    properties = Opt.some(@["id", "attachments"]),
  )
  let resp = client.send(b).valueOr:
    return err("Email/get send failed: " & error.message)
  let getResp = resp.get(getHandle).valueOr:
    return err("Email/get extract failed: " & error.rawType)
  if getResp.list.len == 0:
    return err("Email/get returned empty list for " & string(emailId))
  let email = Email.fromJson(getResp.list[0]).valueOr:
    return err("Email.fromJson failed in getFirstAttachmentBlobId")
  if email.attachments.len == 0:
    return err("Email/get returned no attachments for " & string(emailId))
  ok(email.attachments[0].blobId)

# ---------------------------------------------------------------------------
# Phase F — EmailSubmission helpers
# ---------------------------------------------------------------------------

func resolveSubmissionAccountId*(session: Session): Result[AccountId, string] =
  ## Reads ``session.primaryAccounts`` for the
  ## ``urn:ietf:params:jmap:submission`` URN. Stalwart 0.15.5 binds the
  ## same id to ``mail`` and ``submission``; the helper does not depend
  ## on that equality. Sibling of ``resolveCollationAlgorithms``.
  var accountId: AccountId
  var found = false
  session.primaryAccounts.withValue("urn:ietf:params:jmap:submission", v):
    accountId = v
    found = true
  do:
    return err("session must advertise a primary submission account")
  doAssert found
  ok(accountId)

func buildEnvelope*(fromEmail, toEmail: string): Result[Envelope, string] =
  ## Absorbs the four-stage RFC5321Mailbox / SubmissionAddress /
  ## ReversePath / NonEmptyRcptList boilerplate that every Phase F
  ## EmailSubmission test would otherwise repeat. Both addresses use
  ## empty SubmissionParams (the simple case Stalwart expects for
  ## local-domain delivery).
  let fromMb = parseRFC5321Mailbox(fromEmail).valueOr:
    return err("parseRFC5321Mailbox(" & fromEmail & "): " & error.message)
  let toMb = parseRFC5321Mailbox(toEmail).valueOr:
    return err("parseRFC5321Mailbox(" & toEmail & "): " & error.message)
  let fromAddr =
    SubmissionAddress(mailbox: fromMb, parameters: Opt.none(SubmissionParams))
  let toAddr = SubmissionAddress(mailbox: toMb, parameters: Opt.none(SubmissionParams))
  let rcpts = parseNonEmptyRcptList(@[toAddr]).valueOr:
    return err("parseNonEmptyRcptList: empty or duplicate recipients")
  ok(Envelope(mailFrom: reversePath(fromAddr), rcptTo: rcpts))

proc resolveOrCreateRoleMailbox(
    client: var JmapClient,
    mailAccountId: AccountId,
    role: MailboxRole,
    creationLabel, narrativeName: string,
): Result[Id, string] =
  ## Mailbox/get → scan for a mailbox whose ``role`` matches; on miss,
  ## creates a new mailbox under the Inbox-role parent with that role.
  ## Internal — exposed via the ``resolveOrCreateDrafts`` /
  ## ``resolveOrCreateSent`` named wrappers below so call sites read as
  ## the role they want.
  let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
  let resp1 = client.send(b1).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp1.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.rawType)
  for node in mbResp.list:
    let mb = Mailbox.fromJson(node).valueOr:
      return err("Mailbox parse failed during " & narrativeName & " lookup")
    for r in mb.role:
      if r == role:
        return ok(mb.id)
  let inbox = ?resolveInboxId(client, mailAccountId)
  let create = parseMailboxCreate(
    name = narrativeName, parentId = Opt.some(inbox), role = Opt.some(role)
  ).valueOr:
    return err("parseMailboxCreate(" & narrativeName & "): " & error.message)
  let cid = parseCreationId(creationLabel).valueOr:
    return err("parseCreationId(" & creationLabel & "): " & error.message)
  var createTbl = initTable[CreationId, MailboxCreate]()
  createTbl[cid] = create
  let (b2, setHandle) =
    addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp2 = client.send(b2).valueOr:
    return err("Mailbox/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Mailbox/set extract failed: " & error.rawType)
  var createdId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Mailbox/set rejected " & narrativeName & ": " & error.rawType)
    createdId = item.id
    found = true
  do:
    return err("Mailbox/set returned no result for creationId " & creationLabel)
  doAssert found
  ok(createdId)

proc resolveOrCreateDrafts*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string] =
  ## Returns the ``Drafts``-role mailbox id, creating one under Inbox if
  ## absent. RFC 8621 §2.2 ``Drafts`` role.
  resolveOrCreateRoleMailbox(
    client, mailAccountId, roleDrafts, "phaseFDrafts", "Drafts"
  )

proc resolveOrCreateSent*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string] =
  ## Returns the ``Sent``-role mailbox id, creating one under Inbox if
  ## absent. RFC 8621 §2.2 ``Sent`` role.
  resolveOrCreateRoleMailbox(client, mailAccountId, roleSent, "phaseFSent", "Sent")

proc seedDraftEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    drafts: Id,
    fromAddr, toAddr: EmailAddress,
    subject, body: string,
    creationLabel: string,
): Result[Id, string] =
  ## Variant of ``seedSimpleEmail`` parametrised on from/to addresses,
  ## destination mailbox (typically ``Drafts``), and body text. Marks
  ## the email with the IANA ``$draft`` keyword (RFC 8621 §4.1.1) so
  ## EmailSubmission references a real draft, not an arbitrary message.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[drafts]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let draftKeyword = parseKeyword("$draft").valueOr:
    return err("parseKeyword($draft) failed: " & error.message)
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
    keywords = initKeywordSet(@[draftKeyword]),
    fromAddr = Opt.some(@[fromAddr]),
    to = Opt.some(@[toAddr]),
    subject = Opt.some(subject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

proc pollSubmissionDelivery*(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    budgetMs: int = 10000,
): Result[EmailSubmission[usFinal], string] =
  ## Polls EmailSubmission/get every 200 ms until ``undoStatus ==
  ## final``, returning the phantom-narrowed ``EmailSubmission[usFinal]``.
  ## ``Err`` on budget elapse — the bound is iterations of (sleep + poll),
  ## so the function is decoupled from wall-clock drift.
  const PollMs = 200
  let maxIters = max(1, budgetMs div PollMs)
  for _ in 0 ..< maxIters:
    let (b, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp = client.send(b).valueOr:
      return err("EmailSubmission/get send failed: " & error.message)
    let getResp = resp.get(getHandle).valueOr:
      return err("EmailSubmission/get extract failed: " & error.rawType)
    if getResp.list.len > 0:
      let any = AnyEmailSubmission.fromJson(getResp.list[0]).valueOr:
        return err("AnyEmailSubmission.fromJson failed during poll")
      let final = any.asFinal()
      if final.isSome:
        return ok(final.unsafeGet)
    sleep(PollMs)
  err(
    "pollSubmissionDelivery: budget exhausted (" & $budgetMs &
      "ms) without undoStatus=final"
  )

# ---------------------------------------------------------------------------
# Phase G — multi-principal + cancel-pending helpers
# ---------------------------------------------------------------------------

proc initBobClient*(cfg: LiveTestConfig): Result[JmapClient, ValidationError] =
  ## Sibling of the alice-flavoured ``initJmapClient`` idiom each Phase A–F
  ## test inlines. Constructs a ``JmapClient`` authenticating as bob via
  ## ``cfg.bobToken``. The Result rail mirrors ``initJmapClient`` directly —
  ## any future widening of ``initJmapClient``'s error rail propagates here
  ## without a signature change at call sites.
  initJmapClient(
    sessionUrl = cfg.sessionUrl, bearerToken = cfg.bobToken, authScheme = cfg.authScheme
  )

func buildEnvelopeWithHoldFor*(
    fromEmail, toEmail: string, holdSeconds: HoldForSeconds
): Result[Envelope, string] =
  ## Variant of ``buildEnvelope`` carrying an RFC 4865 ``HOLDFOR=`` Mail-
  ## parameter on ``mailFrom``. The typed ``HoldForSeconds`` argument
  ## prevents callers from passing arbitrary ``UnsignedInt``s; the
  ## ``parseSubmissionParams`` call cannot Err for a single well-formed
  ## ``holdForParam``. Used by Phase G Steps 41 and 42.
  let fromMb = parseRFC5321Mailbox(fromEmail).valueOr:
    return err("parseRFC5321Mailbox(" & fromEmail & "): " & error.message)
  let toMb = parseRFC5321Mailbox(toEmail).valueOr:
    return err("parseRFC5321Mailbox(" & toEmail & "): " & error.message)
  let params = parseSubmissionParams(@[holdForParam(holdSeconds)]).valueOr:
    return err("parseSubmissionParams(holdFor): unexpected error")
  let fromAddr = SubmissionAddress(mailbox: fromMb, parameters: Opt.some(params))
  let toAddr = SubmissionAddress(mailbox: toMb, parameters: Opt.none(SubmissionParams))
  let rcpts = parseNonEmptyRcptList(@[toAddr]).valueOr:
    return err("parseNonEmptyRcptList: empty or duplicate recipients")
  ok(Envelope(mailFrom: reversePath(fromAddr), rcptTo: rcpts))

func buildEnvelopeMulti*(
    fromEmail: string, toEmails: openArray[string]
): Result[Envelope, string] =
  ## Variant of ``buildEnvelope`` parametrised on a list of envelope
  ## recipients. Each ``toEmails`` entry maps to a ``SubmissionAddress``
  ## with empty parameters. Caller controls duplicates via the input
  ## list — ``parseNonEmptyRcptList`` rejects a duplicated recipient
  ## mailbox per its existing contract. Used by Phase G Step 40.
  let fromMb = parseRFC5321Mailbox(fromEmail).valueOr:
    return err("parseRFC5321Mailbox(" & fromEmail & "): " & error.message)
  let fromAddr =
    SubmissionAddress(mailbox: fromMb, parameters: Opt.none(SubmissionParams))
  var rcptAddrs: seq[SubmissionAddress] = @[]
  for toEmail in toEmails:
    let toMb = parseRFC5321Mailbox(toEmail).valueOr:
      return err("parseRFC5321Mailbox(" & toEmail & "): " & error.message)
    rcptAddrs.add(
      SubmissionAddress(mailbox: toMb, parameters: Opt.none(SubmissionParams))
    )
  let rcpts = parseNonEmptyRcptList(rcptAddrs).valueOr:
    return err("parseNonEmptyRcptList: empty or duplicate recipients")
  ok(Envelope(mailFrom: reversePath(fromAddr), rcptTo: rcpts))

proc resolveOrCreateAliceIdentity*(
    client: var JmapClient, submissionAccountId: AccountId
): Result[Id, string] =
  ## Identity/get → scan for ``alice@example.com``; on miss, Identity/set
  ## create ``email = "alice@example.com"``, ``name = "Alice"``. Returns
  ## the resolved id either way. Idempotent across runs because the lookup
  ## precedes every create. Consolidates the inline block duplicated five
  ## times across Phase F Steps 32–36 and reused by Phase G Steps 38, 40,
  ## 41, 42.
  let (b1, getHandle) = addIdentityGet(initRequestBuilder(), submissionAccountId)
  let resp1 = client.send(b1).valueOr:
    return err("Identity/get send failed: " & error.message)
  let getResp = resp1.get(getHandle).valueOr:
    return err("Identity/get extract failed: " & error.rawType)
  for node in getResp.list:
    let ident = Identity.fromJson(node).valueOr:
      return err("Identity parse failed during alice lookup")
    if ident.email == "alice@example.com":
      return ok(ident.id)
  let createIdent = parseIdentityCreate(email = "alice@example.com", name = "Alice").valueOr:
    return err("parseIdentityCreate failed: " & error.message)
  let cid = parseCreationId("seedAliceIdentity").valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, IdentityCreate]()
  createTbl[cid] = createIdent
  let (b2, setHandle) = addIdentitySet(
    initRequestBuilder(), submissionAccountId, create = Opt.some(createTbl)
  )
  let resp2 = client.send(b2).valueOr:
    return err("Identity/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Identity/set extract failed: " & error.rawType)
  var createdId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Identity/set create rejected: " & error.rawType)
    createdId = item.id
    found = true
  do:
    return err("Identity/set returned no result for creationId seedAliceIdentity")
  doAssert found
  ok(createdId)

proc pollSubmissionPending*(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    budgetMs: int = 5000,
): Result[EmailSubmission[usPending], string] =
  ## Structural mirror of ``pollSubmissionDelivery`` on the opposite
  ## phantom narrowing. Polls ``EmailSubmission/get`` every 200 ms until
  ## ``undoStatus == pending``, returning the phantom-narrowed
  ## ``EmailSubmission[usPending]`` so ``cancelUpdate`` is callable at the
  ## type level. Used by Phase G Steps 41 and 42.
  const PollMs = 200
  let maxIters = max(1, budgetMs div PollMs)
  for _ in 0 ..< maxIters:
    let (b, getHandle) = addEmailSubmissionGet(
      initRequestBuilder(), submissionAccountId, ids = directIds(@[submissionId])
    )
    let resp = client.send(b).valueOr:
      return err("EmailSubmission/get send failed: " & error.message)
    let getResp = resp.get(getHandle).valueOr:
      return err("EmailSubmission/get extract failed: " & error.rawType)
    if getResp.list.len > 0:
      let any = AnyEmailSubmission.fromJson(getResp.list[0]).valueOr:
        return err("AnyEmailSubmission.fromJson failed during poll")
      let pending = any.asPending()
      if pending.isSome:
        return ok(pending.unsafeGet)
    sleep(PollMs)
  err(
    "pollSubmissionPending: budget exhausted (" & $budgetMs &
      "ms) without undoStatus=pending"
  )

proc findEmailBySubjectInMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    mailbox: Id,
    subject: string,
    attempts: int = 10,
    intervalMs: int = 200,
): Result[Id, string] =
  ## Polls ``Email/query`` filtered by ``inMailbox`` + ``subject`` until
  ## a matching email surfaces or the attempt budget elapses. Returns the
  ## first matching id; ``Err`` on absence after ``attempts`` empty
  ## results. Absorbs SMTP delivery asynchrony at the test layer per the
  ## Phase C Step 18 precedent. Used by Phase G Step 38.
  let filter = filterCondition(
    EmailFilterCondition(inMailbox: Opt.some(mailbox), subject: Opt.some(subject))
  )
  for _ in 0 ..< max(1, attempts):
    let (b, queryHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
    let resp = client.send(b).valueOr:
      return err("Email/query send failed: " & error.message)
    let queryResp = resp.get(queryHandle).valueOr:
      return err("Email/query extract failed: " & error.rawType)
    if queryResp.ids.len > 0:
      return ok(queryResp.ids[0])
    sleep(intervalMs)
  err(
    "findEmailBySubjectInMailbox: no match after " & $attempts & " attempts (subject=" &
      subject & ")"
  )

proc seedMultiRecipientDraft*(
    client: var JmapClient,
    mailAccountId: AccountId,
    drafts: Id,
    fromAddr: EmailAddress,
    toAddrs: openArray[EmailAddress],
    subject, body: string,
    creationLabel: string,
): Result[Id, string] =
  ## Variant of ``seedDraftEmail`` parametrised on a list of recipients.
  ## Marks the email with the IANA ``$draft`` keyword (RFC 8621 §4.1.1)
  ## so EmailSubmission references a real draft. Funnels through the
  ## same ``Email/set`` blueprint pipeline; returns the server-assigned
  ## id. Used by Phase G Step 40.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[drafts]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let draftKeyword = parseKeyword("$draft").valueOr:
    return err("parseKeyword($draft) failed: " & error.message)
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
    keywords = initKeywordSet(@[draftKeyword]),
    fromAddr = Opt.some(@[fromAddr]),
    to = Opt.some(@toAddrs),
    subject = Opt.some(subject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

# ---------------------------------------------------------------------------
# Phase H — state-delta baseline helper
# ---------------------------------------------------------------------------

proc captureBaselineState*[T](
    client: var JmapClient, accountId: AccountId
): Result[JmapState, string] =
  ## Issues ``T/get`` with an empty id list to capture the current ``state``
  ## of the entity surface for ``accountId``. The empty ids array (``[]``)
  ## sends ``ids: []`` on the wire — Stalwart returns zero records but the
  ## ``state`` field is still populated, which is the only value the helper
  ## needs. Used as the ``sinceState`` baseline for ``T/changes`` invocations
  ## across Phase H Steps 43, 45, 46, 47, 48. ``T`` must satisfy the
  ## ``getMethodName(T)`` and ``capabilityUri(T)`` resolvers — every entity
  ## registered via ``registerJmapEntity`` in ``mail_entities.nim`` qualifies.
  let (b, getHandle) = addGet[T](initRequestBuilder(), accountId, ids = directIds(@[]))
  let resp = client.send(b).valueOr:
    return err("captureBaselineState[" & $T & "]: send failed: " & error.message)
  let getResp = resp.get(getHandle).valueOr:
    return err("captureBaselineState[" & $T & "]: extract failed: " & error.rawType)
  ok(getResp.state)
