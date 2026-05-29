# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Email entity and supporting types for RFC 8621 (JMAP Mail) section 4.
## Email is the store-backed read model; ParsedEmail is the blob-backed
## model for Email/parse. EmailComparator and EmailBodyFetchOptions are
## query-time parameter types. All types colocated per domain cohesion
## (Decision D14).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sets
import std/strutils
import std/tables

import ../types/validation
import ../types/primitives
import ../types/framework
import ../types/identifiers
import ../types/errors
import ../types/collation
import ../types/field_echo

import ./keyword
import ./mailbox
import ./addresses
import ./headers
import ./body

# =============================================================================
# PlainSortProperty
# =============================================================================

type PlainSortProperty* = enum
  ## Sort properties that take no additional parameters (RFC 8621 section 4.4.2).
  pspReceivedAt = "receivedAt"
  pspSize = "size"
  pspFrom = "from"
  pspTo = "to"
  pspSubject = "subject"
  pspSentAt = "sentAt"

# =============================================================================
# KeywordSortProperty
# =============================================================================

type KeywordSortProperty* = enum
  ## Sort properties that require an accompanying Keyword (RFC 8621 section 4.4.2).
  kspHasKeyword = "hasKeyword"
  kspAllInThreadHaveKeyword = "allInThreadHaveKeyword"
  kspSomeInThreadHaveKeyword = "someInThreadHaveKeyword"

# =============================================================================
# EmailComparator
# =============================================================================

type EmailComparatorKind* = enum
  ## Discriminant for EmailComparator: plain sort or keyword-bearing sort.
  eckPlain
  eckKeyword

type EmailComparator* {.ruleOff: "objects".} = object
  ## Email-specific sort criterion (RFC 8621 section 4.4.2). Extends the
  ## standard Comparator with keyword-bearing sort properties. Case object
  ## makes illegal states (keyword sort without keyword) unrepresentable.
  isAscending*: Opt[bool] ## Absent = server default (RFC: true).
  collation*: Opt[CollationAlgorithm] ## RFC 4790 collation identifier.
  case kind*: EmailComparatorKind
  of eckPlain:
    property*: PlainSortProperty ## Non-keyword sort property.
  of eckKeyword:
    keywordProperty*: KeywordSortProperty ## Keyword-bearing sort property.
    keyword*: Keyword ## Required for keyword sorts.

func plainComparator*(
    property: PlainSortProperty,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): EmailComparator =
  ## Constructs an EmailComparator for a non-keyword sort property.
  ## Infallible — all input combinations are valid.
  return EmailComparator(
    kind: eckPlain, property: property, isAscending: isAscending, collation: collation
  )

func keywordComparator*(
    keywordProperty: KeywordSortProperty,
    keyword: Keyword,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): EmailComparator =
  ## Constructs an EmailComparator for a keyword-bearing sort property.
  ## Infallible — all input combinations are valid.
  return EmailComparator(
    kind: eckKeyword,
    keywordProperty: keywordProperty,
    keyword: keyword,
    isAscending: isAscending,
    collation: collation,
  )

# =============================================================================
# EmailGetProperty — typed Email/get + Email/parse property selector (A3.6)
# =============================================================================

type EmailGetPropertyKind* = enum
  ## Discriminator for ``EmailGetProperty``. Backing strings are the
  ## RFC 8621 §4.1 Email property wire names; ``egkHeader`` carries a
  ## dynamic ``header:Name[:asForm][:all]`` selector, ``egkOther`` a
  ## capability-extension property whose raw identifier lives alongside.
  egkId = "id"
  egkBlobId = "blobId"
  egkThreadId = "threadId"
  egkMailboxIds = "mailboxIds"
  egkKeywords = "keywords"
  egkSize = "size"
  egkReceivedAt = "receivedAt"
  egkHeaders = "headers"
  egkMessageId = "messageId"
  egkInReplyTo = "inReplyTo"
  egkReferences = "references"
  egkSender = "sender"
  egkFrom = "from"
  egkTo = "to"
  egkCc = "cc"
  egkBcc = "bcc"
  egkReplyTo = "replyTo"
  egkSubject = "subject"
  egkSentAt = "sentAt"
  egkBodyStructure = "bodyStructure"
  egkBodyValues = "bodyValues"
  egkTextBody = "textBody"
  egkHtmlBody = "htmlBody"
  egkAttachments = "attachments"
  egkHasAttachment = "hasAttachment"
  egkPreview = "preview"
  egkHeader ## dynamic ``header:Name[:asForm][:all]`` form
  egkOther ## capability-extension property

