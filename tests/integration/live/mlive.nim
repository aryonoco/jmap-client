# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test scaffolds shared across the live-suite tests.
## ``mconfig.nim`` stays single-purpose (env contract); this module owns
## the server-interaction recipes that would otherwise be inlined
## verbatim across multiple test files: resolving Alice's inbox via
## ``Mailbox/get``, seeding text/plain ``Email`` instances, seeding
## structured (multipart/alternative, multipart/mixed, message/rfc822)
## emails for the body-content tests, and the Cat-B
## ``assertSuccessOrTypedError`` helper that lets every refactor site
## assert client behaviour uniformly across configured targets.
##
## Helpers return ``Result[T, string]`` so callers can chain ``.expect``
## with the same ergonomics as ``loadLiveTestTargets``. They take a
## ``var JmapClient`` because ``client.send`` requires it.

{.push raises: [].}

import std/httpclient
import std/json
import std/os
import std/sets
import std/strutils
import std/tables

const liveBudgetMul* = when defined(jmapLiveShard): 3 else: 1
  ## Polling-budget multiplier. ``just test-full`` runs the Stalwart,
  ## James, and Cyrus live shards concurrently under ``-d:jmapLiveShard``;
  ## three parallel testament + Nim compile + JMAP-call pipelines on the
  ## same host stretch SMTP queue-drain and delivery times well past the
  ## defaults tuned for serial execution. The serial path
  ## (``just test-integration``) leaves the multiplier at 1.

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/protocol/builder
import jmap_client/internal/types/identifiers
import ./mconfig

# Live test files import ``./mlive`` for the high-level helpers
# (``resolveInboxId``, ``seedSimpleEmail``, etc.) — re-exporting
# ``builder`` and ``identifiers`` here gives them ``initRequestBuilder``,
# ``BuilderId``, and ``initBuilderId`` transitively so they don't
# each have to re-import the internal paths.
export builder, identifiers

proc makeBuilderId*(): BuilderId =
  ## A6-brand helper for live tests — fixed ``(0, 0)`` brand is
  ## sufficient because every handle/dispatched-response pair in a
  ## given test is constructed from the same builder, so the brand
  ## check at ``handle.get(dr)`` always sees matching values. Exported
  ## so live tests that ``import ./mlive`` see ``makeBuilderId()``
  ## without re-importing ``mfixtures``.
  initBuilderId(0'u64, 0'u64)

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
  ## ``alice@example.com`` with display name ``"Alice"`` — the seeded
  ## test principal across every configured target. Smart-constructor
  ## invariant: input is RFC-valid by literal so ``parseEmailAddress``
  ## cannot Err here.
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
  let (b, mbHandle) = addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
  let resp = client.send(b.freeze()).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.message)
  for mb in mbResp.list:
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
  let (b, setHandle) = addEmailSet(
    initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
  )
  let resp = client.send(b.freeze()).valueOr:
    return err("Email/set send failed: " & error.message)
  let setResp = resp.get(setHandle).valueOr:
    return err("Email/set extract failed: " & error.message)
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
  ## \r\n<body>``. Configured targets parse it on receive and expose
  ## the parsed form via ``Email/parse``.
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
  let (b1, mbHandle) = addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
  let resp1 = client.send(b1.freeze()).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp1.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.message)
  for mb in mbResp.list:
    if mb.name == name:
      return ok(mb.id)
  let inbox = ?resolveInboxId(client, mailAccountId)
  let create = parseMailboxCreate(name = name, parentId = Opt.some(inbox)).valueOr:
    return err("parseMailboxCreate failed: " & error.message)
  let cid = parseCreationId("phaseEMailbox").valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, MailboxCreate]()
  createTbl[cid] = create
  let (b2, setHandle) = addMailboxSet(
    initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
  )
  let resp2 = client.send(b2.freeze()).valueOr:
    return err("Mailbox/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Mailbox/set extract failed: " & error.message)
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
    initRequestBuilder(makeBuilderId()),
    mailAccountId,
    ids = directIds(@[emailId]),
    properties = Opt.some(@["id", "attachments"]),
  )
  let resp = client.send(b.freeze()).valueOr:
    return err("Email/get send failed: " & error.message)
  let getResp = resp.get(getHandle).valueOr:
    return err("Email/get extract failed: " & error.message)
  if getResp.list.len == 0:
    return err("Email/get returned empty list for " & string(emailId))
  let email = getResp.list[0]
  if email.attachments.len == 0:
    return err("Email/get returned no attachments for " & string(emailId))
  ok(email.attachments[0].blobId)

