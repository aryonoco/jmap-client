# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Template-based assertion helpers for Result, Opt, and JSON types. Templates
## ensure line numbers point to the calling test block on failure.

import std/strutils
import std/json
import std/tables

import jmap_client/validation
import jmap_client/errors
import jmap_client/capabilities
import jmap_client/session

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

template assertErrKind*(r: untyped, expectedKind: untyped) =
  ## Verifies that a Result is Err and its error has a .kind field matching expectedKind.
  doAssert r.isErr, "expected Err, got Ok"
  let k = r.error.kind
  doAssert k == expectedKind, "expected kind " & $expectedKind & ", got " & $k

template assertGt*(actual, expected: untyped) =
  ## Verifies actual > expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a > e, "expected " & $a & " > " & $e

template assertGe*(actual, expected: untyped) =
  ## Verifies actual >= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a >= e, "expected " & $a & " >= " & $e

template assertLt*(actual, expected: untyped) =
  ## Verifies actual < expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a < e, "expected " & $a & " < " & $e

template assertLe*(actual, expected: untyped) =
  ## Verifies actual <= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a <= e, "expected " & $a & " <= " & $e

template assertInRange*(val, lo, hi: untyped) =
  ## Verifies lo <= val <= hi with diagnostics.
  let v = val
  let l = lo
  let h = hi
  doAssert v >= l and v <= h, "expected " & $v & " in [" & $l & ", " & $h & "]"

template assertTrue*(expr: untyped, msg: string) =
  ## Annotated boolean assertion with context message.
  doAssert expr, msg

template assertFalse*(expr: untyped, msg: string) =
  ## Annotated boolean negation assertion with context message.
  doAssert not expr, msg

template assertNe*(actual, expected: untyped) =
  ## Value-displaying inequality assertion. Shows both sides on failure.
  let a = actual
  let e = expected
  doAssert a != e, "expected " & $a & " != " & $e

template assertTransportErr*(ce: untyped, expectedKind: TransportErrorKind) =
  ## Verifies a ClientError is a transport error with the given kind.
  doAssert ce.kind == cekTransport, "expected cekTransport, got " & $ce.kind
  doAssert ce.transport.kind == expectedKind,
    "expected " & $expectedKind & ", got " & $ce.transport.kind

template assertRequestErr*(ce: untyped, expectedType: RequestErrorType) =
  ## Verifies a ClientError is a request error with the given type.
  doAssert ce.kind == cekRequest, "expected cekRequest, got " & $ce.kind
  doAssert ce.request.errorType == expectedType,
    "expected " & $expectedType & ", got " & $ce.request.errorType

template assertMethodErrType*(me: untyped, expectedType: MethodErrorType) =
  ## Verifies a MethodError has the given type.
  doAssert me.errorType == expectedType,
    "expected " & $expectedType & ", got " & $me.errorType

template assertSetErrType*(se: untyped, expectedType: SetErrorType) =
  ## Verifies a SetError has the given type.
  doAssert se.errorType == expectedType,
    "expected " & $expectedType & ", got " & $se.errorType

# ---------------------------------------------------------------------------
# JSON assertion templates (Layer 2 serde tests)
# ---------------------------------------------------------------------------

template assertJsonFieldPresent*(obj: JsonNode, key: string) =
  ## Verifies a JSON object has a non-nil field.
  doAssert obj{key} != nil, "expected field '" & key & "' to be present"

template assertJsonFieldAbsent*(obj: JsonNode, key: string) =
  ## Verifies a JSON object does not have a field (nil).
  doAssert obj{key}.isNil, "expected field '" & key & "' to be absent"

template assertJsonKind*(
    node: JsonNode, expectedKind: JsonNodeKind, context: string = ""
) =
  ## Verifies JSON node has the expected kind.
  let desc =
    if context.len > 0:
      " for " & context
    else:
      ""
  doAssert node.kind == expectedKind,
    "expected JSON " & $expectedKind & desc & ", got " & $node.kind

