# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the BodyPartPath / BodyPartLocation / error-path-depth
## triad (Part E §6.1.5c scenarios 37p–37r). These value types underpin
## ``ebcBodyPartHeaderDuplicate.where`` reporting: the location of a
## constraint violation inside a body tree.

{.push raises: [].}

import std/tables

import jmap_client/mail/body
import jmap_client/mail/email_blueprint
import jmap_client/mail/headers
import jmap_client/identifiers
import jmap_client/validation

import ../../massertions
import ../../mfixtures

block discriminantDistinguishesSameBytes: # §6.1.5c scenario 37p
  # BodyPartLocation's discriminant is load-bearing — two locations
  # whose payload bytes happen to coincide (partId "p" vs blobId "p")
  # remain distinct because the kind differs. K-3 equality enforces
  # this at the discriminant layer before any field read.
  let inline =
    BodyPartLocation(kind: bplInline, partId: parsePartIdFromServer("p").get())
  let blob = BodyPartLocation(kind: bplBlobRef, blobId: parseBlobId("p").get())
  doAssert not bodyPartLocationEq(inline, blob),
    "discriminant must distinguish identical byte payloads"
  # Self-equality preserved on both sides.
  doAssert bodyPartLocationEq(inline, inline)
  doAssert bodyPartLocationEq(blob, blob)

block depthFivePathEncoding: # §6.1.5c scenario 37q
  # Build a spine with a multipart at depth 5 (path @[0,0,0,0,0]) that
  # carries a ``content-type`` extraHeaders entry colliding with its
  # own domain-field header set. ``walkBodyPartDuplicates`` emits the
  # single violation at that path.
  var targetExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  targetExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
  let innermostLeaf = makeBlueprintBodyPartInline()
  let targetMp = makeBlueprintBodyPartMultipart(
    subParts = @[innermostLeaf], extraHeaders = targetExtra
  )
  # Wrap ``targetMp`` in 5 more multiparts so its position in the tree
  # is exactly @[0, 0, 0, 0, 0] relative to the root (``structuredBody``
  # starts path walks at ``@[]`` on the root).
  var spine = targetMp
  for _ in 0 ..< 5:
    spine = makeBlueprintBodyPartMultipart(subParts = @[spine])
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(spine)
  )
  assertBlueprintErrCount res, 1
  assertBlueprintErr res, ebcBodyPartHeaderDuplicate
  # Direct path inspection — not via K-4's borrowed ``==`` because we
  # want element-wise pinning per design §6.1.5c sc 37q.
  var hit = false
  for e in res.unsafeError.items:
    if e.constraint == ebcBodyPartHeaderDuplicate and e.where.kind == bplMultipart:
      assertEq e.where.path.len, 5
      for i in 0 .. 4:
        assertEq e.where.path[i], 0
      hit = true
  doAssert hit, "expected a single bplMultipart duplicate at depth 5"

block depthCouplingInvariantSampled: # §6.1.5c scenario 37r
  # Spot-check the property 97d invariant (``where.path.len <=
  # MaxBodyPartDepth``) against three independent triggers: 37q's
  # depth-5 case reconstructed here, a 7g-style depth-2 case, and
  # a 7k-style flat-attachments path. A runtime sample, not a
  # proof — the structural bound is argued in the design doc.

  # Trigger A — depth-5 multipart (mirrors 37q).
  block:
    var extra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    extra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
    let target = makeBlueprintBodyPartMultipart(
      subParts = @[makeBlueprintBodyPartInline()], extraHeaders = extra
    )
    var spine = target
    for _ in 0 ..< 5:
      spine = makeBlueprintBodyPartMultipart(subParts = @[spine])
    let res = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(spine)
    )
    assertErr res
    for e in res.unsafeError.items:
      if e.where.kind == bplMultipart:
        assertLe e.where.path.len, MaxBodyPartDepth

  # Trigger B — depth-2 multipart (mirrors Step 15 sc 7g).
  block:
    var extra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    extra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
    let inner = makeBlueprintBodyPartMultipart(
      subParts = @[makeBlueprintBodyPartInline()], extraHeaders = extra
    )
    let mid =
      makeBlueprintBodyPartMultipart(subParts = @[makeBlueprintBodyPartInline(), inner])
    let root = makeBlueprintBodyPartMultipart(subParts = @[mid])
    let res = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    assertErr res
    for e in res.unsafeError.items:
      if e.where.kind == bplMultipart:
        assertLe e.where.path.len, MaxBodyPartDepth

  # Trigger C — flat-body attachments[1] multipart (mirrors sc 7k).
  block:
    var extra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    extra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
    let offender = makeBlueprintBodyPartMultipart(
      subParts = @[makeBlueprintBodyPartInline()], extraHeaders = extra
    )
    let body = makeFlatBody(
      attachments = @[makeBlueprintBodyPartBlobRef(blobId = makeBlobId("a0")), offender]
    )
    let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), body = body)
    assertErr res
    for e in res.unsafeError.items:
      if e.where.kind == bplMultipart:
        assertLe e.where.path.len, MaxBodyPartDepth
