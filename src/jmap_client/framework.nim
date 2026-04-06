# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Generic method framework types for JMAP standard methods (RFC 8620 §5).
## Covers filters, comparators, patch objects, and query change tracking.

import std/hashes
import std/tables
from std/json import JsonNode, newJNull

import ./validation
import ./primitives

{.push raises: [].}

type PropertyName* = distinct string
  ## A non-empty property name identifying a field on an entity type (RFC 8620 §5.5).

defineStringDistinctOps(PropertyName)

func parsePropertyName*(raw: string): Result[PropertyName, ValidationError] =
  ## Validates and constructs a PropertyName. Rejects empty strings.
  if raw.len == 0:
    return err(validationError("PropertyName", "must not be empty", raw))
  ok(PropertyName(raw))

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

func filterCondition*[C](cond: C): Filter[C] =
  ## Wraps a condition value as a leaf filter node.
  Filter[C](kind: fkCondition, condition: cond)

func filterOperator*[C](op: FilterOperator, conditions: seq[Filter[C]]): Filter[C] =
  ## Composes child filters under a boolean operator (AND, OR, NOT).
  Filter[C](kind: fkOperator, operator: op, conditions: conditions)

type Comparator* = object
  ## Sort criterion for /query requests (RFC 8620 §5.5). Determines the sort order
  ## for results returned by a /query method call.
  ##
  ## Construction sealed via Pattern A (architecture §1.5.2): ``rawProperty`` is
  ## module-private, blocking direct construction from outside this module.
  ## Use ``parseComparator`` to construct.
  rawProperty: string ## module-private; validated PropertyName
  isAscending*: bool ## true = ascending (RFC default)
  collation*: Opt[string] ## RFC 4790 collation algorithm identifier

func property*(c: Comparator): PropertyName =
  ## Returns the validated property name for this comparator.
  PropertyName(c.rawProperty)

func parseComparator*(
    property: PropertyName,
    isAscending: bool = true,
    collation: Opt[string] = Opt.none(string),
): Comparator =
  ## Constructs a Comparator. Infallible given a valid PropertyName.
  Comparator(
    rawProperty: string(property), isAscending: isAscending, collation: collation
  )

type PatchObject* = distinct Table[string, JsonNode]
  ## Map of JSON Pointer paths to values for /set update operations (RFC 8620 §5.3).

func len*(p: PatchObject): int {.borrow.} ## Returns the number of entries in the patch.

func emptyPatch*(): PatchObject =
  ## Creates an empty PatchObject with no entries.
  PatchObject(initTable[string, JsonNode]())

func setProp*(
    patch: PatchObject, path: string, value: JsonNode
): Result[PatchObject, ValidationError] =
  ## Sets a property at the given JSON Pointer path.
  if path.len == 0:
    return err(validationError("PatchObject", "path must not be empty", ""))
  var t = Table[string, JsonNode](patch)
  t[path] = value
  ok(PatchObject(t))

func deleteProp*(
    patch: PatchObject, path: string
): Result[PatchObject, ValidationError] =
  ## Sets a property to null (deletion in JMAP PatchObject semantics).
  if path.len == 0:
    return err(validationError("PatchObject", "path must not be empty", ""))
  var t = Table[string, JsonNode](patch)
  t[path] = newJNull()
  ok(PatchObject(t))

func getKey*(patch: PatchObject, key: string): Opt[JsonNode] =
  ## Returns the value at key, or none if absent.
  let t = Table[string, JsonNode](patch)
  if t.hasKey(key):
    Opt.some(t.getOrDefault(key))
  else:
    Opt.none(JsonNode)

type AddedItem* = object
  ## An item added to query results at a specific position (RFC 8620 §5.6).
  ##
  ## Construction sealed via Pattern A (architecture Limitation 5/6a):
  ## ``rawId`` is module-private, blocking direct construction from outside
  ## this module. Use ``initAddedItem`` to construct.
  rawId: string ## module-private; validated Id
  index*: UnsignedInt ## the position index

func id*(item: AddedItem): Id =
  ## Returns the validated item identifier.
  Id(item.rawId)

func initAddedItem*(id: Id, index: UnsignedInt): AddedItem =
  ## Constructs an AddedItem. Infallible given validated Id and UnsignedInt.
  AddedItem(rawId: string(id), index: index)