type EmailGetProperty* {.ruleOff: "objects".} = object
  ## Typed RFC 8621 §4.1 Email/get + §4.9 Email/parse property selector.
  ## Construction sealed; use the ``egp…`` constants, ``emailGetHeader``,
  ## or ``parseEmailGetProperty``.
  case rawKind: EmailGetPropertyKind
  of egkHeader:
    rawHeader: HeaderPropertyKey
  of egkOther:
    rawIdentifier: string
  of egkId, egkBlobId, egkThreadId, egkMailboxIds, egkKeywords, egkSize, egkReceivedAt,
      egkHeaders, egkMessageId, egkInReplyTo, egkReferences, egkSender, egkFrom, egkTo,
      egkCc, egkBcc, egkReplyTo, egkSubject, egkSentAt, egkBodyStructure, egkBodyValues,
      egkTextBody, egkHtmlBody, egkAttachments, egkHasAttachment, egkPreview:
    discard

func kind*(p: EmailGetProperty): EmailGetPropertyKind =
  ## Returns the discriminator — a named arm, ``egkHeader``, or ``egkOther``.
  p.rawKind

func wireName*(p: EmailGetProperty): string =
  ## RFC 8621 §4.1 wire name. ``egkHeader`` reconstructs the
  ## ``header:Name[:asForm][:all]`` string; ``egkOther`` is the captured
  ## identifier.
  case p.rawKind
  of egkHeader:
    p.rawHeader.toPropertyString()
  of egkOther:
    p.rawIdentifier
  of egkId, egkBlobId, egkThreadId, egkMailboxIds, egkKeywords, egkSize, egkReceivedAt,
      egkHeaders, egkMessageId, egkInReplyTo, egkReferences, egkSender, egkFrom, egkTo,
      egkCc, egkBcc, egkReplyTo, egkSubject, egkSentAt, egkBodyStructure, egkBodyValues,
      egkTextBody, egkHtmlBody, egkAttachments, egkHasAttachment, egkPreview:
    $p.rawKind

func `$`*(p: EmailGetProperty): string =
  ## Wire-form string — equivalent to ``wireName``.
  p.wireName

func `==`*(a, b: EmailGetProperty): bool =
  ## Wire-identity equality: the classifying parser never yields ``egkOther``
  ## for a known wire name, and ``egkHeader`` round-trips through its
  ## ``HeaderPropertyKey`` wire form, so wire-name identity is structural
  ## identity.
  a.wireName == b.wireName

func hash*(p: EmailGetProperty): Hash =
  ## Consistent with ``==`` — equal wire names hash equal.
  hash(p.wireName)

const
  egpId* = EmailGetProperty(rawKind: egkId) ## Selects ``id``.
  egpBlobId* = EmailGetProperty(rawKind: egkBlobId) ## Selects ``blobId``.
  egpThreadId* = EmailGetProperty(rawKind: egkThreadId) ## Selects ``threadId``.
  egpMailboxIds* = EmailGetProperty(rawKind: egkMailboxIds) ## Selects ``mailboxIds``.
  egpKeywords* = EmailGetProperty(rawKind: egkKeywords) ## Selects ``keywords``.
  egpSize* = EmailGetProperty(rawKind: egkSize) ## Selects ``size``.
  egpReceivedAt* = EmailGetProperty(rawKind: egkReceivedAt) ## Selects ``receivedAt``.
  egpHeaders* = EmailGetProperty(rawKind: egkHeaders) ## Selects ``headers``.
  egpMessageId* = EmailGetProperty(rawKind: egkMessageId) ## Selects ``messageId``.
  egpInReplyTo* = EmailGetProperty(rawKind: egkInReplyTo) ## Selects ``inReplyTo``.
  egpReferences* = EmailGetProperty(rawKind: egkReferences) ## Selects ``references``.
  egpSender* = EmailGetProperty(rawKind: egkSender) ## Selects ``sender``.
  egpFrom* = EmailGetProperty(rawKind: egkFrom) ## Selects ``from``.
  egpTo* = EmailGetProperty(rawKind: egkTo) ## Selects ``to``.
  egpCc* = EmailGetProperty(rawKind: egkCc) ## Selects ``cc``.
  egpBcc* = EmailGetProperty(rawKind: egkBcc) ## Selects ``bcc``.
  egpReplyTo* = EmailGetProperty(rawKind: egkReplyTo) ## Selects ``replyTo``.
  egpSubject* = EmailGetProperty(rawKind: egkSubject) ## Selects ``subject``.
  egpSentAt* = EmailGetProperty(rawKind: egkSentAt) ## Selects ``sentAt``.
  egpBodyStructure* = EmailGetProperty(rawKind: egkBodyStructure)
    ## Selects ``bodyStructure``.
  egpBodyValues* = EmailGetProperty(rawKind: egkBodyValues) ## Selects ``bodyValues``.
  egpTextBody* = EmailGetProperty(rawKind: egkTextBody) ## Selects ``textBody``.
  egpHtmlBody* = EmailGetProperty(rawKind: egkHtmlBody) ## Selects ``htmlBody``.
  egpAttachments* = EmailGetProperty(rawKind: egkAttachments) ## Selects ``attachments``.
  egpHasAttachment* = EmailGetProperty(rawKind: egkHasAttachment)
    ## Selects ``hasAttachment``.
  egpPreview* = EmailGetProperty(rawKind: egkPreview) ## Selects ``preview``.

