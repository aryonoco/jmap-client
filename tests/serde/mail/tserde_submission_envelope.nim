# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Smoke serde tests for the EmailSubmission envelope concern (Step 10):
## happy-path round-trip across every parameter family, the null-reverse-
## path wire shape, and empty-``rcptTo`` rejection. Exhaustive enum sweeps
## and property-based checks land with G2.

{.push raises: [].}

import std/json

import jmap_client/internal/mail/serde_submission_envelope
import jmap_client/internal/mail/submission_envelope
import jmap_client/internal/serialisation/serde
import jmap_client/types

import ../../massertions
import ../../mtestblock

# ============= A. Happy-path round-trip =============

testCase roundTripEnvelopeWithRichParameters:
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
        sizeParam(parseUnsignedInt(12345).get()),
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

testCase nullReversePathWireShape:
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

testCase emptyRcptToIsRejected:
  ## RFC 8621 §7 ¶5 mandates ``rcptTo`` be non-empty;
  ## ``parseNonEmptyRcptListFromServer`` rejects an empty array, surfacing
  ## as ``svkFieldParserFailed`` anchored at ``/rcptTo``.
  let badJson =
    %*{"mailFrom": {"email": "sender@example.com", "parameters": nil}, "rcptTo": []}
  let res = Envelope.fromJson(badJson)
  assertSvKind res, svkFieldParserFailed
  assertSvPath res, "/rcptTo"

# ============= D. ENVID + RET round-trip =============

