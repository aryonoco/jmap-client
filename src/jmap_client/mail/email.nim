# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Email entity and supporting types for RFC 8621 (JMAP Mail) section 4.
## Email is the store-backed read model; ParsedEmail is the blob-backed
## model for Email/parse. EmailComparator and EmailBodyFetchOptions are
## query-time parameter types. All types colocated per domain cohesion
## (Decision D14).

{.push raises: [].}

import std/tables

import ../validation
import ../primitives
import ../framework

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
  collation*: Opt[string] ## RFC 4790 collation identifier.
  case kind*: EmailComparatorKind
  of eckPlain:
    property*: PlainSortProperty ## Non-keyword sort property.
  of eckKeyword:
    keywordProperty*: KeywordSortProperty ## Keyword-bearing sort property.
    keyword*: Keyword ## Required for keyword sorts.

func plainComparator*(
    property: PlainSortProperty,
    isAscending: Opt[bool] = Opt.none(bool),
    collation: Opt[string] = Opt.none(string),
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
    collation: Opt[string] = Opt.none(string),
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
  ## Store-backed Email read model (RFC 8621 section 4.1).
  ## A typed Email is a complete domain object — every property present.
  ## Partial-property access uses raw ``GetResponse.list: seq[JsonNode]``.

  # -- Metadata (section 4.1.1) -- server-set, immutable except mailboxIds/keywords
  id*: Id ## JMAP object id (not Message-ID header).
  blobId*: Id ## Raw RFC 5322 octets.
  threadId*: Id ## Thread this Email belongs to.
  mailboxIds*: MailboxIdSet ## At least one Mailbox at all times (RFC invariant).
  keywords*: KeywordSet ## Default: empty set.
  size*: UnsignedInt ## Raw message size in octets.
  receivedAt*: UTCDate ## IMAP internal date.

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
  bodyStructure*: EmailBodyPart ## Full MIME tree.
  bodyValues*: Table[PartId, EmailBodyValue]
    ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart] ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart] ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart] ## Leaf parts — non-body content.
  hasAttachment*: bool ## Server heuristic.
  preview*: string ## Up to 256 characters plaintext fragment.

func parseEmail*(e: Email): Result[Email, ValidationError] =
  ## Validates the single domain invariant: mailboxIds must not be empty.
  ## RFC 8621 section 4.1.1: "An Email in the mail store MUST belong to one or
  ## more Mailboxes at all times."
  if e.mailboxIds.len == 0:
    return err(validationError("Email", "mailboxIds must not be empty", ""))
  ok(e)

func isLeaf*(part: EmailBodyPart): bool =
  ## True if this part is a leaf (not multipart/*). Convenience predicate
  ## for asserting the RFC guarantee that textBody, htmlBody, and attachments
  ## contain only leaf parts (D6).
  not part.isMultipart

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
  bodyStructure*: EmailBodyPart ## Full MIME tree.
  bodyValues*: Table[PartId, EmailBodyValue]
    ## Text part contents; empty if none fetched.
  textBody*: seq[EmailBodyPart] ## Leaf parts — text/plain preference.
  htmlBody*: seq[EmailBodyPart] ## Leaf parts — text/html preference.
  attachments*: seq[EmailBodyPart] ## Leaf parts — non-body content.
  hasAttachment*: bool ## Server heuristic.
  preview*: string ## Up to 256 characters plaintext fragment.
