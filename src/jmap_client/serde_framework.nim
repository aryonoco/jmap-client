# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP framework types: FilterOperator, Comparator,
## Filter[C], and AddedItem (RFC 8620 sections 5.5, 5.6).

{.push raises: [], noSideEffect.}

import std/json

import ./serde
import ./types

# =============================================================================
# FilterOperator
# =============================================================================

func toJson*(op: FilterOperator): JsonNode =
  ## Serialise FilterOperator to its RFC string.
  return %($op)

func fromJson*(
    T: typedesc[FilterOperator], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[FilterOperator, SerdeViolation] =
  ## Deserialise a JSON string to FilterOperator. Not total — unknown
  ## operators return ``svkEnumNotRecognised`` because the RFC defines
  ## exactly three.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  let raw = node.getStr("")
  case raw
  of "AND":
    return ok(foAnd)
  of "OR":
    return ok(foOr)
  of "NOT":
    return ok(foNot)
  else:
    return err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path,
        enumTypeLabel: "FilterOperator",
        rawValue: raw,
      )
    )

# =============================================================================
# Comparator
# =============================================================================

func toJson*(c: Comparator): JsonNode =
  ## Serialise Comparator to JSON (RFC 8620 section 5.5).
  var node = %*{"property": string(c.property), "isAscending": c.isAscending}
  for col in c.collation:
    node["collation"] = %col
  return node

func fromJson*(
    T: typedesc[Comparator], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Comparator, SerdeViolation] =
  ## Deserialise JSON to Comparator (RFC 8620 section 5.5).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let propNode = ?fieldJString(node, "property", path)
  let property = ?wrapInner(parsePropertyName(propNode.getStr("")), path / "property")
  let ascNode = node{"isAscending"}
  if not ascNode.isNil and ascNode.kind != JBool:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / "isAscending",
        expectedKind: JBool,
        actualKind: ascNode.kind,
      )
    )
  let isAscending = ascNode.getBool(true)
    # nil-safe; returns true (RFC default) when absent
  let collNode = node{"collation"}
  var collation = Opt.none(string)
  if not collNode.isNil and collNode.kind == JString:
    collation = Opt.some(collNode.getStr(""))
  return ok(parseComparator(property, isAscending, collation))

# =============================================================================
# Filter[C]
# =============================================================================

func toJson*[C](
    f: Filter[C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): JsonNode =
  ## Serialise Filter[C] to JSON. Caller provides condition serialiser.
  case f.kind
  of fkCondition:
    return filterConditionToJson(f.condition)
  of fkOperator:
    var conditions = newJArray()
    for child in f.conditions:
      conditions.add(child.toJson(filterConditionToJson))
    return %*{"operator": $f.operator, "conditions": conditions}

const MaxFilterDepth* = 128
  ## Maximum nesting depth for Filter[C].fromJson deserialisation.
  ## Defence-in-depth guard against stack overflow (StackOverflowDefect is
  ## uncatchable). 128 is generous for any realistic JMAP query while
  ## preventing pathological nesting.
  ## Note: std/json's parseJson has its own DepthLimit of 1000, but this
  ## library's fromJson accepts pre-parsed JsonNode, so that limit does not
  ## apply at this layer.

func fromJsonImpl[C](
    node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    depth: int,
    path: JsonPath,
): Result[Filter[C], SerdeViolation] =
  ## Internal recursive helper with depth tracking.
  ?expectKind(node, JObject, path)
  if depth <= 0:
    return
      err(SerdeViolation(kind: svkDepthExceeded, path: path, maxDepth: MaxFilterDepth))
  let opNode = node{"operator"}
  if opNode.isNil:
    let cond = ?fromCondition(node, path)
    return ok(filterCondition(cond))
  let op = ?FilterOperator.fromJson(opNode, path / "operator")
  let conditionsNode = ?fieldJArray(node, "conditions", path)
  var children: seq[Filter[C]] = @[]
  for i, childNode in conditionsNode.getElems(@[]):
    let child =
      ?fromJsonImpl[C](childNode, fromCondition, depth - 1, path / "conditions" / i)
    children.add(child)
  return ok(filterOperator(op, children))

func fromJson*[C](
    T: typedesc[Filter[C]],
    node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    path: JsonPath = emptyJsonPath(),
): Result[Filter[C], SerdeViolation] =
  ## Deserialise JSON to Filter[C]. Caller provides condition deserialiser.
  ## Dispatches on presence of "operator" key. Nesting depth is capped at
  ## MaxFilterDepth to prevent stack overflow on pathological input.
  discard $T # consumed for nimalyzer params rule
  return fromJsonImpl[C](node, fromCondition, MaxFilterDepth, path)

# =============================================================================
# AddedItem
# =============================================================================

func toJson*(item: AddedItem): JsonNode =
  ## Serialise AddedItem to JSON (RFC 8620 section 5.6).
  return %*{"id": string(item.id), "index": int64(item.index)}

func fromJson*(
    T: typedesc[AddedItem], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[AddedItem, SerdeViolation] =
  ## Deserialise JSON to AddedItem.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let indexNode = ?fieldJInt(node, "index", path)
  let index = ?UnsignedInt.fromJson(indexNode, path / "index")
  return ok(initAddedItem(id, index))
