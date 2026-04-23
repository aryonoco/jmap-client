# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## EmailUpdate algebra for RFC 8621 (JMAP Mail) §4.6 update path. Six
## protocol-primitive smart constructors plus five domain-named convenience
## constructors produce typed ``EmailUpdate`` values; ``initEmailUpdateSet``
## composes them into a validated, conflict-free batch.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/sets
import std/sequtils
import std/sugar
import std/tables

import ../validation
import ../primitives

import ./keyword
import ./mailbox

# =============================================================================
# EmailUpdate
# =============================================================================

type EmailUpdateVariantKind* = enum
  ## Discriminator for EmailUpdate: names the RFC 8621 §4.6 wire patch
  ## operation being expressed. Six variants cover precisely the RFC-
  ## sanctioned patch ops — four sub-path writes (keywords/{k},
  ## mailboxIds/{id}) plus two full-replace writes (keywords, mailboxIds).
  euAddKeyword
  euRemoveKeyword
  euSetKeywords
  euAddToMailbox
  euRemoveFromMailbox
  euSetMailboxIds

type EmailUpdate* {.ruleOff: "objects".} = object
  ## Single typed Email patch operation (RFC 8621 §4.6). Six variants cover
  ## precisely the RFC-sanctioned wire patch ops; properties that are set-
  ## at-creation-only (``receivedAt``, ``subject``, body fields) deliberately
  ## have no update variant.
  case kind*: EmailUpdateVariantKind
  of euAddKeyword, euRemoveKeyword:
    keyword*: Keyword
  of euSetKeywords:
    keywords*: KeywordSet
  of euAddToMailbox, euRemoveFromMailbox:
    mailboxId*: Id
  of euSetMailboxIds:
    mailboxes*: NonEmptyMailboxIdSet

# -----------------------------------------------------------------------------
# Protocol-primitive smart constructors (design §3.2.2)
# -----------------------------------------------------------------------------
#
# All total — return ``EmailUpdate`` directly, no ``Result``. Field-level
# invariants are pre-discharged by their own type's smart constructor.

func addKeyword*(k: Keyword): EmailUpdate =
  ## Set a single keyword on the target Email (sub-path write on
  ## ``keywords/{k}``).
  EmailUpdate(kind: euAddKeyword, keyword: k)

func removeKeyword*(k: Keyword): EmailUpdate =
  ## Clear a single keyword on the target Email (sub-path delete on
  ## ``keywords/{k}``).
  EmailUpdate(kind: euRemoveKeyword, keyword: k)

func setKeywords*(ks: KeywordSet): EmailUpdate =
  ## Replace the full keyword set on the target Email (full-replace on
  ## ``keywords``). Empty set is valid — clears all keywords.
  EmailUpdate(kind: euSetKeywords, keywords: ks)

func addToMailbox*(id: Id): EmailUpdate =
  ## Add the target Email to a mailbox (sub-path write on
  ## ``mailboxIds/{id}``). Additive — other mailbox memberships are
  ## preserved.
  EmailUpdate(kind: euAddToMailbox, mailboxId: id)

func removeFromMailbox*(id: Id): EmailUpdate =
  ## Remove the target Email from a mailbox (sub-path delete on
  ## ``mailboxIds/{id}``). Other mailbox memberships are preserved.
  EmailUpdate(kind: euRemoveFromMailbox, mailboxId: id)

func setMailboxIds*(ids: NonEmptyMailboxIdSet): EmailUpdate =
  ## Replace the full mailbox-membership set on the target Email (full-
  ## replace on ``mailboxIds``). Non-empty by construction — RFC 8621 §4.1.2
  ## forbids orphaning an Email from all mailboxes.
  EmailUpdate(kind: euSetMailboxIds, mailboxes: ids)

# -----------------------------------------------------------------------------
# Domain-named convenience constructors (design §3.2.3)
# -----------------------------------------------------------------------------

func markRead*(): EmailUpdate =
  ## Mark the target Email as read (sets the IANA ``$seen`` keyword).
  addKeyword(kwSeen)

func markUnread*(): EmailUpdate =
  ## Mark the target Email as unread (clears the IANA ``$seen`` keyword).
  removeKeyword(kwSeen)

func markFlagged*(): EmailUpdate =
  ## Flag the target Email (sets the IANA ``$flagged`` keyword).
  addKeyword(kwFlagged)

