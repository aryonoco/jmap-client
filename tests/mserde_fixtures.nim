# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde-dependent test helpers, separated from mfixtures.nim to avoid
## coupling Layer 1 tests to Layer 2 serde modules. This file will be
## updated in Phase 2 (serde migration).

import std/json

import results

import jmap_client/validation
import jmap_client/serde

proc intToJson*(c: int): JsonNode {.noSideEffect, raises: [].} =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  {.cast(noSideEffect).}:
    %*{"value": c}

proc fromIntCondition*(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise a JSON object to int for Filter[int] tests.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))
