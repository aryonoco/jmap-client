# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Scaffolding helpers for L2 serde — `expectKind`, `fieldJ*`, optional
## field extractors, ID-array parsers, table parsers. Consumed by
## sibling L2 modules and by direct in-tree callers under
## `internal/protocol/` and `internal/mail/`.
##
## L2-private. Reach from in-tree callers via direct H10 import.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types
import ./serde
import ./serde_diagnostics

func expectKind*(
    node: JsonNode, expected: JsonNodeKind, path: JsonPath
): Result[void, SerdeViolation] =
  ## Assert that ``node`` has the given kind. A nil node maps to
  ## ``svkNilNode`` — this is the top-level case, where the whole
  ## document was expected but absent. A non-nil wrong-kind node maps to
  ## ``svkWrongKind`` at the current path.
  if node.isNil:
    return
      err(SerdeViolation(kind: svkNilNode, path: path, expectedKindForNil: expected))
  if node.kind != expected:
    return err(
      SerdeViolation(
        kind: svkWrongKind, path: path, expectedKind: expected, actualKind: node.kind
      )
    )
  return ok()

func fieldOfKind*(
    node: JsonNode, key: string, expected: JsonNodeKind, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Extract a required typed child from an object node. Missing →
  ## ``svkMissingField`` anchored at the parent path (the child doesn't
  ## exist to point at). Wrong kind → ``svkWrongKind`` at ``path / key``.
  ## Precondition: caller has already verified ``node.kind == JObject``.
  let child = node{key}
  if child.isNil:
    return err(SerdeViolation(kind: svkMissingField, path: path, missingFieldName: key))
  if child.kind != expected:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / key,
        expectedKind: expected,
        actualKind: child.kind,
      )
    )
  return ok(child)

