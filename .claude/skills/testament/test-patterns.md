# Test Patterns for jmap-client

This project uses Railway-Oriented Programming via nim-results for error handling:

- **Construction errors:** Smart constructors return `Result[T, ValidationError]`
- **Transport/request errors:** `Result[T, ClientError]` (aliased as `JmapResult[T]`)
- **Response-level errors:** `MethodError` and `SetError` are data in successful responses

All error types are plain objects carried on the Result error rail, not exceptions.

## Module Boilerplate

Every test file follows this structure:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

import jmap_client/primitives  # module under test
```

## Testing Smart Constructors

Smart constructors return `Result[T, ValidationError]`. Test both rails:

```nim
# Success case — isOk, extract with .get()
block:
  let r = parseId("valid-id")
  doAssert r.isOk
  doAssert $r.get() == "valid-id"

# Failure case — isErr, inspect the error
block:
  let r = parseId("")
  doAssert r.isErr
  doAssert r.error.typeName == "Id"
  doAssert "1-255" in r.error.message or "empty" in r.error.message
```

Use `block:` to isolate each test case and prevent variable name collisions.

## Testing Option[T]

```nim
import std/options

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
]

for (input, expectOk) in testCases:
  let r = parseId(input)
  doAssert r.isOk == expectOk
  if expectOk:
    doAssert $r.get() == input
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
  let r = CoreCapabilities.fromJson(j)
  doAssert r.isOk
  let rt = r.get()
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
| `just test-file tests/unit/tprimitives.nim` | Run a single test file |
| `just test-report` | Generate HTML test report |
