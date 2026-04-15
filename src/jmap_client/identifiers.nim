# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Semantically distinct identifier types built on Id validation rules. Separate
## from primitives.nim because these omit `len` — length is meaningless for
## opaque server tokens.

{.push raises: [], noSideEffect.}

import std/hashes

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
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "AccountId", raw))
  return ok(AccountId(raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  detectNonControlString(raw).isOkOr:
    return err(toValidationError(error, "JmapState", raw))
  return ok(JmapState(raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  detectNonEmpty(raw).isOkOr:
    return err(toValidationError(error, "MethodCallId", raw))
  return ok(MethodCallId(raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  detectNonEmptyNoPrefix(raw).isOkOr:
    return err(toValidationError(error, "CreationId", raw))
  return ok(CreationId(raw))
