# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for VacationResponse entity (RFC 8621 section 7).

{.push raises: [].}

import std/json

import ../serde
import ../types
import ./vacation

# =============================================================================
# Helpers
# =============================================================================

func parseOptUtcDate(
    node: JsonNode, key: string
): Result[Opt[UTCDate], ValidationError] =
  ## Parse an optional UTCDate field. Absent or null yields Opt.none;
  ## JString yields Opt.some with parsed value; other types rejected.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(UTCDate))
  ?checkJsonKind(field, JString, "VacationResponse", key & " must be string")
  let d = ?UTCDate.fromJson(field)
  return ok(Opt.some(d))

func parseOptString(node: JsonNode, key: string): Opt[string] =
  ## Parse an optional string field. Absent, null, or non-string yields none.
  let field = node{key}
  if field.isNil or field.kind == JNull or field.kind != JString:
    return Opt.none(string)
  return Opt.some(field.getStr(""))

# =============================================================================
# Helpers — toJson
# =============================================================================

func emitOptUtcDate(node: JsonNode, key: string, opt: Opt[UTCDate]) =
  ## Emits an optional UTCDate field as its serialised value or null.
  for val in opt:
    node[key] = val.toJson()
    return
  node[key] = newJNull()

func emitOptString(node: JsonNode, key: string, opt: Opt[string]) =
  ## Emits an optional string field as its value or null.
  for val in opt:
    node[key] = %val
    return
  node[key] = newJNull()

# =============================================================================
# VacationResponse
# =============================================================================

func toJson*(vr: VacationResponse): JsonNode =
  ## Serialise VacationResponse to JSON. Emits the singleton id field in the
  ## JSON output even though the Nim type has no id field.
  var node = newJObject()
  node["id"] = %VacationResponseSingletonId
  node["isEnabled"] = %vr.isEnabled
  node.emitOptUtcDate("fromDate", vr.fromDate)
  node.emitOptUtcDate("toDate", vr.toDate)
  node.emitOptString("subject", vr.subject)
  node.emitOptString("textBody", vr.textBody)
  node.emitOptString("htmlBody", vr.htmlBody)
  return node

func fromJson*(
    T: typedesc[VacationResponse], node: JsonNode
): Result[VacationResponse, ValidationError] =
  ## Deserialise JSON object to VacationResponse. Validates the singleton id
  ## field and required isEnabled boolean. Optional date and string fields
  ## default to Opt.none when absent or null.
  ?checkJsonKind(node, JObject, $T)
  ?checkJsonKind(node{"id"}, JString, $T, "missing or invalid id")
  if node{"id"}.getStr("") != VacationResponseSingletonId:
    return err(parseError($T, "id must be \"singleton\""))
  ?checkJsonKind(node{"isEnabled"}, JBool, $T, "missing or invalid isEnabled")
  let isEnabled = node{"isEnabled"}.getBool(false)
  let fromDate = ?parseOptUtcDate(node, "fromDate")
  let toDate = ?parseOptUtcDate(node, "toDate")
  let subject = parseOptString(node, "subject")
  let textBody = parseOptString(node, "textBody")
  let htmlBody = parseOptString(node, "htmlBody")
  return ok(
    VacationResponse(
      isEnabled: isEnabled,
      fromDate: fromDate,
      toDate: toDate,
      subject: subject,
      textBody: textBody,
      htmlBody: htmlBody,
    )
  )
