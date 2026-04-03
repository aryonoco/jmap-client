# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP framework types: FilterOperator, Comparator,
## Filter[C], PatchObject, and AddedItem (RFC 8620 sections 5.3, 5.5, 5.6).

import std/json
import std/options
import std/tables

import ./serde
import ./types

# =============================================================================
# FilterOperator
# =============================================================================

proc toJson*(op: FilterOperator): JsonNode =
  ## Serialise FilterOperator to its RFC string.
  %($op)

proc fromJson*(T: typedesc[FilterOperator], node: JsonNode): FilterOperator =
  ## Deserialise a JSON string to FilterOperator. Not total — unknown
  ## operators return err because the RFC defines exactly three.
  checkJsonKind(node, JString, $T)
  case node.getStr("")
  of "AND":
    foAnd
  of "OR":
    foOr
  of "NOT":
    foNot
  else:
    raise parseError($T, "unknown operator: " & node.getStr(""))

# =============================================================================
# Comparator
# =============================================================================

proc toJson*(c: Comparator): JsonNode =
  ## Serialise Comparator to JSON (RFC 8620 section 5.5).
  result = %*{"property": string(c.property), "isAscending": c.isAscending}
  if c.collation.isSome:
    result["collation"] = %c.collation.get()

proc fromJson*(T: typedesc[Comparator], node: JsonNode): Comparator =
  ## Deserialise JSON to Comparator (RFC 8620 section 5.5).
  checkJsonKind(node, JObject, $T)
  let propNode = node{"property"}
  checkJsonKind(propNode, JString, $T, "missing or invalid property")
  let property = parsePropertyName(propNode.getStr(""))
  let ascNode = node{"isAscending"}
  if not ascNode.isNil:
    if ascNode.kind != JBool:
      raise parseError($T, "isAscending must be boolean")
  let isAscending = ascNode.getBool(true)
    # nil-safe; returns true (RFC default) when absent
  let collNode = node{"collation"}
  var collation = none(string)
  if not collNode.isNil:
    if collNode.kind == JString:
      collation = some(collNode.getStr(""))
  parseComparator(property, isAscending, collation)

# =============================================================================
# Filter[C]
# =============================================================================

proc toJson*[C](f: Filter[C], filterConditionToJson: proc(c: C): JsonNode): JsonNode =
  ## Serialise Filter[C] to JSON. Caller provides condition serialiser.
  case f.kind
  of fkCondition:
    filterConditionToJson(f.condition)
  of fkOperator:
    var conditions = newJArray()
    for child in f.conditions:
      conditions.add(child.toJson(filterConditionToJson))
    %*{"operator": $f.operator, "conditions": conditions}

const MaxFilterDepth* = 128
  ## Maximum nesting depth for Filter[C].fromJson deserialisation.
  ## Defence-in-depth guard against stack overflow (StackOverflowDefect is
  ## uncatchable). 128 is generous for any realistic JMAP query while
  ## preventing pathological nesting.
  ## Note: std/json's parseJson has its own DepthLimit of 1000, but this
  ## library's fromJson accepts pre-parsed JsonNode, so that limit does not
  ## apply at this layer.

proc fromJsonImpl[C](
    node: JsonNode, fromCondition: proc(n: JsonNode): C, depth: int
): Filter[C] =
  ## Internal recursive helper with depth tracking.
  const typeName = "Filter"
  checkJsonKind(node, JObject, typeName)
  if depth <= 0:
    raise parseError(typeName, "maximum nesting depth exceeded")
  let opNode = node{"operator"}
  if opNode.isNil:
    let cond = fromCondition(node)
    filterCondition(cond)
  else:
    let op = FilterOperator.fromJson(opNode)
    let conditionsNode = node{"conditions"}
    checkJsonKind(
      conditionsNode, JArray, typeName, "missing or invalid conditions array"
    )
    var children: seq[Filter[C]] = @[]
    for childNode in conditionsNode.getElems(@[]):
      let child = fromJsonImpl[C](childNode, fromCondition, depth - 1)
      children.add(child)
    filterOperator(op, children)

proc fromJson*[C](
    T: typedesc[Filter[C]], node: JsonNode, fromCondition: proc(n: JsonNode): C
): Filter[C] =
  ## Deserialise JSON to Filter[C]. Caller provides condition deserialiser.
  ## Dispatches on presence of "operator" key. Nesting depth is capped at
  ## MaxFilterDepth to prevent stack overflow on pathological input.
  discard $T # consumed for nimalyzer params rule
  fromJsonImpl[C](node, fromCondition, MaxFilterDepth)

# =============================================================================
# PatchObject
# =============================================================================

proc toJson*(patch: PatchObject): JsonNode =
  ## Serialise PatchObject to JSON. Keys are JSON Pointer paths,
  ## null values represent property deletion.
  let tbl = Table[string, JsonNode](patch)
  result = newJObject()
  for path, value in tbl:
    result[path] = value

proc fromJson*(T: typedesc[PatchObject], node: JsonNode): PatchObject =
  ## Deserialise JSON to PatchObject using smart constructors.
  ## null values -> deleteProp, other values -> setProp.
  checkJsonKind(node, JObject, $T)
  var patch = emptyPatch()
  for path, value in node.pairs:
    if value.isNil or value.kind == JNull:
      patch = deleteProp(patch, path)
    else:
      patch = setProp(patch, path, value)
  patch

# =============================================================================
# AddedItem
# =============================================================================

proc toJson*(item: AddedItem): JsonNode =
  ## Serialise AddedItem to JSON (RFC 8620 section 5.6).
  result = %*{"id": string(item.id), "index": int64(item.index)}

proc fromJson*(T: typedesc[AddedItem], node: JsonNode): AddedItem =
  ## Deserialise JSON to AddedItem.
  checkJsonKind(node, JObject, $T)
  let id = Id.fromJson(node{"id"})
  let index = UnsignedInt.fromJson(node{"index"})
  AddedItem(id: id, index: index)
