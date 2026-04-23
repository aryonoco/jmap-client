# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``EmailBlueprint`` smart constructor, accessors, derived
## ``bodyValues``, ``BlueprintBodyValue`` single-field serde, and FFI
## value-type non-aliasing (Part E §6.1.1, §6.1.2, §6.1.7, §6.4.4).
##
## Scenarios exercising ``EmailBlueprint.toJson`` (§6.1.1 sc 18 full and
## §6.1.7 sc 50 full) are partial here and complete in Phase 4 Step 18
## (``tests/serde/mail/tserde_email_blueprint.nim``) once serde lands.

{.push raises: [].}

import std/json
import std/sets
import std/strutils
import std/tables

import jmap_client/mail/body
import jmap_client/mail/email_blueprint
import jmap_client/mail/headers
import jmap_client/mail/mailbox
import jmap_client/mail/serde_body
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# =============================================================================
# A. Smart-constructor, accessors, accumulated errors (§6.1.1, §6.1.2)
# =============================================================================

block minimalBlueprintDefaults: # §6.1.1 scenario 1
  let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet())
  assertBlueprintOkEq res, makeEmailBlueprint()

block publicNamingContract: # §6.1.1 scenario 1a
  let bp = makeEmailBlueprint()
  doAssert compiles(bp.fromAddr), "expected bp.fromAddr to compile"
  doAssert compiles(bp.mailboxIds), "expected bp.mailboxIds to compile"
  # No ``from`` accessor — `from` is a Nim keyword, so backtick-access
  # to the raw-field namespace must also fail externally (Pattern A).
  assertNotCompiles bp.`from`
  assertNotCompiles bp.rawFromAddr

block structuredBodyAccepted: # §6.1.1 scenario 3
  let inline = makeBlueprintBodyPartInline()
  let root = makeBlueprintBodyPartMultipart(subParts = @[inline])
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertOk res
  let bp = res.get()
  doAssert bp.bodyKind == ebkStructured
  doAssert blueprintBodyPartEq(bp.body.bodyStructure, root)

block textBodyTypeMismatch: # §6.1.1 scenario 5
  let htmlLeaf = makeBlueprintBodyPartInline(contentType = "text/html")
  let body = flatBody(textBody = Opt.some(htmlLeaf))
  let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), body = body)
  assertBlueprintErrContains res, ebcTextBodyNotTextPlain, actualTextType, "text/html"

block htmlBodyTypeMismatch: # §6.1.1 scenario 6
  let textLeaf = makeBlueprintBodyPartInline(contentType = "text/plain")
  let body = flatBody(htmlBody = Opt.some(textLeaf))
  let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), body = body)
  assertBlueprintErrContains res, ebcHtmlBodyNotTextHtml, actualHtmlType, "text/plain"

block topLevelFromDuplicate: # §6.1.1 scenario 7
  let res = makeBlueprintWithDuplicateAt(
    dupName = "from", dupKind = ebcEmailTopLevelHeaderDuplicate
  )
  assertBlueprintErrContains res, ebcEmailTopLevelHeaderDuplicate, dupName, "from"

block bodyStructureSubjectDuplicate: # §6.1.1 scenario 7a
  let res = makeBlueprintWithDuplicateAt(
    dupName = "subject", dupKind = ebcBodyStructureHeaderDuplicate
  )
  assertBlueprintErrContains res,
    ebcBodyStructureHeaderDuplicate, bodyStructureDupName, "subject"

block bodyStructureFromSameInBoth: # §6.1.1 scenario 7b
  let res = makeBlueprintWithDuplicateAt(
    dupName = "from", dupKind = ebcBodyStructureHeaderDuplicate
  )
  assertBlueprintErrContains res,
    ebcBodyStructureHeaderDuplicate, bodyStructureDupName, "from"

block bodyStructureRootUniqueCustom: # §6.1.1 scenario 7c
  # Root extraHeaders carries a name with no top-level counterpart —
  # constraint 3b must NOT fire.
  var rootExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  rootExtra[makeBlueprintBodyHeaderName("x-custom")] = makeBhmvTextSingle()
  let root = makeBlueprintBodyPartMultipart(
    subParts = @[makeBlueprintBodyPartInline()], extraHeaders = rootExtra
  )
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertOk res