func emailGetHeader*(key: HeaderPropertyKey): EmailGetProperty =
  ## Header-field selector (``header:Name[:asForm][:all]``). ``key`` is
  ## already validated, so this constructor cannot fail.
  EmailGetProperty(rawKind: egkHeader, rawHeader: key)

func parseEmailGetProperty*(raw: string): Result[EmailGetProperty, ValidationError] =
  ## Classifying smart constructor: ``header:``-prefixed input parses as a
  ## ``HeaderPropertyKey``; otherwise an exact, case-sensitive match against
  ## the RFC 8621 §4.1 wire names, with unknown non-control strings falling
  ## to ``egkOther`` (capability-extension forward-compat, A11).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "EmailGetProperty", raw))
  if raw.startsWith("header:"):
    let key = ?parseHeaderPropertyName(raw)
    return ok(EmailGetProperty(rawKind: egkHeader, rawHeader: key))
  case raw
  of "id":
    ok(egpId)
  of "blobId":
    ok(egpBlobId)
  of "threadId":
    ok(egpThreadId)
  of "mailboxIds":
    ok(egpMailboxIds)
  of "keywords":
    ok(egpKeywords)
  of "size":
    ok(egpSize)
  of "receivedAt":
    ok(egpReceivedAt)
  of "headers":
    ok(egpHeaders)
  of "messageId":
    ok(egpMessageId)
  of "inReplyTo":
    ok(egpInReplyTo)
  of "references":
    ok(egpReferences)
  of "sender":
    ok(egpSender)
  of "from":
    ok(egpFrom)
  of "to":
    ok(egpTo)
  of "cc":
    ok(egpCc)
  of "bcc":
    ok(egpBcc)
  of "replyTo":
    ok(egpReplyTo)
  of "subject":
    ok(egpSubject)
  of "sentAt":
    ok(egpSentAt)
  of "bodyStructure":
    ok(egpBodyStructure)
  of "bodyValues":
    ok(egpBodyValues)
  of "textBody":
    ok(egpTextBody)
  of "htmlBody":
    ok(egpHtmlBody)
  of "attachments":
    ok(egpAttachments)
  of "hasAttachment":
    ok(egpHasAttachment)
  of "preview":
    ok(egpPreview)
  else:
    ok(EmailGetProperty(rawKind: egkOther, rawIdentifier: raw))

defineSealedNonEmptySeqOps(EmailGetProperty)

# =============================================================================
# EmailBodyProperty — typed Email/get bodyProperties selector (A3.6)
# =============================================================================

type EmailBodyPropertyKind* = enum
  ## Discriminator for ``EmailBodyProperty``. Backing strings are the
  ## RFC 8621 §4.1.4 EmailBodyPart property wire names; ``ebpkHeader``
  ## carries a dynamic ``header:Name[:asForm][:all]`` selector, ``ebpkOther``
  ## a capability-extension property whose raw identifier lives alongside.
  ebpkPartId = "partId"
  ebpkBlobId = "blobId"
  ebpkSize = "size"
  ebpkName = "name"
  ebpkType = "type"
  ebpkCharset = "charset"
  ebpkDisposition = "disposition"
  ebpkCid = "cid"
  ebpkLanguage = "language"
  ebpkLocation = "location"
  ebpkSubParts = "subParts"
  ebpkHeaders = "headers"
  ebpkHeader ## dynamic ``header:Name[:asForm][:all]`` form
  ebpkOther ## capability-extension property

