# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde-dependent test helpers, separated from mfixtures.nim to avoid
## coupling Layer 1 tests to Layer 2 serde modules.

import std/json

import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_diagnostics
import jmap_client/internal/serialisation/serde_helpers
import jmap_client/internal/types/validation

proc intToJson*(c: int): JsonNode =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  ## Retained for the ``Filter[int].fromJson`` callback slot (the deserialiser
  ## still carries an explicit condition parser). Construction-side
  ## (``Filter[int].toJson``) picks up ``toJson*(c: int)`` below via ``mixin``.
  %*{"value": c}

proc toJson*(c: int): JsonNode =
  ## UFCS serialiser for ``int`` — the mixin-resolved path inside
  ## ``Filter[C].toJson`` uses this overload when ``C = int``. Same body as
  ## ``intToJson`` to keep the wire shape identical across both slots.
  %*{"value": c}

proc fromIntCondition*(
    n: JsonNode, path: JsonPath = emptyJsonPath()
): Result[int, SerdeViolation] =
  ## Deserialise a JSON object to int for Filter[int] tests.
  ?expectKind(n, JObject, path)
  let vNode = ?fieldJInt(n, "value", path)
  ok(vNode.getInt(0))