block bodyStructureSubPartOutOfScope: # §6.1.1 scenario 7d
  # Sub-part of the root carries the colliding header — scope is ROOT
  # only (design §3.3), so constraint 3b does not fire.
  var subExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  subExtra[makeBlueprintBodyHeaderName("x-subpart-only")] = makeBhmvTextSingle()
  let sub = makeBlueprintBodyPartInline(extraHeaders = subExtra)
  let root = makeBlueprintBodyPartMultipart(subParts = @[sub])
  var topExtra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  topExtra[makeBlueprintEmailHeaderName("x-subpart-only")] = makeBhmvTextSingle()
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    body = structuredBody(root),
    extraHeaders = topExtra,
  )
  assertOk res

block bodyPartContentTypeDuplicate: # §6.1.1 scenario 7e
  let res = makeBlueprintWithDuplicateAt(
    dupName = "content-type", dupKind = ebcBodyPartHeaderDuplicate
  )
  assertBlueprintErrContains res,
    ebcBodyPartHeaderDuplicate, bodyPartDupName, "content-type"

block bodyPartContentDispositionDuplicate: # §6.1.1 scenario 7f
  # Inline leaf with both ``disposition`` domain field AND a
  # ``content-disposition`` extraHeaders entry — domain-field set is
  # ``{content-type, content-disposition}``, so collision fires.
  var partExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  partExtra[makeBlueprintBodyHeaderName("content-disposition")] = makeBhmvTextSingle()
  let leaf = BlueprintBodyPart(
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: makeBlueprintBodyValue(),
    ),
    contentType: "text/plain",
    extraHeaders: partExtra,
    name: Opt.none(string),
    disposition: Opt.some(dispositionAttachment),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = flatBody(textBody = Opt.some(leaf))
  )
  assertBlueprintErrContains res,
    ebcBodyPartHeaderDuplicate, bodyPartDupName, "content-disposition"

block bodyPartMultipartPathDepthTwo: # §6.1.1 scenario 7g
  # Build root -> child0(multipart) -> child2(multipart with dup). The
  # colliding header on the inner multipart yields ``where.path ==
  # @[0, 2]``. The multipart's domain-field set always includes
  # ``content-type``, so an ``extraHeaders`` entry for the same name
  # collides deterministically.
  var innerExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  innerExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
  let inner = makeBlueprintBodyPartMultipart(
    subParts = @[makeBlueprintBodyPartInline()], extraHeaders = innerExtra
  )
  let mid = makeBlueprintBodyPartMultipart(
    subParts = @[
      makeBlueprintBodyPartInline(),
      makeBlueprintBodyPartInline(partId = parsePartIdFromServer("2").get()),
      inner,
    ]
  )
  let root = makeBlueprintBodyPartMultipart(subParts = @[mid])
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertErr res
  let errs = res.unsafeError
  var found = false
  for e in errs.items:
    if e.constraint == ebcBodyPartHeaderDuplicate and e.where.kind == bplMultipart and
        e.where.path == makeBodyPartPath(@[0, 2]) and e.bodyPartDupName == "content-type":
      found = true
      break
  doAssert found, "expected multipart-at-depth-2 duplicate, got " & $errs

block bodyPartBlobRefAtDepthTwo: # §6.1.1 scenario 7h
  # Blob-ref leaf at @[0, 0] with a colliding header. ``locationOf``
  # routes to ``bplBlobRef`` (leaf), so ``where`` carries the blobId.
  var leafExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  leafExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
  let target = makeBlueprintBodyPartBlobRef(
    blobId = makeBlobId("blobDeep"), extraHeaders = leafExtra
  )
  let mid = makeBlueprintBodyPartMultipart(subParts = @[target])
  let root = makeBlueprintBodyPartMultipart(subParts = @[mid])
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertErr res
  var found = false
  for e in res.unsafeError.items:
    if e.constraint == ebcBodyPartHeaderDuplicate and e.where.kind == bplBlobRef and
        e.where.blobId == makeBlobId("blobDeep"):
      found = true
      break
  doAssert found, "expected blob-ref duplicate at depth 2, got " & $res.unsafeError