type EmailBodyProperty* {.ruleOff: "objects".} = object
  ## Typed RFC 8621 §4.1.4 EmailBodyPart property selector for the
  ## ``bodyProperties`` fetch override. Construction sealed; use the
  ## ``ebp…`` constants, ``emailBodyHeader``, or ``parseEmailBodyProperty``.
  case rawKind: EmailBodyPropertyKind
  of ebpkHeader:
    rawHeader: HeaderPropertyKey
  of ebpkOther:
    rawIdentifier: string
  of ebpkPartId, ebpkBlobId, ebpkSize, ebpkName, ebpkType, ebpkCharset, ebpkDisposition,
      ebpkCid, ebpkLanguage, ebpkLocation, ebpkSubParts, ebpkHeaders:
    discard

func kind*(p: EmailBodyProperty): EmailBodyPropertyKind =
  ## Returns the discriminator — a named arm, ``ebpkHeader``, or ``ebpkOther``.
  p.rawKind

func wireName*(p: EmailBodyProperty): string =
  ## RFC 8621 §4.1.4 wire name. ``ebpkHeader`` reconstructs the
  ## ``header:Name[:asForm][:all]`` string; ``ebpkOther`` is the captured
  ## identifier.
  case p.rawKind
  of ebpkHeader:
    p.rawHeader.toPropertyString()
  of ebpkOther:
    p.rawIdentifier
  of ebpkPartId, ebpkBlobId, ebpkSize, ebpkName, ebpkType, ebpkCharset, ebpkDisposition,
      ebpkCid, ebpkLanguage, ebpkLocation, ebpkSubParts, ebpkHeaders:
    $p.rawKind

func `$`*(p: EmailBodyProperty): string =
  ## Wire-form string — equivalent to ``wireName``.
  p.wireName

func `==`*(a, b: EmailBodyProperty): bool =
  ## Wire-identity equality: the classifying parser never yields ``ebpkOther``
  ## for a known wire name, and ``ebpkHeader`` round-trips through its
  ## ``HeaderPropertyKey`` wire form, so wire-name identity is structural
  ## identity.
  a.wireName == b.wireName

func hash*(p: EmailBodyProperty): Hash =
  ## Consistent with ``==`` — equal wire names hash equal.
  hash(p.wireName)

const
  ebpPartId* = EmailBodyProperty(rawKind: ebpkPartId) ## Selects ``partId``.
  ebpBlobId* = EmailBodyProperty(rawKind: ebpkBlobId) ## Selects ``blobId``.
  ebpSize* = EmailBodyProperty(rawKind: ebpkSize) ## Selects ``size``.
  ebpName* = EmailBodyProperty(rawKind: ebpkName) ## Selects ``name``.
  ebpType* = EmailBodyProperty(rawKind: ebpkType) ## Selects ``type``.
  ebpCharset* = EmailBodyProperty(rawKind: ebpkCharset) ## Selects ``charset``.
  ebpDisposition* = EmailBodyProperty(rawKind: ebpkDisposition)
    ## Selects ``disposition``.
  ebpCid* = EmailBodyProperty(rawKind: ebpkCid) ## Selects ``cid``.
  ebpLanguage* = EmailBodyProperty(rawKind: ebpkLanguage) ## Selects ``language``.
  ebpLocation* = EmailBodyProperty(rawKind: ebpkLocation) ## Selects ``location``.
  ebpSubParts* = EmailBodyProperty(rawKind: ebpkSubParts) ## Selects ``subParts``.
  ebpHeaders* = EmailBodyProperty(rawKind: ebpkHeaders) ## Selects ``headers``.

func emailBodyHeader*(key: HeaderPropertyKey): EmailBodyProperty =
  ## Header-field body-part selector (``header:Name[:asForm][:all]``). ``key``
  ## is already validated, so this constructor cannot fail.
  EmailBodyProperty(rawKind: ebpkHeader, rawHeader: key)