func fieldJObject*(
    node: JsonNode, key: string, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Required object-valued field; short-hand over ``fieldOfKind``.
  return fieldOfKind(node, key, JObject, path)

func fieldJString*(
    node: JsonNode, key: string, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Required string-valued field; short-hand over ``fieldOfKind``.
  return fieldOfKind(node, key, JString, path)

func fieldJArray*(
    node: JsonNode, key: string, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Required array-valued field; short-hand over ``fieldOfKind``.
  return fieldOfKind(node, key, JArray, path)

func fieldJBool*(
    node: JsonNode, key: string, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Required boolean-valued field; short-hand over ``fieldOfKind``.
  return fieldOfKind(node, key, JBool, path)

func fieldJInt*(
    node: JsonNode, key: string, path: JsonPath
): Result[JsonNode, SerdeViolation] =
  ## Required integer-valued field; short-hand over ``fieldOfKind``.
  return fieldOfKind(node, key, JInt, path)

func optField*(node: JsonNode, key: string): Opt[JsonNode] =
  ## Lenient optional field access: absent → ``Opt.none``. Kind is NOT
  ## validated; callers that need typed optionals check the kind on the
  ## extracted node.
  let child = node{key}
  if child.isNil:
    return Opt.none(JsonNode)
  return Opt.some(child)

func expectLen*(node: JsonNode, n: int, path: JsonPath): Result[void, SerdeViolation] =
  ## Assert that a JSON array has exactly ``n`` elements. Precondition:
  ## caller has already verified ``node.kind == JArray``.
  if node.len != n:
    return err(
      SerdeViolation(
        kind: svkArrayLength, path: path, expectedLen: n, actualLen: node.len
      )
    )
  return ok()

func nonEmptyStr*(
    s: string, label: string, path: JsonPath
): Result[void, SerdeViolation] =
  ## Assert that a wire-boundary string is non-empty. ``label`` describes
  ## the field's purpose (``"method name"``, ``"type field"``, etc.) —
  ## the translator renders it verbatim followed by ``" must not be empty"``.
  if s.len == 0:
    return
      err(SerdeViolation(kind: svkEmptyRequired, path: path, emptyFieldLabel: label))
  return ok()

func wrapInner*[T](
    r: Result[T, ValidationError], path: JsonPath
): Result[T, SerdeViolation] =
  ## Bridge an L1 smart-constructor failure into the serde railway. The
  ## inner ``ValidationError`` is preserved losslessly inside
  ## ``svkFieldParserFailed`` — the translator reconstructs its original
  ## shape, augmented only with the path suffix.
  if r.isOk:
    return ok(r.get())
  return err(SerdeViolation(kind: svkFieldParserFailed, path: path, inner: r.error))

func collectExtras*(node: JsonNode, knownKeys: openArray[string]): Opt[JsonNode] =
  ## Collect non-standard fields from a JSON object into ``Opt[JsonNode]``.
  ## Returns ``Opt.none`` when no extra fields exist.
  ## Precondition: caller has verified ``node.kind == JObject``.
  var extras = newJObject()
  var found = false
  for key, val in node.pairs:
    if key notin knownKeys:
      extras[key] = val
      found = true
  if found:
    return Opt.some(extras)
  return Opt.none(JsonNode)

func parseIdArray*(node: JsonNode, path: JsonPath): Result[seq[Id], SerdeViolation] =
  ## Validate ``node`` as a JSON array and parse each element as a
  ## server-assigned ``Id``. Used when the whole node IS the array.
  ?expectKind(node, JArray, path)
  var ids: seq[Id] = @[]
  for i, elem in node.getElems(@[]):
    let id = ?wrapInner(parseIdFromServer(elem.getStr("")), path / i)
    ids.add(id)
  return ok(ids)

func parseIdArrayField*(
    parent: JsonNode, key: string, path: JsonPath
): Result[seq[Id], SerdeViolation] =
  ## Required id-array field on an object: missing → ``svkMissingField``,
  ## wrong kind → ``svkWrongKind``, per-element failure →
  ## ``svkFieldParserFailed``. Preferred over ``parseIdArray(node{"key"}, …)``
  ## because it distinguishes missing from wrong-kind.
  let arrNode = ?fieldJArray(parent, key, path)
  var ids: seq[Id] = @[]
  for i, elem in arrNode.getElems(@[]):
    let id = ?wrapInner(parseIdFromServer(elem.getStr("")), path / key / i)
    ids.add(id)
  return ok(ids)

func parseOptIdArray*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[seq[Id], SerdeViolation] =
  ## Lenient variant of ``parseIdArray``: absent or non-array nodes
  ## collapse to the empty seq. For optional id arrays such as
  ## ``GetResponse.notFound``. Per-element failures still surface via
  ## ``svkFieldParserFailed`` at ``path / i``.
  if node.isNil or node.kind != JArray:
    return ok(newSeq[Id]())
  var ids: seq[Id] = @[]
  for i, elem in node.getElems(@[]):
    let id = ?wrapInner(parseIdFromServer(elem.getStr("")), path / i)
    ids.add(id)
  return ok(ids)

func collapseNullToEmptySeq*[T](
    node: JsonNode,
    key: string,
    parser: proc(s: string): Result[T, ValidationError] {.noSideEffect, raises: [].},
    path: JsonPath,
): Result[seq[T], SerdeViolation] =
  ## Parse a ``T[]|null`` field by key where null or absent collapses to
  ## an empty seq. Each array element's string value is passed to
  ## ``parser``. Used by response types that have nullable string-keyed
  ## arrays (D13) — generic over the element type so both ``Id`` and
  ## ``BlobId`` arrays can share this helper.
  let child = node{key}
  if child.isNil or child.kind != JArray:
    return ok(newSeq[T]())
  var items: seq[T] = @[]
  for i, elem in child.getElems(@[]):
    items.add(?wrapInner(parser(elem.getStr("")), path / key / i))
  return ok(items)

func parseKeyedTable*[K, T](
    node: JsonNode,
    parseKey: proc(raw: string): Result[K, ValidationError] {.noSideEffect, raises: [].},
    parseValue: proc(n: JsonNode, p: JsonPath): Result[T, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    path: JsonPath,
): Result[Table[K, T], SerdeViolation] =
  ## Parse a JSON object into ``Table[K, T]``. Each key is parsed via
  ## the server-validated smart constructor ``parseKey``; each value
  ## via ``parseValue``, which receives the descended path. Nil or
  ## non-object node yields an empty table (lenient, D15).
  ##
  ## ``K`` must satisfy Table's requirements (``hash``, ``==``) — every
  ## opaque-token distinct-string in this codebase (``Id``, ``BlobId``,
  ## ``AccountId``, etc.) does so via the borrow convention.
  if node.isNil or node.kind != JObject:
    return ok(initTable[K, T]())
  var tbl = initTable[K, T](node.len)
  for key, val in node.pairs:
    let k = ?wrapInner(parseKey(key), path / key)
    let parsed = ?parseValue(val, path / key)
    tbl[k] = parsed
  return ok(tbl)

func optJsonField*(node: JsonNode, key: string, kind: JsonNodeKind): Opt[JsonNode] =
  ## Lenient typed-optional field access: absent, null, or wrong kind →
  ## ``Opt.none``. Companion to ``fieldOfKind`` (strict: returns a Result
  ## with the specific violation).
  let child = node{key}
  if child.isNil or child.kind != kind:
    return Opt.none(JsonNode)
  return Opt.some(child)

func optToJsonOrNull*[T](opt: Opt[T]): JsonNode =
  ## Convert an optional value to JSON via ``toJson`` when present, or
  ## ``newJNull()`` when absent. Call site:
  ## ``node[key] = opt.optToJsonOrNull()``.
  result = newJNull()
  for val in opt:
    result = val.toJson()

func optStringToJsonOrNull*(opt: Opt[string]): JsonNode =
  ## Convert an optional string to a JSON string when present, or
  ## ``newJNull()`` when absent. Specialised because ``string`` has no
  ## ``toJson`` overload in this codebase (``%`` is the idiom).
  result = newJNull()
  for val in opt:
    result = %val