block accumulatedDuplicatesCount: # §6.1.1 scenario 7i
  # Two independent collisions in one parse: "from" top-level dup plus
  # "content-type" body-part dup. The accumulating rail returns both,
  # not the first.
  var topExtra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  # Use hfRaw — "from" allows Addresses/GroupedAddresses/Raw; hfText
  # would add a third (allowed-form) error and mask the dup-count test.
  topExtra[makeBlueprintEmailHeaderName("from")] = makeBhmvRawSingle()
  var partExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  partExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
  let leaf = makeBlueprintBodyPartInline(extraHeaders = partExtra)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    body = flatBody(textBody = Opt.some(leaf)),
    fromAddr = Opt.some(@[makeEmailAddress()]),
    extraHeaders = topExtra,
  )
  assertBlueprintErrCount res, 2
  assertBlueprintErrAny res,
    {ebcEmailTopLevelHeaderDuplicate, ebcBodyPartHeaderDuplicate}

block sentAtDateAliasCollision: # §6.1.1 scenario 7j
  # ``sentAt`` convenience field implies header name ``date``.
  var topExtra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  topExtra[makeBlueprintEmailHeaderName("date")] = makeBhmvDateSingle()
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    sentAt = Opt.some(parseDate("2026-04-13T12:00:00Z").get()),
    extraHeaders = topExtra,
  )
  assertBlueprintErrContains res, ebcEmailTopLevelHeaderDuplicate, dupName, "date"

block flatAttachmentsNestedPathEncoding: # §6.1.1 scenario 7k
  # Flat body with 3 attachments: attachments[2] is a multipart with a
  # colliding ``content-type`` extraHeaders entry on its own root.
  # Per §3.4, flat-body path encoding for attachments[i] starts at
  # ``2 + i`` — attachments[2] yields first-path-element ``4``.
  var innerExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  innerExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
  let offender = makeBlueprintBodyPartMultipart(
    subParts = @[makeBlueprintBodyPartInline()], extraHeaders = innerExtra
  )
  let att0 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("a0"))
  let att1 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("a1"))
  let body = flatBody(attachments = @[att0, att1, offender])
  let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), body = body)
  assertErr res
  var found = false
  for e in res.unsafeError.items:
    if e.constraint == ebcBodyPartHeaderDuplicate and e.where.kind == bplMultipart and
        e.where.path.len == 1 and e.where.path[idx(0)] == 4:
      found = true
      break
  doAssert found, "expected attachments[2] path @[4], got " & $res.unsafeError

block bodyPartLocationRoundTrip: # §6.1.1 scenario 7l
  let inline = makeBodyPartLocationInline(parsePartIdFromServer("3").get())
  let blob = makeBodyPartLocationBlobRef(makeBlobId("blobZ"))
  let mp = makeBodyPartLocationMultipart(makeBodyPartPath(@[1, 2, 3]))
  doAssert bodyPartLocationEq(inline, inline)
  doAssert bodyPartLocationEq(blob, blob)
  doAssert bodyPartLocationEq(mp, mp)
  doAssert not bodyPartLocationEq(inline, blob)
  doAssert not bodyPartLocationEq(blob, mp)
  doAssert not bodyPartLocationEq(inline, mp)

block allowedFormRejected: # §6.1.1 scenario 9
  # "subject" allows {hfText, hfRaw}; hfAddresses is rejected.
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[makeBlueprintEmailHeaderName("subject")] =
    makeBhmvAddressesSingle(value = @[makeEmailAddress()])
  let res =
    parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra)
  assertBlueprintErrContains res, ebcAllowedFormRejected, rejectedName, "subject"
  assertBlueprintErrContains res, ebcAllowedFormRejected, rejectedForm, hfAddresses

block messageRenderingSixVariants: # §6.1.1 scenario 11a
  # Six distinct variants → six distinct human-readable renderings.
  let path0 = makeBodyPartPath(@[0])
  let errs = @[
    EmailBlueprintError(constraint: ebcEmailTopLevelHeaderDuplicate, dupName: "from"),
    EmailBlueprintError(
      constraint: ebcBodyStructureHeaderDuplicate, bodyStructureDupName: "subject"
    ),
    EmailBlueprintError(
      constraint: ebcBodyPartHeaderDuplicate,
      where: BodyPartLocation(kind: bplMultipart, path: path0),
      bodyPartDupName: "content-type",
    ),
    EmailBlueprintError(
      constraint: ebcTextBodyNotTextPlain, actualTextType: "text/html"
    ),
    EmailBlueprintError(
      constraint: ebcHtmlBodyNotTextHtml, actualHtmlType: "text/plain"
    ),
    EmailBlueprintError(
      constraint: ebcAllowedFormRejected,
      rejectedName: "subject",
      rejectedForm: hfAddresses,
    ),
  ]
  var rendered = initHashSet[string]()
  for e in errs:
    rendered.incl message(e)
  doAssert rendered.len == 6, "expected six distinct messages, got " & $rendered.len

