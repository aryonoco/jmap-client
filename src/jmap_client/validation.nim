# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared validation infrastructure — error type, borrow templates, charset
## constants, and Result helpers used by all smart constructors.

{.push raises: [].}

import std/hashes
import std/sequtils

import results
export results

template ruleOff*(name: string) {.pragma.}
  ## Suppresses a nimalyzer rule for subsequent declarations until ruleOn.

template ruleOn*(name: string) {.pragma.}
  ## Re-enables a nimalyzer rule previously suppressed by ruleOff.

type ValidationError* = object
  ## Structured error carrying the type name, failure reason, and raw input.
  ## Returned on the error rail by all smart constructors on invalid input.
  typeName*: string ## Which type failed ("Id", "UnsignedInt", etc.)
  message*: string ## The failure reason
  value*: string ## The raw input that failed validation

func validationError*(typeName, message, value: string): ValidationError =
  ## Constructs a ValidationError value for use on the error rail.
  return ValidationError(typeName: typeName, message: message, value: value)

template defineStringDistinctOps*(T: typedesc) =
  ## Borrows standard operations for a ``distinct string`` type: equality,
  ## stringification, hashing, and length.
  func `==`*(a, b: T): bool {.borrow.}
    ## Equality comparison delegated to the underlying string.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying string.
  func hash*(a: T): Hash {.borrow.} ## Hash delegated to the underlying string.
  func len*(a: T): int {.borrow.} ## Length delegated to the underlying string.

template defineIntDistinctOps*(T: typedesc) =
  ## Borrows standard operations for a ``distinct int`` type: equality,
  ## ordering, stringification, and hashing.
  func `==`*(a, b: T): bool {.borrow.}
    ## Equality comparison delegated to the underlying integer.
  func `<`*(a, b: T): bool {.borrow.}
    ## Less-than comparison delegated to the underlying integer.
  func `<=`*(a, b: T): bool {.borrow.}
    ## Less-or-equal comparison delegated to the underlying integer.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying integer.
  func hash*(a: T): Hash {.borrow.} ## Hash delegated to the underlying integer.

template defineHashSetDistinctOps*(T: typedesc, E: typedesc) =
  ## Borrows standard read-only operations for a ``distinct HashSet``
  ## type. ``T`` is the distinct type, ``E`` is the element type.
  ## No mutation operations — these are immutable read models (Decision B3).
  ## No ``==`` or ``hash`` — set equality is not a domain operation for
  ## these types; they are constructed once and queried, never compared
  ## as whole sets or used as table keys.
  func len*(s: T): int {.borrow.}
    ## Number of elements delegated to the underlying HashSet.
  func contains*(s: T, e: E): bool {.borrow.}
    ## Membership test delegated to the underlying HashSet.
  func card*(s: T): int {.borrow.} ## Cardinality delegated to the underlying HashSet.

func validateServerAssignedToken*(
    typeName: string, raw: string
): Result[void, ValidationError] =
  ## Shared validation for server-assigned identifiers: 1–255 octets, no
  ## control characters. Used by parseIdFromServer and parseAccountId to
  ## eliminate duplicated validation logic.
  if raw.len < 1 or raw.len > 255:
    return err(validationError(typeName, "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError(typeName, "contains control characters", raw))
  return ok()

const Base64UrlChars* = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}
  ## Characters permitted in RFC 8620 §1.2 entity identifiers.