# ---------------------------------------------------------------------------
# Phase F — EmailSubmission helpers
# ---------------------------------------------------------------------------

func resolveSubmissionAccountId*(session: Session): Result[AccountId, string] =
  ## Reads ``session.primaryAccounts`` for the
  ## ``urn:ietf:params:jmap:submission`` URN. Configured targets may
  ## bind the same id to ``mail`` and ``submission`` or distinct ids;
  ## the helper does not depend on that equality. Sibling of
  ## ``resolveCollationAlgorithms``.
  var accountId: AccountId
  var found = false
  session.primaryAccounts.withValue("urn:ietf:params:jmap:submission", v):
    accountId = v
    found = true
  do:
    return err("session must advertise a primary submission account")
  doAssert found
  ok(accountId)

func resolveMailAccountId*(session: Session): Result[AccountId, string] =
  ## Reads ``session.primaryAccounts`` for the
  ## ``urn:ietf:params:jmap:mail`` URN. Sibling of
  ## ``resolveSubmissionAccountId``. Configured targets may bind the
  ## same id to ``mail`` and ``submission`` or distinct ids; the
  ## helper does not depend on that equality.
  var accountId: AccountId
  var found = false
  session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
    accountId = v
    found = true
  do:
    return err("session must advertise a primary mail account")
  doAssert found
  ok(accountId)

func buildEnvelope*(fromEmail, toEmail: string): Result[Envelope, string] =
  ## Absorbs the four-stage RFC5321Mailbox / SubmissionAddress /
  ## ReversePath / NonEmptyRcptList boilerplate that every Phase F
  ## EmailSubmission test would otherwise repeat. Both addresses use
  ## empty SubmissionParams — the canonical local-domain delivery
  ## shape every configured target accepts.
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
  let (b1, mbHandle) = addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
  let resp1 = client.send(b1.freeze()).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp1.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.message)
  for mb in mbResp.list:
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
  let (b2, setHandle) = addMailboxSet(
    initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
  )
  let resp2 = client.send(b2.freeze()).valueOr:
    return err("Mailbox/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Mailbox/set extract failed: " & error.message)
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

proc awaitSmtpQueueDrain*(
    adminBasic: string, sessionUrl: string, budgetMs: int = 60000 * liveBudgetMul
): Result[void, string] =
  ## Polls Stalwart's admin ``/api/queue/messages?values=true`` endpoint
  ## until ``data.total == 0``. Provides a deterministic barrier for
  ## sequential submission tests against Stalwart: each test exits
  ## only when Stalwart's outgoing SMTP queue is genuinely drained,
  ## eliminating cumulative-load failures in the full integration
  ## suite. The drain barrier is Stalwart-specific because Stalwart
  ## exposes the admin queue API; James and Cyrus use inbox-arrival
  ## verification (``pollEmailDeliveryToInbox``) to observe SMTP
  ## completion. ``adminBasic`` is the base64("admin:password")
  ## credential from ``JMAP_TEST_STALWART_ADMIN_BASIC`` (populated by
  ## ``seed-stalwart.sh``); ``sessionUrl`` is the JMAP session URL,
  ## from which the admin URL is derived (same host:port, different
  ## path). On a clean queue this returns within one poll (~100 ms).
  const PollMs = 100
  let maxIters = max(1, budgetMs div PollMs)
  let baseUrl = sessionUrl.replace("/jmap/session", "")
  let adminUrl = baseUrl & "/api/queue/messages?values=true"
  var headers = newHttpHeaders()
  headers["Authorization"] = "Basic " & adminBasic
  headers["Accept"] = "application/json"
  let httpClient =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpClient(headers = headers)
    except CatchableError as e:
      return err("queue-drain httpClient init failed: " & e.msg)
  defer:
    try:
      httpClient.close()
    except CatchableError:
      discard
  for _ in 0 ..< maxIters:
    let body =
      try:
        {.cast(raises: [CatchableError]).}:
          httpClient.getContent(adminUrl)
      except CatchableError as e:
        return err("queue-drain GET failed: " & e.msg)
    let parsed =
      try:
        {.cast(raises: [CatchableError]).}:
          parseJson(body)
      except CatchableError as e:
        return err("queue-drain parseJson failed: " & e.msg)
    let dataNode = parsed{"data"}
    if dataNode.isNil:
      return err("queue-drain response missing 'data': " & body)
    let totalNode = dataNode{"total"}
    if totalNode.isNil:
      return err("queue-drain response missing 'data.total': " & body)
    let total = totalNode.getInt(-1)
    if total == 0:
      return ok()
    sleep(PollMs)
  err(
    "awaitSmtpQueueDrain: budget exhausted (" & $budgetMs & "ms) without queue draining"
  )

