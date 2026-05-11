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

# ============= A. fromJson (lenient) =============

block fromJsonEmpty:
  ## Empty object parses to NoCreate() successfully.
  let node = %*{}
  let res = NoCreate.fromJson(node)
  assertOk res

block fromJsonArbitraryObject:
  ## Any wire payload parses successfully — NoCreate ignores the body
  ## per D6 (tolerate-gracefully for singleton-only entities).
  let node = %*{"unexpectedField": "value", "anotherField": 42}
  let res = NoCreate.fromJson(node)
  assertOk res

block fromJsonNull:
  ## Even a null node parses successfully.
  let node = newJNull()
  let res = NoCreate.fromJson(node)
  assertOk res

# ============= B. toJson =============

block toJsonProducesEmptyObject:
  ## NoCreate.toJson emits an empty JSON object — symmetric round-trip
  ## anchor (D3.7).
  let n = NoCreate()
  let emitted = n.toJson()
  doAssert emitted.kind == JObject
  doAssert emitted.len == 0

# ============= C. Round-trip =============

block roundTripPreservesShape:
  ## fromJson(toJson(NoCreate())) → ok(NoCreate()).
  let original = NoCreate()
  let res = NoCreate.fromJson(original.toJson())
  assertOk res
