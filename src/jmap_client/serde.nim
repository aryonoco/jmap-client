# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared serialisation helpers and primitive/identifier type ser/de pairs.
## All domain serde modules import this module for the shared helpers.

{.push raises: [].}

import std/json

import ./types

func parseError*(typeName, message: string): ValidationError =
  ## Convenience constructor for deserialisation errors.
  ## Sets value to empty — JSON context is captured in message.
  validationError(typeName, message, "")

func checkJsonKind*(
    node: JsonNode, expected: JsonNodeKind, typeName: string, message: string = ""
): Result[void, ValidationError] =
  ## Validates JsonNodeKind before extraction. Returns err on mismatch.
  let checkMsg =
    if message.len > 0:
      message
    else:
      "expected JSON " & $expected
  if node.isNil:
    return err(validationError(typeName, checkMsg, ""))
  if node.kind != expected:
    return err(validationError(typeName, checkMsg, ""))
  ok()

func collectExtras*(node: JsonNode, knownKeys: openArray[string]): Opt[JsonNode] =
  ## Collect non-standard fields from a JSON object into Opt[JsonNode].
  ## Returns none if no extra fields exist.
  ## Precondition: caller has verified node.kind == JObject.
  var extras = newJObject()
  var found = false
  for key, val in node.pairs:
    if key notin knownKeys:
      extras[key] = val
      found = true
  if found:
    Opt.some(extras)
  else:
    Opt.none(JsonNode)

func optJsonField*(node: JsonNode, key: string, kind: JsonNodeKind): Opt[JsonNode] =
  ## Lenient field extraction: absent, null, or wrong kind -> none.
  ## Companion to checkJsonKind (strict: returns Result with error details).
  let child = node{key}
  if child.isNil or child.kind != kind:
    Opt.none(JsonNode)
  else:
    Opt.some(child)

# --- Serde templates for distinct types ---
#
# Each template generates a concrete toJson/fromJson overload. The parser
# parameter (untyped) is the smart constructor name for the target type.

template defineDistinctStringToJson*(T: typedesc) =
  ## Generates a ``toJson`` overload that serialises a distinct string type
  ## to a JSON string node.
  func toJson*(x: T): JsonNode =
    ## Serialise distinct string to JSON string.
    %(string(x))

template defineDistinctStringFromJson*(T: typedesc, parser: untyped) =
  ## Generates a ``fromJson`` overload that deserialises a JSON string node
  ## via the type's smart constructor (passed as ``parser``).
  func fromJson*(t: typedesc[T], node: JsonNode): Result[T, ValidationError] =
    ## Deserialise JSON string via the type's smart constructor.
    ?checkJsonKind(node, JString, $T)
    parser(node.getStr(""))

template defineDistinctIntToJson*(T: typedesc, Base: typedesc) =
  ## Generates a ``toJson`` overload that serialises a distinct int type
  ## to a JSON integer node via the given base integer type.
  func toJson*(x: T): JsonNode =
    ## Serialise distinct int to JSON integer.
    %(Base(x))

template defineDistinctIntFromJson*(T: typedesc, parser: untyped) =
  ## Generates a ``fromJson`` overload that deserialises a JSON integer node
  ## via the type's smart constructor (passed as ``parser``).
  func fromJson*(t: typedesc[T], node: JsonNode): Result[T, ValidationError] =
    ## Deserialise JSON integer via the type's smart constructor.
    ?checkJsonKind(node, JInt, $T)
    parser(node.getBiggestInt(0))

# --- toJson/fromJson: distinct string types ---

defineDistinctStringToJson(Id)
defineDistinctStringToJson(AccountId)
defineDistinctStringToJson(JmapState)
defineDistinctStringToJson(MethodCallId)
defineDistinctStringToJson(CreationId)
defineDistinctStringToJson(UriTemplate)
defineDistinctStringToJson(PropertyName)
defineDistinctStringToJson(Date)
defineDistinctStringToJson(UTCDate)

defineDistinctStringFromJson(Id, parseIdFromServer)
defineDistinctStringFromJson(AccountId, parseAccountId)
defineDistinctStringFromJson(JmapState, parseJmapState)
defineDistinctStringFromJson(MethodCallId, parseMethodCallId)
defineDistinctStringFromJson(CreationId, parseCreationId)
defineDistinctStringFromJson(UriTemplate, parseUriTemplate)
defineDistinctStringFromJson(PropertyName, parsePropertyName)
defineDistinctStringFromJson(Date, parseDate)
defineDistinctStringFromJson(UTCDate, parseUtcDate)

# --- toJson/fromJson: distinct int types ---

defineDistinctIntToJson(UnsignedInt, int64)
defineDistinctIntToJson(JmapInt, int64)

defineDistinctIntFromJson(UnsignedInt, parseUnsignedInt)
defineDistinctIntFromJson(JmapInt, parseJmapInt)

# --- toJson/fromJson: MaxChanges ---

func toJson*(x: MaxChanges): JsonNode =
  ## Serialise MaxChanges to JSON integer.
  %(int64(UnsignedInt(x)))

func fromJson*(
    T: typedesc[MaxChanges], node: JsonNode
): Result[MaxChanges, ValidationError] =
  ## Deserialise a JSON integer to MaxChanges (must be > 0).
  ?checkJsonKind(node, JInt, $T)
  let ui = ?parseUnsignedInt(node.getBiggestInt(0))
  parseMaxChanges(ui)
