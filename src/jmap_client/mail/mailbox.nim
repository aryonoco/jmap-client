# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Mailbox entity and supporting types for RFC 8621 (JMAP Mail) section 2.
## MailboxRole identifies well-known mailbox roles. MailboxIdSet is an immutable
## set of mailbox identifiers. MailboxRights encodes per-mailbox ACL flags.
## Mailbox is the read model; MailboxCreate is the creation model with a smart
## constructor enforcing non-empty name.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sets
import std/strutils
import std/tables

import ../validation
import ../primitives

# =============================================================================
# MailboxRole
# =============================================================================

type MailboxRoleKind* = enum
  ## Discriminator for ``MailboxRole``. Backing strings are the RFC 8621 §2
  ## wire identifiers; ``mrOther`` carries a vendor-extension role whose
  ## raw identifier lives alongside.
  mrInbox = "inbox"
  mrDrafts = "drafts"
  mrSent = "sent"
  mrTrash = "trash"
  mrJunk = "junk"
  mrArchive = "archive"
  mrImportant = "important"
  mrAll = "all"
  mrFlagged = "flagged"
  mrSubscriptions = "subscriptions"
  mrOther

type MailboxRole* {.ruleOff: "objects".} = object
  ## Validated RFC 8621 §2 mailbox role.
  ##
  ## Construction sealed: ``rawKind`` and ``rawIdentifier`` are module-private,
  ## so direct literal construction from outside this module is rejected.
  ## Use ``parseMailboxRole`` for untrusted input, or the named ``roleInbox``
  ## / ``roleDrafts`` / ... constants for the 10 well-known values.
  ##
  ## Lowercase-normalised: the parser folds input to lowercase before
  ## classification and vendor-extension capture — round-trips losslessly
  ## over the wire.
  case rawKind: MailboxRoleKind
  of mrOther:
    rawIdentifier: string ## wire identifier for vendor extensions
  of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
      mrFlagged, mrSubscriptions:
    discard

func kind*(r: MailboxRole): MailboxRoleKind =
  ## Returns the discriminator — one of the ten RFC 8621 kinds or ``mrOther``.
  return r.rawKind

func identifier*(r: MailboxRole): string =
  ## Returns the wire identifier string. For the ten well-known kinds, this
  ## is the enum's backing string; for ``mrOther`` it is the vendor-extension
  ## identifier captured at parse time.
  case r.rawKind
  of mrOther:
    return r.rawIdentifier
  of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
      mrFlagged, mrSubscriptions:
    return $r.rawKind

func `$`*(r: MailboxRole): string =
  ## Wire-form string — equivalent to ``identifier``.
  return r.identifier

func `==`*(a, b: MailboxRole): bool =
  ## Structural equality. Two values are equal iff their kinds agree and,
  ## for ``mrOther``, their raw identifiers match byte-for-byte.
  ##
  ## Nested case on both operands — see collation.nim `==` for the
  ## strict-required pattern.
  case a.rawKind
  of mrOther:
    case b.rawKind
    of mrOther:
      a.rawIdentifier == b.rawIdentifier
    of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
        mrFlagged, mrSubscriptions:
      false
  of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
      mrFlagged, mrSubscriptions:
    case b.rawKind
    of mrOther:
      false
    of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
        mrFlagged, mrSubscriptions:
      a.rawKind == b.rawKind

func hash*(r: MailboxRole): Hash =
  ## Hash mixing the kind ordinal with the raw identifier for ``mrOther``.
  ## Consistent with ``==`` — equal values produce equal hashes.
  var h: Hash = 0
  h = h !& hash(ord(r.rawKind))
  case r.rawKind
  of mrOther:
    h = h !& hash(r.rawIdentifier)
  of mrInbox, mrDrafts, mrSent, mrTrash, mrJunk, mrArchive, mrImportant, mrAll,
      mrFlagged, mrSubscriptions:
    discard
  result = !$h

const
  roleInbox* = MailboxRole(rawKind: mrInbox) ## RFC 8621 well-known role.
  roleDrafts* = MailboxRole(rawKind: mrDrafts) ## RFC 8621 well-known role.
  roleSent* = MailboxRole(rawKind: mrSent) ## RFC 8621 well-known role.
  roleTrash* = MailboxRole(rawKind: mrTrash) ## RFC 8621 well-known role.
  roleJunk* = MailboxRole(rawKind: mrJunk) ## RFC 8621 well-known role.
  roleArchive* = MailboxRole(rawKind: mrArchive) ## RFC 8621 well-known role.
  roleImportant* = MailboxRole(rawKind: mrImportant) ## RFC 8621 well-known role.
  roleAll* = MailboxRole(rawKind: mrAll) ## RFC 8621 well-known role.
  roleFlagged* = MailboxRole(rawKind: mrFlagged) ## RFC 8621 well-known role.
  roleSubscriptions* = MailboxRole(rawKind: mrSubscriptions) ## RFC 8621 well-known role.