func markUnflagged*(): EmailUpdate =
  ## Unflag the target Email (clears the IANA ``$flagged`` keyword).
  removeKeyword(kwFlagged)

func moveToMailbox*(id: Id): EmailUpdate =
  ## Move the target Email to mailbox ``id``, REPLACING its full mailbox
  ## membership. Matches universal mail-UI "Move to" semantics (design
  ## §3.2.3.1, F21). Callers wanting additive membership use
  ## ``addToMailbox(id)`` instead.
  EmailUpdate(
    kind: euSetMailboxIds,
    # @[id] is non-empty by construction; parseNonEmptyMailboxIdSet cannot
    # Err here.
    mailboxes: parseNonEmptyMailboxIdSet(@[id]).get(),
  )

# =============================================================================
# EmailUpdateSet
# =============================================================================

type EmailUpdateSet* = distinct seq[EmailUpdate]
  ## Validated, conflict-free batch of EmailUpdate operations targeting a
  ## single Email id. Construction gated by initEmailUpdateSet — the raw
  ## distinct constructor is not part of the public surface.

# -----------------------------------------------------------------------------
# Conflict ADT
# -----------------------------------------------------------------------------

type PathShape = enum
  psSubPath
  psFullReplace

type PathOp = object
  targetPath: string
  parentPath: string
  kind: EmailUpdateVariantKind

type ConflictKind = enum
  ckDuplicatePath
  ckOppositeOps
  ckPrefixCollision

type Conflict {.ruleOff: "objects".} = object
  ## Named conflict — decouples the domain classification step
  ## (``samePathConflicts`` / ``parentPrefixConflicts``) from the wire
  ## ``ValidationError`` shape. ``toValidationError`` is the single
  ## translation boundary, so adding a ``ConflictKind`` variant forces a
  ## compile error at exactly one place.
  case kind: ConflictKind
  of ckDuplicatePath, ckOppositeOps:
    targetPath: string
  of ckPrefixCollision:
    property: string

func shape(k: EmailUpdateVariantKind): PathShape =
  ## Single source of truth for sub-path vs full-replace classification;
  ## ``parentPrefixConflicts`` partitions the op set via this one switch
  ## so Class 3 stays purely a set-algebra question.
  case k
  of euAddKeyword, euRemoveKeyword, euAddToMailbox, euRemoveFromMailbox: psSubPath
  of euSetKeywords, euSetMailboxIds: psFullReplace

func classify(u: EmailUpdate): PathOp =
  ## Logical paths only — RFC 6901 JSON Pointer escaping happens at the
  ## serde layer, which re-derives independently because it cares about
  ## escaped wire keys, a different concern.
  case u.kind
  of euAddKeyword, euRemoveKeyword:
    PathOp(targetPath: "keywords/" & $u.keyword, parentPath: "keywords", kind: u.kind)
  of euSetKeywords:
    PathOp(targetPath: "keywords", parentPath: "keywords", kind: u.kind)
  of euAddToMailbox, euRemoveFromMailbox:
    PathOp(
      targetPath: "mailboxIds/" & $u.mailboxId, parentPath: "mailboxIds", kind: u.kind
    )
  of euSetMailboxIds:
    PathOp(targetPath: "mailboxIds", parentPath: "mailboxIds", kind: u.kind)

# -----------------------------------------------------------------------------
# Conflict detection
# -----------------------------------------------------------------------------

func parentPrefixConflicts(ops: openArray[PathOp]): seq[Conflict] =
  ## Class 3 — RFC 8620 §5.3 prefix-pointer prohibition. A wire patch
  ## MUST NOT pair a full-replace on ``<p>`` with any sub-path write under
  ## ``<p>/...``; detection is the intersection of the two parent-path
  ## sets.
  let replaced =
    ops.filterIt(it.kind.shape == psFullReplace).mapIt(it.parentPath).toHashSet
  let subPathed =
    ops.filterIt(it.kind.shape == psSubPath).mapIt(it.parentPath).toHashSet
  collect:
    for parent in (replaced * subPathed):
      Conflict(kind: ckPrefixCollision, property: parent)

