# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared validation infrastructure — error type, borrow templates, charset
## constants, and Result helpers used by all smart constructors.

{.push raises: [].}

import std/hashes

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
  ValidationError(typeName: typeName, message: message, value: value)

template defineStringDistinctOps*(T: typedesc) =
  ## Borrows standard operations for a ``distinct string`` type: equality,
  ## stringification, hashing, and length.
  func `==`*(a, b: T): bool {.borrow.}
    ## Equality comparison delegated to the underlying string.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying string.
  func hash*(a: T): Hash {.borrow.}
    ## Hash delegated to the underlying string.
  func len*(a: T): int {.borrow.}
    ## Length delegated to the underlying string.

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
  func hash*(a: T): Hash {.borrow.}
    ## Hash delegated to the underlying integer.

const Base64UrlChars* = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}
  ## Characters permitted in RFC 8620 §1.2 entity identifiers.
