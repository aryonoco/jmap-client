# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Thread entity for RFC 8621 (JMAP Mail) section 3. A Thread groups related
## Emails; every Thread contains at least one Email. Both properties (id,
## emailIds) are server-set and immutable — Thread has no /set method.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

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

func emailIds*(t: Thread): seq[Id] =
  ## Identifiers of Emails in this Thread, guaranteed non-empty.
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
