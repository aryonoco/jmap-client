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

func parseComparatorCore(
    node: JsonNode, typeName: string
): Result[(PropertyName, bool, Opt[string]), ValidationError] =
  ## Parse Comparator fields from JSON. Separated to avoid the requiresInit
  ## interaction: Comparator contains PropertyName {.requiresInit.}, so
  ## err()/? on Result[Comparator, ValidationError] fails to compile.
  checkJsonKind(node, JObject, typeName)
  let propNode = node{"property"}
  checkJsonKind(propNode, JString, typeName, "missing or invalid property")
  let property = ?parsePropertyName(propNode.getStr(""))
  let ascNode = node{"isAscending"}
  var isAscending = true # RFC default when absent
  if not ascNode.isNil:
    if ascNode.kind != JBool:
      return err(parseError(typeName, "isAscending must be boolean"))
    isAscending = ascNode.getBool(true)
  let collNode = node{"collation"}
  var collation: Opt[string] = Opt.none(string)
  if not collNode.isNil:
    if collNode.kind == JString:
      collation = Opt.some(collNode.getStr(""))
  ok((property, isAscending, collation))

func fromJson*(
    T: typedesc[Comparator], node: JsonNode
): Result[Comparator, ValidationError] =
  ## Deserialise JSON to Comparator (RFC 8620 section 5.5).
  ## Uses initResultErr and helper func because Comparator has PropertyName
  ## {.requiresInit.}, triggering the nim-results requiresInit limitation.
  let coreResult = parseComparatorCore(node, $T)
  if coreResult.isErr:
    return initResultErr[Comparator, ValidationError](coreResult.error)
  let core = coreResult.get()
  let comparator = parseComparator(core[0], core[1], core[2])
  if comparator.isErr:
    return initResultErr[Comparator, ValidationError](comparator.error)
  ok(comparator.get())

# =============================================================================
# Filter[C]
# =============================================================================

func toJson*[C](
    f: Filter[C], condToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].}
): JsonNode =
  ## Serialise Filter[C] to JSON. Caller provides condition serialiser.
  case f.kind
  of fkCondition:
    condToJson(f.condition)
  of fkOperator:
    {.cast(noSideEffect).}:
      var conditions = newJArray()
      for child in f.conditions:
        conditions.add(child.toJson(condToJson))
      %*{"operator": $f.operator, "conditions": conditions}

func fromJson*[C](
    T: typedesc[Filter[C]],
    node: JsonNode,
    fromCondition:
      proc(n: JsonNode): Result[C, ValidationError] {.noSideEffect, raises: [].},
): Result[Filter[C], ValidationError] =
  ## Deserialise JSON to Filter[C]. Caller provides condition deserialiser.
  ## Dispatches on presence of "operator" key.
  checkJsonKind(node, JObject, $T)
  let opNode = node{"operator"}
  if opNode.isNil:
    let cond = ?fromCondition(node)
    ok(filterCondition(cond))
  else:
    let op = ?FilterOperator.fromJson(opNode)
    let conditionsNode = node{"conditions"}
    checkJsonKind(conditionsNode, JArray, $T, "missing or invalid conditions array")
    var children: seq[Filter[C]]
    for childNode in conditionsNode.getElems(@[]):
      let child = ?Filter[C].fromJson(childNode, fromCondition)
      children.add(child)
    ok(filterOperator(op, children))

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
