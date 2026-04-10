# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Semantically distinct identifier types built on Id validation rules. Separate
## from primitives.nim because these omit `len` — length is meaningless for
## opaque server tokens.

{.push raises: [], noSideEffect.}

import std/hashes
import std/sequtils

import ./validation

type AccountId* = distinct string
  ## Server-assigned account identifier (RFC 8620 §2). Distinct from Id to
  ## prevent cross-use.

defineStringDistinctOps(AccountId)

type JmapState* = distinct string
  ## Opaque server state token for change tracking (RFC 8620 §5.3). No len
  ## borrow — length is meaningless.

func `==`*(a, b: JmapState): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: JmapState): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: JmapState): Hash {.borrow.} ## Hash delegated to the underlying string.

type MethodCallId* = distinct string
  ## Client-assigned tag correlating requests with responses in a batch
  ## (RFC 8620 §3.2).

func `==`*(a, b: MethodCallId): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: MethodCallId): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: MethodCallId): Hash {.borrow.} ## Hash delegated to the underlying string.

type CreationId* = distinct string
  ## Client-assigned temporary ID for back-references within a /set call
  ## (RFC 8620 §5.3). Wire format prefixes with '#'.

func `==`*(a, b: CreationId): bool {.borrow.}
  ## Equality comparison delegated to the underlying string.
func `$`*(a: CreationId): string {.borrow.}
  ## String representation delegated to the underlying string.
func hash*(a: CreationId): Hash {.borrow.} ## Hash delegated to the underlying string.

func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  ?validateServerAssignedToken("AccountId", raw)
  doAssert raw.len >= 1 and raw.len <= 255
  return ok(AccountId(raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  if raw.len == 0:
    return err(validationError("JmapState", "must not be empty", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("JmapState", "contains control characters", raw))
  doAssert raw.len > 0
  return ok(JmapState(raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  if raw.len == 0:
    return err(validationError("MethodCallId", "must not be empty", raw))
  doAssert raw.len > 0
  return ok(MethodCallId(raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  if raw.len < 1:
    return err(validationError("CreationId", "must not be empty", raw))
  elif raw[0] == '#':
    return err(validationError("CreationId", "must not include '#' prefix", raw))
  doAssert raw.len > 0
  return ok(CreationId(raw))
