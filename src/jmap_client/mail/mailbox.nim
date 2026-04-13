# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mailbox entity and supporting types for RFC 8621 (JMAP Mail) section 2.
## MailboxRole identifies well-known mailbox roles. MailboxIdSet is an immutable
## set of mailbox identifiers. MailboxRights encodes per-mailbox ACL flags.
## Mailbox is the read model; MailboxCreate is the creation model with a smart
## constructor enforcing non-empty name.

{.push raises: [], noSideEffect.}

import std/hashes
import std/sets
import std/strutils

import ../validation
import ../primitives

# =============================================================================
# MailboxRole
# =============================================================================

type MailboxRole* = distinct string
  ## A mailbox role label: non-empty, case-insensitive, stored as lowercase.
  ## Single parser — no strict/lenient pair (Decision B20: no meaningful gap
  ## between spec and structural constraints).

defineStringDistinctOps(MailboxRole)

func parseMailboxRole*(raw: string): Result[MailboxRole, ValidationError] =
  ## Validates non-empty, normalises to lowercase. Used for both client and
  ## server values — single parser per Decision B20.
  if raw.len == 0:
    return err(validationError("MailboxRole", "must not be empty", raw))
  let mr = MailboxRole(raw.toLowerAscii())
  doAssert mr.len > 0
  return ok(mr)

const
  roleInbox* = MailboxRole("inbox") ## RFC 8621 well-known role.
  roleDrafts* = MailboxRole("drafts") ## RFC 8621 well-known role.
  roleSent* = MailboxRole("sent") ## RFC 8621 well-known role.
  roleTrash* = MailboxRole("trash") ## RFC 8621 well-known role.
  roleJunk* = MailboxRole("junk") ## RFC 8621 well-known role.
  roleArchive* = MailboxRole("archive") ## RFC 8621 well-known role.
  roleImportant* = MailboxRole("important") ## RFC 8621 well-known role.
  roleAll* = MailboxRole("all") ## RFC 8621 well-known role.
  roleFlagged* = MailboxRole("flagged") ## RFC 8621 well-known role.
  roleSubscriptions* = MailboxRole("subscriptions") ## RFC 8621 well-known role.

# =============================================================================
# Mailbox ID Collections
# =============================================================================
#
# Two parallel types with different invariants, kept side-by-side so the
# "same shape, different contract" relationship is structurally visible
# (Part E §4.2.3, Decision E15).

# 1. MailboxIdSet — general-purpose, empty allowed (read models, Decision B4)

type MailboxIdSet* = distinct HashSet[Id]
  ## Immutable set of mailbox identifiers. Read-only operations only — no
  ## mutation after construction (Decision B4, same pattern as KeywordSet).

defineHashSetDistinctOps(MailboxIdSet, Id)

func initMailboxIdSet*(ids: openArray[Id]): MailboxIdSet =
  ## Constructs a MailboxIdSet from the given identifiers. Empty set is valid.
  ## Duplicates are naturally deduplicated by the underlying HashSet.
  var hs = initHashSet[Id](ids.len)
  for id in ids:
    hs.incl(id)
  let ms = MailboxIdSet(hs)
  return ms

iterator items*(ms: MailboxIdSet): Id =
  ## Yields each identifier in the set. Unwraps the distinct type to iterate
  ## the underlying HashSet.
  for id in HashSet[Id](ms):
    yield id

# 2. NonEmptyMailboxIdSet — creation-context, at-least-one enforced (Part E §4.2)

type NonEmptyMailboxIdSet* = distinct HashSet[Id]
  ## Non-empty set of mailbox identifiers for client-constructed email
  ## creation payloads. Construction is gated by parseNonEmptyMailboxIdSet;
  ## mutating operations (incl, excl) are deliberately not borrowed — they
  ## would violate the at-least-one invariant. Consumed by parseEmailBlueprint
  ## (Phase 3 Step 11) as the typed mailboxIds parameter.