template assertJsonFieldKind*(obj: JsonNode, key: string, expectedKind: JsonNodeKind) =
  ## Verifies a JSON object field is present and has the expected kind.
  let field = obj{key}
  doAssert field != nil, "expected field '" & key & "' to be present"
  doAssert field.kind == expectedKind,
    "field '" & key & "': expected " & $expectedKind & ", got " & $field.kind

template assertJsonFieldEq*(obj: JsonNode, key: string, expected: untyped) =
  ## Verifies a JSON object field is present and its value equals expected.
  let field = obj{key}
  doAssert field != nil, "expected field '" & key & "' to be present"
  let actual = field
  let exp = expected
  doAssert actual == exp, "field '" & key & "': expected " & $exp & ", got " & $actual

template assertJsonFieldCount*(obj: JsonNode, expected: int) =
  ## Verifies a JSON object has the expected number of fields.
  doAssert obj.kind == JObject, "expected JSON JObject, got " & $obj.kind
  let actual = obj.getFields().len
  let exp = expected
  doAssert actual == exp, "expected " & $exp & " fields, got " & $actual

template assertJsonArrayLen*(arr: JsonNode, expected: int) =
  ## Verifies a JSON node is an array with exactly the expected number of elements.
  doAssert arr.kind == JArray, "expected JSON JArray, got " & $arr.kind
  let actual = arr.getElems(@[]).len
  let exp = expected
  doAssert actual == exp, "expected array len " & $exp & ", got " & $actual

template assertJsonFieldIsNull*(obj: JsonNode, key: string) =
  ## Verifies a JSON object field is present and is JNull.
  let field = obj{key}
  doAssert field != nil, "expected field '" & key & "' to be present"
  doAssert field.kind == JNull,
    "field '" & key & "': expected JNull, got " & $field.kind

template assertRoundTrip*[T](fromJsonProc: untyped, value: T) =
  ## Verifies toJson -> fromJson round-trip identity for a type.
  let j = value.toJson()
  let rt = fromJsonProc(j)
  doAssert rt.isOk, "round-trip failed: fromJson returned Err"
  doAssert rt.get() == value, "round-trip identity violated"

# ---------------------------------------------------------------------------
# Domain-specific assertion templates
# ---------------------------------------------------------------------------

template assertOkWithDiag*(r: untyped) =
  ## Verifies Result is Ok, printing the error message on failure.
  if r.isErr:
    doAssert false, "expected Ok, got Err: " & r.error.message

template assertTableContains*[K, V](t: Table[K, V], key: K) =
  ## Verifies a Table contains the given key.
  doAssert t.hasKey(key), "expected table to contain key"

template assertSeqContains*[T](s: seq[T], item: T) =
  ## Verifies a seq contains the given item.
  doAssert item in s, "expected seq to contain item"

template assertCapOkEq*(r: untyped, expected: ServerCapability) =
  ## Verifies Result is Ok and its ServerCapability value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert capEq(v, expected), "ServerCapability values differ"

template assertSessionOkEq*(r: untyped, expected: Session) =
  ## Verifies Result is Ok and its Session value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert sessionEq(v, expected), "Session values differ"

template assertSetOkEq*(r: untyped, expected: SetError) =
  ## Verifies Result is Ok and its SetError value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert setErrorEq(v, expected), "SetError values differ"

# ---------------------------------------------------------------------------
# Table-driven deserialisation error helpers
# ---------------------------------------------------------------------------

template assertDeserMissingField*(
    baseJson: JsonNode, field: string, fromJsonProc: untyped
) =
  ## Verifies that removing a field from JSON causes deserialisation to fail.
  let j = baseJson.copy()
  j.delete(field)
  let r = fromJsonProc(j)
  doAssert r.isErr, "expected Err when '" & field & "' missing, got Ok"

template assertDeserWrongKind*(
    baseJson: JsonNode, field: string, wrongValue: JsonNode, fromJsonProc: untyped
) =
  ## Verifies that setting a field to wrong JSON kind causes deserialisation to fail.
  let j = baseJson.copy()
  j[field] = wrongValue
  let r = fromJsonProc(j)
  doAssert r.isErr, "expected Err when '" & field & "' has wrong kind, got Ok"