type SubmissionPollState = enum
  spsPolling
  spsFinalised
  spsEvicted

proc trySubmissionGet(
    client: var JmapClient, submissionAccountId: AccountId, submissionId: Id
): Result[(SubmissionPollState, Opt[EmailSubmission[usFinal]]), string] =
  ## Single ``EmailSubmission/get`` poll attempt. Returns the new
  ## state plus the typed ``EmailSubmission[usFinal]`` when the
  ## record carried it.
  let (b, getHandle) = addEmailSubmissionGet(
    initRequestBuilder(makeBuilderId()),
    submissionAccountId,
    ids = directIds(@[submissionId]),
  )
  let resp = client.send(b.freeze()).valueOr:
    return err("EmailSubmission/get send failed: " & error.message)
  let getResp = resp.get(getHandle).valueOr:
    return err("EmailSubmission/get extract failed: " & error.message)
  if getResp.list.len > 0:
    let any = getResp.list[0]
    let final = any.asFinal()
    if final.isSome:
      return ok((spsFinalised, Opt.some(final.unsafeGet)))
    return ok((spsPolling, Opt.none(EmailSubmission[usFinal])))
  if submissionId in getResp.notFound:
    # Cyrus 3.12.2 fire-and-forget eviction
    # (``imap/jmap_mail_submission.c``).
    return ok((spsEvicted, Opt.none(EmailSubmission[usFinal])))
  ok((spsPolling, Opt.none(EmailSubmission[usFinal])))

proc pollSubmissionUntilFinal(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    initialState: SubmissionPollState,
    maxIters: int,
    pollMs: int,
): Result[(SubmissionPollState, Opt[EmailSubmission[usFinal]]), string] =
  ## Iterates ``trySubmissionGet`` until the state leaves
  ## ``spsPolling`` or the iteration budget elapses. Returns the
  ## final state and the typed ``EmailSubmission[usFinal]`` if any
  ## was observed.
  var pendingFinal: Opt[EmailSubmission[usFinal]] = Opt.none(EmailSubmission[usFinal])
  var pollState = initialState
  for _ in 0 ..< maxIters:
    if pollState != spsPolling:
      break
    let (newState, maybeFinal) =
      ?trySubmissionGet(client, submissionAccountId, submissionId)
    pollState = newState
    if maybeFinal.isSome:
      pendingFinal = maybeFinal
    if pollState == spsPolling:
      sleep(pollMs)
  ok((pollState, pendingFinal))

proc pollSubmissionDelivery*(
    client: var JmapClient,
    submissionAccountId: AccountId,
    submissionId: Id,
    createUndoStatus: Opt[UndoStatus] = Opt.none(UndoStatus),
    budgetMs: int = 50000 * liveBudgetMul,
): Result[Opt[EmailSubmission[usFinal]], string] =
  ## Polls EmailSubmission/get until ``undoStatus == final``, then —
  ## when running against Stalwart — awaits Stalwart's outgoing SMTP
  ## queue to drain. The return type is ``Opt[EmailSubmission[usFinal]]``
  ## because servers diverge on submission retention:
  ##
  ## - **Stalwart 0.15.5** retains submission records indefinitely;
  ##   ``/get`` always returns the entity and the helper returns
  ##   ``ok(Opt.some(<final>))``. Callers can pattern-match on the
  ##   inner Opt to inspect the typed ``EmailSubmission[usFinal]``.
  ## - **Cyrus 3.12.2** finalises and discards the submission record
  ##   immediately on non-HOLDFOR submissions
  ##   (``imap/jmap_mail_submission.c``). The ``createUndoStatus``
  ##   argument carries the ``undoStatus`` from the create response
  ##   (RFC 8621 §7.5 ¶2 permitted, captured by
  ##   ``EmailSubmissionCreatedItem.undoStatus``); when it is
  ##   ``Opt.some(usFinal)`` the helper short-circuits — the
  ##   submission is already complete and any poll would race the
  ##   eviction. ``/get`` reporting the id in ``notFound`` mid-poll
  ##   is also treated as "evicted after final".
  ## - **James 3.9** has no usable ``EmailSubmission/get``; live
  ##   tests against James use the ``pollEmailDeliveryToInbox``
  ##   verifier instead (Cat-D pattern).
  ##
  ## ``Err`` only on JMAP-poll budget elapse without ever reaching a
  ## final/evicted state, or queue-drain timeout (Stalwart leg).
  const PollMs = 200
  let maxIters = max(1, budgetMs div PollMs)
  let initialState =
    if createUndoStatus.isSome and createUndoStatus.unsafeGet == usFinal:
      spsEvicted
    else:
      spsPolling
  let (pollState, pendingFinal) = ?pollSubmissionUntilFinal(
    client, submissionAccountId, submissionId, initialState, maxIters, PollMs
  )
  if pollState == spsPolling:
    return err(
      "pollSubmissionDelivery: budget exhausted (" & $budgetMs &
        "ms) without undoStatus=final"
    )
  # K1 barrier: wait for Stalwart's SMTP queue to drain so the
  # helper's contract is genuine SMTP completion, not just JMAP-side
  # commit lock. Reads the Stalwart-prefixed env vars directly so the
  # barrier remains a no-op on the James and Cyrus legs of any Cat-D
  # iteration (their drain semantics are observed via inbox arrival
  # in ``pollEmailDeliveryToInbox``, not via an admin queue API).
  let adminBasic = getEnv("JMAP_TEST_STALWART_ADMIN_BASIC")
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  if adminBasic.len > 0 and sessionUrl.len > 0:
    ?awaitSmtpQueueDrain(adminBasic, sessionUrl)
  ok(pendingFinal)