func parseEmailBodyProperty*(raw: string): Result[EmailBodyProperty, ValidationError] =
  ## Classifying smart constructor: ``header:``-prefixed input parses as a
  ## ``HeaderPropertyKey``; otherwise an exact, case-sensitive match against
  ## the RFC 8621 §4.1.4 wire names, with unknown non-control strings falling
  ## to ``ebpkOther`` (capability-extension forward-compat, A11).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "EmailBodyProperty", raw))
  if raw.startsWith("header:"):
    let key = ?parseHeaderPropertyName(raw)
    return ok(EmailBodyProperty(rawKind: ebpkHeader, rawHeader: key))
  case raw
  of "partId":
    ok(ebpPartId)
  of "blobId":
    ok(ebpBlobId)
  of "size":
    ok(ebpSize)
  of "name":
    ok(ebpName)
  of "type":
    ok(ebpType)
  of "charset":
    ok(ebpCharset)
  of "disposition":
    ok(ebpDisposition)
  of "cid":
    ok(ebpCid)
  of "language":
    ok(ebpLanguage)
  of "location":
    ok(ebpLocation)
  of "subParts":
    ok(ebpSubParts)
  of "headers":
    ok(ebpHeaders)
  else:
    ok(EmailBodyProperty(rawKind: ebpkOther, rawIdentifier: raw))

defineSealedNonEmptySeqOps(EmailBodyProperty)

# =============================================================================
# EmailBodyFetchOptions
# =============================================================================

type BodyValueScope* = enum
  ## Which body value parts to include in ``bodyValues``.
  ## Replaces three RFC booleans with a single domain-meaningful choice (D9).
  ## ``bvsNone`` must remain first (ordinal 0) so ``default()`` produces
  ## correct RFC defaults.
  bvsNone ## No body values fetched (all three bools false).
  bvsText ## fetchTextBodyValues = true.
  bvsHtml ## fetchHTMLBodyValues = true.
  bvsTextAndHtml ## fetchTextBodyValues = true, fetchHTMLBodyValues = true.
  bvsAll ## fetchAllBodyValues = true.

type EmailBodyFetchOptions* {.ruleOff: "objects".} = object
  ## Shared parameters for Email/get and Email/parse body value fetching.
  ## ``default(EmailBodyFetchOptions)`` produces correct RFC defaults
  ## (no body properties override, no body values, no truncation).
  bodyProperties*: Opt[NonEmptySeq[EmailBodyProperty]]
    ## Override default body part properties (RFC 8621 §4.1.4). Typed
    ## selector; ``Opt.none`` keeps the server's default property set.
  fetchBodyValues*: BodyValueScope ## Default: bvsNone.
  maxBodyValueBytes*: Opt[UnsignedInt] ## Absent = no truncation.

# =============================================================================
# Email
# =============================================================================

type Email* {.ruleOff: "objects".} = object
  ## Server-shaped Email read model (RFC 8621 section 4.1). Every field
  ## the wire admits absence on is ``Opt[T]`` because ``Email/get``
  ## supports property filtering — any property may be absent in a
  ## sparse response. The default-properties fetch (``properties =
  ## Opt.none``) populates each Opt with ``Opt.some``; property-filtered
  ## fetches populate only the requested properties.

  # -- Metadata (section 4.1.1) -- server-set; absent under property filter
  id*: Opt[Id] ## JMAP object id (not Message-ID header).
  blobId*: Opt[BlobId] ## Raw RFC 5322 octets.
  threadId*: Opt[Id] ## Thread this Email belongs to.
  mailboxIds*: Opt[MailboxIdSet]
    ## At least one Mailbox at all times when present (RFC §4.1.1
    ## server invariant); ``Opt.none`` means the property was not
    ## requested.
  keywords*: Opt[KeywordSet] ## Default-properties shape: ``Opt.some(empty set)``.
  size*: Opt[UnsignedInt] ## Raw message size in octets.
  receivedAt*: Opt[UTCDate] ## IMAP internal date.

  # -- Convenience headers (section 4.1.2-4.1.3) -- Opt.none = header absent in message
  messageId*: Opt[seq[string]] ## header:Message-ID:asMessageIds
  inReplyTo*: Opt[seq[string]] ## header:In-Reply-To:asMessageIds
  references*: Opt[seq[string]] ## header:References:asMessageIds
  sender*: Opt[seq[EmailAddress]] ## header:Sender:asAddresses
  fromAddr*: Opt[seq[EmailAddress]]
    ## header:From:asAddresses (``from`` is a Nim keyword).
  to*: Opt[seq[EmailAddress]] ## header:To:asAddresses
  cc*: Opt[seq[EmailAddress]] ## header:Cc:asAddresses
  bcc*: Opt[seq[EmailAddress]] ## header:Bcc:asAddresses
  replyTo*: Opt[seq[EmailAddress]] ## header:Reply-To:asAddresses
  subject*: Opt[string] ## header:Subject:asText
  sentAt*: Opt[Date] ## header:Date:asDate

  # -- Raw headers (section 4.1.3) --
  headers*: seq[EmailHeader] ## All header fields in message order; @[] if absent.

  # -- Dynamic header properties (section 4.1.3) --
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
    ## Parsed headers requested via ``header:Name:asForm`` (last instance).
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
    ## Parsed headers requested via ``header:Name:asForm:all`` (all instances).

  # -- Body (section 4.1.4) --
  bodyStructure*: Opt[EmailBodyPart]
    ## Full MIME tree; ``Opt.none`` when ``bodyStructure`` was not
    ## requested under a property filter.
  bodyValues*: Table[PartId, EmailBodyValue]
    ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart] ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart] ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart] ## Leaf parts — non-body content.
  hasAttachment*: bool ## Server heuristic.
  preview*: string ## Up to 256 characters plaintext fragment.

