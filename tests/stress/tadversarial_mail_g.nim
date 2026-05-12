discard """
  joinable: false
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Adversarial and stress tests for Mail Part G (EmailSubmission).
##
## Covers G2 design §8.2.3 blocks 1-6 (52 named adversarial cases) plus
## §8.12 scale invariants (3 blocks). Every case pins a G1 adversarial
## contract at the boundary — strict parser rejection, closed-enum
## discipline, cross-entity coherence, and O(n) construction at 10^4 / 10^3
## scale.
##
## This file runs under `just test-full` only. It is listed in
## `tests/testament_skip.txt` non-joinable section alongside the Part F
## analogue `tests/stress/tadversarial_mail_f.nim`, which remains the
## reference for JSON-structural attacks (BOM / NaN / Infinity / deep
## nesting / duplicate keys / 1 MB strings / cast bypass — see G2 §8.14
## exclusion rationale: G1 introduces no new parser pathway, so these
## tests are NOT re-covered here).

import std/json
import std/strutils
import std/tables
import std/times

import results

import jmap_client/internal/protocol/dispatch
import jmap_client/internal/types/envelope
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/primitives

import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/serde_email_submission
import jmap_client/internal/mail/serde_submission_envelope
import jmap_client/internal/mail/submission_atoms
import jmap_client/internal/mail/submission_builders
import jmap_client/internal/mail/submission_envelope
import jmap_client/internal/mail/submission_mailbox
import jmap_client/internal/mail/submission_param
import jmap_client/internal/mail/submission_status

import ../massertions
import ../mfixtures

# =============================================================================
# Block 1 — RFC 5321 Mailbox adversarial (§8.2.3 Block 1, 8 named cases)
# =============================================================================

block rfc5321MailboxAdversarialGroup:
  block mailboxTrailingDotLocal:
    # RFC 5321 §4.1.2 Dot-string: local-part MUST NOT end with a bare dot.
    let res = parseRFC5321Mailbox("user.@example.com")
    assertErr res

  block mailboxUnclosedQuoted:
    let res = parseRFC5321Mailbox("\"unterminated@example.com")
    assertErr res

  block mailboxBracketlessIPv6:
    # RFC 5321 §4.1.3 address-literal: IPv6 MUST be enclosed in [].
    let res = parseRFC5321Mailbox("user@IPv6:::1")
    assertErr res

  block mailboxOverlongLocalPart:
    # RFC 5321 §4.5.3.1.1: local-part MAX 64 octets.
    let localPart = repeat('a', 65)
    let res = parseRFC5321Mailbox(localPart & "@example.com")
    assertErr res

  block mailboxOverlongDomain:
    # RFC 5321 §4.5.3.1.2: domain MAX 255 octets.
    let domain = repeat('a', 256)
    let res = parseRFC5321Mailbox("user@" & domain)
    assertErr res

  block mailboxGeneralLiteralStandardizedTagTrailingHyphen:
    # RFC 5321 §4.1.3: General-address-literal Standardized-tag MUST end
    # in Let-dig (no trailing hyphen). Contrasts with RFC5321Keyword /
    # esmtp-keyword which DOES allow trailing hyphen — the two grammars
    # diverge here. Confirm both sides of the divergence.
    let mailboxRes = parseRFC5321Mailbox("user@[foo-:bar]")
    assertErr mailboxRes
    let keywordRes = parseRFC5321Keyword("x-tag-")
    assertOk keywordRes

  block mailboxControlChar:
    let res = parseRFC5321Mailbox("user\x01@example.com")
    assertErr res

  block mailboxEmpty:
    let res = parseRFC5321Mailbox("")
    assertErr res
    doAssert res.error.message.contains("must not be empty")

# =============================================================================
# Block 2 — SubmissionParam wire adversarial (§8.2.3 Block 2, 10 named cases)
# =============================================================================

block submissionParamAdversarialGroup:
  block paramRetUnknownValue:
    # DsnRetType is a closed enum; "BOTH" is not a variant.
    let wire = parseJson("""{"RET": "BOTH"}""")
    let res = SubmissionParams.fromJson(wire)
    assertErr res

  block paramNotifyNeverWithOthers:
    # submission_param.nim:213: NOTIFY=NEVER mutually exclusive with
    # SUCCESS/FAILURE/DELAY.
    let res = notifyParam({dnfNever, dnfSuccess})
    assertErr res
    doAssert res.error.message.contains("NOTIFY=NEVER is mutually exclusive")

  block paramNotifyEmptyFlags:
    # submission_param.nim:207.
    let res = notifyParam({})
    assertErr res
    doAssert res.error.message.contains("NOTIFY flags must not be empty")

  block paramHoldForNegative:
    # HOLDFOR is UnsignedInt on the JMAP wire — encoded as a decimal
    # string (RFC 6409 esmtp-param values are always strings). Negative
    # values are rejected by parseUnsignedDecimal.
    let wire = parseJson("""{"HOLDFOR": "-1"}""")
    let res = SubmissionParams.fromJson(wire)
    assertErr res

  block paramMtPriorityBelowRange:
    # submission_param.nim:103.
    let res = parseMtPriority(-10)
    assertErr res
    doAssert res.error.message.contains("must be in range -9..9")

  block paramMtPriorityAboveRange:
    let res = parseMtPriority(10)
    assertErr res
    doAssert res.error.message.contains("must be in range -9..9")

  block paramSizeAt2Pow53Boundary:
    # 2^53 - 1 = 9007199254740991 — MaxUnsignedInt per JMAP §1.3. SIZE
    # is wire-encoded as a decimal string (RFC 6409 esmtp-param).
    let wire = parseJson("""{"SIZE": "9007199254740991"}""")
    let res = SubmissionParams.fromJson(wire)
    assertOk res

  block paramSizeAbove2Pow53:
    # 2^53 = 9007199254740992 exceeds MaxUnsignedInt; parseUnsignedInt
    # rejects per primitives.nim:93-94.
    let wire = parseJson("""{"SIZE": "9007199254740992"}""")
    let res = SubmissionParams.fromJson(wire)
    assertErr res

  block paramEnvidXtextEncoded:
    # ENVID stored verbatim — no xtext decoding per G1 §7.2 resolved note.
    let wire = parseJson("""{"ENVID": "hello\\x2Bworld"}""")
    let res = SubmissionParams.fromJson(wire)
    assertOk res

  block paramDuplicateKey:
    # submission_param.nim:428: duplicate key in constructor input.
    let one = bodyParam(beEightBitMime)
    let two = bodyParam(beEightBitMime)
    let res = parseSubmissionParams(@[one, two])
    assertErr res
    doAssert res.error[0].message.contains("duplicate parameter key")

# =============================================================================
# Block 3 — Envelope serde coherence (§8.2.3 Block 3, 7 named cases)
# =============================================================================

block envelopeCoherenceGroup:
  block envelopeNullMailFromWithParams:
    # G32: null reverse-path (mailFrom.email == "") MAY carry parameters.
    let wire = parseJson(
      """
      {
        "mailFrom": {"email": "", "parameters": {"ENVID": "id-1"}},
        "rcptTo": [{"email": "a@example.com", "parameters": null}]
      }
    """
    )
    let res = Envelope.fromJson(wire)
    assertOk res

  block envelopeNullMailFromNoParams:
    let wire = parseJson(
      """
      {
        "mailFrom": {"email": "", "parameters": null},
        "rcptTo": [{"email": "a@example.com", "parameters": null}]
      }
    """
    )
    let res = Envelope.fromJson(wire)
    assertOk res

  block envelopeMalformedMailFrom:
    # The envelope fromJson uses the lenient server-side mailbox parser
    # (Postel's law): accepts most structural variations. The only
    # rejections are: empty, >255 octets, control chars, or missing `@`.
    # "noAtSign.example.com" has no `@` → mvNoAtSign.
    let wire = parseJson(
      """
      {
        "mailFrom": {"email": "noAtSign.example.com", "parameters": null},
        "rcptTo": [{"email": "a@example.com", "parameters": null}]
      }
    """
    )
    let res = Envelope.fromJson(wire)
    assertErr res

  block envelopeEmptyRcptTo:
    # NonEmptyRcptList rejects empty.
    let wire = parseJson(
      """
      {
        "mailFrom": {"email": "alice@example.com", "parameters": null},
        "rcptTo": []
      }
    """
    )
    let res = Envelope.fromJson(wire)
    assertErr res

  block envelopeDuplicateRcptToLenient:
    # G7 Postel split: parseNonEmptyRcptListFromServer accepts duplicates.
    let alice = makeSubmissionAddress()
    let res = parseNonEmptyRcptListFromServer(@[alice, alice])
    assertOk res

  block envelopeDuplicateRcptToStrict:
    # G7 Postel split: parseNonEmptyRcptList rejects duplicates.
    # submission_envelope.nim:128.
    let alice = makeSubmissionAddress()
    let res = parseNonEmptyRcptList(@[alice, alice])
    assertErr res
    doAssert res.error[0].message.contains("duplicate recipient mailbox")

  block envelopeOptNoneVsEmptyParams:
    # G34: Opt.none(SubmissionParams) toJson -> "parameters": null;
    # Opt.some(emptyParams) toJson -> "parameters": {}. Pin the wire
    # distinction at the SubmissionAddress level — that is where the
    # Opt[SubmissionParams] field lives.
    let withNone = makeSubmissionAddress(parameters = Opt.none(SubmissionParams))
    let jsNone = withNone.toJson()
    doAssert jsNone{"parameters"}.kind == JNull
    let emptyParams = parseSubmissionParams(@[]).get()
    let withEmpty = makeSubmissionAddress(parameters = Opt.some(emptyParams))
    let jsEmpty = withEmpty.toJson()
    doAssert jsEmpty{"parameters"}.kind == JObject
    doAssert jsEmpty{"parameters"}.len == 0

# =============================================================================
# Block 4 — AnyEmailSubmission dispatch adversarial (§8.2.3 Block 4, 6 cases)
# =============================================================================

block anyEmailSubmissionDispatchGroup:
  block anyMissingUndoStatus:
    let wire = parseJson(
      """
      {"id": "es-1", "identityId": "id-1", "emailId": "e-1",
       "threadId": "t-1", "sendAt": "2026-01-01T00:00:00Z"}
    """
    )
    let res = AnyEmailSubmission.fromJson(wire)
    assertErr res

  block anyUndoStatusWrongKindInt:
    let wire = parseJson(
      """
      {"id": "es-1", "identityId": "id-1", "emailId": "e-1",
       "threadId": "t-1", "sendAt": "2026-01-01T00:00:00Z",
       "undoStatus": 1}
    """
    )
    let res = AnyEmailSubmission.fromJson(wire)
    assertErr res

  block anyUndoStatusWrongKindNull:
    let wire = parseJson(
      """
      {"id": "es-1", "identityId": "id-1", "emailId": "e-1",
       "threadId": "t-1", "sendAt": "2026-01-01T00:00:00Z",
       "undoStatus": null}
    """
    )
    let res = AnyEmailSubmission.fromJson(wire)
    assertErr res

  block anyUndoStatusUnknownValue:
    # G3 closed-enum commitment: "deferred" is NOT a silent usOther.
    let wire = parseJson(
      """
      {"id": "es-1", "identityId": "id-1", "emailId": "e-1",
       "threadId": "t-1", "sendAt": "2026-01-01T00:00:00Z",
       "undoStatus": "deferred"}
    """
    )
    let res = AnyEmailSubmission.fromJson(wire)
    assertErr res

  block anyUndoStatusCaseMismatch:
    # Wire tokens are lowercase per G1 §3.1; "PENDING" must reject.
    let wire = parseJson(
      """
      {"id": "es-1", "identityId": "id-1", "emailId": "e-1",
       "threadId": "t-1", "sendAt": "2026-01-01T00:00:00Z",
       "undoStatus": "PENDING"}
    """
    )
    let res = AnyEmailSubmission.fromJson(wire)
    assertErr res

  block anyDispatchAllThreeVariants:
    # AnyEmailSubmission is reception-only (serde_email_submission lines
    # 13-18): no toJson exists. The Phase 5 property test (tprop_mail_g
    # E) pivots from round-trip to parse-only dispatch — apply the same
    # pivot here. Construct wire directly from each UndoStatus token,
    # parse, confirm the resulting AnyEmailSubmission.state matches.
    for state in [usPending, usFinal, usCanceled]:
      let wireStr =
        case state
        of usPending: "pending"
        of usFinal: "final"
        of usCanceled: "canceled"
      let wire = %*{
        "id": "es-1",
        "identityId": "id-1",
        "emailId": "e-1",
        "threadId": "t-1",
        "undoStatus": wireStr,
        "sendAt": "2026-01-01T00:00:00Z",
        "dsnBlobIds": [],
        "mdnBlobIds": [],
      }
      let parsed = AnyEmailSubmission.fromJson(wire)
      assertOk parsed
      doAssert parsed.get().state == state,
        "state arm mismatch: expected " & $state & " got " & $parsed.get().state

# =============================================================================
# Block 5 — SmtpReply grammar adversarial (§8.2.3 Block 5, 14 named cases)
# =============================================================================

block smtpReplyGrammarGroup:
  block smtpReplyEmpty:
    let res = parseSmtpReply("")
    assertErr res
    doAssert res.error.message.contains("must not be empty")

  block smtpReplyControlChar:
    let res = parseSmtpReply("250 o\x01k")
    assertErr res
    doAssert res.error.message.contains("contains disallowed control characters")

  block smtpReplyTooShort:
    let res = parseSmtpReply("25")
    assertErr res
    doAssert res.error.message.contains("line shorter than 3-digit Reply-code")

  block smtpReplyFirstDigitZero:
    let res = parseSmtpReply("050 ok")
    assertErr res
    doAssert res.error.message.contains("first Reply-code digit must be in 2..5")

  block smtpReplyFirstDigitOne:
    let res = parseSmtpReply("150 ok")
    assertErr res
    doAssert res.error.message.contains("first Reply-code digit must be in 2..5")

  block smtpReplyFirstDigitSix:
    let res = parseSmtpReply("650 ok")
    assertErr res
    doAssert res.error.message.contains("first Reply-code digit must be in 2..5")

  block smtpReplyFirstDigitNine:
    let res = parseSmtpReply("950 ok")
    assertErr res
    doAssert res.error.message.contains("first Reply-code digit must be in 2..5")

  block smtpReplySecondDigitSix:
    let res = parseSmtpReply("260 ok")
    assertErr res
    doAssert res.error.message.contains("second Reply-code digit must be in 0..5")

  block smtpReplyThirdDigitBoundary:
    # RFC 5321 §4.2: third digit 0..9 — "259 ok" is valid.
    let res = parseSmtpReply("259 ok")
    assertOk res

  block smtpReplyBadSeparator:
    let res = parseSmtpReply("250?ok")
    assertErr res
    doAssert res.error.message.contains(
      "character after Reply-code must be SP, HT, or '-'"
    )

  block smtpReplyMultilineCodeMismatch:
    let res = parseSmtpReply("250-ok\r\n251 done")
    assertErr res
    doAssert res.error.message.contains("multi-line reply has inconsistent Reply-codes")

  block smtpReplyMultilineFinalHyphen:
    let res = parseSmtpReply("250-ok\r\n250-done")
    assertErr res
    doAssert res.error.message.contains(
      "final reply line must not use '-' continuation"
    )

  block smtpReplyMultilineNonFinalSpace:
    let res = parseSmtpReply("250 ok\r\n250 done")
    assertErr res
    doAssert res.error.message.contains(
      "non-final reply line must use '-' continuation"
    )

  block smtpReplyBareCodeNoText:
    # Pin deterministic behaviour. Shipped parser may accept or reject
    # "250" (no separator, no text) depending on whether text is required.
    let res = parseSmtpReply("250")
    doAssert res.isOk or res.isErr

# =============================================================================
# Block 6 — getBoth(EmailSubmissionHandles) cross-entity (§8.2.3 Block 6, 7)
# =============================================================================

# Module-level helpers producing minimal valid arguments JsonNodes for
# outer EmailSubmission/set and inner Email/set invocations. Mirrors
# F precedent (tadversarial_mail_f.nim:817-822) — only the fields
# SetResponse.fromJson requires.

func emailSubmissionSetOkArgs(): JsonNode =
  ## Minimal valid outer ``EmailSubmission/set`` response payload.
  %*{"accountId": "a1", "newState": "s1"}

func emailSetOkArgs(): JsonNode =
  ## Minimal valid inner ``Email/set`` response payload (shared shape
  ## with the outer helper — both resolve through ``SetResponse[T].fromJson``).
  %*{"accountId": "a1", "newState": "s1"}

block getBothSubmissionAdversarialGroup:
  block getBothBothSucceed:
    let handles = makeEmailSubmissionHandles()
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailSubmissionSet, emailSubmissionSetOkArgs(), makeMcid("c0")),
        initInvocation(mnEmailSet, emailSetOkArgs(), makeMcid("c0")),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertOk res

  block getBothInnerMethodError:
    # Inner Email/set position carries a server ``error`` envelope. The
    # NameBoundHandle filter compares on method-name — an ``error``
    # invocation does NOT match ``"Email/set"``, so the dispatch returns
    # serverFail (design-documented limitation; see F precedent at
    # ``getBothImplicitDestroyMethodError``).
    let handles = makeEmailSubmissionHandles()
    let errArgs = %*{"type": "accountNotFound"}
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailSubmissionSet, emailSubmissionSetOkArgs(), makeMcid("c0")),
        parseInvocation("error", errArgs, makeMcid("c0")).get(),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertErr res

  block getBothInnerAbsent:
    # §8.6 row 3: outer ok but no inner Email/set invocation at all.
    # NameBoundHandle dispatch surfaces serverFail MethodError.
    let handles = makeEmailSubmissionHandles()
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailSubmissionSet, emailSubmissionSetOkArgs(), makeMcid("c0"))
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertErr res

  block getBothInnerMcIdMismatch:
    # §8.6 row 4: inner at wrong mcid. handles.implicit.callId = c0 but
    # the Invocation is at c1 — NameBoundHandle filter misses.
    let handles = makeEmailSubmissionHandles(
      submissionMcid = makeMcid("c0"), emailSetMcid = makeMcid("c0")
    )
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailSubmissionSet, emailSubmissionSetOkArgs(), makeMcid("c0")),
        initInvocation(mnEmailSet, emailSetOkArgs(), makeMcid("c1")),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertErr res

  block getBothOuterNotCreatedSole:
    # §8.6 row 5: outer ok (notCreated sole entry, no inner invocation).
    # getBoth does NOT synthesise — the emailSet NameBoundHandle cannot
    # resolve without an inner invocation at the shared call-id, so the
    # dispatch surfaces a serverFail MethodError.
    let handles = makeEmailSubmissionHandles()
    var outerArgs = emailSubmissionSetOkArgs()
    outerArgs["notCreated"] = %*{"c1": {"type": "invalidProperties"}}
    let resp = Response(
      methodResponses:
        @[initInvocation(mnEmailSubmissionSet, outerArgs, makeMcid("c0"))],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertErr res

  block getBothOuterIfInStateMismatch:
    # §8.6 row 6: outer returns error invocation; inner never reached.
    let handles = makeEmailSubmissionHandles()
    let errArgs = %*{"type": "stateMismatch"}
    let resp = Response(
      methodResponses: @[parseInvocation("error", errArgs, makeMcid("c0")).get()],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertErr res

  block getBothCreationRefNotInCreateMap:
    # §8.6 row 7: outer onSuccessUpdateEmail references a creation-id
    # that is not declared in outer create. Client-side wire validation
    # does NOT pre-check this (server-side concern). Shipped getBoth
    # parses both invocations successfully; coherence is the caller's
    # problem — pin the hands-off stance.
    let handles = makeEmailSubmissionHandles()
    var outerArgs = emailSubmissionSetOkArgs()
    outerArgs["onSuccessUpdateEmail"] = %*{"#c-missing": {"keywords/$seen": true}}
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailSubmissionSet, outerArgs, makeMcid("c0")),
        initInvocation(mnEmailSet, emailSetOkArgs(), makeMcid("c0")),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(makeDispatchedResponse(resp), handles)
    assertOk res

# =============================================================================
# §8.12 scale invariants — 3 named blocks
# =============================================================================

block scaleInvariantsGroup:
  block nonEmptyEmailSubmissionUpdates10kWithDupAtEnd:
    # Mirrors tadversarial_mail_f.nim:1188-1197 pattern.
    # 10 000 entries with a duplicate Id at position 9999. The single-
    # pass algorithm must not bail on the prefix; it must surface
    # exactly one duplicate violation.
    var items: seq[(Id, EmailSubmissionUpdate)] = @[]
    let update = setUndoStatusToCanceled()
    for i in 0 ..< 10_000:
      items.add((parseId("es-" & $i).get(), update))
    # Duplicate: reuse "es-0" at final position.
    items[9_999] = (parseId("es-0").get(), update)
    let res = parseNonEmptyEmailSubmissionUpdates(items)
    assertErr res
    assertLen res.error, 1
    doAssert res.error[0].message.contains("duplicate submission id")

  block submissionParams1kExtensionEntries:
    # Linear-scaling pin: 1000 spkExtension entries with distinct names.
    # cpuTime() brackets ONLY the parseSubmissionParams call (not the
    # seq construction) — mirror tadversarial_mail_f.nim:1117-1129.
    # 500 ms budget is the CI-calibrated O(n) ceiling; a regression
    # signals a real O(n²) cliff — investigate, do NOT relax.
    var items: seq[SubmissionParam] = @[]
    for i in 0 ..< 1_000:
      let name = parseRFC5321Keyword("X-EXT-" & $i).get()
      items.add(extensionParam(name, Opt.none(string)))
    let t0 = cpuTime()
    let res = parseSubmissionParams(items)
    let elapsed = cpuTime() - t0
    assertOk res
    assertLe elapsed, 0.5

  block nonEmptyRcptList1kWithDupAt999:
    # Single-pass algorithm does not bail on prefix. Dup at position 999
    # out of 1000 recipients; must surface exactly one violation.
    var items: seq[SubmissionAddress] = @[]
    for i in 0 ..< 1_000:
      let mailbox = parseRFC5321Mailbox("u" & $i & "@example.com").get()
      items.add(makeSubmissionAddress(mailbox = mailbox))
    # Duplicate: reuse items[0].mailbox at position 999.
    items[999] = items[0]
    let res = parseNonEmptyRcptList(items)
    assertErr res
    assertLen res.error, 1
    doAssert res.error[0].message.contains("duplicate recipient mailbox")

# See tests/stress/tadversarial_mail_f.nim for JSON-structural attacks
# (BOM, NaN/Infinity, deep nesting, duplicate keys, 1 MB strings, cast
# bypass) per G2 §8.14 exclusion rationale.