defineNonEmptyHashSetDistinctOps(NonEmptyMailboxIdSet, Id)

func parseNonEmptyMailboxIdSet*(
    ids: openArray[Id]
): Result[NonEmptyMailboxIdSet, ValidationError] =
  ## Strict: requires at least one identifier. Duplicates are deduplicated
  ## by the underlying HashSet. Returns err on empty input.
  if ids.len == 0:
    return err(validationError("NonEmptyMailboxIdSet", "must not be empty", ""))
  var hs = initHashSet[Id](ids.len)
  for id in ids:
    hs.incl(id)
  let nems = NonEmptyMailboxIdSet(hs)
  doAssert HashSet[Id](nems).len > 0
  return ok(nems)

# =============================================================================
# MailboxRights
# =============================================================================

type MailboxRights* {.ruleOff: "objects".} = object
  ## Per-mailbox access control flags (RFC 8621 §2, myRights).
  ## No smart constructor — all boolean combinations are valid (Decision B6).
  mayReadItems*: bool ## May fetch email metadata and content.
  mayAddItems*: bool ## May add emails to this mailbox.
  mayRemoveItems*: bool ## May remove emails from this mailbox.
  maySetSeen*: bool ## May modify the $seen keyword.
  maySetKeywords*: bool ## May modify keywords other than $seen.
  mayCreateChild*: bool ## May create child mailboxes.
  mayRename*: bool ## May rename or move this mailbox.
  mayDelete*: bool ## May delete this mailbox.
  maySubmit*: bool ## May submit emails for sending via this mailbox.

# =============================================================================
# Mailbox
# =============================================================================

type Mailbox* {.ruleOff: "objects".} = object
  ## A Mailbox read model (RFC 8621 §2). No smart constructor — fromJson
  ## enforces non-empty name at the parsing boundary (Decision B5).
  id*: Id ## Server-assigned identifier.
  name*: string ## Display name, must be non-empty.
  parentId*: Opt[Id] ## Parent mailbox, or none for top-level.
  role*: Opt[MailboxRole] ## Well-known role, or none for user-created.
  sortOrder*: UnsignedInt ## Sort position hint, default 0.
  totalEmails*: UnsignedInt ## Total emails in this mailbox.
  unreadEmails*: UnsignedInt ## Unread emails in this mailbox.
  totalThreads*: UnsignedInt ## Total threads in this mailbox.
  unreadThreads*: UnsignedInt ## Unread threads in this mailbox.
  myRights*: MailboxRights ## ACL flags for the authenticated user.
  isSubscribed*: bool ## Whether the user has subscribed to this mailbox.

# =============================================================================
# MailboxCreate
# =============================================================================

type MailboxCreate* {.ruleOff: "objects".} = object
  ## Creation model for Mailbox — excludes server-set fields (id, counts,
  ## myRights). Smart constructor enforces non-empty name (Decision B7).
  name*: string ## Required, must be non-empty.
  parentId*: Opt[Id] ## Parent mailbox, or none for top-level.
  role*: Opt[MailboxRole] ## Role to assign, or none.
  sortOrder*: UnsignedInt ## Sort position hint, default 0.
  isSubscribed*: bool ## Whether to subscribe, default false.

func parseMailboxCreate*(
    name: string,
    parentId: Opt[Id] = Opt.none(Id),
    role: Opt[MailboxRole] = Opt.none(MailboxRole),
    sortOrder: UnsignedInt = UnsignedInt(0),
    isSubscribed: bool = false,
): Result[MailboxCreate, ValidationError] =
  ## Smart constructor: validates non-empty name, constructs MailboxCreate.
  ## All parameters except name have RFC-matching defaults for ergonomic use.
  if name.len == 0:
    return err(validationError("MailboxCreate", "name must not be empty", ""))
  let mc = MailboxCreate(
    name: name,
    parentId: parentId,
    role: role,
    sortOrder: sortOrder,
    isSubscribed: isSubscribed,
  )
  doAssert mc.name.len > 0
  return ok(mc)