# ---------------------------------------------------------------------------
# Phase G — multi-principal + cancel-pending helpers
# ---------------------------------------------------------------------------

proc initBobClient*(cfg: LiveTestTarget): Result[JmapClient, ValidationError] =
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
  ## precedes every create.
  ##
  ## Cyrus 3.12.2 emits server-default identities with empty ``email`` /
  ## ``name`` fields (Identity is "read-only from config" —
  ## ``imap/jmap_mail_submission.c:116-120``). When no exact email match
  ## surfaces but the account already has an identity, the helper
  ## returns that identity's id rather than attempting an Identity/set
  ## create that the server lacks (``metUnknownMethod`` on Cyrus).
  let (b1, getHandle) =
    addIdentityGet(initRequestBuilder(makeBuilderId()), submissionAccountId)
  let resp1 = client.send(b1.freeze()).valueOr:
    return err("Identity/get send failed: " & error.message)
  let getResp = resp1.get(getHandle).valueOr:
    return err("Identity/get extract failed: " & error.message)
  var fallbackId: Opt[Id] = Opt.none(Id)
  for ident in getResp.list:
    if ident.email == "alice@example.com":
      return ok(ident.id)
    if fallbackId.isNone:
      fallbackId = Opt.some(ident.id)
  for id in fallbackId:
    return ok(id)
  let createIdent = parseIdentityCreate(email = "alice@example.com", name = "Alice").valueOr:
    return err("parseIdentityCreate failed: " & error.message)
  let cid = parseCreationId("seedAliceIdentity").valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, IdentityCreate]()
  createTbl[cid] = createIdent
  let (b2, setHandle) = addIdentitySet(
    initRequestBuilder(makeBuilderId()),
    submissionAccountId,
    create = Opt.some(createTbl),
  )
  let resp2 = client.send(b2.freeze()).valueOr:
    return err("Identity/set send failed: " & error.message)
  let setResp = resp2.get(setHandle).valueOr:
    return err("Identity/set extract failed: " & error.message)
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
    budgetMs: int = 25000 * liveBudgetMul,
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
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      ids = directIds(@[submissionId]),
    )
    let resp = client.send(b.freeze()).valueOr:
      return err("EmailSubmission/get send failed: " & error.message)
    let getResp = resp.get(getHandle).valueOr:
      return err("EmailSubmission/get extract failed: " & error.message)
    if getResp.list.len > 0:
      let any = getResp.list[0]
      let pending = any.asPending()
      if pending.isSome:
        return ok(pending.unsafeGet)
    sleep(PollMs)
  err(
    "pollSubmissionPending: budget exhausted (" & $budgetMs &
      "ms) without undoStatus=pending"
  )

proc reconnectClient*(target: LiveTestTarget, client: var JmapClient) =
  ## Closes ``client`` and replaces it with a freshly-initialised
  ## one. Used after Email/set seeding when the test then needs
  ## Email/query to surface the seeded ids: Cyrus 3.12.2's Xapian
  ## rolling indexer doesn't propagate writes from the writing
  ## client's HTTP keep-alive session to its own subsequent reads —
  ## the new emails only become observable to a fresh connection.
  ## Stalwart and James index synchronously and are unaffected, but
  ## reconnecting carries no behavioural cost on them either (just
  ## the per-call TCP setup, a few ms).
  client.close()
  client = initJmapClient(
      sessionUrl = target.sessionUrl,
      bearerToken = target.aliceToken,
      authScheme = target.authScheme,
    )
    .expect("reconnectClient initJmapClient[" & $target.kind & "]")

