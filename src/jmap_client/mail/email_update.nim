# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## EmailUpdate algebra for RFC 8621 (JMAP Mail) §4.6 update path. Six
## protocol-primitive smart constructors plus five domain-named convenience
## constructors produce typed ``EmailUpdate`` values; ``initEmailUpdateSet``
## composes them into a validated, conflict-free batch.

{.push raises: [], noSideEffect.}

import std/sets
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

func pathInfo(u: EmailUpdate): (string, string, bool) =
  ## Returns ``(targetPath, parentPath, isFullReplace)`` for conflict
  ## detection. Logical paths only — RFC 6901 JSON Pointer escaping happens
  ## at the serde layer, which re-derives independently because it cares
  ## about escaped wire keys, a different concern.
  case u.kind
  of euAddKeyword, euRemoveKeyword:
    ("keywords/" & $u.keyword, "keywords", false)
  of euSetKeywords:
    ("keywords", "keywords", true)
  of euAddToMailbox, euRemoveFromMailbox:
    ("mailboxIds/" & $u.mailboxId, "mailboxIds", false)
  of euSetMailboxIds:
    ("mailboxIds", "mailboxIds", true)

func initEmailUpdateSet*(
    updates: openArray[EmailUpdate]
): Result[EmailUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor (Part F design §3.2.4). Rejects:
  ##   * empty input (F22) — the builder's ``update: Opt[Table[Id, _]]`` has
  ##     exactly one "no updates for this id" representation: omit the entry
  ##     from the outer table;
  ##   * Class 1 — duplicate target path (two updates writing the same wire
  ##     key with the same value-shape);
  ##   * Class 2 — opposite operations on the same sub-path (e.g.
  ##     addKeyword + removeKeyword on the same keyword);
  ##   * Class 3 — sub-path operation alongside full-replace on the same
  ##     parent (RFC 8620 §5.3 prefix-pointer prohibition).
  ## All violations surface in a single Err pass. Class 1/2 detection
  ## compares each subsequent update's kind against the FIRST occurrence at
  ## that target path — three updates at one path produce two errors, not
  ## three.
  var errs: seq[ValidationError] = @[]

  if updates.len == 0:
    errs.add validationError("EmailUpdateSet", "must contain at least one update", "")

  var firstKindAtPath = initTable[string, EmailUpdateVariantKind]()
  var parentReplaced = initHashSet[string]()
  var parentSubPathed = initHashSet[string]()

  for u in updates:
    let (targetPath, parentPath, isFullReplace) = pathInfo(u)

    if targetPath in firstKindAtPath:
      let firstKind = firstKindAtPath[targetPath]
      if firstKind == u.kind:
        errs.add validationError("EmailUpdateSet", "duplicate target path", targetPath)
      else:
        errs.add validationError(
          "EmailUpdateSet", "opposite operations on same sub-path", targetPath
        )
    else:
      firstKindAtPath[targetPath] = u.kind

    if isFullReplace:
      parentReplaced.incl(parentPath)
    else:
      parentSubPathed.incl(parentPath)

  for parent in parentReplaced:
    if parent in parentSubPathed:
      errs.add validationError(
        "EmailUpdateSet", "sub-path operation alongside full-replace on same parent",
        parent,
      )

  if errs.len > 0:
    return err(errs)
  return ok(EmailUpdateSet(@updates))
