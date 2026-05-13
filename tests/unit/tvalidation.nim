# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for ValidationError construction and sealed-object ops templates.

import std/hashes

import jmap_client/internal/types/validation
import ../mtestblock

# Test sealed objects — top-level so export markers in op templates apply.
type TestStr {.ruleOff: "objects".} = object
  rawValue: string

defineSealedStringOps(TestStr)

type TestInt {.ruleOff: "objects".} = object
  rawValue: int64

defineSealedIntOps(TestInt)

# --- validationError constructor ---

testCase validationErrorConstructor:
  let ve = validationError("Id", "length must be 1-255", "")
  doAssert ve.typeName == "Id"
  doAssert ve.message == "length must be 1-255"
  doAssert ve.value == ""

testCase validationErrorAllFields:
  let ve = validationError("UnsignedInt", "must be non-negative", "-1")
  doAssert ve.typeName == "UnsignedInt"
  doAssert ve.message == "must be non-negative"
  doAssert ve.value == "-1"

# --- defineSealedStringOps ---

testCase stringDistinctOps:
  const a = TestStr(rawValue: "hello")
  const b = TestStr(rawValue: "hello")
  const c = TestStr(rawValue: "world")

  # Equality
  doAssert a == b
  doAssert not (a == c)

  # String conversion
  doAssert $a == "hello"

  # Hash — equal values must produce equal hashes
  doAssert hash(a) == hash(b)

  # Length
  doAssert a.len == 5
  doAssert TestStr(rawValue: "").len == 0

# --- defineSealedIntOps ---

testCase intDistinctOps:
  const x = TestInt(rawValue: 10)
  const y = TestInt(rawValue: 10)
  const z = TestInt(rawValue: 20)

  # Equality
  doAssert x == y
  doAssert not (x == z)

  # Less than
  doAssert x < z
  doAssert not (z < x)

  # Less than or equal
  doAssert x <= y
  doAssert x <= z
  doAssert not (z <= x)

  # String conversion
  doAssert $x == "10"
  doAssert $TestInt(rawValue: -100) == "-100"

  # Hash — equal values must produce equal hashes
  doAssert hash(x) == hash(y)

# --- Base64UrlChars ---

testCase base64UrlChars:
  # Uppercase letters
  doAssert 'A' in Base64UrlChars
  doAssert 'Z' in Base64UrlChars

  # Lowercase letters
  doAssert 'a' in Base64UrlChars
  doAssert 'z' in Base64UrlChars

  # Digits
  doAssert '0' in Base64UrlChars
  doAssert '9' in Base64UrlChars

  # Special base64url characters
  doAssert '-' in Base64UrlChars
  doAssert '_' in Base64UrlChars

  # Standard base64 characters NOT in base64url
  doAssert '=' notin Base64UrlChars
  doAssert '+' notin Base64UrlChars
  doAssert '/' notin Base64UrlChars

  # Other characters that must be absent
  doAssert ' ' notin Base64UrlChars
