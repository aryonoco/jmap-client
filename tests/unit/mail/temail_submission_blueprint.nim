# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``parseEmailSubmissionBlueprint`` (G1 §5.2, with
## G15-tightening to Pattern A sealing). Pins the accumulating-error
## Result shape, UFCS accessor publication, sealing against brace
## construction, default ``envelope`` argument, and auto-derived
## structural equality.

{.push raises: [].}

import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/submission_envelope
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions

block symbolsExported:
  doAssert compiles(EmailSubmissionBlueprint)
  doAssert compiles(parseEmailSubmissionBlueprint)

block minimalBlueprint:
  let idI = parseId("identity-123").get()
  let idE = parseId("email-456").get()
  let res = parseEmailSubmissionBlueprint(idI, idE)
  assertOk res
  let bp = res.get()
  # UFCS accessor calls — read-identical to field access.
  assertEq bp.identityId, idI
  assertEq bp.emailId, idE
  doAssert bp.envelope.isNone, "envelope should default to Opt.none"

block accessorContract:
  # Pins that the UFCS accessors are exported and read-identical to
  # field access. The three ``compiles`` probes succeed iff the accessor
  # funcs are visible from this module.
  let idI = parseId("i-acc").get()
  let idE = parseId("e-acc").get()
  let bp = parseEmailSubmissionBlueprint(idI, idE).get()
  doAssert compiles(bp.identityId)
  doAssert compiles(bp.emailId)
  doAssert compiles(bp.envelope)

block sealingContract:
  # Pins Pattern A sealing: brace construction with the raw* field names
  # fails from outside the module. This is the contract that forces
  # callers through parseEmailSubmissionBlueprint, which is the point of
  # the hybrid shape. `idI`/`idE` appear only inside `not compiles(...)`,
  # so mark them {.used.} — the speculative-compile macro context doesn't
  # count as a use for the declared-but-not-used analysis.
  let idI {.used.} = parseId("i-seal").get()
  let idE {.used.} = parseId("e-seal").get()
  doAssert not compiles(
    EmailSubmissionBlueprint(
      rawIdentityId: idI, rawEmailId: idE, rawEnvelope: Opt.none(Envelope)
    )
  ), "rawIdentityId must be module-private (Pattern A sealing)"
  # Public-field names should not exist either — proves we did not leave
  # a backdoor with public duplicates.
  doAssert not compiles(
    EmailSubmissionBlueprint(
      identityId: idI, emailId: idE, envelope: Opt.none(Envelope)
    )
  ), "public fields would bypass the smart constructor"

block blueprintWithEnvelope:
  let idI = parseId("i2").get()
  let idE = parseId("e2").get()
  let mbox = parseRFC5321Mailbox("rcpt@example.com").get()
  let rcpt = SubmissionAddress(mailbox: mbox, parameters: Opt.none(SubmissionParams))
  let env =
    Envelope(mailFrom: nullReversePath(), rcptTo: parseNonEmptyRcptList(@[rcpt]).get())
  let res = parseEmailSubmissionBlueprint(idI, idE, Opt.some(env))
  assertOk res
  let bp = res.get()
  doAssert bp.envelope.isSome, "envelope Opt.some should round-trip"
  assertEq bp.envelope.get(), env

block defaultEnvelopeIsNone:
  let idI = parseId("i3").get()
  let idE = parseId("e3").get()
  let bp = parseEmailSubmissionBlueprint(idI, idE).get()
  doAssert bp.envelope.isNone

block inequalityOnIdentity:
  let idI1 = parseId("iA").get()
  let idI2 = parseId("iB").get()
  let idE = parseId("e5").get()
  let bp1 = parseEmailSubmissionBlueprint(idI1, idE).get()
  let bp2 = parseEmailSubmissionBlueprint(idI2, idE).get()
  doAssert bp1 != bp2

block blueprintInvalidIdentityId:
  # Pins rejection of a malformed identityId at the upstream parseId
  # boundary. parseEmailSubmissionBlueprint (email_submission.nim:152)
  # accepts pre-parsed Id values, so the Id-layer message is the one any
  # blueprint caller encounters; grep-locked from validation.nim:189.
  let res = parseId("bad@identity")
  assertErr res
  assertEq res.error.typeName, "Id"
  assertEq res.error.message, "contains characters outside base64url alphabet"
  assertEq res.error.value, "bad@identity"

block blueprintInvalidEmailId:
  # Symmetric Id-layer rejection for the emailId field.
  let res = parseId("bad@email")
  assertErr res
  assertEq res.error.typeName, "Id"
  assertEq res.error.message, "contains characters outside base64url alphabet"
  assertEq res.error.value, "bad@email"

block blueprintAccumulatesBothIdErrors:
  # G2 §8.3 row 555 says "both malformed id inputs must accumulate".
  # G1's parseEmailSubmissionBlueprint accepts pre-parsed Ids, so the
  # accumulation architecturally lives in the caller's two parseId calls.
  # This block pins per-call error independence (each error preserves its
  # own value and message) and smoke-checks that the blueprint's seq
  # error-rail shape (Result[_, seq[ValidationError]]) is preserved for
  # forward-compat with future blueprint-level constraints.
  let identityRes = parseId("bad@identity")
  let emailRes = parseId("bad@email")
  assertErr identityRes
  assertErr emailRes
  # Independent value pins — each error carries its own raw verbatim:
  assertEq identityRes.error.value, "bad@identity"
  assertEq emailRes.error.value, "bad@email"
  # Same rejection class (non-base64url), but independent ValidationError
  # instances; messages grep-locked from validation.nim:189:
  assertEq identityRes.error.message, "contains characters outside base64url alphabet"
  assertEq emailRes.error.message, "contains characters outside base64url alphabet"
  # Structural pin — the blueprint's error rail remains a seq. If a
  # future refactor demotes to Result[_, ValidationError], the
  # compiles() probe fails, flagging the regression.
  let idI = parseId("validA").get()
  let idE = parseId("validB").get()
  let okRes = parseEmailSubmissionBlueprint(idI, idE)
  assertOk okRes
  doAssert compiles(okRes.error.len),
    "blueprint error rail must remain seq[ValidationError] for accumulation forward-compat"

block blueprintPatternASealExplicitRawField:
  # G38 Pattern A per-field seal probes using the standardised
  # assertNotCompiles template (massertions.nim:150). Complements the
  # shipped sealingContract block (lines 46-64) which uses raw
  # `doAssert not compiles(...)` in-line and covers only record-literal
  # construction. This block adds:
  #   (a) per-field probes that pinpoint WHICH field regressed if the
  #       seal breaks (single-name construction + read-access);
  #   (b) read-side coverage (the shipped block only tests write/ctor).
  # G38 (§8.13 row 1038) remains SHIPPED via sealingContract; this
  # block is supplementary diagnostic coverage.
  let idI = parseId("i-pa").get()
  let idE = parseId("e-pa").get()
  # (1) Record-literal construction with raw* field names is sealed:
  assertNotCompiles(
    EmailSubmissionBlueprint(
      rawIdentityId: idI, rawEmailId: idE, rawEnvelope: Opt.none(Envelope)
    )
  )
  # (2) Per-field read-access from outside the module is also sealed.
  # An accidental future `rawIdentityId*` export would surface here.
  let bp = parseEmailSubmissionBlueprint(idI, idE).get()
  assertNotCompiles(bp.rawIdentityId)
  assertNotCompiles(bp.rawEmailId)
  assertNotCompiles(bp.rawEnvelope)
