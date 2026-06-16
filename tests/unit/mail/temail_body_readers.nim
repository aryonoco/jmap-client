# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 Email body readers: bodyValue, leafTextParts,
## decodedTextBody, and the textBodies fetch-options helper (RFC 8621 §4.1.4).

{.push raises: [].}

import std/tables

import jmap_client/internal/mail/email
import jmap_client/internal/mail/body
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/validation # re-exports nim-results (Opt/.get)

import ../../massertions
import ../../mtestblock

proc pid(s: string): PartId =
  ## A PartId parsed from the given server-form string.
  parsePartIdFromServer(s).get()

proc textLeaf(contentType, partId: string): EmailBodyPart =
  ## A non-multipart leaf with the given content type and partId.
  EmailBodyPart(
    headers: @[],
    contentType: contentType,
    size: parseUnsignedInt(0).get(),
    isMultipart: false,
    partId: pid(partId),
    blobId: parseBlobId("b" & partId).get(),
  )

proc emailWith(
    textBody: seq[EmailBodyPart], values: seq[(PartId, EmailBodyValue)]
): Email =
  ## An Email carrying the given ``textBody`` parts and ``bodyValues`` entries.
  Email(textBody: textBody, bodyValues: values.toTable)

proc multipartNode(contentType: string, subParts: seq[EmailBodyPart]): EmailBodyPart =
  ## A minimal multipart node wrapping the given child parts.
  EmailBodyPart(
    headers: @[],
    contentType: contentType,
    size: parseUnsignedInt(0).get(),
    isMultipart: true,
    subParts: subParts,
  )

testCase bodyValuePresent:
  let p = pid("1")
  let e =
    emailWith(@[textLeaf("text/plain", "1")], @[(p, EmailBodyValue(value: "hello"))])
  assertSomeEq e.bodyValue(p), EmailBodyValue(value: "hello")

testCase bodyValueAbsentIsNone:
  let e = emailWith(
    @[textLeaf("text/plain", "1")], @[(pid("1"), EmailBodyValue(value: "hello"))]
  )
  assertNone e.bodyValue(pid("missing"))

testCase bodyValueRoundTripsFlags:
  let p = pid("1")
  let e = emailWith(
    @[textLeaf("text/plain", "1")],
    @[(p, EmailBodyValue(value: "x", isTruncated: true, isEncodingProblem: true))],
  )
  let got = e.bodyValue(p)
  assertSome got
  for v in got:
    assertEq v.isTruncated, true
    assertEq v.isEncodingProblem, true

testCase decodedTextBodyJoinsTextPlain:
  let e = emailWith(
    @[textLeaf("text/plain", "1"), textLeaf("text/plain", "2")],
    @[
      (pid("1"), EmailBodyValue(value: "foo")), (pid("2"), EmailBodyValue(value: "bar"))
    ],
  )
  assertSomeEq e.decodedTextBody(), "foobar"

testCase decodedTextBodySkipsHtml:
  let e = emailWith(
    @[textLeaf("text/html", "1")], @[(pid("1"), EmailBodyValue(value: "<p>hi</p>"))]
  )
  assertNone e.decodedTextBody()

testCase decodedTextBodyNoneWhenNotFetched:
  let e = emailWith(
    @[textLeaf("text/plain", "1")], @[(pid("other"), EmailBodyValue(value: "x"))]
  )
  assertNone e.decodedTextBody()

testCase leafTextPartsYieldsTextBodyLeaves:
  let e = emailWith(
    @[textLeaf("text/plain", "1"), textLeaf("text/html", "2")],
    newSeq[(PartId, EmailBodyValue)](),
  )
  var seen: seq[string] = @[]
  for part in e.leafTextParts():
    case part.isMultipart
    of false:
      seen.add($part.partId)
    of true:
      discard
  assertEq seen, @["1", "2"]

testCase leafTextPartsSkipsNestedMultipart:
  let e = emailWith(
    @[
      multipartNode("multipart/mixed", @[textLeaf("text/plain", "nested")]),
      textLeaf("text/plain", "leaf"),
    ],
    newSeq[(PartId, EmailBodyValue)](),
  )
  var seen: seq[string] = @[]
  for part in e.leafTextParts():
    case part.isMultipart
    of false:
      seen.add($part.partId)
    of true:
      discard
  assertEq seen, @["leaf"]

testCase textBodiesSetsTextScopeAndCap:
  let opts = textBodies(parseUnsignedInt(1024).get())
  assertEq opts.fetchBodyValues, bvsText
  assertSomeEq opts.maxBodyValueBytes, parseUnsignedInt(1024).get()

testCase textBodiesNoCap:
  let opts = textBodies()
  assertEq opts.fetchBodyValues, bvsText
  assertNone opts.maxBodyValueBytes