testCase paramEnvidAndRetRoundTrip:
  ## §8.3 parameter-family continuation (ENVID + RET). G32 reverse-path
  ## lift of a concrete mailbox; bare ``rcptTo``. RFC 3461 §4.4 (ENVID)
  ## and §5.3 (RET=FULL). Round-trip via JSON structural equality;
  ## spot-check wire backings.
  let senderParams =
    parseSubmissionParams(@[envidParam("envid-2026-04"), retParam(retFull)]).unsafeGet()
  let senderMailbox = parseRFC5321Mailbox("sender@example.com").unsafeGet()
  let senderAddr =
    SubmissionAddress(mailbox: senderMailbox, parameters: Opt.some(senderParams))
  let mailFrom = reversePath(senderAddr)

  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"

  let mfParams = firstJson{"mailFrom"}{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JObject
  assertJsonFieldEq mfParams, "ENVID", %"envid-2026-04"
  assertJsonFieldEq mfParams, "RET", %"FULL"

# ============= E. HOLDFOR + HOLDUNTIL round-trip =============

testCase paramHoldForAndHoldUntilRoundTrip:
  ## §8.3 parameter-family continuation (HOLDFOR + HOLDUNTIL). G32
  ## reverse-path lift. RFC 4865 FUTURERELEASE (delay + absolute-time).
  ## Numeric parameters ride as JSON strings of decimal digits (RFC 8621
  ## §7.3.2); HOLDUNTIL as raw RFC 3339 Zulu.
  let secs = parseHoldForSeconds(parseUnsignedInt(3600).get()).unsafeGet()
  let until = parseUtcDate("2026-12-31T23:59:59Z").unsafeGet()
  let senderParams =
    parseSubmissionParams(@[holdForParam(secs), holdUntilParam(until)]).unsafeGet()
  let senderMailbox = parseRFC5321Mailbox("sender@example.com").unsafeGet()
  let senderAddr =
    SubmissionAddress(mailbox: senderMailbox, parameters: Opt.some(senderParams))
  let mailFrom = reversePath(senderAddr)

  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"

  let mfParams = firstJson{"mailFrom"}{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JObject
  assertJsonFieldEq mfParams, "HOLDFOR", %"3600"
  assertJsonFieldEq mfParams, "HOLDUNTIL", %"2026-12-31T23:59:59Z"

# ============= F. BY + MT-PRIORITY + SMTPUTF8 round-trip =============

testCase paramByAndMtPriorityAndSmtpUtf8RoundTrip:
  ## §8.3 parameter-family completion (BY + MT-PRIORITY + SMTPUTF8). G32
  ## reverse-path lift. RFC 2852 §3 (BY=<deadline>;<mode>), RFC 6710 §2
  ## (MT-PRIORITY), RFC 6531 §3.4 (SMTPUTF8 nullary). SMTPUTF8 emits
  ## ``"SMTPUTF8": null`` — the canonical wire shape for a valueless
  ## SMTP extension.
  let pri = parseMtPriority(5).unsafeGet()
  let senderParams = parseSubmissionParams(
      @[
        byParam(parseJmapInt(120).get(), dbmReturn),
        mtPriorityParam(pri),
        smtpUtf8Param(),
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
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"

  let mfParams = firstJson{"mailFrom"}{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JObject
  assertJsonFieldEq mfParams, "BY", %"120;R"
  assertJsonFieldEq mfParams, "MT-PRIORITY", %"5"
  let utf8 = mfParams{"SMTPUTF8"}
  doAssert utf8 != nil and utf8.kind == JNull

# ============= G. Null reverse path carrying Mail-parameters =============

testCase reversePathNullWithParamsRoundTrip:
  ## §8.3 ReversePath null-path parameter carriage. G32 / G33
  ## discriminator (``rpkNullPath`` arm) with ``nullPathParams =
  ## Opt.some``. RFC 5321 §4.1.1.2 permits Mail-parameters on the null
  ## reverse-path. Wire: ``{"email": "", "parameters": {...}}``;
  ## round-trip preserves both the null-path discriminator and the
  ## parameter bag.
  let params =
    parseSubmissionParams(@[sizeParam(parseUnsignedInt(4096).get())]).unsafeGet()
  let mailFrom = nullReversePath(Opt.some(params))

  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let mfNode = firstJson{"mailFrom"}
  doAssert mfNode != nil and mfNode.kind == JObject
  assertJsonFieldEq mfNode, "email", %""
  let mfParams = mfNode{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JObject
  assertJsonFieldEq mfParams, "SIZE", %"4096"

  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"
  let roundMailFrom = parsed.unsafeGet().mailFrom
  doAssert roundMailFrom.kind == rpkNullPath
  assertSome roundMailFrom.nullPathParams

# ============= H. Mailbox reverse path without parameters =============

testCase reversePathMailboxWithoutParamsRoundTrip:
  ## §8.3 ReversePath mailbox arm with ``parameters = Opt.none``. G33
  ## discriminator (``rpkMailbox`` arm) + G34 parameters nullability.
  ## Wire: ``{"email": "sender@example.com", "parameters": null}`` —
  ## ``Opt.none`` on ``SubmissionAddress.parameters`` emits JSON null,
  ## never key elision (see ``toJson(SubmissionAddress)`` in
  ## ``serde_submission_envelope.nim:432-436``).
  let senderMailbox = parseRFC5321Mailbox("sender@example.com").unsafeGet()
  let senderAddr =
    SubmissionAddress(mailbox: senderMailbox, parameters: Opt.none(SubmissionParams))
  let mailFrom = reversePath(senderAddr)

  let aliceMailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let aliceAddr =
    SubmissionAddress(mailbox: aliceMailbox, parameters: Opt.none(SubmissionParams))
  let rcptTo = parseNonEmptyRcptListFromServer(@[aliceAddr]).unsafeGet()
  let env = Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

  let firstJson = env.toJson()
  let mfNode = firstJson{"mailFrom"}
  doAssert mfNode != nil and mfNode.kind == JObject
  assertJsonFieldEq mfNode, "email", %"sender@example.com"
  let mfParams = mfNode{"parameters"}
  doAssert mfParams != nil and mfParams.kind == JNull

  let parsed = Envelope.fromJson(firstJson)
  assertOk parsed
  let secondJson = parsed.unsafeGet().toJson()
  doAssert firstJson == secondJson, "envelope did not round-trip via JSON"
  let roundMailFrom = parsed.unsafeGet().mailFrom
  doAssert roundMailFrom.kind == rpkMailbox
  assertNone roundMailFrom.sender.parameters

# ============= I. Opt.none vs Opt.some(empty) distinction (G34) =============

testCase parametersOptNoneDistinctFromEmptyObject:
  ## §8.3 G34 pin: ``Opt.none(SubmissionParams)`` and
  ## ``Opt.some(emptyParams)`` are wire-distinct and both must round-trip
  ## preserving the distinction. ``Opt.none`` serialises to JSON null;
  ## ``Opt.some(empty)`` serialises to the empty JSON object ``{}``.
  ## ``parseSubmissionParams(@[])`` is accepted by design (see
  ## ``submission_param.nim:409`` comment and line 431 implementation).
  ## The single most load-bearing serde distinction in envelope coverage.
  let mailbox = parseRFC5321Mailbox("alice@example.com").unsafeGet()
  let addrNone =
    SubmissionAddress(mailbox: mailbox, parameters: Opt.none(SubmissionParams))
  let emptyParams = parseSubmissionParams(@[]).unsafeGet()
  let addrEmpty = SubmissionAddress(mailbox: mailbox, parameters: Opt.some(emptyParams))

  let jsonNone = addrNone.toJson()
  let jsonEmpty = addrEmpty.toJson()

  # Wire-distinct: null versus empty object.
  let pNone = jsonNone{"parameters"}
  doAssert pNone != nil and pNone.kind == JNull
  let pEmpty = jsonEmpty{"parameters"}
  doAssert pEmpty != nil and pEmpty.kind == JObject
  doAssert pEmpty.len == 0

  # Round-trip preserves the distinction.
  let roundNone = SubmissionAddress.fromJson(jsonNone)
  assertOk roundNone
  let jsonNone2 = roundNone.unsafeGet().toJson()
  doAssert jsonNone == jsonNone2, "Opt.none parameters did not round-trip"
  doAssert jsonNone2{"parameters"}.kind == JNull
  assertNone roundNone.unsafeGet().parameters

  let roundEmpty = SubmissionAddress.fromJson(jsonEmpty)
  assertOk roundEmpty
  let jsonEmpty2 = roundEmpty.unsafeGet().toJson()
  doAssert jsonEmpty == jsonEmpty2, "Opt.some(empty) parameters did not round-trip"
  let pEmpty2 = jsonEmpty2{"parameters"}
  doAssert pEmpty2.kind == JObject and pEmpty2.len == 0
  assertSome roundEmpty.unsafeGet().parameters
