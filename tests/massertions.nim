# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Template-based assertion helpers for Result, Option, and JSON types.
## Templates ensure line numbers point to the calling test block on failure.

import std/strutils
import std/json
import std/times

import jmap_client/internal/types/validation
import jmap_client/internal/types/errors
import jmap_client/internal/types/capabilities
import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/headers
import jmap_client/internal/mail/submission_param
import jmap_client/internal/mail/submission_status
import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/serde_email_submission

import ./mfixtures
import ./m_l2_serde
export m_l2_serde

{.push ruleOff: "hasDoc".}

template assertOk*(expr: untyped) =
  ## Verifies a Result is ok, or that an expression evaluates without panic.
  when compiles(expr.isOk):
    let res = expr
    doAssert res.isOk, "expected Ok result, got Err"
  else:
    discard expr

template assertErr*(expr: untyped) =
  ## Verifies a Result is err.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"

template toValidationShape(err: untyped): ValidationError =
  ## Normalises an error rail value to ``ValidationError`` shape so the
  ## existing substring/field-matching helpers dispatch against either
  ## an L1 ``ValidationError`` (unchanged) or an L2 ``SerdeViolation``
  ## (translated via ``toValidationError``). The ``rootType`` of
  ## ``"Serde"`` is a synthetic label — tests should prefer
  ## ``assertSvKind`` / ``assertSvInner`` when asserting at the serde
  ## boundary; this bridge only preserves existing substring tests.
  when err is SerdeViolation:
    toValidationError(err, "Serde")
  else:
    err

template assertErrFields*(expr: untyped, tn, expectedMsg, val: string) =
  ## Verifies error fields on a Result.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let e = toValidationShape(res.error)
  doAssert e.typeName == tn, "typeName: expected " & tn & ", got " & e.typeName
  doAssert e.message == expectedMsg,
    "message: expected " & expectedMsg & ", got " & e.message
  doAssert e.value == val, "value: expected " & val & ", got " & e.value

template assertErrType*(expr: untyped, tn: string) =
  ## Verifies the typeName field of a Result error.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  doAssert toValidationShape(res.error).typeName == tn

template assertErrMsg*(expr: untyped, expectedMsg: string) =
  ## Verifies the message field of a Result error.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  doAssert toValidationShape(res.error).message == expectedMsg

template assertSome*(o: untyped) =
  doAssert o.isSome, "expected Some, got None"

template assertNone*(o: untyped) =
  doAssert o.isNone, "expected None, got Some"

template assertEq*(actual, expected: untyped) =
  ## Value-displaying equality assertion. Shows both sides on failure.
  let a = actual
  let e = expected
  doAssert a == e, "expected " & $e & ", got " & $a

template assertErrContains*(expr: untyped, substring: string) =
  ## Verifies the message field of a Result error contains a substring.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let m = toValidationShape(res.error).message
  doAssert strutils.contains(m, substring),
    "expected message containing '" & substring & "', got '" & m & "'"

# ---------------------------------------------------------------------------
# SerdeViolation assertions (structural — NOT substring-based)
# ---------------------------------------------------------------------------
# These replace the pattern ``assertErrContains(res, "missing X")`` that used
# to paper over stringly-typed serde errors. Pattern-match on the ADT kind
# instead; variant fields live under each ``of`` arm (see ``SerdeViolation``
# in ``serde.nim``).

template assertSvKind*(expr: untyped, expected: SerdeViolationKind) =
  ## Verifies that a Result[_, SerdeViolation] err is the expected kind.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let sv = res.error
  doAssert sv.kind == expected, "expected svk " & $expected & ", got " & $sv.kind

template assertSvPath*(expr: untyped, expectedRfc6901: string) =
  ## Verifies the RFC 6901 JSON-Pointer rendering of the violation's path.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let actual = $res.error.path
  doAssert actual == expectedRfc6901,
    "expected path '" & expectedRfc6901 & "', got '" & actual & "'"

