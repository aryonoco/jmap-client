# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde-dependent test helpers, separated from mfixtures.nim to avoid
## coupling Layer 1 tests to Layer 2 serde modules.

import std/json

import jmap_client/serde
import jmap_client/validation

proc intToJson*(c: int): JsonNode =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  %*{"value": c}

proc fromIntCondition*(
    n: JsonNode, path: JsonPath = emptyJsonPath()
): Result[int, SerdeViolation] =
  ## Deserialise a JSON object to int for Filter[int] tests.
  ?expectKind(n, JObject, path)
  let vNode = ?fieldJInt(n, "value", path)
  ok(vNode.getInt(0))