proc pollEmailQueryIndexed*(
    target: LiveTestTarget,
    mailAccountId: AccountId,
    filter: Filter[EmailFilterCondition],
    expectedIds: HashSet[Id],
    budgetMs: int = 30000 * liveBudgetMul,
): Result[seq[Id], string] =
  ## Polls ``Email/query`` with the given ``filter`` until every id in
  ## ``expectedIds`` surfaces in the result set or the budget elapses.
  ## Returns the final ids list (not necessarily containing only the
  ## expected ids — the result set may include other matches).
  ##
  ## Each iteration creates a **fresh** JmapClient so the underlying
  ## TCP connection is closed and re-opened. This works around a
  ## Cyrus 3.12.2 latency where the rolling indexer doesn't surface
  ## newly-seeded emails to a long-lived HTTP keep-alive session
  ## that previously seeded them — the new emails only become
  ## observable to a separate connection. Stalwart and James are
  ## unaffected (they index synchronously and serve consistent
  ## results across keep-alive sessions); the only cost on those
  ## servers is the per-iteration TCP setup, amortised by the
  ## first-iteration return-on-success.
  ##
  ## Used by tests where the server's full-text index settles
  ## asynchronously. Cyrus 3.12.2's Xapian rolling indexer typically
  ## settles within ~500 ms of Email/set on a quiet server.
  ##
  ## ``Err`` if the budget elapses without all expected ids
  ## surfacing — that signals either an indexing failure or an
  ## incorrect test expectation, both worth surfacing as a failed
  ## assertion at the call site.
  const PollMs = 500
  let maxIters = max(1, budgetMs div PollMs)
  for _ in 0 ..< maxIters:
    var client = initJmapClient(
      sessionUrl = target.sessionUrl,
      bearerToken = target.aliceToken,
      authScheme = target.authScheme,
    ).valueOr:
      return err("pollEmailQueryIndexed: initJmapClient failed: " & error.message)
    discard client.fetchSession().valueOr:
      client.close()
      return err("pollEmailQueryIndexed: fetchSession failed: " & error.message)
    let (b, queryHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
    )
    let resp = client.send(b.freeze()).valueOr:
      client.close()
      return err("Email/query send failed: " & error.message)
    let queryResp = resp.get(queryHandle).valueOr:
      client.close()
      return err("Email/query extract failed: " & error.message)
    client.close()
    let ids = queryResp.ids
    var allPresent = true
    for expected in expectedIds:
      var found = false
      for got in ids:
        if got == expected:
          found = true
          break
      if not found:
        allPresent = false
        break
    if allPresent:
      return ok(ids)
    sleep(PollMs)
  err(
    "pollEmailQueryIndexed: " & $budgetMs &
      "ms budget exhausted before every expected id surfaced"
  )

proc findEmailBySubjectInMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    mailbox: Id,
    subject: string,
    attempts: int = 50,
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
    let (b, queryHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
    )
    let resp = client.send(b.freeze()).valueOr:
      return err("Email/query send failed: " & error.message)
    let queryResp = resp.get(queryHandle).valueOr:
      return err("Email/query extract failed: " & error.message)
    if queryResp.ids.len > 0:
      return ok(queryResp.ids[0])
    sleep(intervalMs)
  err(
    "findEmailBySubjectInMailbox: no match after " & $attempts & " attempts (subject=" &
      subject & ")"
  )

proc pollEmailDeliveryToInbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    budgetMs: int = 5000 * liveBudgetMul,
): Result[Id, string] =
  ## Polls for an email with the given ``subject`` to appear in
  ## ``inbox``. Cat-D verification path for any target where
  ## ``EmailSubmission/get`` is unavailable or returns a null
  ## ``deliveryStatus``: James 3.9 has no ``EmailSubmission/get`` at
  ## all; Cyrus 3.12.2 hardcodes ``deliveryStatus`` to ``null``
  ## (`imap/jmap_mail_submission.c:1200-1201`). Stalwart Cat-D legs use
  ## ``pollSubmissionDelivery`` plus the SMTP queue drain barrier.
  ##
  ## **Implementation: search-index-free.** The naive
  ## ``Email/query`` with ``subject`` filter has unbounded indexing lag
  ## on Cyrus under sustained parallel-shard load — the email is
  ## delivered to the mailbox within milliseconds (visible via LMTP +
  ## ``Mailbox/get`` counts), but Cyrus's search index can take minutes
  ## to surface the subject. ``search_index_headers: no`` in
  ## ``imapd.conf`` skips Xapian for headers, but the indexer still
  ## lags. ``Email/query`` with only the ``inMailbox`` filter reads the
  ## mailbox state directly and is consistent the moment LMTP completes;
  ## ``Email/get`` likewise reads the cache without touching the search
  ## index. So we use those two and filter by subject client-side.
  ##
  ## Cost: O(mailbox-size) per poll iteration on the wire. Test
  ## mailboxes stay small (each test cleans up after itself), so this is
  ## bounded.
  const PollMs = 100
  let maxIters = max(1, budgetMs div PollMs)
  let filter = filterCondition(EmailFilterCondition(inMailbox: Opt.some(inbox)))
  for _ in 0 ..< maxIters:
    let (b1, queryHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(filter)
    )
    let resp1 = client.send(b1.freeze()).valueOr:
      return err("Email/query send failed: " & error.message)
    let qr = resp1.get(queryHandle).valueOr:
      return err("Email/query extract failed: " & error.message)
    if qr.ids.len > 0:
      let (b2, getHandle) = addEmailGet(
        initRequestBuilder(makeBuilderId()),
        mailAccountId,
        ids = directIds(qr.ids),
        properties = Opt.some(@["id", "subject"]),
      )
      let resp2 = client.send(b2.freeze()).valueOr:
        return err("Email/get send failed: " & error.message)
      let gr = resp2.get(getHandle).valueOr:
        return err("Email/get extract failed: " & error.message)
      for emailRec in gr.list:
        for actualSubject in emailRec.subject:
          if actualSubject == subject:
            for id in emailRec.id:
              return ok(id)
    sleep(PollMs)
  err(
    "pollEmailDeliveryToInbox: " & $budgetMs &
      "ms budget exhausted without arrival (subject=" & subject & ")"
  )

template assertOn*(target: LiveTestTarget, cond: bool, msg: string) =
  ## Suffixes the bracketed target kind to every assertion message so
  ## test failures from a single ``forEachLiveTarget`` iteration are
  ## attributable to a specific server. Pure expansion, no helpers.
  doAssert cond, msg & " [" & $target.kind & "]"

template assertOn*(target: LiveTestTarget, cond: bool) =
  ## Two-argument variant of ``assertOn`` for boolean post-conditions
  ## that don't need a custom message — the bracketed target kind is
  ## still surfaced so failures attribute to a specific server.
  doAssert cond, "[" & $target.kind & "]"

template assertSuccessOrTypedError*[T](
    target: LiveTestTarget,
    extract: Result[T, GetError],
    allowedErrors: set[MethodErrorType],
    onSuccess: untyped,
) =
  ## Cat-B refactor helper. Asserts on client-library behaviour
  ## uniformly across configured targets:
  ##
  ## - When the server implements the surface, the body runs against
  ##   the parsed result (bound as ``success`` injected into the
  ##   caller's scope) — verifying the same semantic round-trip the
  ##   pre-refactor test asserted.
  ## - When the server returns a typed JMAP error, the error type
  ##   must be in ``allowedErrors`` — exercising the client's typed-
  ##   error projection against a real-world server response.
  ##
  ## Under A6 the inner railway is ``GetError``; the ``gekMethod`` arm
  ## wraps the original ``MethodError`` verbatim, while
  ## ``gekHandleMismatch`` indicates a programming bug (handle from a
  ## different builder) and is fatal here.
  ##
  ## Both arms are positive client-library contract assertions; the
  ## test never branches its assertion on which server replied. See
  ## ``docs/plan/12-integration-testing-L-cyrus.md`` §0 for the
  ## testing philosophy and the operational test ("If a mail-client
  ## application developer linked this library and ran my test code
  ## against any RFC-conformant JMAP server …").
  case extract.isOk
  of true:
    let success {.inject.} = extract.unsafeValue
    onSuccess
  of false:
    let getErr = extract.unsafeError
    assertOn target,
      getErr.kind == gekMethod,
      "inner-railway error must be gekMethod, not gekHandleMismatch"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in allowedErrors,
      "method error must be in allowed set " & $allowedErrors & " (got rawType=" &
        methodErr.rawType & ")"

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
  ## sends ``ids: []`` on the wire — configured targets return zero records
  ## but the ``state`` field is still populated, which is the only value
  ## the helper
  ## needs. Used as the ``sinceState`` baseline for ``T/changes`` invocations
  ## across Phase H Steps 43, 45, 46, 47, 48. ``T`` must satisfy the
  ## ``getMethodName(T)`` and ``capabilityUri(T)`` resolvers — every entity
  ## registered via ``registerJmapEntity`` in ``mail_entities.nim`` qualifies.
  let (b, getHandle) =
    addGet[T](initRequestBuilder(makeBuilderId()), accountId, ids = directIds(@[]))
  let resp = client.send(b.freeze()).valueOr:
    return err("captureBaselineState[" & $T & "]: send failed: " & error.message)
  let getResp = resp.get(getHandle).valueOr:
    return err("captureBaselineState[" & $T & "]: extract failed: " & error.message)
  ok(getResp.state)

