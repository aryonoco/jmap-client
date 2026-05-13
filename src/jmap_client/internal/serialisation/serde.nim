# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared serialisation helpers, primitive/identifier ser/de pairs, and the
## ``SerdeViolation`` structured-error ADT that every ``fromJson`` in this
## codebase produces on failure.
##
## Design: ``fromJson`` sites return ``Result[T, SerdeViolation]`` — a
## sum-type carrying an RFC 6901 JSON Pointer (``JsonPath``) plus a
## variant-specific payload. Composition preserves the path: when an outer
## ``fromJson`` calls an inner one, the outer prepends path segments as it
## descends. Translation to the wire ``ValidationError`` shape happens at
## exactly one site — ``toValidationError`` — at the L3/L4 boundary.
##
## Adding a new structural-violation kind forces a compile error in
## ``toValidationError`` and nowhere else.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils
import std/tables

import ../../types

# =============================================================================
# JsonPath — structured RFC 6901 JSON Pointer
# =============================================================================

type JsonPathElementKind* = enum
  ## Discriminator for ``JsonPathElement`` — a path segment is either a
  ## named object key or a zero-based array index.
  jpeKey
  jpeIndex

type JsonPathElement* {.ruleOff: "objects".} = object
  ## One segment of a ``JsonPath``. Discriminated so indices and escaped
  ## keys remain distinguishable throughout composition.
  case kind*: JsonPathElementKind
  of jpeKey:
    key*: string
  of jpeIndex:
    idx*: int

type JsonPath* {.ruleOff: "objects".} = object
  ## Ordered, immutable path of object keys and array indices — rendered
  ## as an RFC 6901 JSON Pointer string by ``$``. Sealed Pattern-A
  ## object — ``rawValue`` is module-private. Composed left-to-right via
  ## the ``/`` operator as a ``fromJson`` descends the wire tree.
  rawValue: seq[JsonPathElement]

func emptyJsonPath*(): JsonPath =
  ## The empty RFC 6901 pointer — references the root of the document.
  return JsonPath(rawValue: @[])

func jsonPointerEscape*(s: string): string =
  ## RFC 6901 §3 reference-token escaping. ``~`` MUST be escaped first:
  ## escaping ``/`` first would produce ``~1`` that a second pass would
  ## re-escape into ``~01``, corrupting tokens containing ``/``.
  return s.replace("~", "~0").replace("/", "~1")

func `/`*(p: JsonPath, key: string): JsonPath =
  ## Extend the path with a named object key. Produces a fresh path;
  ## ``p`` is unchanged.
  return JsonPath(rawValue: p.rawValue & @[JsonPathElement(kind: jpeKey, key: key)])

func `/`*(p: JsonPath, idx: int): JsonPath =
  ## Extend the path with a zero-based array index. Produces a fresh
  ## path; ``p`` is unchanged.
  return JsonPath(rawValue: p.rawValue & @[JsonPathElement(kind: jpeIndex, idx: idx)])

func `$`*(p: JsonPath): string =
  ## Render as an RFC 6901 JSON Pointer string. The empty path renders
  ## as ``""`` (references the whole document); otherwise each segment
  ## contributes a leading ``/`` plus the escaped token or the index.
  result = ""
  for elem in p.rawValue:
    case elem.kind
    of jpeKey:
      result.add("/" & jsonPointerEscape(elem.key))
    of jpeIndex:
      result.add("/" & $elem.idx)

# =============================================================================
# SerdeViolation — structured deserialisation error
# =============================================================================

type SerdeViolationKind* = enum
  ## Enumerates the structural deserialisation-failure modes. Each variant
  ## corresponds to exactly one ``of`` arm in ``SerdeViolation``; adding a
  ## kind here forces a compile error in ``toValidationError``.
  svkWrongKind ## Node present but the wrong ``JsonNodeKind``.
  svkNilNode ## Node absent where one was required (top-level only).
  svkMissingField ## Required object field not present.
  svkEmptyRequired ## Wire-boundary non-empty invariant violated.
  svkArrayLength ## Array had the wrong number of elements.
  svkFieldParserFailed ## An inner smart constructor rejected the value.
  svkConflictingFields ## Two mutually-exclusive fields both present.
  svkEnumNotRecognised ## Token outside the enum's accepted set.
  svkDepthExceeded ## Recursive nesting exceeded the stack-safety cap.