func isLeaf*(part: EmailBodyPart): bool =
  ## True if this part is a leaf (not multipart/*). Convenience predicate
  ## for asserting the RFC guarantee that textBody, htmlBody, and attachments
  ## contain only leaf parts (D6).
  not part.isMultipart

# =============================================================================
# PartialEmail
# =============================================================================

type PartialEmail* {.ruleOff: "objects".} = object
  ## RFC 8621 §4 partial Email — every field elided when the server
  ## does not echo it (sparse ``/get`` or ``/set`` update-echo).
  ##
  ## Field shape rule (A4 + A3.6 D4): wire-nullable fields use
  ## ``FieldEcho[T]`` (three states: absent / null / value); wire-non-
  ## nullable fields use ``Opt[T]`` (two states: absent / value).
  ##
  ## The library is the sole producer; consumers consume these values
  ## via ``SetResponse[EmailCreatedItem, PartialEmail].updateResults``
  ## and ``GetResponse[PartialEmail].list``. No public builder accepts
  ## a consumer-constructed ``PartialEmail`` (D5).

  # -- Metadata (non-nullable on the wire) --
  id*: Opt[Id]
  blobId*: Opt[BlobId]
  threadId*: Opt[Id]
  mailboxIds*: Opt[MailboxIdSet]
  keywords*: Opt[KeywordSet]
  size*: Opt[UnsignedInt]
  receivedAt*: Opt[UTCDate]

  # -- Convenience headers (nullable on the wire — null when source message
  # lacks the header per RFC 8621 §4.1.2-4.1.3) --
  messageId*: FieldEcho[seq[string]]
  inReplyTo*: FieldEcho[seq[string]]
  references*: FieldEcho[seq[string]]
  sender*: FieldEcho[seq[EmailAddress]]
  fromAddr*: FieldEcho[seq[EmailAddress]]
  to*: FieldEcho[seq[EmailAddress]]
  cc*: FieldEcho[seq[EmailAddress]]
  bcc*: FieldEcho[seq[EmailAddress]]
  replyTo*: FieldEcho[seq[EmailAddress]]
  subject*: FieldEcho[string]
  sentAt*: FieldEcho[Date]

  # -- Raw headers (non-nullable on the wire — array always present when fetched) --
  headers*: Opt[seq[EmailHeader]]
  requestedHeaders*: Opt[Table[HeaderPropertyKey, HeaderValue]]
  requestedHeadersAll*: Opt[Table[HeaderPropertyKey, seq[HeaderValue]]]

  # -- Body (bodyStructure nullable when not requested; others non-nullable) --
  bodyStructure*: FieldEcho[EmailBodyPart]
  bodyValues*: Opt[Table[PartId, EmailBodyValue]]
  textBody*: Opt[seq[EmailBodyPart]]
  htmlBody*: Opt[seq[EmailBodyPart]]
  attachments*: Opt[seq[EmailBodyPart]]
  hasAttachment*: Opt[bool]
  preview*: Opt[string]

# =============================================================================
# ParsedEmail
# =============================================================================

