# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/hashes
import std/sequtils

import pkg/results

import ./validation

type AccountId* {.requiresInit.} = distinct string

defineStringDistinctOps(AccountId)

type JmapState* {.requiresInit.} = distinct string

func `==`*(a, b: JmapState): bool {.borrow.}
func `$`*(a: JmapState): string {.borrow.}
func hash*(a: JmapState): Hash {.borrow.}

type MethodCallId* {.requiresInit.} = distinct string

func `==`*(a, b: MethodCallId): bool {.borrow.}
func `$`*(a: MethodCallId): string {.borrow.}
func hash*(a: MethodCallId): Hash {.borrow.}

type CreationId* {.requiresInit.} = distinct string

func `==`*(a, b: CreationId): bool {.borrow.}
func `$`*(a: CreationId): string {.borrow.}
func hash*(a: CreationId): Hash {.borrow.}

func parseAccountId*(raw: string): Result[AccountId, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## AccountIds are server-assigned Id[Account] values (§1.6.2, §2) —
  ## same lenient rules as parseIdFromServer.
  if raw.len < 1 or raw.len > 255:
    return err(validationError("AccountId", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("AccountId", "contains control characters", raw))
  ok(AccountId(raw))

func parseJmapState*(raw: string): Result[JmapState, ValidationError] =
  ## Non-empty, no control characters. Server-assigned — same defensive
  ## checks as other server-assigned identifiers.
  if raw.len == 0:
    return err(validationError("JmapState", "must not be empty", raw))
  if raw.anyIt(it < ' '):
    return err(validationError("JmapState", "contains control characters", raw))
  ok(JmapState(raw))

func parseMethodCallId*(raw: string): Result[MethodCallId, ValidationError] =
  ## Non-empty. Client-generated.
  if raw.len == 0:
    return err(validationError("MethodCallId", "must not be empty", raw))
  ok(MethodCallId(raw))

func parseCreationId*(raw: string): Result[CreationId, ValidationError] =
  ## Non-empty. Must not start with '#' (the prefix is a wire-format concern).
  if raw.len == 0:
    return err(validationError("CreationId", "must not be empty", raw))
  if raw[0] == '#':
    return err(validationError("CreationId", "must not include '#' prefix", raw))
  ok(CreationId(raw))
