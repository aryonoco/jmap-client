# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Identity entity for RFC 8621 (JMAP Mail) section 6. An Identity stores
## information about an email address or domain a user may send as. Identity
## is a read model with plain public fields; IdentityCreate is the creation
## model with a smart constructor enforcing non-empty email.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables

import ../types/validation
import ../types/primitives
import ./addresses

type Identity* {.ruleOff: "objects".} = object
  ## An Identity represents information about an email address or domain
  ## the user may send from (RFC 8621 section 6).
  id*: Id ## Server-assigned identifier.
  name*: string ## Display name for this identity, default "".
  email*: string ## Email address, immutable after creation.
  replyTo*: Opt[seq[EmailAddress]] ## Default Reply-To addresses, or none.
  bcc*: Opt[seq[EmailAddress]] ## Default Bcc addresses, or none.
  textSignature*: string ## Plain text signature, default "".
  htmlSignature*: string ## HTML signature, default "".
  mayDelete*: bool ## Whether the client may delete this identity.

type IdentityCreate* {.ruleOff: "objects".} = object
  ## Creation model for Identity — excludes server-set fields (id, mayDelete).
  email*: string ## Required, must be non-empty.
  name*: string ## Display name, default "".
  replyTo*: Opt[seq[EmailAddress]] ## Default Reply-To addresses, or none.
  bcc*: Opt[seq[EmailAddress]] ## Default Bcc addresses, or none.
  textSignature*: string ## Plain text signature, default "".
  htmlSignature*: string ## HTML signature, default "".

type IdentityCreatedItem* {.ruleOff: "objects".} = object
  ## Server-authoritative subset returned in Identity/set ``created[cid]``
  ## (RFC 8620 §5.3): the server MUST return ``id`` plus any server-set or
  ## server-modified properties; for Identity, the only such property is
  ## ``mayDelete``. The full ``Identity`` record is NOT returned — the
  ## client already knows the other fields (it sent them in ``create``).
  ##
  ## ``mayDelete`` is ``Opt[bool]`` rather than ``bool`` because Stalwart
  ## 0.15.5 omits it from this payload (a strict-RFC §5.3 minor
  ## divergence): the create acknowledgement is just ``{"id": "<id>"}``.
  ## Postel's-law accommodation per ``.claude/rules/nim-conventions.md``
  ## §"Serde Conventions": be lenient on receive. Mirrors the
  ## ``EmailCreatedItem`` design (``email.nim``).
  id*: Id
  mayDelete*: Opt[bool]

func parseIdentityCreate*(
    email: string,
    name: string = "",
    replyTo: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    bcc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    textSignature: string = "",
    htmlSignature: string = "",
): Result[IdentityCreate, ValidationError] =
  ## Smart constructor: validates non-empty email, constructs IdentityCreate.
  ## All parameters except email have RFC-matching defaults for ergonomic use.
  if email.len == 0:
    return err(validationError("IdentityCreate", "email must not be empty", ""))
  return ok(
    IdentityCreate(
      email: email,
      name: name,
      replyTo: replyTo,
      bcc: bcc,
      textSignature: textSignature,
      htmlSignature: htmlSignature,
    )
  )

# =============================================================================
# Identity Update Algebra (RFC 8621 §6 /set update path)
# =============================================================================

type IdentityUpdateVariantKind* = enum
  ## Discriminator for ``IdentityUpdate``. RFC 8621 §6 settable Identity
  ## properties only — ``id``, ``email``, and ``mayDelete`` have no variant
  ## because they are server-set or immutable-after-create.
  iuSetName
  iuSetReplyTo
  iuSetBcc
  iuSetTextSignature
  iuSetHtmlSignature

