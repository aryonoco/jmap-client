# Test Patterns for jmap-client

This project uses a three-track error railway (see `docs/architecture-options.md`):

- **Track 0 (construction):** `Result[T, ValidationError]` — smart constructor tests below
- **Track 1 (outer):** `JmapResult[T]` = `Result[T, ClientError]` — transport/request tests (future layers)
- **Track 2 (inner):** `Result[MethodResponse, MethodError]` — per-invocation tests (future layers)

Current patterns cover Track 0. Tracks 1 and 2 will be added when those layers are built.

## Module Boilerplate

Every test file in this project follows the same structure as source files:

```nim
# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import pkg/results
import jmap_client/primitives  # module under test
```

## Testing Smart Constructors

Smart constructors return `Result[T, ValidationError]`. Test both success
and failure paths:

```nim
# Success case
block:
  let r = parseId("valid-id")
  doAssert r.isOk
  doAssert $r.get() == "valid-id"

# Failure case — empty string rejected
block:
  let r = parseId("")
  doAssert r.isErr
  doAssert r.error().typeName == "Id"
  doAssert "empty" in r.error().message or "must not" in r.error().message
```

Use `block:` to isolate each test case and prevent variable name collisions.

## Testing Opt[T]

```nim
block:
  let found = findAccount(accounts, knownId)
  doAssert found.isSome
  doAssert found.get().name == "expected"

block:
  let missing = findAccount(accounts, unknownId)
  doAssert missing.isNone
```

## Testing Distinct Type Operations

Distinct types borrow specific operations. Verify each borrowed op works
and that non-borrowed ops are rejected:

```nim
block:
  let a = AccountId("abc")
  let b = AccountId("abc")
  let c = AccountId("xyz")

  # Borrowed: ==, $, hash
  doAssert a == b
  doAssert a != c
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)

  # Unwrap via explicit conversion
  doAssert string(a) == "abc"
```

To test that an operation is NOT available (e.g. `&` not borrowed), use a
reject test in a separate file:

```nim
discard """
  action: "reject"
  errormsg: "type mismatch"
"""
import jmap_client/primitives
let a = AccountId("abc")
let b = AccountId("def")
discard a & b  # must not compile — & not borrowed
```

## Table-Driven Tests

Use a `seq` or array of tuples for repetitive test cases:

```nim
const testCases = [
  ("valid-id", true),
  ("also-valid", true),
  ("", false),
  ("  ", true),  # whitespace-only is valid (only empty is rejected)
]

for (input, expectOk) in testCases:
  let r = parseId(input)
  doAssert r.isOk == expectOk, "Failed for input: '" & input & "'"
```

## Round-Trip Serialisation Tests

Test that toJson -> fromJson preserves values:

```nim
import std/json

block:
  let original = CoreCapabilities(
    maxSizeUpload: UnsignedInt(50_000_000),
    maxConcurrentUpload: UnsignedInt(4),
    maxSizeRequest: UnsignedInt(10_000_000),
    maxConcurrentRequests: UnsignedInt(4),
    maxCallsInRequest: UnsignedInt(16),
    maxObjectsInGet: UnsignedInt(500),
    maxObjectsInSet: UnsignedInt(500),
  )
  let j = original.toJson()
  let roundTripped = CoreCapabilities.fromJson(j)
  doAssert roundTripped.isOk
  let rt = roundTripped.get()
  doAssert rt.maxSizeUpload == original.maxSizeUpload
  doAssert rt.maxCallsInRequest == original.maxCallsInRequest
```

## Testing JSON Wire Format

Verify that serialisation produces the expected wire format:

```nim
import std/json

block:
  let inv = Invocation(
    name: "Mailbox/get",
    arguments: %*{"accountId": "abc123"},
    methodCallId: MethodCallId("call-0"),
  )
  let j = inv.toJson()

  # Invocations are 3-element arrays, NOT objects
  doAssert j.kind == JArray
  doAssert j.len == 3
  doAssert j[0].getStr() == "Mailbox/get"
  doAssert j[2].getStr() == "call-0"
```

## Running Tests

| Command | Description |
|---------|-------------|
| `just test` | Run all tests via testament |
| `just test-verbose` | Run all tests with verbose output |
| `just test-file tests/tprimitives.nim` | Run a single test file |
| `just test-report` | Generate HTML test report |
