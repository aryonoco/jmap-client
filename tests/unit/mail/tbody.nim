# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for body sub-types (scenarios 70–76, 73a, 108a–108b, 125a–125d).

import jmap_client/internal/mail/body
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers

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

# Each of these four named a field that must not sit beside the content it
# contradicts — a blob reference next to inline bytes, children next to a
# leaf. They used to pin that pairing as the sole defect in an otherwise
# valid literal (R3-3). Since C12 both types are sealed: every field,
# discriminators included, is module-private and ``raw*``-prefixed, so no
# literal survives long enough to be judged on its branch. Each scenario is
# therefore restated against the rejection the seal actually issues — the
# ``raw*`` field it names is not writable from here, the same claim the
# ``treject_c12_*`` files pin by error message — and paired with the answer
# the accessors give in its place, so a demoted accessor or a re-opened
# field breaks the scenario rather than passing it vacuously.

testCase blobIdOnInline: # scenario 125a
  # A blob reference cannot be bolted onto inline content: the field is
  # unwritable from here, and an inline leaf answers "no blob" when asked.
  assertNotCompiles BlueprintLeafPart(rawBlobId: parseBlobId("abc").get())
  let inlineLeaf =
    inlinePart(parsePartIdFromServer("1").get(), "text/plain", "hello").leaf
  assertSome inlineLeaf
  assertNone inlineLeaf.get().blobId

testCase charsetOnInline: # scenario 125b
  # ``charset`` describes the bytes of an uploaded blob, so it belongs to a
  # blob-ref leaf only: unwritable from here, absent on an inline leaf, and
  # reachable solely through the blob-ref constructor's own parameter.
  assertNotCompiles BlueprintLeafPart(rawCharset: Opt.some("utf-8"))
  let inlineLeaf =
    inlinePart(parsePartIdFromServer("1").get(), "text/plain", "hello").leaf
  assertSome inlineLeaf
  assertNone inlineLeaf.get().charset
  let blobLeaf = blobRefPart(
    parseBlobId("abc").get(), "application/pdf", charset = Opt.some("utf-8")
  ).leaf
  assertSome blobLeaf
  assertSomeEq blobLeaf.get().charset, "utf-8"

testCase partIdOnMultipartBlueprint: # scenario 125c
  # A container has no identifier of its own: the identifier field is
  # unwritable from here, ``multipartPart`` takes no identifier argument,
  # and a container exposes no leaf that could carry one.
  assertNotCompiles BlueprintLeafPart(rawPartId: parsePartIdFromServer("1").get())
  assertNone multipartPart("multipart/mixed", @[]).leaf

testCase subPartsOnLeafBlueprint: # scenario 125d
  # Children belong to containers: the child list is unwritable from here,
  # and a leaf reports itself as a leaf with no children rather than as a
  # container that happens to be empty.
  let child = inlinePart(parsePartIdFromServer("1").get(), "text/plain", "hello")
  assertNotCompiles BlueprintBodyPart(rawSubParts: @[child])
  assertFalse child.isMultipart, "an inline leaf is not a container"
  assertLen child.subParts, 0
