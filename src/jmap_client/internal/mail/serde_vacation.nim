# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for VacationResponse entity (RFC 8621 section 7).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../serialisation/serde_field_echo
import ../../types
import ./vacation

# =============================================================================
# Helpers
# =============================================================================

func parseOptUtcDate(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[UTCDate], SerdeViolation] =
  ## Parse an optional UTCDate field. Absent or null yields Opt.none;
  ## JString yields Opt.some with parsed value; other types rejected.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(UTCDate))
  ?expectKind(field, JString, path / key)
  let d = ?UTCDate.fromJson(field, path / key)
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
    T: typedesc[VacationResponse], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[VacationResponse, SerdeViolation] =
  ## Deserialise JSON object to VacationResponse. Validates the singleton id
  ## field and required isEnabled boolean. Optional date and string fields
  ## default to Opt.none when absent or null.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  if idNode.getStr("") != VacationResponseSingletonId:
    return err(
      SerdeViolation(
        kind: svkEnumNotRecognised,
        path: path / "id",
        enumTypeLabel: "VacationResponse id",
        rawValue: idNode.getStr(""),
      )
    )
  let isEnabledNode = ?fieldJBool(node, "isEnabled", path)
  let isEnabled = isEnabledNode.getBool(false)
  let fromDate = ?parseOptUtcDate(node, "fromDate", path)
  let toDate = ?parseOptUtcDate(node, "toDate", path)
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

# =============================================================================
# VacationResponseUpdate
# =============================================================================

func toJson*(u: VacationResponseUpdate): (string, JsonNode) =
  ## Emit the ``(wire-key, wire-value)`` pair for a single VacationResponse
  ## update. RFC 8621 §8 settable properties are whole-value replace.
  case u.kind
  of vruSetIsEnabled:
    ("isEnabled", %u.isEnabled)
  of vruSetFromDate:
    ("fromDate", u.fromDate.optToJsonOrNull())
  of vruSetToDate:
    ("toDate", u.toDate.optToJsonOrNull())
  of vruSetSubject:
    ("subject", u.subject.optStringToJsonOrNull())
  of vruSetTextBody:
    ("textBody", u.textBody.optStringToJsonOrNull())
  of vruSetHtmlBody:
    ("htmlBody", u.htmlBody.optStringToJsonOrNull())

func toJson*(us: VacationResponseUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initVacationResponseUpdateSet`` has already rejected duplicate
  ## target properties, so blind aggregation cannot shadow.
  var node = newJObject()
  for u in seq[VacationResponseUpdate](us):
    let (key, value) = u.toJson()
    node[key] = value
  return node

# =============================================================================
# PartialVacationResponse (A4 + A3.6)
# =============================================================================

func fromJson*(
    T: typedesc[PartialVacationResponse],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[PartialVacationResponse, SerdeViolation] =
  ## Deserialise a partial VacationResponse echo (RFC 8621 §7). Lenient
  ## on missing fields; strict on wrong-kind present fields (D4).
  discard $T
  ?expectKind(node, JObject, path)
  let isEnabled = ?parsePartialOptField[bool](node, "isEnabled", path)
  let fromDate = ?parsePartialFieldEcho[UTCDate](node, "fromDate", path)
  let toDate = ?parsePartialFieldEcho[UTCDate](node, "toDate", path)
  let subject = ?parsePartialFieldEcho[string](node, "subject", path)
  let textBody = ?parsePartialFieldEcho[string](node, "textBody", path)
  let htmlBody = ?parsePartialFieldEcho[string](node, "htmlBody", path)
  return ok(
    PartialVacationResponse(
      isEnabled: isEnabled,
      fromDate: fromDate,
      toDate: toDate,
      subject: subject,
      textBody: textBody,
      htmlBody: htmlBody,
    )
  )

func toJson*(p: PartialVacationResponse): JsonNode =
  ## Emit a partial VacationResponse echo — ``fekAbsent`` and
  ## ``Opt.none`` omit the key entirely.
  var node = newJObject()
  for v in p.isEnabled:
    node["isEnabled"] = v.toJson()
  emitPartialFieldEcho[UTCDate](node, "fromDate", p.fromDate)
  emitPartialFieldEcho[UTCDate](node, "toDate", p.toDate)
  emitPartialFieldEcho[string](node, "subject", p.subject)
  emitPartialFieldEcho[string](node, "textBody", p.textBody)
  emitPartialFieldEcho[string](node, "htmlBody", p.htmlBody)
  return node
