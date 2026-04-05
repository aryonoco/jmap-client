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

{.push ruleOff: "hasDoc".}

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
