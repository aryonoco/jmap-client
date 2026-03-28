# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Semantically distinct identifier types built on Id validation rules. Separate
## from primitives.nim because these omit `len` — length is meaningless for
## opaque server tokens.

import std/hashes
import std/sequtils

import pkg/results

import ./validation

type AccountId* {.requiresInit.} = distinct string
  ## Server-assigned account identifier (RFC 8620 §2). Distinct from Id to
  ## prevent cross-use.

defineStringDistinctOps(AccountId)

type JmapState* {.requiresInit.} = distinct string
  ## Opaque server state token for change tracking (RFC 8620 §5.3). No len
  ## borrow — length is meaningless.

{.push ruleOff: "hasDoc".}
func `==`*(a, b: JmapState): bool {.borrow.}
func `$`*(a: JmapState): string {.borrow.}
func hash*(a: JmapState): Hash {.borrow.}
{.pop.}

type MethodCallId* {.requiresInit.} = distinct string
  ## Client-assigned tag correlating requests with responses in a batch
  ## (RFC 8620 §3.2).

{.push ruleOff: "hasDoc".}
func `==`*(a, b: MethodCallId): bool {.borrow.}
func `$`*(a: MethodCallId): string {.borrow.}
func hash*(a: MethodCallId): Hash {.borrow.}
{.pop.}

type CreationId* {.requiresInit.} = distinct string
  ## Client-assigned temporary ID for back-references within a /set call
  ## (RFC 8620 §5.3). Wire format prefixes with '#'.

{.push ruleOff: "hasDoc".}
func `==`*(a, b: CreationId): bool {.borrow.}
func `$`*(a: CreationId): string {.borrow.}
func hash*(a: CreationId): Hash {.borrow.}
{.pop.}

func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("AccountId", "contains control characters", raw))
  doAssert raw.len >= 1 and raw.len <= 255
  ok(AccountId(raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  if raw.len == 0:
    return err(validationError("JmapState", "must not be empty", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("JmapState", "contains control characters", raw))
  doAssert raw.len > 0
  ok(JmapState(raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  if raw.len == 0:
    return err(validationError("MethodCallId", "must not be empty", raw))
  doAssert raw.len > 0
  ok(MethodCallId(raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  if raw.len == 0:
    return err(validationError("CreationId", "must not be empty", raw))
  if raw[0] == '#':
    return err(validationError("CreationId", "must not include '#' prefix", raw))
  doAssert raw.len > 0 and raw[0] != '#'
  ok(CreationId(raw))