type ParsedEmail* {.ruleOff: "objects".} = object
  ## Blob-backed Email for Email/parse responses (RFC 8621 section 4.9).
  ## Missing id, blobId, mailboxIds, keywords, size, receivedAt —
  ## structurally absent, not ``Opt.none`` (D7, D20).

  # -- Metadata -- only threadId survives
  threadId*: Opt[Id] ## Server MAY provide if determinable; else none.

  # -- Convenience headers -- identical structure to Email
  messageId*: Opt[seq[string]] ## header:Message-ID:asMessageIds
  inReplyTo*: Opt[seq[string]] ## header:In-Reply-To:asMessageIds
  references*: Opt[seq[string]] ## header:References:asMessageIds
  sender*: Opt[seq[EmailAddress]] ## header:Sender:asAddresses
  fromAddr*: Opt[seq[EmailAddress]]
    ## header:From:asAddresses (``from`` is a Nim keyword).
  to*: Opt[seq[EmailAddress]] ## header:To:asAddresses
  cc*: Opt[seq[EmailAddress]] ## header:Cc:asAddresses
  bcc*: Opt[seq[EmailAddress]] ## header:Bcc:asAddresses
  replyTo*: Opt[seq[EmailAddress]] ## header:Reply-To:asAddresses
  subject*: Opt[string] ## header:Subject:asText
  sentAt*: Opt[Date] ## header:Date:asDate

  # -- Raw headers --
  headers*: seq[EmailHeader] ## All header fields in message order; @[] if absent.

  # -- Dynamic header properties --
  requestedHeaders*: Table[HeaderPropertyKey, HeaderValue]
    ## Parsed headers requested via ``header:Name:asForm`` (last instance).
  requestedHeadersAll*: Table[HeaderPropertyKey, seq[HeaderValue]]
    ## Parsed headers requested via ``header:Name:asForm:all`` (all instances).

  # -- Body --
  bodyStructure*: Opt[EmailBodyPart]
    ## Full MIME tree; ``Opt.none`` when ``bodyStructure`` was not
    ## requested under a property filter.
  bodyValues*: Table[PartId, EmailBodyValue]
    ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart] ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart] ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart] ## Leaf parts — non-body content.
  hasAttachment*: bool ## Server heuristic.
  preview*: string ## Up to 256 characters plaintext fragment.

# =============================================================================
# EmailCreatedItem
# =============================================================================

type EmailCreatedItem* {.ruleOff: "objects".} = object
  ## Successful-create entry for Email/set, Email/copy, and Email/import
  ## (RFC 8621 §§4.6/4.7/4.8). Exactly the four fields the RFC mandates;
  ## no ``Opt`` on any field — a server omitting any of the four has emitted
  ## a malformed response (Design §2.1, F2).
  id*: Id ## JMAP object id of the created Email.
  blobId*: BlobId ## Blob id for the raw RFC 5322 octets.
  threadId*: Id ## Thread the created Email belongs to.
  size*: UnsignedInt ## Raw message size in octets.

# =============================================================================
# Email Write Responses
# =============================================================================
# Email/set and Email/copy reuse the promoted generic ``SetResponse[T, U]``
# and ``CopyResponse[T]`` from ``methods.nim``. ``SetResponse[
# EmailCreatedItem, PartialEmail]`` carries typed ``createResults`` and
# typed ``updateResults`` (A4 D1/D2). The RFC 8620 §5.3 ``Foo|null``
# inner split on ``updated`` projects to ``Opt[PartialEmail]``
# (``Opt.none`` = wire null; ``Opt.some(p)`` = wire object parsed via
# ``PartialEmail.fromJson``). ``EmailImportResponse`` stays bespoke —
# import has no /set counterpart in the generic family.

type EmailImportResponse* {.ruleOff: "objects".} = object
  ## Email/import response (RFC 8621 §4.8). Minimal — no ``updated`` or
  ## ``destroyed`` (import creates only).
  accountId*: AccountId ## Account the /import targeted.
  oldState*: Opt[JmapState] ## Server state before the call, or none.
  newState*: Opt[JmapState]
    ## Server state after the call. ``Opt.none`` when the server omits
    ## the field — Stalwart 0.15.5 empirically omits ``newState`` for
    ## /import responses with only failure rails populated. RFC 8621 §4.8
    ## mandates the field; library is lenient on receive per Postel's law.
  createResults*: Table[CreationId, Result[EmailCreatedItem, SetError]]
    ## Per-CreationId success/error for imported entries.

# =============================================================================
# EmailCopyItem
# =============================================================================

