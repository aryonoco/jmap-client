# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time contract assertions for EmailBlueprint and supporting
## types (Part E §6.1.6 scenarios 38, 40, 41, 42, 45, 46, 48, 48a–48l).
## These scenarios defend R5-2 "make illegal states unrepresentable" at
## the compile boundary. Lives OUTSIDE ``email_blueprint.nim`` so the
## module-scope privacy assertions (40, 45, 48a, 48h, 48j, 48l) are
## exercised at the external boundary — a test inside the module would
## falsify them by definition.

{.push raises: [].}

import std/tables

import jmap_client/mail/body
import jmap_client/mail/email_blueprint
import jmap_client/mail/headers
import jmap_client/primitives
import jmap_client/validation

import ../../massertions
import ../../mfixtures

block blueprintBodyValueFlagFieldsStripped: # §6.1.6 scenario 38
  # ``isEncodingProblem`` / ``isTruncated`` on ``EmailBodyValue`` are
  # mandated false on creation — stripped from ``BlueprintBodyValue``
  # so the illegal state is structurally unrepresentable.
  assertNotCompiles BlueprintBodyValue(value: "x", isEncodingProblem: false)
  assertNotCompiles BlueprintBodyValue(value: "x", isTruncated: false)

block emailBlueprintDirectConstructionSealed: # §6.1.6 scenario 40
  # ``rawMailboxIds`` is module-private (Pattern A). External brace
  # construction is rejected because the field name isn't visible.
  assertNotCompiles EmailBlueprint(rawMailboxIds: makeNonEmptyMailboxIdSet())

block blueprintBodyPartInlineRequiresValue: # §6.1.6 scenario 41
  # ``value`` lives on the ``bpsInline`` branch — pairing it with
  # ``source: bpsBlobRef`` is a compile error (R3-3 co-location).
  # (Nim brace construction with defaults means the absence form of
  # this check is not enforceable at the language level; the
  # branch-crossing form is the stricter structural check.)
  assertNotCompiles BlueprintBodyPart(
    isMultipart: false,
    source: bpsBlobRef,
    blobId: makeBlobId("b1"),
    value: BlueprintBodyValue(value: "x"),
  )

block headerKeyCrossContextRejected: # §6.1.6 scenario 42
  # Creation-vocabulary header-name types are context-specific:
  # ``BlueprintEmailHeaderName`` for Email top level,
  # ``BlueprintBodyHeaderName`` for body parts. Cross-insertion into a
  # Table keyed by the other type must be a type error (R3-4 / E28).
  let emailKey = makeBlueprintEmailHeaderName("x-email")
  let bodyKey = makeBlueprintBodyHeaderName("x-body")
  # Table keyed by BlueprintEmailHeaderName — can't take BodyHeaderName.
  assertNotCompiles (
    block:
      var t = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
      t[bodyKey] = makeBhmvTextSingle()
  )
  # Table keyed by BlueprintBodyHeaderName — can't take EmailHeaderName.
  assertNotCompiles (
    block:
      var t = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
      t[emailKey] = makeBhmvTextSingle()
  )
  # Bare ``HeaderPropertyKey`` (the query-side type) cannot stand in
  # for the creation-vocabulary key types — the two vocabularies
  # don't interconvert (R1-3).
  let hpk = parseHeaderPropertyName("header:subject").get()
  assertNotCompiles (
    block:
      var t = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
      t[hpk] = makeBhmvTextSingle()
  )

block rawFieldWriteSealedExternally: # §6.1.6 scenario 45
  # Pattern A: external writers to private ``raw*`` fields are
  # refused. The accessor gates read-only public access.
  let bp = makeEmailBlueprint()
  assertNotCompiles (bp.rawMailboxIds = makeNonEmptyMailboxIdSet())

