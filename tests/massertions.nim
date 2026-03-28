# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Template-based assertion helpers for Result and Opt types. Templates ensure
## line numbers point to the calling test block on failure.

import jmap_client/validation

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
