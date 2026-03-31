# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## Serialisation for JMAP framework types: FilterOperator, Comparator,
## Filter[C], PatchObject, and AddedItem (RFC 8620 sections 5.3, 5.5, 5.6).

import std/json
import std/tables

import results

import ./serde
import ./types

# =============================================================================
# FilterOperator
# =============================================================================

func toJson*(op: FilterOperator): JsonNode =
  ## Serialise FilterOperator to its RFC string.
  {.cast(noSideEffect).}:
    %($op)

func fromJson*(
    T: typedesc[FilterOperator], node: JsonNode
): Result[FilterOperator, ValidationError] =
  ## Deserialise a JSON string to FilterOperator. Not total — unknown
  ## operators return err because the RFC defines exactly three.
  checkJsonKind(node, JString, $T)
  case node.getStr("")
  of "AND":
    ok(foAnd)
  of "OR":
    ok(foOr)
  of "NOT":
    ok(foNot)
  else:
    err(parseError($T, "unknown operator: " & node.getStr("")))

# =============================================================================
# Comparator
# =============================================================================

func toJson*(c: Comparator): JsonNode =
  ## Serialise Comparator to JSON (RFC 8620 section 5.5).
  {.cast(noSideEffect).}:
    result = %*{"property": string(c.property), "isAscending": c.isAscending}
    if c.collation.isSome:
      result["collation"] = %c.collation.get()

func fromJson*(
    T: typedesc[Comparator], node: JsonNode
): Result[Comparator, ValidationError] =
  ## Deserialise JSON to Comparator (RFC 8620 section 5.5).
  checkJsonKind(node, JObject, $T)
  let propNode = node{"property"}
  checkJsonKind(propNode, JString, $T, "missing or invalid property")
  let property = ?parsePropertyName(propNode.getStr(""))
  let ascNode = node{"isAscending"}
  if not ascNode.isNil:
    if ascNode.kind != JBool:
      return err(parseError($T, "isAscending must be boolean"))
  let isAscending = ascNode.getBool(true)
    # nil-safe; returns true (RFC default) when absent
  let collNode = node{"collation"}
  var collation = Opt.none(string)
  if not collNode.isNil:
    if collNode.kind == JString:
      collation = Opt.some(collNode.getStr(""))
  ok(?parseComparator(property, isAscending, collation))

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
    filterConditionToJson(f.condition)
  of fkOperator:
    {.cast(noSideEffect).}:
      var conditions = newJArray()
      for child in f.conditions:
        conditions.add(child.toJson(filterConditionToJson))
      %*{"operator": $f.operator, "conditions": conditions}

const MaxFilterDepth* = 128
  ## Maximum nesting depth for Filter[C].fromJson deserialisation.
  ## Defence-in-depth guard against stack overflow (StackOverflowDefect is
  ## uncatchable under {.push raises: [].}). 128 is generous for any realistic
  ## JMAP query while preventing pathological nesting.
  ## Note: std/json's parseJson has its own DepthLimit of 1000, but this
  ## library's fromJson accepts pre-parsed JsonNode, so that limit does not
  ## apply at this layer.

func fromJsonImpl[C](
    node: JsonNode,
    fromCondition:
      proc(n: JsonNode): Result[C, ValidationError] {.noSideEffect, raises: [].},
    depth: int,
): Result[Filter[C], ValidationError] =
  ## Internal recursive helper with depth tracking.
  const typeName = "Filter"
  checkJsonKind(node, JObject, typeName)
  if depth <= 0:
    return err(parseError(typeName, "maximum nesting depth exceeded"))
  let opNode = node{"operator"}
  if opNode.isNil:
    let cond = ?fromCondition(node)
    ok(filterCondition(cond))
  else:
    let op = ?FilterOperator.fromJson(opNode)
    let conditionsNode = node{"conditions"}
    checkJsonKind(
      conditionsNode, JArray, typeName, "missing or invalid conditions array"
    )
    var children: seq[Filter[C]]
    for childNode in conditionsNode.getElems(@[]):
      let child = ?fromJsonImpl[C](childNode, fromCondition, depth - 1)
      children.add(child)
    ok(filterOperator(op, children))

func fromJson*[C](
    T: typedesc[Filter[C]],
    node: JsonNode,
    fromCondition:
      proc(n: JsonNode): Result[C, ValidationError] {.noSideEffect, raises: [].},
): Result[Filter[C], ValidationError] =
  ## Deserialise JSON to Filter[C]. Caller provides condition deserialiser.
  ## Dispatches on presence of "operator" key. Nesting depth is capped at
  ## MaxFilterDepth to prevent stack overflow on pathological input.
  discard $T # consumed for nimalyzer params rule
  fromJsonImpl[C](node, fromCondition, MaxFilterDepth)

# =============================================================================
# PatchObject
# =============================================================================

func toJson*(patch: PatchObject): JsonNode =
  ## Serialise PatchObject to JSON. Keys are JSON Pointer paths,
  ## null values represent property deletion.
  let tbl = Table[string, JsonNode](patch)
  {.cast(noSideEffect).}:
    result = newJObject()
    for path, value in tbl:
      result[path] = value

func fromJson*(
    T: typedesc[PatchObject], node: JsonNode
): Result[PatchObject, ValidationError] =
  ## Deserialise JSON to PatchObject using smart constructors.
  ## null values -> deleteProp, other values -> setProp.
  checkJsonKind(node, JObject, $T)
  var patch = emptyPatch()
  for path, value in node.pairs:
    if value.isNil or value.kind == JNull:
      patch = ?deleteProp(patch, path)
    else:
      patch = ?setProp(patch, path, value)
  ok(patch)

# =============================================================================
# AddedItem
# =============================================================================

func toJson*(item: AddedItem): JsonNode =
  ## Serialise AddedItem to JSON (RFC 8620 section 5.6).
  {.cast(noSideEffect).}:
    result = %*{"id": string(item.id), "index": int64(item.index)}

func fromJson*(
    T: typedesc[AddedItem], node: JsonNode
): Result[AddedItem, ValidationError] =
  ## Deserialise JSON to AddedItem.
  checkJsonKind(node, JObject, $T)
  let id = ?Id.fromJson(node{"id"})
  let index = ?UnsignedInt.fromJson(node{"index"})
  ok(AddedItem(id: id, index: index))
