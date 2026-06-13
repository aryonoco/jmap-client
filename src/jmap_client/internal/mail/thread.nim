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

# nimalyzer: Thread intentionally has no public fields. Fields are
# module-private to enforce the non-empty emailIds invariant via
# parseThread. Public accessor funcs below provide read access;
# UFCS makes t.field syntax work unchanged for callers.
type Thread* {.ruleOff: "objects".} = object
  ## A Thread groups related Emails (RFC 8621 section 3).
  ## Fields are module-private; external access via UFCS accessor funcs.
  rawId: Id ## module-private
  rawEmailIds: seq[Id] ## module-private, guaranteed non-empty

func id*(t: Thread): Id =
  ## Thread identifier.
  return t.rawId

func emailIds*(t: Thread): lent seq[Id] =
  ## Identifiers of Emails in this Thread, guaranteed non-empty.
  ## Borrowed view (`lent`, P12) — read-only, no per-call deep copy of the
  ## sealed container.
  return t.rawEmailIds

func parseThread*(id: Id, emailIds: seq[Id]): Result[Thread, ValidationError] =
  ## Smart constructor: validates emailIds is non-empty, constructs Thread.
  if emailIds.len == 0:
    return err(validationError("Thread", "emailIds must contain at least one Id", ""))
  return ok(Thread(rawId: id, rawEmailIds: emailIds))

# =============================================================================
# PartialThread
# =============================================================================

type PartialThread* {.ruleOff: "objects".} = object
  ## RFC 8621 §3 partial Thread. Sparse ``/get`` only — Thread has no
  ## ``/set`` (RFC 8621 §3 defines only ``/get`` and ``/changes``;
  ## threads are server-derived from Email composition, not server-
  ## stored). Private-fields-plus-accessor shape mirrors ``Thread`` (D8)
  ## for structural symmetry — no invariant to enforce on the partial
  ## side.
  rawId: Opt[Id]
  rawEmailIds: Opt[seq[Id]]

func id*(p: PartialThread): Opt[Id] =
  ## UFCS accessor — ``partial.id`` reads as a field access.
  return p.rawId

func emailIds*(p: PartialThread): Opt[seq[Id]] =
  ## UFCS accessor — ``partial.emailIds`` reads as a field access.
  return p.rawEmailIds

func initPartialThread*(id: Opt[Id], emailIds: Opt[seq[Id]]): PartialThread =
  ## Module-public constructor exposed for the serde layer. ``PartialThread``
  ## carries no validation invariants (D8 — privacy is consistency, not
  ## safety), so this is a trivial wrapper. Direct case-object literal
  ## construction is the alternative but is rejected outside this module
  ## because the raw fields are unexported.
  return PartialThread(rawId: id, rawEmailIds: emailIds)

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