func parseMailboxRole*(raw: string): Result[MailboxRole, ValidationError] =
  ## Validates and constructs a ``MailboxRole``. Rejects empty input and
  ## control characters; lowercase-normalises and classifies against the
  ## ten RFC 8621 §2 well-known roles, falling back to ``mrOther`` for
  ## vendor extensions. Lossless round-trip over the wire:
  ## ``$(parseMailboxRole(x).get) == x.toLowerAscii`` holds for every ``x``
  ## that survives detection. Single parser — no strict/lenient pair
  ## (Decision B20: no meaningful gap between spec and structural constraints).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "MailboxRole", raw))
  let normalised = raw.toLowerAscii()
  let parsed = parseEnum[MailboxRoleKind](normalised, mrOther)
  case parsed
  of mrInbox:
    return ok(roleInbox)
  of mrDrafts:
    return ok(roleDrafts)
  of mrSent:
    return ok(roleSent)
  of mrTrash:
    return ok(roleTrash)
  of mrJunk:
    return ok(roleJunk)
  of mrArchive:
    return ok(roleArchive)
  of mrImportant:
    return ok(roleImportant)
  of mrAll:
    return ok(roleAll)
  of mrFlagged:
    return ok(roleFlagged)
  of mrSubscriptions:
    return ok(roleSubscriptions)
  of mrOther:
    return ok(MailboxRole(rawKind: mrOther, rawIdentifier: normalised))

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
  MailboxIdSet(ids.toHashSet)

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
  return ok(NonEmptyMailboxIdSet(ids.toHashSet))

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
# MailboxCreatedItem — Mailbox/set ``created[cid]`` payload (RFC 8620 §5.3)
# =============================================================================

type MailboxCreatedItem* {.ruleOff: "objects".} = object
  ## Server-authoritative subset returned in Mailbox/set ``created[cid]``
  ## (RFC 8620 §5.3): the server MUST return ``id`` plus any server-set
  ## or server-modified properties. For Mailbox, the server-set
  ## properties per RFC 8621 §2.1 are the four count fields and
  ## ``myRights``. The full ``Mailbox`` record is NOT returned — the
  ## client already knows the other fields (it sent them in ``create``).
  ##
  ## All five server-set fields are ``Opt[T]`` because Stalwart 0.15.5
  ## omits them from this payload (a strict-RFC §5.3 minor divergence):
  ## the create acknowledgement is just ``{"id": "<id>"}``. Postel's-law
  ## accommodation per ``.claude/rules/nim-conventions.md`` §"Serde
  ## Conventions": be lenient on receive. Mirrors the
  ## ``IdentityCreatedItem`` design (``identity.nim``).
  id*: Id
  totalEmails*: Opt[UnsignedInt]
  unreadEmails*: Opt[UnsignedInt]
  totalThreads*: Opt[UnsignedInt]
  unreadThreads*: Opt[UnsignedInt]
  myRights*: Opt[MailboxRights]

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

# =============================================================================
# NonEmptyMailboxUpdates — whole-container /set update algebra (RFC 8621 §2.5)
# =============================================================================

type NonEmptyMailboxUpdates* = distinct Table[Id, MailboxUpdateSet]
  ## Non-empty, duplicate-free batch of per-mailbox update operations keyed
  ## by existing Mailbox ``Id``. Construction gated by
  ## ``parseNonEmptyMailboxUpdates``; the raw distinct constructor is
  ## module-private surface. Shape mirrors
  ## ``NonEmptyEmailSubmissionUpdates`` (email_submission.nim) —
  ## ``addSet[Mailbox, ...]`` serialises the container via its own
  ## ``toJson`` rather than assembling the wire patch per-caller.

func parseNonEmptyMailboxUpdates*(
    items: openArray[(Id, MailboxUpdateSet)]
): Result[NonEmptyMailboxUpdates, seq[ValidationError]] =
  ## Accumulating smart constructor. Rejects:
  ##   * empty input — the ``/set`` builder's ``update:`` field has
  ##     exactly one "no updates" representation: omit the entry via
  ##     ``Opt.none``.
  ##   * duplicate ``Id`` keys — silent last-wins shadowing at Table
  ##     construction would swallow caller data; ``openArray`` (not
  ##     ``Table``) preserves duplicates for inspection.
  ## All violations surface in a single Err pass; each repeated id is
  ## reported exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    items,
    it[0],
    typeName = "NonEmptyMailboxUpdates",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate mailbox id",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[Id, MailboxUpdateSet](items.len)
  for (id, updateSet) in items:
    t[id] = updateSet
  ok(NonEmptyMailboxUpdates(t))
