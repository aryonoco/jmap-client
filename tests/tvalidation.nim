# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/hashes

import jmap_client/validation

# Test distinct types — must be at top level for export markers in borrow templates
type TestStr {.requiresInit.} = distinct string

defineStringDistinctOps(TestStr)

type TestInt {.requiresInit.} = distinct int64

defineIntDistinctOps(TestInt)

# --- validationError constructor ---

block validationErrorConstructor:
  let ve = validationError("Id", "length must be 1-255", "")
  doAssert ve.typeName == "Id"
  doAssert ve.message == "length must be 1-255"
  doAssert ve.value == ""

block validationErrorAllFields:
  let ve = validationError("UnsignedInt", "must be non-negative", "-1")
  doAssert ve.typeName == "UnsignedInt"
  doAssert ve.message == "must be non-negative"
  doAssert ve.value == "-1"

# --- defineStringDistinctOps ---

block stringDistinctOps:
  let a = TestStr("hello")
  let b = TestStr("hello")
  let c = TestStr("world")

  # Equality
  doAssert a == b
  doAssert not (a == c)

  # String conversion
  doAssert $a == "hello"

  # Hash — equal values must produce equal hashes
  doAssert hash(a) == hash(b)

  # Length
  doAssert a.len == 5
  doAssert TestStr("").len == 0

# --- defineIntDistinctOps ---

block intDistinctOps:
  let x = TestInt(10)
  let y = TestInt(10)
  let z = TestInt(20)

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
  doAssert $TestInt(-100) == "-100"

  # Hash — equal values must produce equal hashes
  doAssert hash(x) == hash(y)

# --- Base64UrlChars ---

block base64UrlChars:
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
