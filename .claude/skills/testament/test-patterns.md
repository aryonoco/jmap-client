# Test Patterns for jmap-client

This project uses exceptions for error handling:

- **Construction errors:** Smart constructors raise `ValidationError` on invalid input
- **Transport/request errors:** `ClientError` (wrapping `TransportError`/`RequestError`) — tested in Layer 4/5
- **Response-level errors:** `MethodError` and `SetError` are data in successful responses, not exceptions

Current patterns cover construction errors. Transport/request patterns will be added when those layers are built.

## Module Boilerplate

Every test file follows this structure:

```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

import jmap_client/primitives  # module under test
```

## Testing Smart Constructors

Smart constructors return the validated type directly on success and raise
`ValidationError` on failure. Test both paths:

```nim
# Success case
block:
  let id = parseId("valid-id")
  doAssert $id == "valid-id"

# Failure case — empty string rejected
block:
  doAssertRaises(ValidationError):
    discard parseId("")
```

To inspect the exception fields on failure:

```nim
block:
  var caught = false
  try:
    discard parseId("")
  except ValidationError as e:
    caught = true
    doAssert e.typeName == "Id"
    doAssert "empty" in e.msg or "must not" in e.msg
  doAssert caught
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
  ("  ", true),  # whitespace-only is valid (only empty is rejected)
]

for (input, expectOk) in testCases:
  if expectOk:
    let id = parseId(input)
    doAssert $id == input
  else:
    doAssertRaises(ValidationError):
      discard parseId(input)
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
  let rt = CoreCapabilities.fromJson(j)
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
