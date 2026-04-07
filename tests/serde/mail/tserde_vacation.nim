# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for VacationResponse entity (scenarios 38-44 + edge cases).

import std/json

import jmap_client/mail/vacation
import jmap_client/mail/serde_vacation
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. VacationResponse fromJson =============

block fromJsonAllFields: # scenario 38
  let node = %*{
    "id": "singleton",
    "isEnabled": true,
    "fromDate": "2024-01-15T10:30:00Z",
    "toDate": "2024-02-15T10:30:00Z",
    "subject": "Out of office",
    "textBody": "I am on holiday.",
    "htmlBody": "<p>I am on holiday.</p>",
  }
  let res = VacationResponse.fromJson(node)
  assertOk res
  let vr = res.get()
  assertEq vr.isEnabled, true
  assertSome vr.fromDate
  assertEq $vr.fromDate.get(), "2024-01-15T10:30:00Z"
  assertSome vr.toDate
  assertEq $vr.toDate.get(), "2024-02-15T10:30:00Z"
  assertSomeEq vr.subject, "Out of office"
  assertSomeEq vr.textBody, "I am on holiday."
  assertSomeEq vr.htmlBody, "<p>I am on holiday.</p>"

block fromJsonOptionalFieldsNull: # scenario 39
  let node = %*{
    "id": "singleton",
    "isEnabled": false,
    "fromDate": nil,
    "toDate": nil,
    "subject": nil,
    "textBody": nil,
    "htmlBody": nil,
  }
  let res = VacationResponse.fromJson(node)
  assertOk res
  let vr = res.get()
  assertEq vr.isEnabled, false
  assertNone vr.fromDate
  assertNone vr.toDate
  assertNone vr.subject
  assertNone vr.textBody
  assertNone vr.htmlBody

block fromJsonWrongId: # scenario 40
  let node = %*{"id": "wrong", "isEnabled": true}
  assertErr VacationResponse.fromJson(node)

block fromJsonIdAbsent: # scenario 41
  let node = %*{"isEnabled": true}
  assertErr VacationResponse.fromJson(node)

block toJsonEmitsSingletonId: # scenario 42
  let vr = VacationResponse(
    isEnabled: false,
    fromDate: Opt.none(UTCDate),
    toDate: Opt.none(UTCDate),
    subject: Opt.none(string),
    textBody: Opt.none(string),
    htmlBody: Opt.none(string),
  )
  let node = vr.toJson()
  assertJsonFieldEq node, "id", %"singleton"

# ============= B. VacationResponse round-trip =============

block roundTrip: # scenario 43
  let fd = parseUtcDate("2024-01-15T10:30:00Z").get()
  let td = parseUtcDate("2024-02-15T10:30:00Z").get()
  let vr = VacationResponse(
    isEnabled: true,
    fromDate: Opt.some(fd),
    toDate: Opt.some(td),
    subject: Opt.some("Away"),
    textBody: Opt.some("Gone fishing."),
    htmlBody: Opt.some("<p>Gone fishing.</p>"),
  )
  let roundTripped = VacationResponse.fromJson(vr.toJson()).get()
  assertEq roundTripped.isEnabled, vr.isEnabled
  assertSome roundTripped.fromDate
  assertEq $roundTripped.fromDate.get(), $vr.fromDate.get()
  assertSome roundTripped.toDate
  assertEq $roundTripped.toDate.get(), $vr.toDate.get()
  assertSomeEq roundTripped.subject, "Away"
  assertSomeEq roundTripped.textBody, "Gone fishing."
  assertSomeEq roundTripped.htmlBody, "<p>Gone fishing.</p>"

# ============= C. VacationResponse type constraints =============

block noIdField: # scenario 44
  assertNotCompiles(
    block:
      var vr: VacationResponse
      discard vr.id
  )

# ============= D. VacationResponse fromJson — validation =============

block fromJsonNotObject:
  assertErr VacationResponse.fromJson(%"string")
  assertErr VacationResponse.fromJson(newJArray())

block fromJsonMissingIsEnabled:
  let node = %*{"id": "singleton"}
  assertErr VacationResponse.fromJson(node)

block fromJsonWrongTypeIsEnabled:
  let node = %*{"id": "singleton", "isEnabled": "true"}
  assertErr VacationResponse.fromJson(node)

block fromJsonInvalidUtcDate:
  let node = %*{"id": "singleton", "isEnabled": true, "fromDate": "not-a-date"}
  assertErr VacationResponse.fromJson(node)

# ============= E. VacationResponse toJson =============

block toJsonAllNone:
  let vr = VacationResponse(
    isEnabled: false,
    fromDate: Opt.none(UTCDate),
    toDate: Opt.none(UTCDate),
    subject: Opt.none(string),
    textBody: Opt.none(string),
    htmlBody: Opt.none(string),
  )
  let node = vr.toJson()
  assertJsonFieldEq node, "isEnabled", %false
  assertJsonFieldEq node, "fromDate", newJNull()
  assertJsonFieldEq node, "toDate", newJNull()
  assertJsonFieldEq node, "subject", newJNull()
  assertJsonFieldEq node, "textBody", newJNull()
  assertJsonFieldEq node, "htmlBody", newJNull()