# ---------------------------------------------------------------------------
# Phase I — extra-headers seed + submission corpus helpers
# ---------------------------------------------------------------------------

proc seedEmailWithHeaders*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    fromAddr: EmailAddress,
    toAddr: EmailAddress,
    subject: string,
    body: string,
    extraHeaders: openArray[(BlueprintEmailHeaderName, BlueprintHeaderMultiValue)],
    creationLabel: string,
): Result[Id, string] =
  ## Variant of ``seedSimpleEmail`` parametrised on caller-supplied
  ## from/to/body and a table of top-level extra headers. Wraps the
  ## existing ``parseEmailBlueprint`` plumbing so the test body can stay
  ## free of repetitive ``BlueprintBodyPart`` / ``Table`` boilerplate.
  ## Used by Phase I Step 53.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
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
  var headerTbl = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  for (k, v) in extraHeaders:
    headerTbl[k] = v
  let blueprint = parseEmailBlueprint(
    mailboxIds = mailboxIds,
    body = flatBody(textBody = Opt.some(textPart)),
    fromAddr = Opt.some(@[fromAddr]),
    to = Opt.some(@[toAddr]),
    subject = Opt.some(subject),
    extraHeaders = headerTbl,
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  emailSetCreate(client, mailAccountId, blueprint, creationLabel)

proc seedSubmissionCorpus*(
    client: var JmapClient,
    mailAccountId: AccountId,
    submissionAccountId: AccountId,
    drafts: Id,
    fromAddr: EmailAddress,
    identities: openArray[Id],
    recipients: openArray[EmailAddress],
    subjects: openArray[string],
    creationLabelPrefix: string,
    holdForSeconds: Opt[HoldForSeconds] = Opt.none(HoldForSeconds),
): Result[seq[Id], string] =
  ## Builds N submissions. ``N == identities.len``; ``recipients`` and
  ## ``subjects`` cycle through their lengths so the caller controls
  ## the corpus shape.  When ``holdForSeconds`` is ``Opt.some``, each
  ## submission carries a HOLDFOR= envelope parameter so the server
  ## retains the record in ``pending`` state — this lets tests that
  ## want to inspect the submission via ``EmailSubmission/get`` work
  ## on Cyrus 3.12.2 (whose fire-and-forget submission model evicts
  ## records on ``final``). Each iteration: seed a draft via
  ## ``seedDraftEmail``, ``EmailSubmission/set create``, then poll to
  ## ``usFinal`` via ``pollSubmissionDelivery``. Returns the seq of
  ## submission ids in submission order.
  if identities.len == 0:
    return err("seedSubmissionCorpus: identities must not be empty")
  if recipients.len == 0:
    return err("seedSubmissionCorpus: recipients must not be empty")
  if subjects.len == 0:
    return err("seedSubmissionCorpus: subjects must not be empty")
  var submissionIds: seq[Id] = @[]
  for i, identityId in identities:
    let recipient = recipients[i mod recipients.len]
    let subject = subjects[i mod subjects.len]
    let draftId = seedDraftEmail(
      client,
      mailAccountId,
      drafts,
      fromAddr,
      recipient,
      subject,
      "phase-i corpus body " & $i,
      creationLabelPrefix & "-draft-" & $i,
    ).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] seedDraftEmail: " & error)
    let envelope =
      if holdForSeconds.isSome:
        buildEnvelopeWithHoldFor(
          fromAddr.email, recipient.email, holdForSeconds.unsafeGet
        ).valueOr:
          return
            err("seedSubmissionCorpus[" & $i & "] buildEnvelopeWithHoldFor: " & error)
      else:
        buildEnvelope(fromAddr.email, recipient.email).valueOr:
          return err("seedSubmissionCorpus[" & $i & "] buildEnvelope: " & error)
    let blueprint = parseEmailSubmissionBlueprint(
      identityId = identityId, emailId = draftId, envelope = Opt.some(envelope)
    ).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] parseEmailSubmissionBlueprint")
    let cid = parseCreationId(creationLabelPrefix & "-sub-" & $i).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] parseCreationId: " & error.message)
    var createTbl = initTable[CreationId, EmailSubmissionBlueprint]()
    createTbl[cid] = blueprint
    let (b, setHandle) = addEmailSubmissionSet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(createTbl),
    )
    let resp = client.send(b.freeze()).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] send: " & error.message)
    let setResp = resp.get(setHandle).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] extract: " & error.message)
    var submissionId: Id
    var createdItem: EmailSubmissionCreatedItem
    var found = false
    setResp.createResults.withValue(cid, outcome):
      let item = outcome.valueOr:
        return err("seedSubmissionCorpus[" & $i & "] create rejected: " & error.rawType)
      submissionId = item.id
      createdItem = item
      found = true
    do:
      return err("seedSubmissionCorpus[" & $i & "] no create result")
    doAssert found
    let final = pollSubmissionDelivery(
      client,
      submissionAccountId,
      submissionId,
      createUndoStatus = createdItem.undoStatus,
    ).valueOr:
      return err("seedSubmissionCorpus[" & $i & "] pollSubmissionDelivery: " & error)
    discard final
    submissionIds.add(submissionId)
  ok(submissionIds)

