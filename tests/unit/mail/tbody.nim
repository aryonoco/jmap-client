# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for body sub-types (scenarios 70–76, 73a, 108a–108b, 125a–125d).

import std/tables

import jmap_client/internal/mail/body
import jmap_client/internal/mail/headers
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

# ============= A. PartId (scenarios 70–76, 73a) =============

testCase parsePartIdValid: # scenario 70
  assertOk parsePartIdFromServer("1")

testCase parsePartIdEmpty: # scenario 71
  assertErrFields parsePartIdFromServer(""), "PartId", "must not be empty", ""

testCase parsePartIdControlChar: # scenario 72
  assertErr parsePartIdFromServer("abc\x1Fdef")

testCase partIdRoundTrip: # scenario 73
  let pid = parsePartIdFromServer("part-1").get()
  assertEq $pid, "part-1"
  assertEq pid, parsePartIdFromServer("part-1").get()

testCase partIdEquality: # scenario 73a
  let a = parsePartIdFromServer("test-id").get()
  let b = parsePartIdFromServer("test-id").get()
  assertEq a, b
  assertEq hash(a), hash(b)

testCase partIdLongValue: # scenario 74
  var long = ""
  for i in 0 ..< 500:
    long.add('a')
  assertOk parsePartIdFromServer(long)

testCase partIdUtf8: # scenario 75
  assertOk parsePartIdFromServer("\xC3\xA9\xC3\xA0\xC3\xBC")

testCase partIdTypicalFormats: # scenario 76
  assertOk parsePartIdFromServer("1")
  assertOk parsePartIdFromServer("1.2")
  assertOk parsePartIdFromServer("1.2.3")

# ============= B. EmailBodyPart compile-time (scenarios 108a–108b) =============

# Nim case objects enforce branch access at runtime (FieldDefect), not compile
# time. The assertNotCompiles tests verify that direct construction with wrong
# branch fields is rejected.

testCase partIdOnMultipart: # scenario 108a
  # Cannot construct a multipart with partId — the field does not exist on
  # the true branch.
  assertNotCompiles(
    EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "multipart/mixed",
      charset: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: parseUnsignedInt(0).get(),
      isMultipart: true,
      subParts: @[],
      partId: parsePartIdFromServer("1").get(),
    )
  )

testCase subPartsOnLeaf: # scenario 108b
  # Cannot construct a leaf with subParts.
  assertNotCompiles(
    EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "text/plain",
      charset: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: parseUnsignedInt(0).get(),
      isMultipart: false,
      partId: parsePartIdFromServer("1").get(),
      blobId: parseBlobId("abc").get(),
      subParts: @[],
    )
  )

# ============= C. BlueprintBodyPart compile-time (scenarios 125a–125d) =============

testCase blobIdOnInline: # scenario 125a
  assertNotCompiles(
    BlueprintBodyPart(
      contentType: "text/plain",
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      leaf: BlueprintLeafPart(
        source: bpsInline,
        partId: parsePartIdFromServer("1").get(),
        value: BlueprintBodyValue(value: ""),
      ),
      blobId: parseBlobId("abc").get(),
    )
  )

testCase charsetOnInline: # scenario 125b
  assertNotCompiles(
    BlueprintBodyPart(
      contentType: "text/plain",
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      leaf: BlueprintLeafPart(
        source: bpsInline,
        partId: parsePartIdFromServer("1").get(),
        value: BlueprintBodyValue(value: ""),
      ),
      charset: Opt.some("utf-8"),
    )
  )

testCase partIdOnMultipartBlueprint: # scenario 125c
  assertNotCompiles(
    BlueprintBodyPart(
      contentType: "multipart/mixed",
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: true,
      subParts: @[],
      partId: parsePartIdFromServer("1").get(),
    )
  )

testCase subPartsOnLeafBlueprint: # scenario 125d
  assertNotCompiles(
    BlueprintBodyPart(
      contentType: "text/plain",
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      leaf: BlueprintLeafPart(
        source: bpsInline,
        partId: parsePartIdFromServer("1").get(),
        value: BlueprintBodyValue(value: ""),
      ),
      subParts: @[],
    )
  )
