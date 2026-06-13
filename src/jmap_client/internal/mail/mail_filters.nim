# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Filter conditions for RFC 8621 (JMAP Mail). MailboxFilterCondition (§2.3),
## EmailHeaderFilter and EmailFilterCondition (§4.4.1). Filter conditions
## encode predicates that flow client-to-server only (toJson, no fromJson).
## MailboxFilterCondition uses Opt[Opt[T]] for three-state *value* filter
## semantics: absent (don't filter), null (filter for no value), or value
## (filter for specific value). Three-state *boolean* filters — ``hasAnyRole``,
## ``isSubscribed``, ``hasAttachment`` — are named enums (P18) rather than
## ``Opt[bool]``, so "no constraint", "require true", and "require false" each
## read at the call site. The remaining EmailFilterCondition fields use simple
## ``Opt[T]`` — they need neither null nor "no constraint" beyond absence.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ../types/validation
import ../types/primitives
import ./mailbox
import ./keyword

type HasAnyRoleFilter* = enum
  ## RFC 8621 §2.3 ``hasAnyRole`` filter, three-state (P18). The zero value
  ## ``hrfNoConstraint`` omits the key from the wire; the other two emit the
  ## RFC boolean. Replaces the prior ``Opt[bool]``, where "absent" and the two
  ## boolean cases read identically at the call site.
  hrfNoConstraint ## Don't filter on role presence (omit ``hasAnyRole``).
  hrfRequireAny ## ``hasAnyRole: true`` — the mailbox MUST have a role.
  hrfRequireNone ## ``hasAnyRole: false`` — the mailbox MUST NOT have a role.

type SubscriptionFilter* = enum
  ## RFC 8621 §2.3 ``isSubscribed`` filter, three-state (P18). The zero value
  ## ``sfNoConstraint`` omits the key from the wire.
  sfNoConstraint ## Don't filter on subscription (omit ``isSubscribed``).
  sfSubscribed ## ``isSubscribed: true`` — only subscribed mailboxes.
  sfNotSubscribed ## ``isSubscribed: false`` — only unsubscribed mailboxes.

type HasAttachmentFilter* = enum
  ## RFC 8621 §4.4.1 ``hasAttachment`` filter, three-state (P18). The zero
  ## value ``hafNoConstraint`` omits the key from the wire.
  hafNoConstraint ## Don't filter on attachments (omit ``hasAttachment``).
  hafYes ## ``hasAttachment: true`` — only emails with an attachment.
  hafNo ## ``hasAttachment: false`` — only emails without an attachment.

type MailboxFilterCondition* {.ruleOff: "objects".} = object
  ## Filter condition for Mailbox/query (RFC 8621 §2.3). No smart constructor —
  ## all field combinations are valid (Decision B16). toJson only — the server
  ## never sends this back (Decision B11).
  ##
  ## Three-state fields use ``Opt[Opt[T]]``:
  ## - ``Opt.none(Opt[T])`` — don't filter on this field (omit from JSON)
  ## - ``Opt.some(Opt.none(T))`` — filter for null/absent (emit null)
  ## - ``Opt.some(Opt.some(v))`` — filter for specific value (emit value)
  parentId*: Opt[Opt[Id]] ## Filter by parent mailbox.
  name*: Opt[string] ## Filter by name substring.
  role*: Opt[Opt[MailboxRole]] ## Filter by role.
  hasAnyRole*: HasAnyRoleFilter ## Filter by whether any role is set (three-state).
  isSubscribed*: SubscriptionFilter ## Filter by subscription status (three-state).

# =============================================================================
# EmailHeaderFilter
# =============================================================================

type EmailHeaderFilter* {.ruleOff: "objects".} = object
  ## Header name/value filter for Email/query (RFC 8621 §4.4.1).
  ## Pattern A: ``name`` is module-private to enforce non-empty invariant.
  name: string ## Module-private — non-empty, enforced by constructor.
  value*: Opt[string] ## Match text, or none = existence check only.

func name*(f: EmailHeaderFilter): string =
  ## Read-only accessor for the sealed header name.
  f.name

func parseEmailHeaderFilter*(
    name: string, value: Opt[string] = Opt.none(string)
): Result[EmailHeaderFilter, ValidationError] =
  ## Constructs an EmailHeaderFilter. Validates non-empty name.
  if name.len == 0:
    return
      err(validationError("EmailHeaderFilter", "header name must not be empty", name))
  return ok(EmailHeaderFilter(name: name, value: value))

# =============================================================================
# EmailFilterCondition
# =============================================================================

type EmailFilterCondition* {.ruleOff: "objects".} = object
  ## Filter condition for Email/query (RFC 8621 §4.4.1). No smart constructor —
  ## all field combinations are valid (Decision B16). toJson only — the server
  ## never sends this back (Decision B11).
  ##
  ## ``Opt.none`` = don't filter on this property (omitted from JSON).
  ## Unlike ``MailboxFilterCondition``, no field needs ``Opt[Opt[T]]``
  ## three-state semantics.

  # -- Mailbox membership --
  inMailbox*: Opt[Id] ## Email must be in this Mailbox.
  inMailboxOtherThan*: Opt[seq[Id]] ## Email must not be in these Mailboxes.

  # -- Date/size --
  before*: Opt[UTCDate] ## receivedAt < this date.
  after*: Opt[UTCDate] ## receivedAt >= this date.
  minSize*: Opt[UnsignedInt] ## size >= this value.
  maxSize*: Opt[UnsignedInt] ## size < this value.

  # -- Thread keyword filters --
  allInThreadHaveKeyword*: Opt[Keyword] ## All thread Emails have this keyword.
  someInThreadHaveKeyword*: Opt[Keyword] ## At least one thread Email has it.
  noneInThreadHaveKeyword*: Opt[Keyword] ## No thread Emails have this keyword.

  # -- Per-email keyword filters --
  hasKeyword*: Opt[Keyword] ## This Email has the keyword.
  notKeyword*: Opt[Keyword] ## This Email does not have the keyword.

  # -- Boolean filter --
  hasAttachment*: HasAttachmentFilter ## Match on hasAttachment value (three-state).

  # -- Text search --
  text*: Opt[string] ## Search From, To, Cc, Bcc, Subject, body.
  fromAddr*: Opt[string] ## Search From header (``from`` is Nim keyword).
  to*: Opt[string] ## Search To header.
  cc*: Opt[string] ## Search Cc header.
  bcc*: Opt[string] ## Search Bcc header.
  subject*: Opt[string] ## Search Subject header.
  body*: Opt[string] ## Search body parts.

  # -- Header filter --
  header*: Opt[EmailHeaderFilter] ## Match header by name/value.