template assertSvInner*(expr: untyped, innerTypeName: string) =
  ## Verifies an ``svkFieldParserFailed`` violation and that the inner
  ## ValidationError carries the given ``typeName``. Use when bridging
  ## to L1 smart-constructor failures propagated through serde.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let sv = res.error
  doAssert sv.kind == svkFieldParserFailed,
    "expected svkFieldParserFailed, got " & $sv.kind
  doAssert sv.inner.typeName == innerTypeName,
    "expected inner typeName '" & innerTypeName & "', got '" & sv.inner.typeName & "'"

template assertSvTranslated*(expr: untyped, rootType: string, substring: string) =
  ## Bridge helper: translates a ``SerdeViolation`` to the wire
  ## ``ValidationError`` via ``toValidationError`` and asserts the
  ## rendered message contains ``substring``. Use when a test genuinely
  ## exercises the translator boundary (e.g. end-to-end failure shape
  ## inspection); prefer ``assertSvKind`` for pure serde-layer assertions.
  let res = expr
  doAssert res.isErr, "expected Err result, got Ok"
  let ve = toValidationError(res.error, rootType)
  doAssert strutils.contains(ve.message, substring),
    "expected translated message containing '" & substring & "', got '" & ve.message &
      "'"

template assertOkEq*(expr: untyped, expected: untyped) =
  ## Evaluates expr (Result) and verifies its Ok value equals expected.
  let res = expr
  doAssert res.isOk, "expected Ok result, got Err"
  let v = res.get()
  let e = expected
  doAssert v == e, "expected " & $e & ", got " & $v

template assertNotCompiles*(expr: untyped) =
  ## Verifies that the given expression does not compile.
  doAssert not compiles(expr), "expected expression to not compile"

template assertLen*(collection: untyped, expected: int) =
  ## Verifies collection length equals expected.
  let actual = collection.len
  let exp = expected
  doAssert actual == exp, "expected len " & $exp & ", got " & $actual

template assertSomeEq*(o: untyped, expected: untyped) =
  ## Verifies Option is Some and its value equals expected.
  doAssert o.isSome, "expected Some, got None"
  let v = o.get()
  let e = expected
  doAssert v == e, "expected " & $e & ", got " & $v

template assertGe*(actual, expected: untyped) =
  ## Verifies actual >= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a >= e, "expected " & $a & " >= " & $e

template assertLe*(actual, expected: untyped) =
  ## Verifies actual <= expected with diagnostics.
  let a = actual
  let e = expected
  doAssert a <= e, "expected " & $a & " <= " & $e

template assertFalse*(expr: untyped, msg: string) =
  ## Annotated boolean negation assertion with context message.
  doAssert not expr, msg

template assertJsonFieldEq*(obj: JsonNode, key: string, expected: untyped) =
  ## Verifies a JSON object field is present and its value equals expected.
  let field = obj{key}
  doAssert field != nil, "expected field '" & key & "' to be present"
  let actual = field
  let exp = expected
  doAssert actual == exp, "field '" & key & "': expected " & $exp & ", got " & $actual

template assertCapOkEq*(expr: untyped, expected: ServerCapability) =
  ## Evaluates expr and verifies its ServerCapability value equals expected.
  let v = expr
  doAssert capEq(v, expected), "ServerCapability values differ"

template assertSetOkEq*(expr: untyped, expected: SetError) =
  ## Evaluates expr and verifies its SetError value equals expected.
  let v = expr
  doAssert setErrorEq(v, expected), "SetError values differ"

# ---------------------------------------------------------------------------
# Mail Part E assertion templates (L-1..L-9). Design §6.5.5 is authoritative.
# ---------------------------------------------------------------------------

