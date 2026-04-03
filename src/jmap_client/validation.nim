# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared validation infrastructure — error type, borrow templates, and charset
## constants used by all smart constructors.

import std/hashes

template ruleOff*(name: string) {.pragma.}
  ## Suppresses a nimalyzer rule for subsequent declarations until ruleOn.

template ruleOn*(name: string) {.pragma.}
  ## Re-enables a nimalyzer rule previously suppressed by ruleOff.

type ValidationError* = object of CatchableError
  ## Structured error carrying the type name, failure reason, and raw input.
  ## Raised by all smart constructors on invalid input.
  ## The ``msg`` field (inherited from CatchableError) carries the failure reason.
  typeName*: string ## Which type failed ("Id", "UnsignedInt", etc.)
  value*: string ## The raw input that failed validation

{.push ruleOff: "hasDoc".}

proc newValidationError*(typeName, message, value: string): ref ValidationError =
  ## Constructs a ref ValidationError suitable for raising.
  result = (ref ValidationError)(msg: message, typeName: typeName, value: value)

template defineStringDistinctOps*(T: typedesc) =
  proc `==`*(a, b: T): bool {.borrow.}
  proc `$`*(a: T): string {.borrow.}
  proc hash*(a: T): Hash {.borrow.}
  proc len*(a: T): int {.borrow.}

template defineIntDistinctOps*(T: typedesc) =
  proc `==`*(a, b: T): bool {.borrow.}
  proc `<`*(a, b: T): bool {.borrow.}
  proc `<=`*(a, b: T): bool {.borrow.}
  proc `$`*(a: T): string {.borrow.}
  proc hash*(a: T): Hash {.borrow.}

const Base64UrlChars* = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}

{.pop.}