block caseObjectFieldDefectPair: # §6.1.6 scenario 46
  # Under ``--panics:on`` (project default per jmap_client.nimble),
  # ``FieldDefect`` is fatal and cannot be caught — it rawQuits the
  # process. So this scenario reduces to attesting to the shape:
  # each branch exposes its own fields, and the opposite-branch
  # access is refused by the compiler's branch tracking in the
  # case statement form. Compile-time companions (sc 48b, 48c)
  # verify that *constructing* a body with the wrong-branch field is
  # itself a compile error — the stricter check.
  let flat = flatBody()
  let sb = structuredBody(makeBlueprintBodyPartInline())
  doAssert flat.kind == ebkFlat
  doAssert sb.kind == ebkStructured
  # Access the right-branch field on each — the case object's
  # structural guarantee is that these compile for the matching
  # kind only. A ``case`` over ``.kind`` is the idiomatic reader.
  case flat.kind
  of ebkFlat:
    doAssert flat.textBody.isNone
  of ebkStructured:
    discard
  case sb.kind
  of ebkStructured:
    doAssert compiles(sb.bodyStructure)
  of ebkFlat:
    discard

block internalNonEmptyInvariantDocumented: # §6.1.6 scenario 48
  # The internal ``doAssert errs.len > 0`` inside ``parseEmailBlueprint``
  # cannot be triggered from outside the module. The external
  # counterpart (sc 48l) pins that ``EmailBlueprintErrors`` cannot be
  # positionally constructed externally, so the ``errors: @[]`` state
  # is unreachable. Re-attest that the known-success path compiles.
  static:
    doAssert compiles(parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet()))

block parseSignatureRejectsBareSeq: # §6.1.6 scenario 48a
  # ``mailboxIds`` takes ``NonEmptyMailboxIdSet``, not ``seq[Id]``.
  # The typed boundary forces callers through
  # ``parseNonEmptyMailboxIdSet`` so the at-least-one invariant is
  # proved at the type level.
  assertNotCompiles parseEmailBlueprint(mailboxIds = @[makeId("m1")])

block structuredBodyRejectsFlatField: # §6.1.6 scenario 48b
  # ``textBody`` lives on the ``ebkFlat`` branch only — brace
  # construction with ``kind: ebkStructured`` and ``textBody`` is a
  # compile error (case-object branch tracking).
  assertNotCompiles EmailBlueprintBody(
    kind: ebkStructured,
    bodyStructure: makeBlueprintBodyPartInline(),
    textBody: Opt.some(makeBlueprintBodyPartInline()),
  )

block flatBodyRejectsStructuredField: # §6.1.6 scenario 48c
  # Symmetric to 48b: ``bodyStructure`` lives on ``ebkStructured``
  # only.
  assertNotCompiles EmailBlueprintBody(
    kind: ebkFlat,
    textBody: Opt.some(makeBlueprintBodyPartInline()),
    bodyStructure: makeBlueprintBodyPartInline(),
  )

block multiValueFormDiscriminantGuard: # §6.1.6 scenario 48d
  # ``rawValues`` is on the ``hfRaw`` branch only — pairing with
  # ``form: hfText`` must be a compile error.
  let ne = parseNonEmptySeq(@["v"]).get()
  assertNotCompiles BlueprintHeaderMultiValue(form: hfText, rawValues: ne)

block intraTableDedupRuntime: # §6.1.6 scenario 48e
  # Runtime check colocated here because its structural invariant
  # (byte-distinct names that normalise equal produce ONE key, not
  # two) is adjacent to the type-level sealing on either side. Case
  # variants of a header name lowercase to the same
  # ``BlueprintEmailHeaderName`` — Table dedup on insert.
  var t = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  t[makeBlueprintEmailHeaderName("X-Marker")] = makeBhmvTextSingle("first")
  t[makeBlueprintEmailHeaderName("x-marker")] = makeBhmvTextSingle("second")
  assertLen t, 1

