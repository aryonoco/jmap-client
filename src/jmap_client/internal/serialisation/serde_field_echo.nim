# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde for ``FieldEcho[T]`` / ``NoCreate`` plus the helper templates
## consumed by every ``Partial*.fromJson`` / ``.toJson``.
##
## The type definitions live in ``internal/types/field_echo.nim``; this
## L2 module hosts everything that depends on ``JsonNode`` /
## ``SerdeViolation`` / ``JsonPath`` (which would form an import cycle
## via the L1 hub if folded into ``field_echo.nim``).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../types
import ./serde

# =============================================================================
# NoCreate serde — D6 lenient parse, symmetric emit
# =============================================================================

func fromJson*(
    T: typedesc[NoCreate], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[NoCreate, SerdeViolation] =
  ## A ``created[cid]`` entry should not occur on a singleton-only
  ## ``/set`` (RFC 8621 §7 — VacationResponse). Tolerate gracefully
  ## (D6): the entry carries no useful payload, and the existing
  ## ``SerdeViolation`` case object has no fitting variant. Consumers
  ## detect protocol violations by checking
  ## ``setResp.createResults.len == 0`` after dispatch.
  discard $T
  discard node
  discard path
  return ok(NoCreate())

func toJson*(n: NoCreate): JsonNode =
  ## D3.7 unidirectional serde symmetry. The library never produces a
  ## value through this path; the function exists so round-trip tests
  ## over ``SetResponse[NoCreate, _].toJson`` compile.
  discard n
  return newJObject()

# =============================================================================
# Helper templates — every Partial*.fromJson uses these uniformly
# =============================================================================

template parsePartialOptField*[T](
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[T], SerdeViolation] =
  ## Parses a wire-non-nullable field as ``Opt[T]``. Absent or null →
  ## ``Opt.none(T)``; present with value → ``Opt.some(parsed)`` via
  ## ``mixin T.fromJson``. Two-state: null and absent collapse. ``T``
  ## binds at the explicit ``[T]`` instantiation.
  mixin fromJson
  block:
    let valNode {.inject.} = node{key}
    if valNode.isNil or valNode.kind == JNull:
      Result[Opt[T], SerdeViolation].ok(Opt.none(T))
    else:
      let parsed = ?T.fromJson(valNode, path / key)
      Result[Opt[T], SerdeViolation].ok(Opt.some(parsed))

template parsePartialFieldEcho*[T](
    node: JsonNode, key: string, path: JsonPath
): Result[FieldEcho[T], SerdeViolation] =
  ## Parses a wire-nullable field as ``FieldEcho[T]``. Absent →
  ## ``fieldAbsent``; present null → ``fieldNull``; present value →
  ## ``fieldValue(parsed)`` via ``mixin T.fromJson``. Three-state —
  ## preserves all RFC 8620 §5.3 distinctions.
  mixin fromJson
  block:
    let valNode {.inject.} = node{key}
    if valNode.isNil:
      Result[FieldEcho[T], SerdeViolation].ok(fieldAbsent(T))
    elif valNode.kind == JNull:
      Result[FieldEcho[T], SerdeViolation].ok(fieldNull(T))
    else:
      let parsed = ?T.fromJson(valNode, path / key)
      Result[FieldEcho[T], SerdeViolation].ok(fieldValue(parsed))

template emitPartialFieldEcho*[T](node: JsonNode, key: string, fe: FieldEcho[T]) =
  ## Emit a ``FieldEcho`` — omit when ``fekAbsent``; emit null when
  ## ``fekNull``; emit the value via ``mixin T.toJson`` when ``fekValue``.
  mixin toJson
  case fe.kind
  of fekAbsent:
    discard
  of fekNull:
    node[key] = newJNull()
  of fekValue:
    node[key] = fe.value.toJson()