block messageBoundedAndPure: # §6.1.1 scenario 11b
  # Adversarial payload: NUL, CRLF, and 100 KB. message() must be
  # bounded (≤ 8 KiB), NUL-stripped, and deterministic across calls.
  let adversarial = "\x00\r\n" & "x".repeat(100_000)
  let e = EmailBlueprintError(
    constraint: ebcTextBodyNotTextPlain, actualTextType: adversarial
  )
  let m1 = message(e)
  let m2 = message(e)
  doAssert m1 == m2, "message(e) must be deterministic"
  assertLe m1.len, 8192
  doAssert not m1.contains('\x00'), "NUL must be stripped from rendered message"

block fullAccessorMarkerTuple: # §6.1.1 scenario 12
  let bp = makeFullEmailBlueprint()
  let alice = makeEmailAddress("alice@example.com", "Alice")
  let bob = makeEmailAddress("bob@example.com", "Bob")
  assertEq bp.fromAddr, Opt.some(@[alice])
  assertEq bp.to, Opt.some(@[bob])
  assertEq bp.cc, Opt.some(@[alice])
  assertEq bp.bcc, Opt.some(@[bob])
  assertEq bp.replyTo, Opt.some(@[alice])
  assertEq bp.sender, Opt.some(alice)
  assertEq bp.subject, Opt.some("hello")
  assertEq bp.sentAt, Opt.some(parseDate("2025-01-15T08:00:00Z").get())
  assertEq bp.messageId, Opt.some(@["<id1@host>"])
  assertEq bp.inReplyTo, Opt.some(@["<id0@host>"])
  assertEq bp.references, Opt.some(@["<id0@host>"])

block flatAttachmentsOnly: # §6.1.1 scenario 17
  let att1 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("a1"))
  let att2 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("a2"))
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    body = flatBody(attachments = @[att1, att2]),
  )
  assertOk res
  let bp = res.get()
  doAssert bp.bodyKind == ebkFlat
  assertLen bp.body.attachments, 2

block flatFullyEmpty: # §6.1.1 scenario 18
  # Empty flat body: no textBody, no htmlBody, no attachments. The
  # smart constructor must accept this (it's the default). Serde-side
  # omit-on-None assertions land in Phase 4 Step 18 alongside
  # ``EmailBlueprint.toJson``.
  let res = parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet())
  assertOk res
  let bp = res.get()
  doAssert bp.bodyKind == ebkFlat
  doAssert bp.body.textBody.isNone
  doAssert bp.body.htmlBody.isNone
  assertLen bp.body.attachments, 0

# =============================================================================
# B. BlueprintBodyValue single-field serde (§6.1.2 scenario 21)
# =============================================================================

block blueprintBodyValueToJsonShape: # §6.1.2 scenario 21
  # RFC 8621 §4.1.4 / Design §4.1.3 — creation body value emits exactly
  # one field ``{"value": "..."}``; the isEncodingProblem/isTruncated
  # flags are stripped at the type level (sc 38 pairs here).
  let node = toJson(BlueprintBodyValue(value: "Hello"))
  assertEq $node, """{"value":"Hello"}"""
  assertJsonStringEquals node, "value", "Hello"
  assertJsonKeyAbsent node, "isEncodingProblem"
  assertJsonKeyAbsent node, "isTruncated"

# =============================================================================
# C. Derived bodyValues accessor (§6.1.7 scenarios 49–50b)
# =============================================================================

block bodyValuesHarvestsInlineLeaves: # §6.1.7 scenario 49
  let p1 = parsePartIdFromServer("1").get()
  let p2 = parsePartIdFromServer("2").get()
  let leaf1 =
    makeBlueprintBodyPartInline(partId = p1, value = BlueprintBodyValue(value: "first"))
  let leaf2 = makeBlueprintBodyPartInline(
    partId = p2, value = BlueprintBodyValue(value: "second")
  )
  let root = makeBlueprintBodyPartMultipart(subParts = @[leaf1, leaf2])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    .get()
  let values = bp.bodyValues
  assertLen values, 2
  doAssert p1 in values
  doAssert p2 in values
  assertEq values[p1].value, "first"
  assertEq values[p2].value, "second"

