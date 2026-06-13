# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Whitebox test for now-private ``serdeToMethodError`` in
## ``internal/protocol/dispatch.nim``. Brought into scope via Nim's
## ``include`` directive.

include jmap_client/internal/protocol/dispatch
{.pop.}

import jmap_client/internal/types/validation

import ../mfixtures
import ../massertions
import ../mtestblock

testCase serdeToMethodErrorPreservation:
  ## Verify kind is metServerFail, description carries the canonical
  ## ``ValidationError.reason`` projection ("typeName: reason"), and
  ## extras is a JObject containing typeName and value keys. An
  ## ``svkFieldParserFailed`` wrapping an inner ValidationError preserves
  ## the inner typeName/value losslessly through the translator.
  let ve = validationError("AccountId", "length must be 1-255 octets", "")
  let sv = SerdeViolation(kind: svkFieldParserFailed, path: emptyJsonPath(), inner: ve)
  let me = serdeToMethodError("Wrapper")(sv)
  doAssert me.kind == metServerFail
  doAssert me.rawType == "serverFail"
  doAssert me.description.isSome
  doAssert me.description.get() == "AccountId: length must be 1-255 octets"
  doAssert me.extras.isSome
  let extras = me.extras.get()
  doAssert extras.kind == JObject
  doAssert extras{"typeName"}.getStr("") == "AccountId"
  doAssert extras{"value"}.getStr("?") == ""
