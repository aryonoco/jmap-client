# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Whitebox tests for now-private helpers in
## ``internal/protocol/methods.nim``. Brought into scope via Nim's
## ``include`` directive — the module's ``*``-stripped helpers
## (``optState``, ``optUnsignedInt``) are reachable through textual
## source inclusion. H10 lint exempts ``tests/`` from the internal-
## boundary rule; ``include`` is the textual counterpart for symbols
## stripped of ``*`` per A1b.

include jmap_client/internal/protocol/methods
{.pop.}

import ../mfixtures
import ../mtestblock

testCase optStateLeniency:
  ## Lenient optState: absent, null, wrong kind, empty string all yield none.
  let absent = %*{"other": "val"}
  doAssert optState(absent, "oldState").isNone
  let jnull = %*{"oldState": nil}
  doAssert optState(jnull, "oldState").isNone
  let wrongKind = %*{"oldState": 42}
  doAssert optState(wrongKind, "oldState").isNone
  let emptyStr = %*{"oldState": ""}
  doAssert optState(emptyStr, "oldState").isNone
  let valid = %*{"oldState": "state1"}
  let result = optState(valid, "oldState")
  doAssert result.isSome
  doAssert result.get() == makeState("state1")

testCase optUnsignedIntLeniency:
  ## Lenient optUnsignedInt: absent, null, wrong kind, negative all yield none.
  let absent = %*{"other": "val"}
  doAssert optUnsignedInt(absent, "total").isNone
  let jnull = %*{"total": nil}
  doAssert optUnsignedInt(jnull, "total").isNone
  let wrongKind = %*{"total": "42"}
  doAssert optUnsignedInt(wrongKind, "total").isNone
  let negative = %*{"total": -1}
  doAssert optUnsignedInt(negative, "total").isNone
  let valid = %*{"total": 100}
  let result = optUnsignedInt(valid, "total")
  doAssert result.isSome