block bodyValuesEmptyOnAllBlobRef: # §6.1.7 scenario 50
  # All leaves blob-referenced — no inline partIds to harvest. Serde
  # omit-on-empty assertion lands in Phase 4 Step 18 alongside
  # ``EmailBlueprint.toJson``.
  let b1 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("b1"))
  let b2 = makeBlueprintBodyPartBlobRef(blobId = makeBlobId("b2"))
  let root = makeBlueprintBodyPartMultipart(subParts = @[b1, b2])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    .get()
  assertLen bp.bodyValues, 0

block bodyValuesIsDerivedNotCached: # §6.1.7 scenario 50a
  # Two blueprints with different inline-leaf payloads: each reports
  # its own body tree, confirming the accessor recomputes from the
  # tree rather than reading a cached copy written at construction.
  let p1 = parsePartIdFromServer("1").get()
  let leafA =
    makeBlueprintBodyPartInline(partId = p1, value = BlueprintBodyValue(value: "A"))
  let leafB =
    makeBlueprintBodyPartInline(partId = p1, value = BlueprintBodyValue(value: "B"))
  let bpA = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leafA)),
    )
    .get()
  let bpB = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leafB)),
    )
    .get()
  assertEq bpA.bodyValues[p1].value, "A"
  assertEq bpB.bodyValues[p1].value, "B"

block bodyValuesCorrespondence: # §6.1.7 scenario 50b
  # Manual walk produces identical (partId, value) pairs as the
  # derived accessor — the set-level equality is the correspondence.
  let p1 = parsePartIdFromServer("1").get()
  let p2 = parsePartIdFromServer("2").get()
  let p3 = parsePartIdFromServer("3").get()
  let inline1 =
    makeBlueprintBodyPartInline(partId = p1, value = BlueprintBodyValue(value: "one"))
  let inline2 =
    makeBlueprintBodyPartInline(partId = p2, value = BlueprintBodyValue(value: "two"))
  let inline3 =
    makeBlueprintBodyPartInline(partId = p3, value = BlueprintBodyValue(value: "three"))
  let inner = makeBlueprintBodyPartMultipart(subParts = @[inline2, inline3])
  let root = makeBlueprintBodyPartMultipart(subParts = @[inline1, inner])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    .get()
  let derived = bp.bodyValues
  var manual = initHashSet[(PartId, string)]()
  manual.incl((p1, "one"))
  manual.incl((p2, "two"))
  manual.incl((p3, "three"))
  var seen = initHashSet[(PartId, string)]()
  for pid, bv in derived.pairs:
    seen.incl((pid, bv.value))
  doAssert manual == seen, "derived pairs diverge from manual walk"

# =============================================================================
# D. FFI value-type non-aliasing (§6.4.4 scenarios 102b, 102d)
# =============================================================================

block idValueTypeNonAliasing: # §6.4.4 scenario 102b
  # ``NonEmptyMailboxIdSet`` stores Ids by value (Id = distinct string,
  # seq passed by value into the set constructor). Rebinding a source
  # variable after construction must not mutate the set's contents.
  var id1 = makeId("mbox-one")
  let s = parseNonEmptyMailboxIdSet(@[id1]).get()
  id1 = makeId("mbox-two")
  doAssert makeId("mbox-one") in s, "set must retain original id by value"
  doAssert not (makeId("mbox-two") in s), "rebind must not leak into the set"

block nonEmptySeqDistinctCopySemantics: # §6.4.4 scenario 102d
  # Unwrapping a ``distinct seq[T]`` to ``seq[T]`` copies; mutating the
  # unwrapped copy must not affect the original. The non-empty
  # invariant is structural, not just documented.
  let ne = parseNonEmptySeq(@["v"]).get()
  var raw = seq[string](ne)
  raw.setLen(0)
  doAssert ne.len == 1, "NonEmptySeq must retain element after unwrap-mutate"
  doAssert ne.head == "v", "NonEmptySeq element value must be preserved"