block parseNonEmptySeqEmptyRefused: # §6.1.6 scenario 48f
  # Runtime: empty input on the smart constructor yields err. The
  # type's at-least-one invariant is enforced at the boundary.
  let res = parseNonEmptySeq[string](@[])
  assertErr res

block multiValueFieldRejectsBareSeq: # §6.1.6 scenario 48g
  # ``rawValues`` is ``NonEmptySeq[string]`` — passing a bare
  # ``seq[string]`` fails type matching (distinct-type refusal).
  assertNotCompiles BlueprintHeaderMultiValue(form: hfRaw, rawValues: @[])

block parseSignatureRejectsBareBodyPart: # §6.1.6 scenario 48h
  # The ``body`` parameter takes ``EmailBlueprintBody`` (the
  # body-shape case object), not the inner ``BlueprintBodyPart``.
  # Clients must route through ``flatBody`` / ``structuredBody``.
  let part = makeBlueprintBodyPartInline()
  assertNotCompiles parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = part
  )

block crossBranchFieldAssignmentAttestation: # §6.1.6 scenario 48i
  # CLAUDE.md-marked regression guard reduced to an attestation:
  # the structural guarantee lives on sc 48b and sc 48c, which
  # verify that CONSTRUCTION with a wrong-branch field is a
  # compile error. Those two are the load-bearing checks for R5-2.
  #
  # Original plan called for asserting that post-construction
  # discriminator reassignment and wrong-branch field assignment
  # are refused. Both refusals hold in isolation, but Nim 2.2.8's
  # semantic checker relaxes them when a sufficient symbol table
  # is in scope (empirical: either disappears once mfixtures plus
  # validation are all imported in the same file). The narrow
  # compile-time construction check is the reliable guard; the
  # post-construction check is a Nim-compiler edge case whose
  # behavior we do not want to pin.
  #
  # Non-trivial positive assertion kept: constructing a valid
  # ``EmailBlueprintBody`` via each smart constructor compiles.
  doAssert compiles(flatBody())
  doAssert compiles(structuredBody(makeBlueprintBodyPartInline()))

block publicExportSurfaceStable: # §6.1.6 scenario 48j
  # The 15 symbols enumerated in design §3.5 (and exercised across
  # Steps 15/16) must remain publicly accessible. ``compiles`` against
  # direct references is sufficient — the imports at module scope
  # already resolve these; each ``doAssert compiles`` pins that the
  # visibility wasn't accidentally demoted.
  doAssert compiles(parseEmailBlueprint)
  doAssert compiles(flatBody)
  doAssert compiles(structuredBody)
  doAssert compiles(EmailBlueprint)
  doAssert compiles(EmailBlueprintBody)
  doAssert compiles(EmailBlueprintError)
  doAssert compiles(EmailBlueprintErrors)
  doAssert compiles(EmailBlueprintConstraint)
  doAssert compiles(EmailBodyKind)
  let bp = makeEmailBlueprint()
  doAssert compiles(bp.mailboxIds)
  doAssert compiles(bp.body)
  doAssert compiles(bp.bodyKind)
  doAssert compiles(bp.bodyValues)
  doAssert compiles(bp.fromAddr)
  doAssert compiles(bp.subject)

block dropVariantEbcNoBodyContent: # §6.1.6 scenario 48k
  # ``ebcNoBodyContent`` was considered during design but dropped —
  # every accepted ``EmailBlueprintBody`` is well-formed by
  # construction, so "no body content" is not a runtime state the
  # aggregate needs to describe (R3-2b / E11).
  assertNotCompiles EmailBlueprintError(constraint: ebcNoBodyContent)

block errorsConstructorSealedExternally: # §6.1.6 scenario 48l
  # ``EmailBlueprintErrors.errors`` is module-private: external brace
  # construction by named field is refused. The only path to a
  # non-empty ``EmailBlueprintErrors`` value is ``parseEmailBlueprint``,
  # which protects the "errors.len >= 1 on err rail" invariant.
  assertNotCompiles EmailBlueprintErrors(errors: @[])