template assertBlueprintErr*(expr: untyped, variant: EmailBlueprintConstraint) =
  ## L-1: verifies a Result is err AND at least one error carries the
  ## given ``EmailBlueprintConstraint`` variant. Delegates the isErr
  ## check to ``assertErr`` so diagnostic wording stays consistent.
  let res = expr
  assertErr res
  var found = false
  for e in res.unsafeError.items:
    if e.constraint == variant:
      found = true
      break
  doAssert found,
    "expected Err containing variant " & $variant & ", got " & $res.unsafeError

template assertBlueprintErrContains*(
    expr: untyped, variant: EmailBlueprintConstraint, field, expected: untyped
) =
  ## L-2: verifies a Result is err AND at least one error matches both
  ## the variant discriminant and a variant-specific field value. The
  ## discriminant guard precedes the field read, which is what keeps the
  ## case-object field access safe at runtime.
  let res = expr
  assertErr res
  var matched = false
  for e in res.unsafeError.items:
    if e.constraint == variant and e.field == expected:
      matched = true
      break
  doAssert matched,
    "variant " & $variant & " with expected field value not found: " & $res.unsafeError

template assertBlueprintErrCount*(expr: untyped, n: int) =
  ## L-3: exact-count assertion on the accumulated error rail. Verifies
  ## that every violation was surfaced, not just the first.
  let res = expr
  assertErr res
  let actual = res.unsafeError.len
  doAssert actual == n, "expected " & $n & " errors, got " & $actual

template assertBlueprintOkEq*(expr: untyped, expected: EmailBlueprint) =
  ## L-4: ok-rail equality via K-7 ``emailBlueprintEq``. Parallel to
  ## ``assertCapOkEq`` / ``assertSetOkEq`` above — delegates the
  ## value-level comparison to the dedicated helper rather than relying
  ## on a compiler-generated ``==`` that cannot traverse case objects.
  let res = expr
  doAssert res.isOk, "expected Ok result, got Err"
  let v = res.get()
  doAssert emailBlueprintEq(v, expected), "EmailBlueprint values differ"

template assertJsonKeyAbsent*(node: JsonNode, key: string) =
  ## L-5: symmetric complement of ``assertJsonFieldEq`` — asserts that
  ## an optional serde field was omitted from the encoded object.
  let field = node{key}
  doAssert field == nil, "expected field '" & key & "' to be absent"

template assertJsonHasHeaderKey*(
    node: JsonNode, name: string, form: HeaderForm, isAll = false
) =
  ## L-6 (presence half): composes the ``"header:Name:asForm[:all]"``
  ## wire key and asserts it is present on ``node``. Exploits that each
  ## ``HeaderForm`` variant's backing string IS the wire ``as*`` suffix.
  let suffix = if isAll: ":all" else: ""
  let wireKey = "header:" & name & ":" & $form & suffix
  let field = node{wireKey}
  doAssert field != nil, "expected header key '" & wireKey & "' present"

template assertJsonMissingHeaderKey*(
    node: JsonNode, name: string, form: HeaderForm, isAll = false
) =
  ## L-6 (absence half): asserts the composed header wire key is NOT
  ## present on ``node``.
  let suffix = if isAll: ":all" else: ""
  let wireKey = "header:" & name & ":" & $form & suffix
  doAssert node{wireKey} == nil, "expected header key '" & wireKey & "' absent"

template assertBlueprintErrAny*(
    expr: untyped, variants: set[EmailBlueprintConstraint]
) =
  ## L-7: every variant in ``variants`` must appear at least once on the
  ## error rail. Useful for accumulated-failure scenarios where multiple
  ## independent checks fire.
  let res = expr
  assertErr res
  var seen: set[EmailBlueprintConstraint] = {}
  for e in res.unsafeError.items:
    if e.constraint in variants:
      seen.incl e.constraint
  let missing = variants - seen
  doAssert missing == {}, "missing variants: " & $missing

