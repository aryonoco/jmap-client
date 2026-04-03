# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared serialisation helpers and primitive/identifier type ser/de pairs.
## All domain serde modules import this module for the shared helpers.

import std/json
import std/options

import ./types

proc parseError*(typeName, message: string): ref ValidationError =
  ## Convenience constructor for deserialisation errors.
  ## Sets value to empty — JSON context is captured in message.
  newValidationError(typeName, message, "")

proc checkJsonKind*(
    node: JsonNode, expected: JsonNodeKind, typeName: string, message: string = ""
) =
  ## Validates JsonNodeKind before extraction. Raises ValidationError on mismatch.
  let checkMsg =
    if message.len > 0:
      message
    else:
      "expected JSON " & $expected
  if node.isNil or node.kind != expected:
    raise newValidationError(typeName, checkMsg, "")

proc collectExtras*(node: JsonNode, knownKeys: openArray[string]): Option[JsonNode] =
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

proc toJson*(x: Id): JsonNode =
  ## Serialise Id to JSON string.
  %(string(x))

proc toJson*(x: AccountId): JsonNode =
  ## Serialise AccountId to JSON string.
  %(string(x))

proc toJson*(x: JmapState): JsonNode =
  ## Serialise JmapState to JSON string.
  %(string(x))

proc toJson*(x: MethodCallId): JsonNode =
  ## Serialise MethodCallId to JSON string.
  %(string(x))

proc toJson*(x: CreationId): JsonNode =
  ## Serialise CreationId to JSON string.
  %(string(x))

proc toJson*(x: UriTemplate): JsonNode =
  ## Serialise UriTemplate to JSON string.
  %(string(x))

proc toJson*(x: PropertyName): JsonNode =
  ## Serialise PropertyName to JSON string.
  %(string(x))

proc toJson*(x: Date): JsonNode =
  ## Serialise Date to JSON string.
  %(string(x))

proc toJson*(x: UTCDate): JsonNode =
  ## Serialise UTCDate to JSON string.
  %(string(x))

# --- toJson: distinct int types ---

proc toJson*(x: UnsignedInt): JsonNode =
  ## Serialise UnsignedInt to JSON integer.
  %(int64(x))

proc toJson*(x: JmapInt): JsonNode =
  ## Serialise JmapInt to JSON integer.
  %(int64(x))

# --- fromJson: distinct string types ---

proc fromJson*(T: typedesc[Id], node: JsonNode): Id =
  ## Deserialise a JSON string to Id (lenient: server-assigned).
  checkJsonKind(node, JString, $T)
  parseIdFromServer(node.getStr(""))

proc fromJson*(T: typedesc[AccountId], node: JsonNode): AccountId =
  ## Deserialise a JSON string to AccountId (lenient: server-assigned).
  checkJsonKind(node, JString, $T)
  parseAccountId(node.getStr(""))

proc fromJson*(T: typedesc[JmapState], node: JsonNode): JmapState =
  ## Deserialise a JSON string to JmapState.
  checkJsonKind(node, JString, $T)
  parseJmapState(node.getStr(""))

proc fromJson*(T: typedesc[MethodCallId], node: JsonNode): MethodCallId =
  ## Deserialise a JSON string to MethodCallId.
  checkJsonKind(node, JString, $T)
  parseMethodCallId(node.getStr(""))

proc fromJson*(T: typedesc[CreationId], node: JsonNode): CreationId =
  ## Deserialise a JSON string to CreationId.
  checkJsonKind(node, JString, $T)
  parseCreationId(node.getStr(""))

proc fromJson*(T: typedesc[UriTemplate], node: JsonNode): UriTemplate =
  ## Deserialise a JSON string to UriTemplate.
  checkJsonKind(node, JString, $T)
  parseUriTemplate(node.getStr(""))

proc fromJson*(T: typedesc[PropertyName], node: JsonNode): PropertyName =
  ## Deserialise a JSON string to PropertyName.
  checkJsonKind(node, JString, $T)
  parsePropertyName(node.getStr(""))

proc fromJson*(T: typedesc[Date], node: JsonNode): Date =
  ## Deserialise a JSON string to Date (RFC 3339 structural validation).
  checkJsonKind(node, JString, $T)
  parseDate(node.getStr(""))

proc fromJson*(T: typedesc[UTCDate], node: JsonNode): UTCDate =
  ## Deserialise a JSON string to UTCDate (RFC 3339, Z suffix required).
  checkJsonKind(node, JString, $T)
  parseUtcDate(node.getStr(""))

# --- fromJson: distinct int types ---

proc fromJson*(T: typedesc[UnsignedInt], node: JsonNode): UnsignedInt =
  ## Deserialise a JSON integer to UnsignedInt (0..2^53-1).
  checkJsonKind(node, JInt, $T)
  parseUnsignedInt(node.getBiggestInt(0))

proc fromJson*(T: typedesc[JmapInt], node: JsonNode): JmapInt =
  ## Deserialise a JSON integer to JmapInt (-(2^53-1)..2^53-1).
  checkJsonKind(node, JInt, $T)
  parseJmapInt(node.getBiggestInt(0))

# --- toJson/fromJson: MaxChanges ---

proc toJson*(x: MaxChanges): JsonNode =
  ## Serialise MaxChanges to JSON integer.
  %(int64(UnsignedInt(x)))

proc fromJson*(T: typedesc[MaxChanges], node: JsonNode): MaxChanges =
  ## Deserialise a JSON integer to MaxChanges (must be > 0).
  checkJsonKind(node, JInt, $T)
  let ui = parseUnsignedInt(node.getBiggestInt(0))
  parseMaxChanges(ui)