type EmailCopyItem* {.ruleOff: "objects".} = object
  ## Source email + optional destination-account overrides for Email/copy
  ## (RFC 8621 §4.7). ``Opt.none`` override = preserve source value;
  ## ``Opt.some`` = replace in destination.
  id*: Id ## Source email id in the from-account.
  mailboxIds*: Opt[NonEmptyMailboxIdSet]
    ## If overridden, the resulting Email must still belong to at least one
    ## Mailbox (RFC 8621 §4.1.1); NonEmpty encodes this on the override
    ## type (Design §5.1, F10).
  keywords*: Opt[KeywordSet] ## If overridden, replaces the source keywords.
  receivedAt*: Opt[UTCDate] ## If overridden, replaces the source receivedAt.

func initEmailCopyItem*(
    id: Id,
    mailboxIds: Opt[NonEmptyMailboxIdSet] = Opt.none(NonEmptyMailboxIdSet),
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailCopyItem =
  ## Total constructor. All field types are themselves smart-constructed
  ## (``parseId``, ``parseNonEmptyMailboxIdSet``, ``initKeywordSet``,
  ## ``parseUtcDate``); no cross-field invariant exists at this composition
  ## level (F10).
  EmailCopyItem(
    id: id, mailboxIds: mailboxIds, keywords: keywords, receivedAt: receivedAt
  )

# =============================================================================
# EmailImportItem
# =============================================================================

type EmailImportItem* {.ruleOff: "objects".} = object
  ## Creation-side model for a single Email/import entry (RFC 8621 §4.8).
  blobId*: BlobId ## Previously uploaded message/rfc822 blob.
  mailboxIds*: NonEmptyMailboxIdSet
    ## RFC §4.8: "At least one Mailbox MUST be given." Required + non-empty.
  keywords*: Opt[KeywordSet]
    ## ``Opt.none``: omit the key (server default — empty).
    ## ``Opt.some(empty)``: explicitly empty (Phase 3 serde collapses to
    ## omitted). ``Opt.some(non-empty)``: emit the full keyword map.
  receivedAt*: Opt[UTCDate]
    ## ``Opt.none``: defer to server default (most recent Received header
    ## or import time). Client cannot replicate without parsing the raw
    ## RFC 5322 message (Design §6.1).

func initEmailImportItem*(
    blobId: BlobId,
    mailboxIds: NonEmptyMailboxIdSet,
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailImportItem =
  ## Total constructor. ``mailboxIds`` is required (non-Opt) per RFC §4.8
  ## and pre-validated non-empty via ``NonEmptyMailboxIdSet``. No
  ## cross-field invariants at this level (F15).
  EmailImportItem(
    blobId: blobId, mailboxIds: mailboxIds, keywords: keywords, receivedAt: receivedAt
  )

# =============================================================================
# NonEmptyEmailImportMap
# =============================================================================

type NonEmptyEmailImportMap* {.ruleOff: "objects".} = object
  ## Non-empty, duplicate-``CreationId``-free map of Email/import
  ## creation entries. Sealed Pattern-A object — ``rawValue`` is
  ## module-private. Construction is gated by
  ## ``initNonEmptyEmailImportMap`` (Design §6.2, F13).
  rawValue: Table[CreationId, EmailImportItem]

func toTable*(
    m: NonEmptyEmailImportMap
): Table[CreationId, EmailImportItem] {.inline.} =
  ## Value-projection accessor — returns a copy of the underlying table.
  m.rawValue

func initNonEmptyEmailImportMap*(
    items: openArray[(CreationId, EmailImportItem)]
): Result[NonEmptyEmailImportMap, seq[ValidationError]] =
  ## Accumulating smart constructor mirroring ``initMailboxUpdateSet``
  ## (mailbox.nim) and ``initVacationResponseUpdateSet`` (vacation.nim).
  ## Rejects empty input — ``addEmailImport``'s ``emails`` parameter is
  ## non-Opt; an empty map makes the whole call meaningless (Design §6.2).
  ## Rejects duplicate ``CreationId`` — silent shadowing at Table
  ## construction turns data-loss into a silent accept; ``openArray`` (not
  ## ``Table``) preserves duplicate keys for inspection. All violations
  ## surface in a single Err pass; each repeated CreationId is reported
  ## exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    items,
    it[0],
    typeName = "NonEmptyEmailImportMap",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate CreationId",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[CreationId, EmailImportItem](items.len)
  for (cid, item) in items:
    t[cid] = item
  ok(NonEmptyEmailImportMap(rawValue: t))
