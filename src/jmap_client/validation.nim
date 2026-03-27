# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/hashes

type ValidationError* = object
  typeName*: string ## Which type failed ("Id", "UnsignedInt", etc.)
  message*: string ## What went wrong ("length must be 1-255")
  value*: string ## The raw input that failed validation

func validationError*(typeName, message, value: string): ValidationError =
  ValidationError(typeName: typeName, message: message, value: value)

template defineStringDistinctOps*(T: typedesc) =
  func `==`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}
  func len*(a: T): int {.borrow.}

template defineIntDistinctOps*(T: typedesc) =
  func `==`*(a, b: T): bool {.borrow.}
  func `<`*(a, b: T): bool {.borrow.}
  func `<=`*(a, b: T): bool {.borrow.}
  func `$`*(a: T): string {.borrow.}
  func hash*(a: T): Hash {.borrow.}

const Base64UrlChars* = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}
