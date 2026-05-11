# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Email entity and supporting types for RFC 8621 (JMAP Mail) section 4.
## Email is the store-backed read model; ParsedEmail is the blob-backed
## model for Email/parse. EmailComparator and EmailBodyFetchOptions are
## query-time parameter types. All types colocated per domain cohesion
## (Decision D14).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/sets
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
  bodyProperties*: Opt[seq[PropertyName]] ## Override default body part properties.
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

type NonEmptyEmailImportMap* = distinct Table[CreationId, EmailImportItem]
  ## Non-empty, duplicate-``CreationId``-free map of Email/import creation
  ## entries. Construction is gated by ``initNonEmptyEmailImportMap``; the
  ## raw distinct constructor is not part of the public surface (Design
  ## §6.2, F13).

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
  ok(NonEmptyEmailImportMap(t))
