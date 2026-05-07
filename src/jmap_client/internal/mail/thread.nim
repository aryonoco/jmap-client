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
