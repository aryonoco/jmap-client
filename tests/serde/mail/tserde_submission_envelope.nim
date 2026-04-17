# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Smoke serde tests for the EmailSubmission envelope concern (Step 10):
## happy-path round-trip across every parameter family, the null-reverse-
## path wire shape, and empty-``rcptTo`` rejection. Exhaustive enum sweeps
## and property-based checks land with G2.

{.push raises: [].}

import std/json

import jmap_client/mail/serde_submission_envelope
import jmap_client/mail/submission_envelope
import jmap_client/serde
import jmap_client/types

import ../../massertions

# ============= A. Happy-path round-trip =============

block roundTripEnvelopeWithRichParameters:
  ## Build an envelope whose ``mailFrom`` carries five parameter families
  ## (BODY, SIZE, NOTIFY, ORCPT, extension) and whose ``rcptTo`` mixes a
  ## bare address with one carrying a RET parameter. Round-trip via JSON
  ## structural equality — the wire form must be a fixed point under
  ## ``toJson . fromJson . toJson``.
  let kw = parseRFC5321Keyword("X-VENDOR-FOO").unsafeGet()
  let notify = notifyParam({dnfSuccess, dnfFailure}).unsafeGet()
  let orcptType = parseOrcptAddrType("rfc822").unsafeGet()
  let senderParams = parseSubmissionParams(
      @[
        bodyParam(beEightBitMime),
        sizeParam(UnsignedInt(12345)),
        notify,
        orcptParam(orcptType, "alice@example.com"),
        extensionParam(kw, Opt.some("bar")),
      ]
    )
    .unsafeGet()
  let senderMailbox = parseRFC5321Mailbox("sender@example.com").unsafeGet()
  let senderAddr =
    SubmissionAddress(mailbox: senderMailbox, parameters: Opt.some(senderParams))
  let mailFrom = reversePath(senderAddr)

  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))

  let bobMailbox = parseRFC5321Mailbox("bob@example.com").unsafeGet()
  let bobParams = parseSubmissionParams(@[retParam(retHdrs)]).unsafeGet()
  let bobAddr = SubmissionAddress(mailbox: bobMailbox, parameters: Opt.some(bobParams))

  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr, bobAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"

  # Spot checks on the rendered wire shape.
  let mfNode = firstJson{"mailFrom"}
  doAssert mfNode != nil and mfNode.kind == JObject
  assertJsonFieldEq mfNode, "email", %"sender@example.com"
  let mfParams = mfNode{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JObject
  assertJsonFieldEq mfParams, "BODY", %"8BITMIME"
  assertJsonFieldEq mfParams, "SIZE", %"12345"
  assertJsonFieldEq mfParams, "X-VENDOR-FOO", %"bar"

  let rcArr = firstJson{"rcptTo"}
  doAssert rcArr != nil and rcArr.kind == JArray
  doAssert rcArr.len == 2
  let aliceParams = rcArr[0]{"parameters"}
  doAssert aliceParams != nil and aliceParams.kind == JNull
  let bobWireParams = rcArr[1]{"parameters"}
  doAssert bobWireParams != nil and bobWireParams.kind == JObject
  assertJsonFieldEq bobWireParams, "RET", %"HDRS"

# ============= B. Null reverse-path wire shape =============

block nullReversePathWireShape:
  ## RFC 5321 §4.1.1.2 null reverse-path ``<>`` projects to the wire
  ## shape ``{"email": "", "parameters": null}`` — the fingerprint that
  ## ``ReversePath.fromJson`` discriminates on.
  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: nullReversePath(), rcptTo: rcptTo)

  let json = env.toJson()
  let mfNode = json{"mailFrom"}
  doAssert mfNode != nil and mfNode.kind == JObject
  assertJsonFieldEq mfNode, "email", %""
  let pf = mfNode{"parameters"}
  doAssert pf != nil
  doAssert pf.kind == JNull

  # Round-trip preserves the null path.
  let parsed = Envelope.fromJson(json)
  assertOk parsed
  doAssert parsed.unsafeGet().mailFrom.kind == rpkNullPath
  assertNone parsed.unsafeGet().mailFrom.nullPathParams

# ============= C. Empty rcptTo rejection =============

block emptyRcptToIsRejected:
  ## RFC 8621 §7 ¶5 mandates ``rcptTo`` be non-empty;
  ## ``parseNonEmptyRcptListFromServer`` rejects an empty array, surfacing
  ## as ``svkFieldParserFailed`` anchored at ``/rcptTo``.
  let badJson =
    %*{"mailFrom": {"email": "sender@example.com", "parameters": nil}, "rcptTo": []}
  let res = Envelope.fromJson(badJson)
  assertSvKind res, svkFieldParserFailed
  assertSvPath res, "/rcptTo"