type SerdeViolation* {.ruleOff: "objects".} = object
  ## Structured deserialisation error. The ``path`` locates the violation
  ## inside the wire tree (RFC 6901); the variant carries the detail.
  path*: JsonPath
  case kind*: SerdeViolationKind
  of svkWrongKind:
    expectedKind*: JsonNodeKind
    actualKind*: JsonNodeKind
  of svkNilNode:
    expectedKindForNil*: JsonNodeKind
  of svkMissingField:
    missingFieldName*: string
  of svkEmptyRequired:
    emptyFieldLabel*: string
  of svkArrayLength:
    expectedLen*: int
    actualLen*: int
  of svkFieldParserFailed:
    inner*: ValidationError
  of svkConflictingFields:
    conflictKeyA*: string
    conflictKeyB*: string
    conflictRule*: string
  of svkEnumNotRecognised:
    enumTypeLabel*: string
    rawValue*: string
  of svkDepthExceeded:
    maxDepth*: int

# =============================================================================
# Combinators
# =============================================================================

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

# =============================================================================
# Translator — sole SerdeViolation → ValidationError boundary
# =============================================================================

func toValidationError*(v: SerdeViolation, rootType: string): ValidationError =
  ## Translate a structured violation to the wire ``ValidationError``
  ## shape. The suffix ``" at <rfc-6901-pointer>"`` is appended when the
  ## path is non-empty. For ``svkFieldParserFailed`` the inner
  ## ``typeName`` and ``value`` are preserved verbatim; otherwise
  ## ``rootType`` is used.
  let pathStr = $v.path
  let suffix =
    if pathStr.len == 0:
      ""
    else:
      " at " & pathStr
  case v.kind
  of svkWrongKind:
    return validationError(
      rootType, "expected " & $v.expectedKind & ", got " & $v.actualKind & suffix, ""
    )
  of svkNilNode:
    return validationError(
      rootType, "expected " & $v.expectedKindForNil & ", got nil" & suffix, ""
    )
  of svkMissingField:
    return
      validationError(rootType, "missing field: " & v.missingFieldName & suffix, "")
  of svkEmptyRequired:
    return
      validationError(rootType, v.emptyFieldLabel & " must not be empty" & suffix, "")
  of svkArrayLength:
    return validationError(
      rootType,
      "expected " & $v.expectedLen & " elements, got " & $v.actualLen & suffix,
      "",
    )
  of svkFieldParserFailed:
    return validationError(v.inner.typeName, v.inner.message & suffix, v.inner.value)
  of svkConflictingFields:
    return validationError(
      rootType,
      "cannot specify both " & v.conflictKeyA & " and " & v.conflictKeyB & " (" &
        v.conflictRule & ")" & suffix,
      "",
    )
  of svkEnumNotRecognised:
    return validationError(
      rootType, "unknown " & v.enumTypeLabel & ": " & v.rawValue & suffix, v.rawValue
    )
  of svkDepthExceeded:
    return validationError(
      rootType, "maximum nesting depth (" & $v.maxDepth & ") exceeded" & suffix, ""
    )

# =============================================================================
# Shared serde helpers
# =============================================================================

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
  var out0 = newSeqOfCap[T](node.elems.len)
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

# --- toJson/fromJson: UriTemplate (case-object; manual ser/de) ---

func toJson*(x: UriTemplate): JsonNode =
  ## Serialise a parsed URI template to its lossless source string.
  return %($x)

func fromJson*(
    t: typedesc[UriTemplate], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[UriTemplate, SerdeViolation] =
  ## Deserialise a JSON string through ``parseUriTemplate``. Malformed
  ## templates (unmatched braces, empty ``{}``, invalid variable chars)
  ## surface as ``ValidationError`` wrapped by ``wrapInner``.
  discard $t # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return wrapInner(parseUriTemplate(node.getStr("")), path)

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
