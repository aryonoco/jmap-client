# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Primitive ser/de overloads — `string`/`bool`/`seq[T]`/`Table[K,V]`
## fromJson/toJson, the `defineDistinct*` templates that generate
## per-newtype overloads, the 11 instantiations for the L1 distinct
## types (Id, AccountId, JmapState, MethodCallId, CreationId, BlobId,
## PropertyName, Date, UTCDate, UnsignedInt, JmapInt), and the
## `MaxChanges` ser/de (relocated from serde.nim).
##
## L2-private. Reach from in-tree callers via direct H10 import.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types
import ./serde
import ./serde_diagnostics
import ./serde_helpers

# =============================================================================
# Primitive ``string``/``bool`` toJson/fromJson — feed the mixin-uniform
# helpers in ``serde_field_echo.nim`` for ``Opt[string]`` / ``Opt[bool]`` /
# ``FieldEcho[string]`` partial fields. Existing serde sites continue to use
# ``fieldJString`` / ``node.getStr()`` directly; these overloads are
# additive.
# =============================================================================

func fromJson*(
    T: typedesc[string], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[string, SerdeViolation] =
  ## Deserialise a JSON string node to ``string``. Strict on wrong kind.
  discard $T
  ?expectKind(node, JString, path)
  return ok(node.getStr(""))

func toJson*(s: string): JsonNode =
  ## Serialise ``string`` to a JSON string node.
  return newJString(s)

func fromJson*(
    T: typedesc[bool], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[bool, SerdeViolation] =
  ## Deserialise a JSON boolean node to ``bool``. Strict on wrong kind.
  discard $T
  ?expectKind(node, JBool, path)
  return ok(node.getBool(false))

func toJson*(b: bool): JsonNode =
  ## Serialise ``bool`` to a JSON boolean node.
  return newJBool(b)

# =============================================================================
# Generic ``seq[T]`` toJson/fromJson — element type resolves via ``mixin``
# =============================================================================

func fromJson*[T](
    S: typedesc[seq[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[seq[T], SerdeViolation] =
  ## Parse a JSON array into ``seq[T]``. Each element resolves via
  ## ``mixin T.fromJson`` at instantiation. Nil node parses to the empty
  ## seq (lenient — Postel on receive); non-array kind surfaces a
  ## ``svkWrongKind`` SerdeViolation. Absence-as-empty keeps semantics
  ## aligned with the existing bespoke helpers (``parseBodyPartArray``,
  ## ``parseRawHeaders``); partial parsers add an outer ``hasKey``/``Opt``
  ## wrap before calling this.
  mixin fromJson
  discard $S
  if node.isNil:
    return ok(newSeq[T]())
  ?expectKind(node, JArray, path)
  var out0 = newSeqOfCap[T](node.len)
  for i, child in node.getElems(@[]):
    out0.add(?T.fromJson(child, path / i))
  return ok(out0)

func toJson*[T](xs: seq[T]): JsonNode =
  ## Emit a ``seq[T]`` as a JSON array via ``mixin T.toJson``. Empty seq
  ## emits ``[]``.
  mixin toJson
  result = newJArray()
  for x in xs:
    result.add(x.toJson())

# =============================================================================
# Generic ``Table[K, V]`` toJson/fromJson — keys resolve via
# ``mixin parseFromString(K, raw)``, values via ``mixin V.fromJson``
# =============================================================================

func fromJson*[K, V](
    T: typedesc[Table[K, V]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Table[K, V], SerdeViolation] =
  ## Parse a JSON object into ``Table[K, V]``. Each wire key resolves
  ## via ``mixin parseFromString(K, raw)`` (returning
  ## ``Result[K, ValidationError]``, bridged via ``wrapInner``); each
  ## value resolves via ``mixin V.fromJson``. Nil/non-object nodes parse
  ## to the empty table (lenient — consistent with ``parseKeyedTable``).
  mixin parseFromString
  mixin fromJson
  discard $T
  var out0 = initTable[K, V]()
  if node.isNil or node.kind != JObject:
    return ok(out0)
  for key, child in node.pairs:
    let k = ?wrapInner(parseFromString(K, key), path / key)
    let v = ?V.fromJson(child, path / key)
    out0[k] = v
  return ok(out0)

func toJson*[K, V](tbl: Table[K, V]): JsonNode =
  ## Emit a ``Table[K, V]`` as a JSON object. Keys serialise via ``$``
  ## (``K`` is ``Id``/``PartId``/``HeaderPropertyKey`` — all carry a
  ## ``$`` yielding the wire token); values via ``mixin V.toJson``. Empty
  ## table emits ``{}``.
  mixin toJson
  result = newJObject()
  for k, v in tbl.pairs:
    result[$k] = v.toJson()

# =============================================================================
# Serde templates for distinct types
# =============================================================================
#
# Each template generates a concrete toJson/fromJson overload. The parser
# parameter (untyped) is the smart constructor name for the target type.

template defineDistinctStringToJson*(T: typedesc) =
  ## Generates a ``toJson`` overload that serialises a string-backed
  ## sealed type to a JSON string node. The type must expose ``$`` —
  ## supplied by ``defineSealedStringOps`` / ``defineSealedOpaqueStringOps``.
  func toJson*(x: T): JsonNode =
    ## Serialise sealed string type to JSON string.
    return %($x)

template defineDistinctStringFromJson*(T: typedesc, parser: untyped) =
  ## Generates a ``fromJson`` overload that deserialises a JSON string node
  ## via the type's smart constructor (passed as ``parser``).
  func fromJson*(
      t: typedesc[T], node: JsonNode, path: JsonPath = emptyJsonPath()
  ): Result[T, SerdeViolation] =
    ## Deserialise JSON string via the type's smart constructor.
    discard $t # consumed for nimalyzer params rule
    ?expectKind(node, JString, path)
    return wrapInner(parser(node.getStr("")), path)

template defineDistinctIntToJson*(T: typedesc, asInt: untyped) =
  ## Generates a ``toJson`` overload that serialises a sealed int type
  ## to a JSON integer node via the given projection (e.g. ``toInt64``).
  func toJson*(x: T): JsonNode =
    ## Serialise sealed int type to JSON integer.
    return %asInt(x)

template defineDistinctIntFromJson*(T: typedesc, parser: untyped) =
  ## Generates a ``fromJson`` overload that deserialises a JSON integer node
  ## via the type's smart constructor (passed as ``parser``).
  func fromJson*(
      t: typedesc[T], node: JsonNode, path: JsonPath = emptyJsonPath()
  ): Result[T, SerdeViolation] =
    ## Deserialise JSON integer via the type's smart constructor.
    discard $t # consumed for nimalyzer params rule
    ?expectKind(node, JInt, path)
    return wrapInner(parser(node.getBiggestInt(0)), path)

# --- toJson/fromJson: distinct string types ---

defineDistinctStringToJson(Id)
defineDistinctStringToJson(AccountId)
defineDistinctStringToJson(JmapState)
defineDistinctStringToJson(MethodCallId)
defineDistinctStringToJson(CreationId)
defineDistinctStringToJson(BlobId)
defineDistinctStringToJson(PropertyName)
defineDistinctStringToJson(Date)
defineDistinctStringToJson(UTCDate)

defineDistinctStringFromJson(Id, parseIdFromServer)
defineDistinctStringFromJson(AccountId, parseAccountId)
defineDistinctStringFromJson(JmapState, parseJmapState)
defineDistinctStringFromJson(MethodCallId, parseMethodCallId)
defineDistinctStringFromJson(CreationId, parseCreationId)
defineDistinctStringFromJson(BlobId, parseBlobId)
defineDistinctStringFromJson(PropertyName, parsePropertyName)
defineDistinctStringFromJson(Date, parseDate)
defineDistinctStringFromJson(UTCDate, parseUtcDate)

# --- toJson/fromJson: distinct int types ---

defineDistinctIntToJson(UnsignedInt, toInt64)
defineDistinctIntToJson(JmapInt, toInt64)

defineDistinctIntFromJson(UnsignedInt, parseUnsignedInt)
defineDistinctIntFromJson(JmapInt, parseJmapInt)

# --- toJson/fromJson: MaxChanges ---

func toJson*(x: MaxChanges): JsonNode =
  ## Serialise MaxChanges to JSON integer.
  return %x.toInt64

func fromJson*(
    T: typedesc[MaxChanges], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MaxChanges, SerdeViolation] =
  ## Deserialise a JSON integer to MaxChanges (must be > 0).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JInt, path)
  let ui = ?wrapInner(parseUnsignedInt(node.getBiggestInt(0)), path)
  return wrapInner(parseMaxChanges(ui), path)