func samePathConflicts(ops: openArray[PathOp]): seq[Conflict] =
  ## Class 1 (duplicate target path) and Class 2 (opposite ops on the
  ## same sub-path). ``withValue`` dispatches on presence without
  ## raising, keeping detection compatible with ``{.push raises: [].}``;
  ## raw ``Table.[]`` would infer ``raises: [KeyError]`` under
  ## ``strictEffects``. Subsequent writes at a seen path compare against
  ## the FIRST occurrence, so three writes at one path yield two
  ## conflicts, not three.
  result = @[]
  var firstKindAt = initTable[string, EmailUpdateVariantKind]()
  for op in ops:
    firstKindAt.withValue(op.targetPath, firstKind):
      # Case-object construction with a runtime discriminator is rejected
      # — each branch here commits to a literal ``ConflictKind`` so the
      # compiler can prove the active branch matches the supplied fields.
      if firstKind[] == op.kind:
        result.add Conflict(kind: ckDuplicatePath, targetPath: op.targetPath)
      else:
        result.add Conflict(kind: ckOppositeOps, targetPath: op.targetPath)
    do:
      firstKindAt[op.targetPath] = op.kind

func toValidationError(c: Conflict): ValidationError =
  ## Sole domain-to-wire translator. Detection keeps conflicts in
  ## ``Conflict`` form so the classification step never hand-builds wire
  ## text; adding a ``ConflictKind`` variant forces a compile error here
  ## rather than letting a new violation slip out untranslated.
  ##
  ## Combined of-arm mirrors the declaration (``ckDuplicatePath,
  ## ckOppositeOps`` share ``targetPath``); the inner ``if c.kind ==``
  ## discriminates between them without splitting the arm, which strict
  ## would reject.
  case c.kind
  of ckDuplicatePath, ckOppositeOps:
    if c.kind == ckDuplicatePath:
      validationError("EmailUpdateSet", "duplicate target path", c.targetPath)
    else:
      validationError(
        "EmailUpdateSet", "opposite operations on same sub-path", c.targetPath
      )
  of ckPrefixCollision:
    validationError(
      "EmailUpdateSet", "sub-path operation alongside full-replace on same parent",
      c.property,
    )

# -----------------------------------------------------------------------------
# Smart constructor
# -----------------------------------------------------------------------------

func initEmailUpdateSet*(
    updates: openArray[EmailUpdate]
): Result[EmailUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor (Part F design §3.2.4). Rejects:
  ##   * empty input (F22) — the builder's ``update: Opt[Table[Id, _]]``
  ##     has exactly one "no updates for this id" representation: omit
  ##     the entry from the outer table;
  ##   * Class 1 — duplicate target path;
  ##   * Class 2 — opposite operations on the same sub-path;
  ##   * Class 3 — sub-path operation alongside full-replace on the same
  ##     parent (RFC 8620 §5.3 prefix-pointer prohibition).
  ## All violations surface in a single Err pass.
  if updates.len == 0:
    return
      err(@[validationError("EmailUpdateSet", "must contain at least one update", "")])

  let ops = updates.toSeq.mapIt(classify(it))
  let conflicts = samePathConflicts(ops) & parentPrefixConflicts(ops)
  if conflicts.len > 0:
    return err(conflicts.mapIt(toValidationError(it)))
  ok(EmailUpdateSet(@updates))

# =============================================================================
# NonEmptyEmailUpdates — whole-container /set update algebra (RFC 8621 §4.6)
# =============================================================================

type NonEmptyEmailUpdates* = distinct Table[Id, EmailUpdateSet]
  ## Non-empty, duplicate-free batch of per-email update operations keyed
  ## by existing Email ``Id``. Construction gated by
  ## ``parseNonEmptyEmailUpdates``; the raw distinct constructor is
  ## module-private surface. Shape mirrors ``NonEmptyMailboxUpdates`` and
  ## ``NonEmptyEmailSubmissionUpdates`` — ``addSet[Email, ...]`` serialises
  ## the container via its own ``toJson`` rather than assembling the wire
  ## patch per-caller.

func parseNonEmptyEmailUpdates*(
    items: openArray[(Id, EmailUpdateSet)]
): Result[NonEmptyEmailUpdates, seq[ValidationError]] =
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
    typeName = "NonEmptyEmailUpdates",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate email id",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[Id, EmailUpdateSet](items.len)
  for (id, updateSet) in items:
    t[id] = updateSet
  ok(NonEmptyEmailUpdates(t))
