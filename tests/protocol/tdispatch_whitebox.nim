# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Whitebox test for the decode-failure path in
## ``internal/protocol/dispatch.nim``. A typed-decode failure now rides
## ``jeProtocol`` / ``pfDecode`` carrying the structured ``SerdeViolation``
## verbatim (the retired ``serdeToMethodError`` used to flatten it into a
## synthetic ``serverFail`` MethodError with stringly-typed ``extras``).
## Brought into scope via Nim's ``include`` directive.

include jmap_client/internal/protocol/dispatch
{.pop.}

import std/strutils

import jmap_client/internal/types/validation

import ../mfixtures
import ../massertions
import ../mtestblock

testCase protocolDecodePreservesViolation:
  ## A decode failure preserves the inner ``ValidationError``'s typeName /
  ## value losslessly inside the retained ``SerdeViolation`` — nothing is
  ## flattened to a string. The rendered diagnostic still surfaces the inner
  ## reason via the canonical translator.
  let ve = validationError("AccountId", "length must be 1-255 octets", "")
  let sv = SerdeViolation(kind: svkFieldParserFailed, path: emptyJsonPath(), inner: ve)
  let callId = makeMcid("c0")
  let pf = protocolDecode(callId, sv)
  doAssert pf.kind == pfDecode
  doAssert pf.callId == Opt.some(callId)
  doAssert pf.violation.kind == svkFieldParserFailed
  doAssert pf.violation.inner.typeName == "AccountId"
  doAssert pf.violation.inner.value == ""
  doAssert "length must be 1-255 octets" in jmapProtocol(pf).message
