# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Generic method framework types for JMAP standard methods (RFC 8620 §5).
## Covers filters, comparators, patch objects, and query change tracking.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes

import ./validation
import ./primitives
import ./collation
export collation

type PropertyName* {.ruleOff: "objects".} = object
  ## A non-empty property name identifying a field on an entity type
  ## (RFC 8620 §5.5). Sealed Pattern-A object — ``rawValue`` is
  ## module-private. Construct via ``parsePropertyName``.
  rawValue: string

defineSealedStringOps(PropertyName)

func parsePropertyName*(raw: string): Result[PropertyName, ValidationError] =
  ## Validates and constructs a PropertyName. Rejects empty strings.
  if raw.len == 0:
    return err(validationError("PropertyName", "must not be empty", raw))
  return ok(PropertyName(rawValue: raw))

type FilterOperator* = enum
  ## RFC 8620 §5.5 filter composition operators.
  foAnd = "AND"
  foOr = "OR"
  foNot = "NOT"

type FilterKind* = enum
  ## Discriminator for Filter: either a leaf condition or a composed operator.
  fkCondition
  fkOperator

type Filter*[C] {.ruleOff: "objects".} = object
  ## Recursive filter tree parameterised by condition type C (RFC 8620 §5.5).
  ## The operator arm is sealed (P16): ``rawOperands`` is module-private and
  ## only reachable through the non-empty smart constructors, so an empty
  ## operand list is unrepresentable. ``foNot`` is held to exactly one operand
  ## by ``filterNot`` (its only constructor); ``foAnd`` / ``foOr`` take one or
  ## more via ``filterAnd`` / ``filterOr``. A direct-value recursive single
  ## child field is impossible (it makes the type infinite-size and crashes
  ## codegen), so the one-or-many distinction is carried by the constructors,
  ## not a second discriminator.
  case kind*: FilterKind
  of fkCondition:
    condition*: C
  of fkOperator:
    operator*: FilterOperator ## the boolean operator (AND, OR, NOT)
    rawOperands: NonEmptySeq[Filter[C]] ## module-private; ≥1 guaranteed by type

func filterCondition*[C](cond: C): Filter[C] =
  ## Wraps a condition value as a leaf filter node.
  return Filter[C](kind: fkCondition, condition: cond)

func operands*[C](f: Filter[C]): seq[Filter[C]] =
  ## The child filters of an operator node; an empty seq for a leaf condition
  ## (callers should ``case`` on ``kind`` first). Returns a copy — the sealed
  ## ``rawOperands`` is never aliased out.
  case f.kind
  of fkCondition:
    @[]
  of fkOperator:
    asSeq(f.rawOperands)

func filterNot*[C](child: Filter[C]): Filter[C] =
  ## Negation filter (RFC 8620 §5.5) — NOT has exactly one child. Infallible:
  ## ``@[child]`` has length 1, so ``parseNonEmptySeq`` cannot Err here.
  Filter[C](
    kind: fkOperator, operator: foNot, rawOperands: parseNonEmptySeq(@[child]).get()
  )

func filterAnd*[C](operands: openArray[Filter[C]]): Result[Filter[C], ValidationError] =
  ## Conjunction filter (RFC 8620 §5.5) — AND is one or more conditions.
  ## Rejects an empty operand list.
  let nes = ?parseNonEmptySeq(@operands)
  ok(Filter[C](kind: fkOperator, operator: foAnd, rawOperands: nes))

func filterOr*[C](operands: openArray[Filter[C]]): Result[Filter[C], ValidationError] =
  ## Disjunction filter (RFC 8620 §5.5) — OR is one or more conditions.
  ## Rejects an empty operand list.
  let nes = ?parseNonEmptySeq(@operands)
  ok(Filter[C](kind: fkOperator, operator: foOr, rawOperands: nes))

type SortDirection* = enum
  ## Sort direction for a /query ``Comparator`` (RFC 8620 §5.5). The three
  ## states map exactly onto the three observable states of the optional
  ## ``isAscending`` wire key, replacing the prior ``bool`` / ``Opt[bool]``
  ## soup (P18; "booleans are a code smell"): ``sdServerDefault`` omits the
  ## key (the server applies its RFC default, ascending); ``sdAscending``
  ## emits ``true``; ``sdDescending`` emits ``false``. ``sdServerDefault``
  ## stays first (ordinal 0) so zero-initialisation yields the RFC default.
  sdServerDefault
  sdAscending
  sdDescending

type Comparator* {.ruleOff: "objects".} = object
  ## Sort criterion for /query requests (RFC 8620 §5.5). Determines the
  ## sort order for results returned by a /query method call.
  ##
  ## ``property`` is a public read field: ``PropertyName`` is an
  ## already-validated newtype, so direct construction cannot forge an
  ## illegal value. ``parseComparator`` remains the convenience constructor.
  property*: PropertyName ## validated property name (RFC 8620 §5.5)
  direction*: SortDirection ## sort direction (RFC 8620 §5.5 ``isAscending``)
  collation*: Opt[CollationAlgorithm] ## RFC 4790 collation algorithm identifier

func parseComparator*(
    property: PropertyName,
    direction: SortDirection = sdServerDefault,
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): Comparator =
  ## Constructs a Comparator. Infallible given a valid PropertyName.
  return Comparator(property: property, direction: direction, collation: collation)

type AddedItem* {.ruleOff: "objects".} = object
  ## An item added to query results at a specific position (RFC 8620 §5.6).
  ##
  ## ``id`` is a public read field: ``Id`` is an already-validated newtype,
  ## so direct construction cannot forge an illegal value. ``initAddedItem``
  ## remains the convenience constructor.
  id*: Id ## validated item identifier
  index*: UnsignedInt ## the position index

func initAddedItem*(id: Id, index: UnsignedInt): AddedItem =
  ## Constructs an AddedItem. Infallible given validated Id and UnsignedInt.
  return AddedItem(id: id, index: index)

type QueryParams* = object
  ## Standard query window parameters shared by all ``/query`` methods
  ## (RFC 8620 section 5.5). All defaults match RFC specification via
  ## Nim zero-initialisation: ``QueryParams()`` produces correct RFC defaults.
  position*: JmapInt ## default 0
  anchor*: Opt[Id] ## default: absent
  anchorOffset*: JmapInt ## default 0
  limit*: Opt[UnsignedInt] ## default: absent
  calculateTotal*: bool ## default false
