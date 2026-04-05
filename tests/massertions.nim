# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Template-based assertion helpers for Result, Option, and JSON types.
## Templates ensure line numbers point to the calling test block on failure.

import std/strutils
import std/json

import jmap_client/validation
import jmap_client/errors
import jmap_client/capabilities

import ./mfixtures

{.push ruleOff: "hasDoc".}

template assertOk*(expr: untyped) =
  ## Verifies a Result is ok, or that an expression evaluates without panic.
  when compiles(expr.isOk):
    let res = expr
    doAssert res.isOk, "expected Ok result, got Err"
  else:
    discard expr

template assertErr*(expr: untyped) =
  ## Verifies a Result is err.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"

template assertErrFields*(expr: untyped, tn, expectedMsg, val: string) =
  ## Verifies error fields on a Result.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let e = res.error
  doAssert e.typeName == tn, "typeName: expected " & tn & ", got " & e.typeName
  doAssert e.message == expectedMsg,
    "message: expected " & expectedMsg & ", got " & e.message
  doAssert e.value == val, "value: expected " & val & ", got " & e.value

template assertErrType*(expr: untyped, tn: string) =
  ## Verifies the typeName field of a Result error.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  doAssert res.error.typeName == tn

template assertErrMsg*(expr: untyped, expectedMsg: string) =
  ## Verifies the message field of a Result error.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  doAssert res.error.message == expectedMsg

template assertSome*(o: untyped) =
  doAssert o.isSome, "expected Some, got None"

template assertNone*(o: untyped) =
  doAssert o.isNone, "expected None, got Some"

template assertEq*(actual, expected: untyped) =
  ## Value-displaying equality assertion. Shows both sides on failure.
  let a = actual
  let e = expected
  doAssert a == e, "expected " & $e & ", got " & $a

template assertErrContains*(expr: untyped, substring: string) =
  ## Verifies the message field of a Result error contains a substring.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let m = res.error.message
  doAssert strutils.contains(m, substring),
    "expected message containing '" & substring & "', got '" & m & "'"

template assertOkEq*(expr: untyped, expected: untyped) =
  ## Evaluates expr (Result) and verifies its Ok value equals expected.
  let res = expr
  doAssert res.isOk, "expected Ok result, got Err"
  let v = res.get()
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
  ## Verifies Option is Some and its value equals expected.
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

template assertCapOkEq*(expr: untyped, expected: ServerCapability) =
  ## Evaluates expr and verifies its ServerCapability value equals expected.
  let v = expr
  doAssert capEq(v, expected), "ServerCapability values differ"

template assertSetOkEq*(expr: untyped, expected: SetError) =
  ## Evaluates expr and verifies its SetError value equals expected.
  let v = expr
  doAssert setErrorEq(v, expected), "SetError values differ"