type IdentityUpdate* {.ruleOff: "objects".} = object
  ## Single typed Identity patch operation (RFC 8621 §6). Whole-value
  ## replace semantics — no sub-path targeting. Case object makes
  ## "exactly one target per update" a type-level fact; shape mirrors
  ## ``MailboxUpdate`` and ``VacationResponseUpdate``.
  case kind*: IdentityUpdateVariantKind
  of iuSetName:
    name*: string
  of iuSetReplyTo:
    replyTo*: Opt[seq[EmailAddress]]
      ## Opt.none clears the default Reply-To per RFC 8621 §6.
  of iuSetBcc:
    bcc*: Opt[seq[EmailAddress]] ## Opt.none clears the default Bcc per RFC 8621 §6.
  of iuSetTextSignature:
    textSignature*: string
  of iuSetHtmlSignature:
    htmlSignature*: string

func setName*(name: string): IdentityUpdate =
  ## Replace the Identity's display name.
  IdentityUpdate(kind: iuSetName, name: name)

func setReplyTo*(replyTo: Opt[seq[EmailAddress]]): IdentityUpdate =
  ## Replace the default Reply-To list. Opt.none clears it per RFC 8621 §6.
  IdentityUpdate(kind: iuSetReplyTo, replyTo: replyTo)

func setBcc*(bcc: Opt[seq[EmailAddress]]): IdentityUpdate =
  ## Replace the default Bcc list. Opt.none clears it per RFC 8621 §6.
  IdentityUpdate(kind: iuSetBcc, bcc: bcc)

func setTextSignature*(textSignature: string): IdentityUpdate =
  ## Replace the plain-text signature.
  IdentityUpdate(kind: iuSetTextSignature, textSignature: textSignature)

func setHtmlSignature*(htmlSignature: string): IdentityUpdate =
  ## Replace the HTML signature.
  IdentityUpdate(kind: iuSetHtmlSignature, htmlSignature: htmlSignature)

type IdentityUpdateSet* = distinct seq[IdentityUpdate]
  ## Validated, conflict-free batch of IdentityUpdate operations targeting
  ## a single Identity id. Construction gated by ``initIdentityUpdateSet``
  ## — the raw distinct constructor is not part of the public surface.

func initIdentityUpdateSet*(
    updates: openArray[IdentityUpdate]
): Result[IdentityUpdateSet, seq[ValidationError]] =
  ## Accumulating smart constructor. Rejects:
  ##   * empty input — the /set builder has exactly one "no updates for
  ##     this id" representation (omit the entry from the outer table);
  ##   * duplicate target property — two updates with the same kind would
  ##     produce a JSON patch object with duplicate keys.
  ## All violations surface in a single Err pass; each repeated kind is
  ## reported exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    updates,
    it.kind,
    typeName = "IdentityUpdateSet",
    emptyMsg = "must contain at least one update",
    dupMsg = "duplicate target property",
  )
  if errs.len > 0:
    return err(errs)
  ok(IdentityUpdateSet(@updates))

# =============================================================================
# NonEmptyIdentityUpdates — whole-container /set update algebra (RFC 8621 §6)
# =============================================================================

type NonEmptyIdentityUpdates* = distinct Table[Id, IdentityUpdateSet]
  ## Non-empty, duplicate-free batch of per-identity update operations
  ## keyed by existing Identity ``Id``. Construction gated by
  ## ``parseNonEmptyIdentityUpdates``; the raw distinct constructor is
  ## module-private surface. Shape mirrors ``NonEmptyMailboxUpdates`` and
  ## ``NonEmptyEmailUpdates``.

func parseNonEmptyIdentityUpdates*(
    items: openArray[(Id, IdentityUpdateSet)]
): Result[NonEmptyIdentityUpdates, seq[ValidationError]] =
  ## Accumulating smart constructor. Rejects:
  ##   * empty input — the /set builder's ``update:`` field has exactly
  ##     one "no updates" representation (omit the entry via ``Opt.none``);
  ##   * duplicate ``Id`` keys — silent last-wins shadowing at Table
  ##     construction would swallow caller data; ``openArray`` (not
  ##     ``Table``) preserves duplicates for inspection.
  ## All violations surface in a single Err pass.
  let errs = validateUniqueByIt(
    items,
    it[0],
    typeName = "NonEmptyIdentityUpdates",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate identity id",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[Id, IdentityUpdateSet](items.len)
  for (id, updateSet) in items:
    t[id] = updateSet
  ok(NonEmptyIdentityUpdates(t))
