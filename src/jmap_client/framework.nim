# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Generic method framework types for JMAP standard methods (RFC 8620 §5).
## Covers filters, comparators, patch objects, and query change tracking.

import std/hashes
import std/options
import std/tables
from std/json import JsonNode, newJNull

import ./validation
import ./primitives

type PropertyName* = distinct string
  ## A non-empty property name identifying a field on an entity type (RFC 8620 §5.5).

defineStringDistinctOps(PropertyName)

proc parsePropertyName*(raw: string): PropertyName =
  ## Validates and constructs a PropertyName. Rejects empty strings.
  if raw.len == 0:
    raise newValidationError("PropertyName", "must not be empty", raw)
  PropertyName(raw)

type FilterOperator* = enum
  ## RFC 8620 §5.5 filter composition operators.
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"

type FilterKind* = enum
  ## Discriminator for Filter: either a leaf condition or a composed operator.
  fkCondition
  fkOperator

type Filter*[C] = object
  ## Recursive filter tree parameterised by condition type C (RFC 8620 §5.5).
  case kind*: FilterKind
  of fkCondition:
    condition*: C
  of fkOperator:
    operator*: FilterOperator
    conditions*: seq[Filter[C]]

proc filterCondition*[C](cond: C): Filter[C] =
  ## Wraps a condition value as a leaf filter node.
  Filter[C](kind: fkCondition, condition: cond)

proc filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =
  ## Composes child filters under a boolean operator (AND, OR, NOT).
  Filter[C](kind: fkOperator, operator: op, conditions: conditions)

type Comparator* = object
  ## Sort criterion for /query requests (RFC 8620 §5.5). Determines the sort order
  ## for results returned by a /query method call.
  property*: PropertyName ## the property to sort by
  isAscending*: bool ## true = ascending (RFC default)
  collation*: Option[string] ## RFC 4790 collation algorithm identifier

proc parseComparator*(
    property: PropertyName,
    isAscending: bool = true,
    collation: Option[string] = none(string),
): Comparator =
  ## Constructs a Comparator. Infallible given a valid PropertyName.
  Comparator(property: property, isAscending: isAscending, collation: collation)

type PatchObject* = distinct Table[string, JsonNode]
  ## Map of JSON Pointer paths to values for /set update operations (RFC 8620 §5.3).

proc len*(p: PatchObject): int {.borrow.} ## Returns the number of entries in the patch.

proc emptyPatch*(): PatchObject =
  ## Creates an empty PatchObject with no entries.
  PatchObject(initTable[string, JsonNode]())

proc setProp*(patch: PatchObject, path: string, value: JsonNode): PatchObject =
  ## Sets a property at the given JSON Pointer path.
  if path.len == 0:
    raise newValidationError("PatchObject", "path must not be empty", "")
  var t = Table[string, JsonNode](patch)
  t[path] = value
  PatchObject(t)

proc deleteProp*(patch: PatchObject, path: string): PatchObject =
  ## Sets a property to null (deletion in JMAP PatchObject semantics).
  if path.len == 0:
    raise newValidationError("PatchObject", "path must not be empty", "")
  var t = Table[string, JsonNode](patch)
  t[path] = newJNull()
  PatchObject(t)

proc getKey*(patch: PatchObject, key: string): Option[JsonNode] =
  ## Returns the value at key, or none if absent.
  let t = Table[string, JsonNode](patch)
  if t.hasKey(key):
    some(t[key])
  else:
    none(JsonNode)

type AddedItem* = object
  ## An item added to query results at a specific position (RFC 8620 §5.6).
  id*: Id ## the item identifier
  index*: UnsignedInt ## the position index
