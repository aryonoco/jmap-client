# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``parseEmailSubmissionBlueprint`` (G1 §5.2, with
## G15-tightening to Pattern A sealing). Pins the accumulating-error
## Result shape, UFCS accessor publication, sealing against brace
## construction, default ``envelope`` argument, and auto-derived
## structural equality.

{.push raises: [].}

import jmap_client/mail/email_submission
import jmap_client/mail/submission_envelope
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/validation

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
  # the hybrid shape.
  let idI = parseId("i-seal").get()
  let idE = parseId("e-seal").get()
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
