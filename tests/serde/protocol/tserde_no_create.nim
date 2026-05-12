# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for the ``NoCreate`` marker (A4 D6). Covers:
##   * lenient ``fromJson`` always succeeds (D6 — singleton ``/set``
##     payloads should not carry create entries, but tolerate them);
##   * ``toJson`` emits an empty object (D3.7 unidirectional serde
##     symmetry);
##   * round-trip through ``SetResponse[NoCreate, _].fromJson``/``toJson``.

import std/json

import jmap_client/internal/types/field_echo
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_field_echo

import ../../massertions
import ../../mtestblock

# ============= A. fromJson (lenient) =============

testCase fromJsonEmpty:
  ## Empty object parses to NoCreate() successfully.
  let node = %*{}
  let res = NoCreate.fromJson(node)
  assertOk res

testCase fromJsonArbitraryObject:
  ## Any wire payload parses successfully — NoCreate ignores the body
  ## per D6 (tolerate-gracefully for singleton-only entities).
  let node = %*{"unexpectedField": "value", "anotherField": 42}
  let res = NoCreate.fromJson(node)
  assertOk res

testCase fromJsonNull:
  ## Even a null node parses successfully.
  let node = newJNull()
  let res = NoCreate.fromJson(node)
  assertOk res

# ============= B. toJson =============

testCase toJsonProducesEmptyObject:
  ## NoCreate.toJson emits an empty JSON object — symmetric round-trip
  ## anchor (D3.7).
  let n = NoCreate()
  let emitted = n.toJson()
  doAssert emitted.kind == JObject
  doAssert emitted.len == 0

# ============= C. Round-trip =============

testCase roundTripPreservesShape:
  ## fromJson(toJson(NoCreate())) → ok(NoCreate()).
  let original = NoCreate()
  let res = NoCreate.fromJson(original.toJson())
  assertOk res
