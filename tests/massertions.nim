# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Template-based assertion helpers for Result, Opt, and JSON types. Templates
## ensure line numbers point to the calling test block on failure.

import std/strutils
import std/json

import jmap_client/validation
import jmap_client/errors
import jmap_client/capabilities

import ./mfixtures

{.push ruleOff: "hasDoc".}

template assertOk*(r: untyped) =
  doAssert r.isOk, "expected Ok, got Err"

template assertErr*(r: untyped) =
  doAssert r.isErr, "expected Err, got Ok"

template assertErrFields*(r: untyped, tn, msg, val: string) =
  ## Verifies all three ValidationError fields exactly.
  doAssert r.isErr, "expected Err, got Ok"
  let e = r.error
  doAssert e.typeName == tn, "typeName: expected " & tn & ", got " & e.typeName
  doAssert e.message == msg, "message: expected " & msg & ", got " & e.message
  doAssert e.value == val, "value: expected " & val & ", got " & e.value

template assertErrType*(r: untyped, tn: string) =
  ## Verifies the typeName field of a ValidationError.
  doAssert r.isErr, "expected Err, got Ok"
  doAssert r.error.typeName == tn

template assertErrMsg*(r: untyped, msg: string) =
  ## Verifies the message field of a ValidationError exactly.
  doAssert r.isErr, "expected Err, got Ok"
  doAssert r.error.message == msg

template assertSome*(o: untyped) =
  doAssert o.isSome, "expected Some, got None"

template assertNone*(o: untyped) =
  doAssert o.isNone, "expected None, got Some"

template assertEq*(actual, expected: untyped) =
  ## Value-displaying equality assertion. Shows both sides on failure.
  let a = actual
  let e = expected
  doAssert a == e, "expected " & $e & ", got " & $a

template assertErrContains*(r: untyped, substring: string) =
  ## Verifies the message field contains a substring (useful for long messages).
  doAssert r.isErr, "expected Err, got Ok"
  let msg = r.error.message
  doAssert strutils.contains(msg, substring),
    "expected message containing '" & substring & "', got '" & msg & "'"

template assertOkEq*(r: untyped, expected: untyped) =
  ## Verifies Result is Ok and its value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  let e = expected
  doAssert v == e, "expected " & $e & ", got " & $v

template assertNotCompiles*(expr: untyped) =
  ## Verifies that the given expression does not compile.
  doAssert not compiles(expr), "expected expression to not compile"

template assertLen*(collection: untyped, expected: int) =
  ## Verifies collection length equals expected.
  let actual = collection.len
  let exp = expected
  doAssert actual == exp, "expected len " & $exp & ", got " & $actual

template assertSomeEq*(o: untyped, expected: untyped) =
  ## Verifies Opt is Some and its value equals expected.
  doAssert o.isSome, "expected Some, got None"
  let v = o.get()
  let e = expected
  doAssert v == e, "expected " & $e & ", got " & $v

template assertGe*(actual, expected: untyped) =
  ## Verifies actual >= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a >= e, "expected " & $a & " >= " & $e

template assertLe*(actual, expected: untyped) =
  ## Verifies actual <= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a <= e, "expected " & $a & " <= " & $e

template assertFalse*(expr: untyped, msg: string) =
  ## Annotated boolean negation assertion with context message.
  doAssert not expr, msg

template assertJsonFieldEq*(obj: JsonNode, key: string, expected: untyped) =
  ## Verifies a JSON object field is present and its value equals expected.
  let field = obj{key}
  doAssert field != nil, "expected field '" & key & "' to be present"
  let actual = field
  let exp = expected
  doAssert actual == exp, "field '" & key & "': expected " & $exp & ", got " & $actual

template assertCapOkEq*(r: untyped, expected: ServerCapability) =
  ## Verifies Result is Ok and its ServerCapability value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert capEq(v, expected), "ServerCapability values differ"

template assertSetOkEq*(r: untyped, expected: SetError) =
  ## Verifies Result is Ok and its SetError value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert setErrorEq(v, expected), "SetError values differ"
