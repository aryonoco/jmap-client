# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared serialisation helpers and primitive/identifier type ser/de pairs.
## All domain serde modules import this module for the shared helpers.

{.push raises: [].}

import std/json
import std/options

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

func collectExtras*(node: JsonNode, knownKeys: openArray[string]): Option[JsonNode] =
  ## Collect non-standard fields from a JSON object into Option[JsonNode].
  ## Returns none if no extra fields exist.
  ## Precondition: caller has verified node.kind == JObject.
  var extras = newJObject()
  var found = false
  for key, val in node.pairs:
    if key notin knownKeys:
      extras[key] = val
      found = true
  if found:
    some(extras)
  else:
    none(JsonNode)

# --- toJson: distinct string types ---

func toJson*(x: Id): JsonNode =
  ## Serialise Id to JSON string.
  %(string(x))

func toJson*(x: AccountId): JsonNode =
  ## Serialise AccountId to JSON string.
  %(string(x))

func toJson*(x: JmapState): JsonNode =
  ## Serialise JmapState to JSON string.
  %(string(x))

func toJson*(x: MethodCallId): JsonNode =
  ## Serialise MethodCallId to JSON string.
  %(string(x))

func toJson*(x: CreationId): JsonNode =
  ## Serialise CreationId to JSON string.
  %(string(x))

func toJson*(x: UriTemplate): JsonNode =
  ## Serialise UriTemplate to JSON string.
  %(string(x))

func toJson*(x: PropertyName): JsonNode =
  ## Serialise PropertyName to JSON string.
  %(string(x))

func toJson*(x: Date): JsonNode =
  ## Serialise Date to JSON string.
  %(string(x))

func toJson*(x: UTCDate): JsonNode =
  ## Serialise UTCDate to JSON string.
  %(string(x))

# --- toJson: distinct int types ---

func toJson*(x: UnsignedInt): JsonNode =
  ## Serialise UnsignedInt to JSON integer.
  %(int64(x))

func toJson*(x: JmapInt): JsonNode =
  ## Serialise JmapInt to JSON integer.
  %(int64(x))

# --- fromJson: distinct string types ---

func fromJson*(T: typedesc[Id], node: JsonNode): Result[Id, ValidationError] =
  ## Deserialise a JSON string to Id (lenient: server-assigned).
  ?checkJsonKind(node, JString, $T)
  parseIdFromServer(node.getStr(""))

func fromJson*(
    T: typedesc[AccountId], node: JsonNode
): Result[AccountId, ValidationError] =
  ## Deserialise a JSON string to AccountId (lenient: server-assigned).
  ?checkJsonKind(node, JString, $T)
  parseAccountId(node.getStr(""))

func fromJson*(
    T: typedesc[JmapState], node: JsonNode
): Result[JmapState, ValidationError] =
  ## Deserialise a JSON string to JmapState.
  ?checkJsonKind(node, JString, $T)
  parseJmapState(node.getStr(""))

func fromJson*(
    T: typedesc[MethodCallId], node: JsonNode
): Result[MethodCallId, ValidationError] =
  ## Deserialise a JSON string to MethodCallId.
  ?checkJsonKind(node, JString, $T)
  parseMethodCallId(node.getStr(""))

func fromJson*(
    T: typedesc[CreationId], node: JsonNode
): Result[CreationId, ValidationError] =
  ## Deserialise a JSON string to CreationId.
  ?checkJsonKind(node, JString, $T)
  parseCreationId(node.getStr(""))

func fromJson*(
    T: typedesc[UriTemplate], node: JsonNode
): Result[UriTemplate, ValidationError] =
  ## Deserialise a JSON string to UriTemplate.
  ?checkJsonKind(node, JString, $T)
  parseUriTemplate(node.getStr(""))

func fromJson*(
    T: typedesc[PropertyName], node: JsonNode
): Result[PropertyName, ValidationError] =
  ## Deserialise a JSON string to PropertyName.
  ?checkJsonKind(node, JString, $T)
  parsePropertyName(node.getStr(""))

func fromJson*(T: typedesc[Date], node: JsonNode): Result[Date, ValidationError] =
  ## Deserialise a JSON string to Date (RFC 3339 structural validation).
  ?checkJsonKind(node, JString, $T)
  parseDate(node.getStr(""))

func fromJson*(T: typedesc[UTCDate], node: JsonNode): Result[UTCDate, ValidationError] =
  ## Deserialise a JSON string to UTCDate (RFC 3339, Z suffix required).
  ?checkJsonKind(node, JString, $T)
  parseUtcDate(node.getStr(""))

# --- fromJson: distinct int types ---

func fromJson*(
    T: typedesc[UnsignedInt], node: JsonNode
): Result[UnsignedInt, ValidationError] =
  ## Deserialise a JSON integer to UnsignedInt (0..2^53-1).
  ?checkJsonKind(node, JInt, $T)
  parseUnsignedInt(node.getBiggestInt(0))

func fromJson*(T: typedesc[JmapInt], node: JsonNode): Result[JmapInt, ValidationError] =
  ## Deserialise a JSON integer to JmapInt (-(2^53-1)..2^53-1).
  ?checkJsonKind(node, JInt, $T)
  parseJmapInt(node.getBiggestInt(0))

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
