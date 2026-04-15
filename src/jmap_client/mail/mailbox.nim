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
  return ok(MailboxRole(raw.toLowerAscii()))

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
  return ok(NonEmptyMailboxIdSet(hs))

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
  return ok(
    MailboxCreate(
      name: name,
      parentId: parentId,
      role: role,
      sortOrder: sortOrder,
      isSubscribed: isSubscribed,
    )
  )

# =============================================================================
# Mailbox Update Algebra
# =============================================================================

type MailboxUpdateVariantKind* = enum
  ## Discriminator for MailboxUpdate: names the settable RFC 8621 §2
  ## Mailbox property being replaced. One variant per whole-value target
  ## — no sub-path variants because every Mailbox property is replace-only.
  muSetName
  muSetParentId
  muSetRole
  muSetSortOrder
  muSetIsSubscribed

type MailboxUpdate* {.ruleOff: "objects".} = object
  ## Single typed Mailbox patch operation. One variant per RFC 8621 §2
  ## settable property. Whole-value replace semantics — no sub-path
  ## targeting (contrast EmailUpdate, which targets keyword/mailbox
  ## sub-paths). Case object makes "exactly one target per update" a
  ## type-level fact, closing the empty-update and multi-property-update
  ## holes that a flat five-`Opt[T]` record would leave open.
  case kind*: MailboxUpdateVariantKind
  of muSetName:
    name*: string
  of muSetParentId:
    parentId*: Opt[Id] ## RFC 8621 §2 permits null to reparent to the top level.
  of muSetRole:
    role*: Opt[MailboxRole] ## RFC 8621 §2 permits null to clear the role.
  of muSetSortOrder:
    sortOrder*: UnsignedInt
  of muSetIsSubscribed:
    isSubscribed*: bool

func setName*(name: string): MailboxUpdate =
  ## Replace the target Mailbox's display name. Total — an empty name
  ## would surface as an RFC 8621 §2 server-side rejection, not a
  ## client-side validation error.
  MailboxUpdate(kind: muSetName, name: name)

func setParentId*(parentId: Opt[Id]): MailboxUpdate =
  ## Replace the target Mailbox's parentId. Opt.none reparents to the
  ## top level per RFC 8621 §2.
  MailboxUpdate(kind: muSetParentId, parentId: parentId)

func setRole*(role: Opt[MailboxRole]): MailboxUpdate =
  ## Replace the target Mailbox's role. Opt.none clears the role.
  MailboxUpdate(kind: muSetRole, role: role)

func setSortOrder*(sortOrder: UnsignedInt): MailboxUpdate =
  ## Replace the target Mailbox's sortOrder hint.
  MailboxUpdate(kind: muSetSortOrder, sortOrder: sortOrder)

func setIsSubscribed*(isSubscribed: bool): MailboxUpdate =
  ## Replace the target Mailbox's isSubscribed flag.
  MailboxUpdate(kind: muSetIsSubscribed, isSubscribed: isSubscribed)

type MailboxUpdateSet* = distinct seq[MailboxUpdate]
  ## Validated, conflict-free batch of MailboxUpdate operations targeting
  ## a single Mailbox id. Construction gated by initMailboxUpdateSet —
  ## the raw distinct constructor is not part of the public surface.

func initMailboxUpdateSet*(
    updates: openArray[MailboxUpdate]
): Result[MailboxUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor (Part F design §3.3, §4.4). Rejects:
  ##   * empty input — the builder has exactly one "no updates for this
  ##     id" representation (omit the entry from the outer table);
  ##   * duplicate target property — two updates with the same kind would
  ##     produce a JSON patch object with duplicate keys.
  ## All violations surface in a single Err pass; each repeated kind is
  ## reported exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    updates,
    it.kind,
    typeName = "MailboxUpdateSet",
    emptyMsg = "must contain at least one update",
    dupMsg = "duplicate target property",
  )
  if errs.len > 0:
    return err(errs)
  ok(MailboxUpdateSet(@updates))
