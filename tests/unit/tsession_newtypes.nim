# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for DisplayName and ApiUrl sealed smart constructors (RFC 8620 §2).

import jmap_client/internal/types/session
import jmap_client/internal/types/validation

import ../massertions
import ../mtestblock

# --- parseDisplayName ---

testCase parseDisplayNameValid:
  let v = parseDisplayName("Alice").get()
  doAssert $v == "Alice"

testCase parseDisplayNameEmptyAccepted:
  assertOk parseDisplayName("")

testCase parseDisplayNameControlChar:
  assertErrFields parseDisplayName("bad\x01name"),
    "DisplayName", "contains control characters", "bad\x01name"

testCase parseDisplayNameTabRejected:
  assertErrFields parseDisplayName("tab\there"),
    "DisplayName", "contains control characters", "tab\there"

# --- parseApiUrl ---

testCase parseApiUrlValid:
  let v = parseApiUrl("https://mail.example.com/jmap").get()
  doAssert $v == "https://mail.example.com/jmap"

testCase parseApiUrlEmpty:
  assertErrFields parseApiUrl(""), "ApiUrl", "must not be empty", ""

testCase parseApiUrlNewline:
  assertErrFields parseApiUrl("https://x/\r\njmap"),
    "ApiUrl", "must not contain newline characters", "https://x/\r\njmap"

# --- Sealed ops ---

testCase displayNameEquality:
  let a = parseDisplayName("Alice").get()
  let b = parseDisplayName("Alice").get()
  doAssert a == b