template assertBoundedRatio*(slowExpr, fastExpr: untyped, maxRatio: float) =
  ## L-8: runtime bound on the ratio of two ``cpuTime`` measurements.
  ## Callers supply an ``expensive`` and ``baseline`` expression; this
  ## template enforces ``expensive / baseline <= maxRatio`` (HashDoS
  ## gate). Guard against division by zero when the baseline resolves
  ## below clock resolution.
  let startFast = cpuTime()
  discard fastExpr
  let fastElapsed = cpuTime() - startFast
  let startSlow = cpuTime()
  discard slowExpr
  let slowElapsed = cpuTime() - startSlow
  let ratio =
    if fastElapsed <= 0.0:
      0.0
    else:
      slowElapsed / fastElapsed
  doAssert ratio <= maxRatio, "ratio " & $ratio & " exceeds bound " & $maxRatio

template assertJsonStringEquals*(node: JsonNode, key: string, exactBytes: string) =
  ## L-9: byte-exact string-field match. Unlike ``assertJsonFieldEq``,
  ## this helper pins ``JString`` kind AND compares the decoded string
  ## byte-for-byte, including embedded escapes.
  let field = node{key}
  doAssert field != nil, "expected field '" & key & "' present"
  doAssert field.kind == JString, "expected JString, got " & $field.kind
  let actual = field.getStr()
  doAssert actual == exactBytes,
    "field '" & key & "': expected '" & exactBytes & "', got '" & actual & "'"

# ---------------------------------------------------------------------------
# Mail Part G assertion templates. Wrap the ``*Eq`` helpers from
# ``mfixtures.nim`` (delegating to source-side ``==``) and the
# ``IdOrCreationRef`` wire-shape pin (delegating to L2 ``toJson``).
# ---------------------------------------------------------------------------

template assertPhantomVariantEq*(actual, expected: AnyEmailSubmission) =
  ## Asserts ``UndoStatus`` discriminator equality and branch-dispatched
  ## payload equality. Wraps ``anyEmailSubmissionEq`` with diagnostic
  ## output. Used by ``tprop_mail_g.nim`` Group E for the
  ## ``AnyEmailSubmission`` round-trip property.
  doAssert anyEmailSubmissionEq(actual, expected),
    "AnyEmailSubmission mismatch:\n  actual:   " & $actual & "\n  expected: " & $expected

template assertDeliveryStatusMapEq*(actual, expected: DeliveryStatusMap) =
  ## Distinct-table equality honouring ``RFC5321Mailbox`` byte-equal key
  ## semantics. Wraps ``deliveryStatusMapEq`` with diagnostic output.
  doAssert deliveryStatusMapEq(actual, expected),
    "DeliveryStatusMap mismatch:\n  actual:   " & $actual & "\n  expected: " & $expected

template assertSubmissionParamKeyEq*(a, b: SubmissionParamKey) =
  ## Identity check across the 12-kind matrix (the ``spkExtension`` arm
  ## carries an extension name; the 11 standard kinds are nullary). Wraps
  ## ``submissionParamKeyEq`` with diagnostic output. Used by
  ## ``tsubmission_params.nim`` unit blocks.
  doAssert submissionParamKeyEq(a, b),
    "SubmissionParamKey mismatch:\n  a: " & $a & "\n  b: " & $b

template assertIdOrCreationRefWire*(v: IdOrCreationRef, expected: string) =
  ## Wire-form pin: ``directRef(id)`` serialises as ``$id``;
  ## ``creationRef(cid)`` serialises as ``"#" & $cid``. Mirrors
  ## ``assertJsonStringEquals`` in shape — pins ``JString`` kind AND
  ## compares the decoded string byte-for-byte. Used by
  ## ``tonsuccess_extras.nim`` wire-shape blocks.
  let node = toJson(v)
  doAssert node.kind == JString,
    "expected JString from IdOrCreationRef, got " & $node.kind
  let actual = node.getStr()
  doAssert actual == expected,
    "IdOrCreationRef wire mismatch:\n  actual:   " & actual & "\n  expected: " & expected
