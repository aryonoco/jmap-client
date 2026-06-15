# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Thread entity for RFC 8621 (JMAP Mail) section 3. A Thread groups related
## Emails; every Thread contains at least one Email. Both properties (id,
## emailIds) are server-set and immutable — Thread has no /set method.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes

import ../types/validation
import ../types/primitives

type Thread* {.ruleOff: "objects".} = object
  ## A Thread groups related Emails (RFC 8621 §3). ``emailIds`` is non-empty
  ## only implicitly: §3 requires every Email to belong to a Thread, so a
  ## Thread holds at least one Email — the ``emailIds`` property text states
  ## no such constraint itself. The invariant is carried by the field type
  ## ``NonEmptyIdSeq`` (Tier-A), so the read is a direct public field.
  id*: Id
  emailIds*: NonEmptyIdSeq

func parseThread*(id: Id, emailIds: seq[Id]): Result[Thread, ValidationError] =
  ## ``emailIds`` non-empty — implicit in RFC 8621 §3 (every Email belongs to
  ## a Thread, so a Thread holds ≥1 Email; the property text is silent) —
  ## carried by ``NonEmptyIdSeq``.
  let ids = parseNonEmptyIdSeq(emailIds).valueOr:
    return err(validationError("Thread", "emailIds must contain at least one Id", ""))
  ok(Thread(id: id, emailIds: ids))

# =============================================================================
# PartialThread
# =============================================================================

type PartialThread* {.ruleOff: "objects".} = object
  ## RFC 8621 §3 partial Thread (sparse ``/get``). No invariant — direct fields.
  id*: Opt[Id]
  emailIds*: Opt[seq[Id]]

func initPartialThread*(id: Opt[Id], emailIds: Opt[seq[Id]]): PartialThread =
  ## Module-public constructor exposed for the serde layer. ``PartialThread``
  ## carries no validation invariants (sparse projection), so this is a
  ## trivial wrapper that sets the public fields directly.
  return PartialThread(id: id, emailIds: emailIds)

# =============================================================================
# ThreadGetProperty — typed Thread/get property selector (A3.6)
# =============================================================================

type ThreadGetPropertyKind* = enum
  ## Discriminator for ``ThreadGetProperty``. Backing strings are the
  ## RFC 8621 §3 Thread property wire names; ``tgkOther`` carries a
  ## capability-extension property whose raw identifier lives alongside.
  tgkId = "id"
  tgkEmailIds = "emailIds"
  tgkOther

type ThreadGetProperty* {.ruleOff: "objects".} = object
  ## Typed RFC 8621 §3 Thread/get property selector. Construction sealed;
  ## use the ``tgp…`` constants or ``parseThreadGetProperty``.
  case rawKind: ThreadGetPropertyKind
  of tgkOther:
    rawIdentifier: string
  of tgkId, tgkEmailIds:
    discard

func kind*(p: ThreadGetProperty): ThreadGetPropertyKind =
  ## Returns the discriminator — one of the named arms or ``tgkOther``.
  p.rawKind

func wireName*(p: ThreadGetProperty): string =
  ## RFC 8621 §3 wire name. For ``tgkOther`` this is the captured identifier.
  case p.rawKind
  of tgkOther:
    p.rawIdentifier
  of tgkId, tgkEmailIds:
    $p.rawKind

func `$`*(p: ThreadGetProperty): string =
  ## Wire-form string — equivalent to ``wireName``.
  p.wireName

func `==`*(a, b: ThreadGetProperty): bool =
  ## Wire-identity equality: the classifying parser never yields ``tgkOther``
  ## for a known wire name, so wire-name identity is structural identity.
  a.wireName == b.wireName

func hash*(p: ThreadGetProperty): Hash =
  ## Consistent with ``==`` — equal wire names hash equal.
  hash(p.wireName)

const
  tgpId* = ThreadGetProperty(rawKind: tgkId) ## Selects ``id``.
  tgpEmailIds* = ThreadGetProperty(rawKind: tgkEmailIds) ## Selects ``emailIds``.

func parseThreadGetProperty*(raw: string): Result[ThreadGetProperty, ValidationError] =
  ## Classifying smart constructor: exact, case-sensitive match against the
  ## RFC 8621 §3 wire names; unknown non-control strings fall to ``tgkOther``
  ## (capability-extension forward-compat, A11).
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "ThreadGetProperty", raw))
  case raw
  of "id":
    ok(tgpId)
  of "emailIds":
    ok(tgpEmailIds)
  else:
    ok(ThreadGetProperty(rawKind: tgkOther, rawIdentifier: raw))

defineSealedNonEmptySeqOps(ThreadGetProperty)