# ---------------------------------------------------------------------------
# Phase J — typed-builder-bypass helpers
# ---------------------------------------------------------------------------

proc sendRawInvocation*(
    client: var JmapClient,
    capabilityUris: openArray[string],
    methodName: string,
    arguments: JsonNode,
    callId: string = "c0",
): Result[envelope.Response, ClientError] {.used.} =
  ## Bypasses ``RequestBuilder``'s typed surface to construct a
  ## ``Request`` carrying a single hand-rolled invocation. Uses
  ## ``parseInvocation`` so unknown method names (e.g.
  ## ``Mailbox/snorgleflarp``) round-trip losslessly into the
  ## invocation's ``rawName``. Routes through
  ## ``sendRawHttpForTesting`` because the public ``send`` accepts
  ## only ``BuiltRequest`` (P21 sealed); pre-flight validation is
  ## NOT applied here — adversarial wire shapes are the whole point.
  ## Used by Phase J Steps 62, 67, 68, 70, 72.
  let mcid = parseMethodCallId(callId).valueOr:
    return err(clientError(transportError(tekNetwork, "invalid callId: " & callId)))
  let invocation = parseInvocation(methodName, arguments, mcid).valueOr:
    return
      err(clientError(transportError(tekNetwork, "invalid methodName: " & methodName)))
  var caps: seq[string] = @[]
  for u in capabilityUris:
    caps.add(u)
  let req = Request(
    `using`: caps,
    methodCalls: @[invocation],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  client.sendRawHttpForTesting($req.toJson())

proc buildOversizedRequest*(
    accountId: AccountId, idCount: int
): RequestBuilder {.used.} =
  ## Builds a ``Mailbox/get`` ``RequestBuilder`` carrying ``idCount``
  ## synthetic ids, suitable for driving ``validateLimits(builder,
  ## caps)`` past ``maxObjectsInGet``. The synthetic ids are valid
  ## ``Id`` shapes (1–255 octets, no control chars) so construction
  ## never fails. Returns the builder so callers reach the typed
  ## per-call validation path via ``client.send(builder.freeze())``. Used by
  ## Phase J Step 64.
  var ids = newSeq[Id](idCount)
  for i in 0 ..< idCount:
    ids[i] = Id("phaseJsynth" & $i)
  let (b, _) =
    addMailboxGet(initRequestBuilder(makeBuilderId()), accountId, ids = directIds(ids))
  b

func injectBrokenBackReference*(
    arguments: JsonNode,
    refField: string,
    refPath: string,
    refName: string = "Mailbox/get",
): JsonNode {.used.} =
  ## Wraps an ``arguments`` object with a ``#<refField>`` JSON-Pointer
  ## entry whose target path is ``refPath`` (caller-supplied —
  ## intentionally broken / deep / adversarial). Pure helper. The
  ## caller-supplied ``refName`` lets the broken reference name any
  ## prior method response. Used by Phase J Steps 62, 67, 74.
  result = newJObject()
  for k, v in arguments.pairs:
    if k != refField:
      result[k] = v
  result["#" & refField] = %*{"resultOf": "c0", "name": refName, "path": refPath}
