# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Adversarial and edge-case tests probing byte-level validation semantics,
## UTF-8 boundary behaviour, NUL-byte acceptance in permissive types,
## nimIdentNormalize false matches in enum parsing, and 255-byte boundary
## conditions with multi-byte characters.

import std/json
import std/sets
import std/strutils
import std/tables

import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/framework
import jmap_client/internal/types/errors
import jmap_client/internal/types/session
import jmap_client/internal/types/envelope
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/serialisation/serde_session

import ../massertions
import ../mfixtures
import ../mtestblock

# =============================================================================
# a) Multi-byte UTF-8 at 255-byte boundary
# =============================================================================
# Validates byte-not-character semantics: the length check counts octets, not
# Unicode code points.

testCase idFromServerTwoByteCharsAt255Bytes:
  ## 127 x \xC3\xA9 (2 bytes each) + 1 ASCII char = 255 bytes: ACCEPTED.
  let input = "\xC3\xA9".repeat(127) & "a"
  doAssert input.len == 255
  assertOk parseIdFromServer(input)

testCase accountIdTwoByteCharsAt255Bytes:
  ## Same 255-byte string accepted by parseAccountId.
  let input = "\xC3\xA9".repeat(127) & "a"
  doAssert input.len == 255
  assertOk parseAccountId(input)

testCase idFromServerTwoByteCharsAt256Bytes:
  ## 128 x \xC3\xA9 = 256 bytes: REJECTED (byte-not-character semantics).
  let input = "\xC3\xA9".repeat(128)
  doAssert input.len == 256
  assertErr parseIdFromServer(input)

testCase accountIdTwoByteCharsAt256Bytes:
  ## 128 x \xC3\xA9 = 256 bytes: REJECTED.
  let input = "\xC3\xA9".repeat(128)
  doAssert input.len == 256
  assertErr parseAccountId(input)

# =============================================================================
# b) Invalid UTF-8 acceptance (Layer 1 validates bytes, not Unicode)
# =============================================================================
# These document intentional behaviour: the validators check byte values
# against control-character ranges, not Unicode well-formedness.

testCase idFromServerOverlongNul:
  ## Overlong NUL encoding \xC0\x80: ACCEPTED by lenient parser.
  ## Both bytes are >= 0x20 so they pass the control-character check.
  const input = "abc\xC0\x80def"
  assertOk parseIdFromServer(input)

testCase accountIdOverlongNul:
  ## Overlong NUL encoding \xC0\x80: ACCEPTED by parseAccountId.
  const input = "abc\xC0\x80def"
  assertOk parseAccountId(input)

testCase idFromServerUtf16Surrogate:
  ## UTF-16 surrogate \xED\xA0\x80: ACCEPTED (all bytes >= 0x20, none == 0x7F).
  const input = "abc\xED\xA0\x80def"
  assertOk parseIdFromServer(input)

testCase idFromServerTruncatedMultibyte:
  ## Truncated multi-byte sequence "abc\xC3": ACCEPTED by lenient parser.
  ## 0xC3 is >= 0x20 and not 0x7F.
  const input = "abc\xC3"
  assertOk parseIdFromServer(input)

testCase accountIdTruncatedMultibyte:
  ## Truncated multi-byte sequence: ACCEPTED by parseAccountId.
  const input = "abc\xC3"
  assertOk parseAccountId(input)

# =============================================================================
# c) C1 control codes (0x80-0x9F)
# =============================================================================
# These are Unicode control characters (C1 block) but at byte level they are
# >= 0x20 and not 0x7F, so the validators accept them.

testCase idFromServerC1NextLine:
  ## NEL (U+0085) encoded as \xC2\x85: ACCEPTED.
  ## Both 0xC2 and 0x85 are >= 0x20 and not 0x7F.
  const input = "abc\xC2\x85def"
  assertOk parseIdFromServer(input)

testCase accountIdC1Byte9F:
  ## Raw byte 0x9F: ACCEPTED (>= 0x20, not 0x7F).
  ## This is the APC control character in Unicode, but the check is byte-level.
  const input = "abc\x9Fdef"
  assertOk parseAccountId(input)

testCase idFromServerC1Byte80:
  ## Raw byte 0x80: ACCEPTED (>= 0x20, not 0x7F).
  const input = "abc\x80def"
  assertOk parseIdFromServer(input)

testCase jmapStateC1Byte85:
  ## Raw byte 0x85 in JmapState: ACCEPTED.
  const input = "abc\x85def"
  assertOk parseJmapState(input)

# =============================================================================
# d) Unicode special characters
# =============================================================================

testCase idStrictRejectsBom:
  ## BOM \xEF\xBB\xBF contains bytes outside Base64UrlChars: REJECTED by strict.
  const input = "\xEF\xBB\xBFabc"
  assertErr parseId(input)

testCase idFromServerAcceptsBom:
  ## BOM bytes are all >= 0x20: ACCEPTED by lenient parser.
  const input = "\xEF\xBB\xBFabc"
  assertOk parseIdFromServer(input)

testCase idFromServerZeroWidthSpace:
  ## Zero-width space U+200B encoded as \xE2\x80\x8B: ACCEPTED.
  ## All 3 bytes are >= 0x20 and not 0x7F.
  const input = "\xE2\x80\x8B"
  doAssert input.len == 3
  assertOk parseIdFromServer(input)

testCase accountIdAcceptsBom:
  ## BOM accepted by parseAccountId (bytes >= 0x20, not 0x7F).
  const input = "\xEF\xBB\xBFabc"
  assertOk parseAccountId(input)

# =============================================================================
# e) NUL bytes in permissive types (FFI concern)
# =============================================================================
# parseMethodCallId and parsePropertyName only check non-empty. parseCreationId
# checks non-empty and first char != '#'. None perform control-character checks.

testCase methodCallIdNulByte:
  ## parseMethodCallId("\x00").get(): ACCEPTED (only checks non-empty).
  assertOk parseMethodCallId("\x00")

testCase creationIdNulFirstChar:
  ## parseCreationId("\x00abc").get(): ACCEPTED (first char is \x00, not '#').
  assertOk parseCreationId("\x00abc")

testCase propertyNameNulByte:
  ## parsePropertyName("\x00").get(): ACCEPTED (only checks non-empty).
  assertOk parsePropertyName("\x00")

testCase methodCallIdEmbeddedNul:
  ## "c1\x00hidden": ACCEPTED (no control-character check in MethodCallId).
  assertOk parseMethodCallId("c1\x00hidden")

testCase creationIdEmbeddedNul:
  ## "abc\x00def": ACCEPTED (only first char is checked against '#').
  assertOk parseCreationId("abc\x00def")

testCase propertyNameEmbeddedNul:
  ## "foo\x00bar": ACCEPTED (only non-empty check).
  assertOk parsePropertyName("foo\x00bar")

# =============================================================================
# f) nimIdentNormalize false matches in enum parsing
# =============================================================================
# strutils.parseEnum uses nimIdentNormalize which strips underscores (except
# leading) and lowercases everything except the first character. This produces
# surprising matches when underscores appear in input strings.

testCase methodErrorTypeUnderscoreStripped:
  ## "server_Fail" normalises to "serverfail", matching "serverFail" -> metServerFail.
  doAssert parseMethodErrorType("server_Fail") == metServerFail

testCase methodErrorTypeCaseInsensitiveAfterFirst:
  ## "serverfail" normalises same as "serverFail": both become "serverfail".
  doAssert parseMethodErrorType("serverfail") == metServerFail

testCase methodErrorTypeFirstCharCaseSensitive:
  ## "SERVERFAIL": first char 'S' differs from 's' in "serverFail" -> metUnknown.
  doAssert parseMethodErrorType("SERVERFAIL") == metUnknown

testCase setErrorTypeUnderscoreStripped:
  ## "over_Quota" normalises to "overquota", matching "overQuota" -> setOverQuota.
  doAssert parseSetErrorType("over_Quota") == setOverQuota

testCase setErrorTypeMixedCaseAndUnderscore:
  ## "too_large" normalises to "toolarge", matching "tooLarge" -> setTooLarge.
  doAssert parseSetErrorType("too_large") == setTooLarge

testCase capabilityKindUnderscoreFalseMatch:
  ## "urn:ietf:params:jmap:co_re" normalises to "urn:ietf:params:jmap:core",
  ## matching ckCore's backing string. This is a nimIdentNormalize artefact.
  doAssert parseCapabilityKind("urn:ietf:params:jmap:co_re") == ckCore

testCase requestErrorTypeUnderscoreFalseMatch:
  ## "urn:ietf:params:jmap:error:not_JSON" normalises to
  ## "urn:ietf:params:jmap:error:notjson", matching retNotJson's backing.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:not_JSON") == retNotJson

testCase requestErrorTypeUnderscoreInLimit:
  ## "urn:ietf:params:jmap:error:li_mit" normalises to
  ## "urn:ietf:params:jmap:error:limit", matching retLimit.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:li_mit") == retLimit

testCase methodErrorTypeMultipleUnderscores:
  ## "invalid__Arguments" -> "invalidarguments" matches metInvalidArguments.
  doAssert parseMethodErrorType("invalid__Arguments") == metInvalidArguments

testCase methodErrorTypeTrailingUnderscore:
  ## "forbidden_" -> "forbidden" matches metForbidden.
  doAssert parseMethodErrorType("forbidden_") == metForbidden

testCase setErrorTypeFirstCharMismatch:
  ## "Forbidden" -> first char 'F' differs from 'f' in "forbidden" -> setUnknown.
  doAssert parseSetErrorType("Forbidden") == setUnknown

testCase capabilityKindFirstCharMismatch:
  ## "URN:..." first char 'U' differs from 'u' in "urn:..." -> ckUnknown.
  doAssert parseCapabilityKind("URN:IETF:PARAMS:JMAP:CORE") == ckUnknown

# =============================================================================
# g) CreationId edge case: bare '#'
# =============================================================================

testCase creationIdBareHash:
  ## Bare "#" is rejected: starts with '#'.
  assertErrFields parseCreationId("#"), "CreationId", "must not include '#' prefix", "#"

testCase creationIdHashOnly:
  ## Multiple hashes: first char is '#', so rejected.
  assertErr parseCreationId("###")

# =============================================================================
# h) NUL byte injection in additional types (FFI surface)
# =============================================================================
# Types that accept bare strings without control-character checking may contain
# NUL bytes. When these strings cross FFI to C, strlen() truncates at the NUL,
# making the C side see a different (shorter) string than the Nim side.

testCase uriTemplateAcceptsNul:
  ## parseUriTemplate only checks non-empty; NUL bytes pass validation.
  assertOk parseUriTemplate("https://evil.com\x00/{accountId}")

testCase uriTemplateNulAtStart:
  ## NUL as the first character: non-empty, so accepted.
  assertOk parseUriTemplate("\x00valid")

testCase invocationNameAcceptsNul:
  ## Invocation.rawName is a bare string with no validation (wire boundary).
  let inv = parseInvocation("Email/get\x00Evil/set", newJObject(), makeMcid("c0")).get()
  doAssert inv.rawName.len == 18

testCase resultReferencePathAcceptsNul:
  ## ResultReference.rawPath is a bare string; NUL bytes are preserved.
  let rr = parseResultReference(
      resultOf = makeMcid("c0"), name = "Email/get", path = "/ids\x00/evil"
    )
    .get()
  doAssert rr.rawPath.len == 10

testCase resultReferenceNameAcceptsNul:
  ## ResultReference.rawName is a bare string; NUL bytes are preserved.
  let rr = parseResultReference(
      resultOf = makeMcid("c0"), name = "Email/get\x00hidden", path = "/ids"
    )
    .get()
  doAssert rr.rawName.len == 16

testCase requestUsingAcceptsNul:
  ## Request.using elements are bare strings; NUL bytes are not checked.
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core\x00evil"],
    methodCalls: @[],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`[0].len == 30

testCase transportErrorMessageAcceptsNul:
  ## TransportError.message is a bare string; NUL bytes are preserved.
  let te = transportError(tekNetwork, "connection\x00refused")
  doAssert te.message.len == 18

testCase accountNameAcceptsNul:
  ## Account.name is a bare string; NUL bytes are preserved.
  let acct = Account(
    name: "admin\x00@evil.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[],
  )
  doAssert acct.name.len == 15

# =============================================================================
# i) Overlong UTF-8 encodings beyond NUL
# =============================================================================
# The lenient validators check byte values (>= 0x20, not 0x7F), not UTF-8
# well-formedness. Overlong encodings of control characters have high bytes
# that pass this check.

testCase idFromServerOverlongNewline:
  ## Overlong encoding of newline (0x0A): \xC0\x8A. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x8Adef")

testCase idFromServerOverlongCarriageReturn:
  ## Overlong encoding of CR (0x0D): \xC0\x8D. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x8Ddef")

testCase idFromServerOverlongTab:
  ## Overlong encoding of tab (0x09): \xC0\x89. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x89def")

testCase idFromServerThreeByteOverlongNul:
  ## 3-byte overlong NUL \xE0\x80\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xE0\x80\x80def")

testCase idFromServerFourByteOverlongNul:
  ## 4-byte overlong NUL \xF0\x80\x80\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xF0\x80\x80\x80def")

# =============================================================================
# j) UTF-8 truncation and continuation byte edge cases
# =============================================================================

testCase idFromServerTruncated3Byte1:
  ## Truncated 3-byte sequence: 1 of 3 bytes. 0xE2 >= 0x20, accepted.
  assertOk parseIdFromServer("abc\xE2")

testCase idFromServerTruncated3Byte2:
  ## Truncated 3-byte sequence: 2 of 3 bytes. Both >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xE2\x80")

testCase idFromServerTruncated4Byte1:
  ## Truncated 4-byte sequence: 1 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0")

testCase idFromServerTruncated4Byte2:
  ## Truncated 4-byte sequence: 2 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0\x9F")

testCase idFromServerTruncated4Byte3:
  ## Truncated 4-byte sequence: 3 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0\x9F\x98")

testCase idFromServerLoneLowSurrogate:
  ## Lone low surrogate \xED\xB0\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xED\xB0\x80def")

testCase idFromServerInvalid5ByteSequence:
  ## 5-byte sequence \xF8\x80\x80\x80\x80: never valid UTF-8, but all >= 0x80.
  assertOk parseIdFromServer("\xF8\x80\x80\x80\x80")

testCase idFromServerInvalid6ByteSequence:
  ## 6-byte sequence \xFC\x80\x80\x80\x80\x80: never valid UTF-8, but all >= 0x80.
  assertOk parseIdFromServer("\xFC\x80\x80\x80\x80\x80")

# =============================================================================
# k) Integer boundary precision
# =============================================================================

testCase unsignedIntExactly2Pow53:
  ## 2^53 = 9007199254740992 is one above the maximum; rejected.
  assertErr parseUnsignedInt(9_007_199_254_740_992'i64)

testCase jmapIntNegationOfMinEqualsMax:
  ## -MinJmapInt == MaxJmapInt. Since MinJmapInt = -(2^53-1), this is safe.
  let minVal = parseJmapInt(MinJmapInt).get()
  let negated = -minVal
  let maxVal = parseJmapInt(MaxJmapInt).get()
  doAssert negated == maxVal

testCase unsignedIntNoNegation:
  ## UnsignedInt does not borrow unary negation.
  doAssert not compiles(-parseUnsignedInt(0).get())

testCase httpStatusErrorNegative:
  ## httpStatusError accepts any int, including negative values.
  let te = httpStatusError(-1, "negative status")
  doAssert te.kind == tekHttpStatus
  doAssert te.httpStatus == -1

testCase httpStatusErrorVeryLarge:
  ## httpStatusError accepts very large status codes.
  let te = httpStatusError(99999, "huge status")
  doAssert te.httpStatus == 99999

# =============================================================================
# l) String length extremes for length-unbounded types
# =============================================================================

testCase methodCallIdVeryLong:
  ## MethodCallId has no upper length bound; 65536 bytes accepted.
  assertOk parseMethodCallId("a".repeat(65536))

testCase creationIdVeryLong:
  ## CreationId has no upper length bound; 65536 bytes accepted.
  assertOk parseCreationId("a".repeat(65536))

testCase propertyNameVeryLong:
  ## PropertyName has no upper length bound; 65536 bytes accepted.
  assertOk parsePropertyName("a".repeat(65536))

testCase accountIdAllControlCharsRejected:
  ## 255 bytes of \x01 (control chars) rejected by AccountId.
  assertErr parseAccountId("\x01".repeat(255))

testCase methodCallIdAllControlCharsAccepted:
  ## MethodCallId has no control-character restriction; all control chars accepted.
  assertOk parseMethodCallId("\x01".repeat(255))

testCase allNulBytesForEachType:
  ## 255 bytes of NUL: accepted by permissive types, rejected by strict types.
  assertErr parseId("\x00".repeat(255))
  assertErr parseIdFromServer("\x00".repeat(255))
  assertErr parseAccountId("\x00".repeat(255))
  assertErr parseJmapState("\x00".repeat(255))
  assertOk parseMethodCallId("\x00".repeat(255))
  assertOk parseCreationId("\x00".repeat(255))
  assertOk parsePropertyName("\x00".repeat(255))

testCase allSpacesForIdTypes:
  ## 255 bytes of space: strict Id rejects, lenient accepts.
  assertErr parseId(" ".repeat(255))
  assertOk parseIdFromServer(" ".repeat(255))
  assertOk parseAccountId(" ".repeat(255))

# =============================================================================
# m) Date/time adversarial edge cases
# =============================================================================

testCase dateYear10000:
  ## 5-digit year: position 4 is '0' not '-', so date portion check fails.
  assertErr parseDate("10000-01-01T12:00:00Z")

testCase dateFractionalSecondsWithLowercaseZ:
  ## Fractional seconds followed by lowercase 'z': rejected.
  assertErr parseDate("2024-01-01T12:00:00.123z")

testCase dateFractionalNoTimezone:
  ## Fractional seconds present but no timezone suffix.
  assertErr parseDate("2024-01-01T12:00:00.123")

testCase dateDoubleDot:
  ## Double decimal point in fractional seconds position.
  assertErr parseDate("2024-01-01T12:00:00..123Z")

testCase dateNulInDatePortion:
  ## NUL byte at position 3 in date portion: not a digit, rejected.
  assertErr parseDate("202\x004-01-01T12:00:00Z")

testCase dateLongFractionalSeconds:
  ## 100000-digit fractional seconds: structurally valid, accepted.
  let frac = "1".repeat(100000)
  let input = "2024-01-01T12:00:00." & frac & "Z"
  assertOk parseDate(input)

# =============================================================================
# n) Enum parsing via nimIdentNormalize — additional edge cases
# =============================================================================

testCase methodErrorTypeLeadingUnderscore:
  ## Leading underscore is preserved by nimIdentNormalize; no match.
  doAssert parseMethodErrorType("_serverFail") == metUnknown

testCase methodErrorTypeMultipleLeadingUnderscores:
  ## Multiple leading underscores preserved.
  doAssert parseMethodErrorType("__serverFail") == metUnknown

testCase methodErrorTypeNulTerminated:
  ## NUL byte is not an underscore; breaks the match.
  doAssert parseMethodErrorType("serverFail\x00extra") == metUnknown

testCase methodErrorTypeVeryLong:
  ## Very long string: parseEnum iterates all variants without crashing.
  doAssert parseMethodErrorType("a".repeat(10000)) == metUnknown

testCase methodErrorTypeZeroWidthSpace:
  ## Zero-width space (UTF-8 bytes) embedded in the string breaks matching.
  doAssert parseMethodErrorType("server\xE2\x80\x8BFail") == metUnknown

testCase capabilityUriUnderscoreFalseMatch:
  ## Underscore between 'o' and 'w' in "unknownCapability" is stripped.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:unkno_wnCapability") ==
    retUnknownCapability

# =============================================================================
# o) Session validation attacks
# =============================================================================

testCase uriTemplateVariableSubstringFalseNegative:
  ## "{accountIdblobId}" does NOT contain "{accountId}" as a variable.
  let tmpl =
    parseUriTemplate("https://e.com/{accountIdblobId}/{name}?accept={type}").get()
  doAssert not tmpl.hasVariable("accountId")
  doAssert tmpl.hasVariable("accountIdblobId")

testCase uriTemplateEmptyVariableName:
  ## Empty ``{}`` is now rejected at parse time — the new tokeniser
  ## surfaces position-bearing errors rather than silently round-tripping
  ## nonsensical templates (was lenient substring search before).
  let res = parseUriTemplate("https://e.com/{}/{name}")
  doAssert res.isErr
  doAssert res.error.typeName == "UriTemplate"
  doAssert "empty variable" in res.error.message

testCase sessionCoreCapabilityMismatchedRawUri:
  ## ckCore with a non-matching rawUri is accepted (validation checks kind, not URI).
  let args = makeSessionArgs()
  let weirdCore =
    ServerCapability(rawUri: "urn:NOT:core", kind: ckCore, core: zeroCoreCaps())
  let res = parseSession(
    @[weirdCore],
    args.accounts,
    args.primaryAccounts,
    args.username,
    args.apiUrl,
    args.downloadUrl,
    args.uploadUrl,
    args.eventSourceUrl,
    args.state,
  )
  assertOk res

# =============================================================================
# p) Cross-type safety: additional distinct type isolation
# =============================================================================

testCase methodCallIdVsCreationIdIsolation:
  ## MethodCallId and CreationId are distinct types; comparison rejected.
  doAssert not compiles(makeMcid("a") == makeCreationId("a"))

testCase jmapStateVsPropertyNameIsolation:
  doAssert not compiles(makeState("a") == makePropertyName("a"))

testCase uriTemplateVsPropertyNameIsolation:
  doAssert not compiles(makeUriTemplate("a") == makePropertyName("a"))

testCase dateVsUtcDateIsolation:
  ## Date and UTCDate are distinct types.
  doAssert not compiles(
    parseDate("2024-01-01T12:00:00Z").get() == parseUtcDate("2024-01-01T12:00:00Z").get()
  )

testCase directConstructionBypassesSmartConstructor:
  ## distinct types can be directly constructed, bypassing validation.
  ## This documents the limitation: smart constructors are the only safe path.
  doAssert compiles(Id(""))
  doAssert compiles(UnsignedInt(-999'i64))
  doAssert compiles(AccountId(""))

# =============================================================================
# q) Unicode visual confusion characters
# =============================================================================

testCase idFromServerRtlOverride:
  ## Right-to-left override U+202E: bytes \xE2\x80\xAE, all >= 0x80, accepted.
  assertOk parseIdFromServer("admin\xE2\x80\xAEtoor")

testCase idFromServerCyrillicHomoglyph:
  ## Cyrillic 'a' (U+0430): \xD0\xB0, both bytes >= 0x80, accepted.
  ## Visually similar to Latin 'a' but a different byte sequence.
  assertOk parseIdFromServer("\xD0\xB0bc")

testCase idFromServerZeroWidthJoiner:
  ## Zero-width joiner U+200D: \xE2\x80\x8D, all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("a\xE2\x80\x8Db")

testCase idFromServerBomInMiddle:
  ## BOM \xEF\xBB\xBF in the middle of a string (not just at the start).
  assertOk parseIdFromServer("abc\xEF\xBB\xBFdef")

# =============================================================================
# r) Overlong DEL encoding bypass
# =============================================================================
# Layer 1 validates bytes, not Unicode codepoints. The 2-byte overlong encoding
# of DEL (0xC1 0xBF) bypasses the explicit it == '\x7F' check because byte 0xC1
# is 193 (>= 0x20) and byte 0xBF is 191 (>= 0x20, != 0x7F). This is a known
# Layer 1 limitation; overlong encoding validation is a Layer 2 concern.

testCase overlongDelBypassIdFromServer:
  ## Overlong DEL \xC1\xBF accepted by lenient parser: both bytes pass checks.
  assertOk parseIdFromServer("\xC1\xBF")

testCase overlongDelBypassAccountId:
  ## Overlong DEL \xC1\xBF accepted by parseAccountId: both bytes pass checks.
  assertOk parseAccountId("\xC1\xBF")

testCase overlongDelBypassJmapState:
  ## Overlong DEL \xC1\xBF accepted by parseJmapState: both bytes pass checks.
  assertOk parseJmapState("\xC1\xBF")

# =============================================================================
# s) nimIdentNormalize wider attack surface
# =============================================================================
# Nim's parseEnum uses nimIdentNormalize which is case-insensitive after the
# first character and strips all underscores. RFC 8620 expects exact string
# matching. This conformance risk is addressed at Layer 2 with custom parsing.

testCase nimIdentNormalizeAllCapsCapability:
  ## All-caps after first char: "urn:IETF:PARAMS:JMAP:CORE" matches ckCore.
  doAssert parseCapabilityKind("urn:IETF:PARAMS:JMAP:CORE") == ckCore

testCase nimIdentNormalizeUnderscoreCapability:
  ## Underscores scattered through URI are stripped: matches ckCore.
  doAssert parseCapabilityKind("u___r___n:ietf:params:jmap:core") == ckCore

testCase nimIdentNormalizeMethodError:
  ## "serverFAIL" matches metServerFail (case-insensitive after first char).
  doAssert parseMethodErrorType("serverFAIL") == metServerFail

testCase nimIdentNormalizeMethodErrorUnderscore:
  ## "server___Fail" with triple underscores matches metServerFail.
  doAssert parseMethodErrorType("server___Fail") == metServerFail

testCase nimIdentNormalizeSetError:
  ## "invalidPROPERTIES" matches setInvalidProperties.
  doAssert parseSetErrorType("invalidPROPERTIES") == setInvalidProperties

# =============================================================================
# t) int64 extremes
# =============================================================================

testCase int64ExtremeUnsignedIntHigh:
  ## int64.high = 9223372036854775807 far exceeds 2^53-1; rejected.
  assertErr parseUnsignedInt(int64.high)

testCase int64ExtremeUnsignedIntLow:
  ## int64.low = -9223372036854775808 is negative; rejected.
  assertErr parseUnsignedInt(int64.low)

testCase int64ExtremeJmapIntHigh:
  ## int64.high exceeds 2^53-1; rejected.
  assertErr parseJmapInt(int64.high)

testCase int64ExtremeJmapIntLow:
  ## int64.low is below -(2^53-1); rejected.
  assertErr parseJmapInt(int64.low)

# =============================================================================
# u) NUL as last byte: highest-risk FFI truncation pattern
# =============================================================================
# When C processes these strings via strlen(), the trailing NUL is invisible,
# yielding a valid-looking shorter string. Layer 5 must strip or reject
# trailing NULs at the FFI boundary.

testCase nulLastByteInvocationName:
  ## Invocation rawName with trailing NUL: Nim preserves it, C strlen() would not.
  let inv = parseInvocation("Email/get\x00", newJObject(), makeMcid("c0")).get()
  doAssert inv.rawName.len > 9
  doAssert inv.rawName.len == 10

testCase nulLastByteResultReferencePath:
  ## ResultReference rawPath with trailing NUL: Nim preserves it.
  let rr = parseResultReference(
      resultOf = makeMcid("c0"), name = "Email/get", path = "/ids\x00"
    )
    .get()
  doAssert rr.rawPath.len > 4
  doAssert rr.rawPath.len == 5

testCase nulLastByteRequestUsing:
  ## Request.using element with trailing NUL: Nim preserves it.
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core\x00"],
    methodCalls: @[],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`[0].len > 25
  doAssert req.`using`[0].len == 26

# =============================================================================
# v) Shared JsonNode aliasing
# =============================================================================

testCase jsonNodeAliasingInInvocation:
  ## JsonNode is a ref type; aliasing means mutations to the original are
  ## visible through the Invocation's arguments field (ref sharing under ARC).
  let args = newJObject()
  args["key1"] = newJString("value1")
  let inv = parseInvocation("Test/method", args, makeMcid("c0")).get()
  # Mutate the original JsonNode after construction.
  args["key2"] = newJString("injected")
  # Under ARC, ref sharing means the Invocation sees the mutation.
  doAssert inv.arguments.hasKey("key2")
  doAssert inv.arguments["key2"].getStr() == "injected"

# =============================================================================
# w) Additional UTF-8 edge cases
# =============================================================================

testCase utf8BomMiddleOfString:
  ## BOM \xEF\xBB\xBF in the middle: 9 bytes total, all bytes >= 0x20, accepted.
  let r = parseIdFromServer("abc\xEF\xBB\xBFdef").get()
  doAssert r.len == 9

testCase utf8FourByteEmojiAtBoundary:
  ## 4-byte emoji at byte position 252 pushing total to 256 bytes.
  ## Strict parser rejects: non-base64url bytes.
  ## Lenient parser rejects: 256 bytes exceeds the 255 limit.
  let prefix = "a".repeat(252)
  const emoji = "\xF0\x9F\x98\x80" # 4 bytes
  let input = prefix & emoji
  doAssert input.len == 256
  assertErr parseId(input)
  assertErr parseIdFromServer(input)

testCase utf8MixedValidInvalid:
  ## \xFF and \xFE are invalid UTF-8 lead bytes but both are >= 0x20, not 0x7F.
  ## The lenient parser accepts them (byte-level validation, not Unicode).
  assertOk parseIdFromServer("abc\xFF\xFEdef")

# =============================================================================
# CRLF injection in error messages
# =============================================================================
# Documents that Layer 1 preserves CRLF bytes in error strings. Layer 2/4
# must sanitise before logging or including in HTTP responses.

testCase crlfInjectionInMethodError:
  ## methodError with CRLF in rawType: Layer 1 preserves the bytes verbatim.
  let me = methodError("serverFail\r\nX-Injected: header")
  doAssert "\r\n" in me.rawType
  doAssert me.rawType == "serverFail\r\nX-Injected: header"
  doAssert me.errorType == metUnknown

testCase crlfInjectionInTransportError:
  ## transportError with CRLF in message: Layer 1 preserves the bytes verbatim.
  let te = transportError(tekNetwork, "error\r\nX-Injected: header")
  doAssert "\r\n" in te.message
  doAssert te.message == "error\r\nX-Injected: header"

testCase crlfInjectionInSetError:
  ## setError with CRLF in rawType: Layer 1 preserves the bytes verbatim.
  let se = setError("forbidden\r\nX-Injected: header")
  doAssert "\r\n" in se.rawType
  doAssert se.rawType == "forbidden\r\nX-Injected: header"
  doAssert se.errorType == setUnknown

testCase crlfInjectionInRequestError:
  ## requestError with CRLF in rawType: Layer 1 preserves the bytes verbatim.
  let re = requestError("urn:ietf:params:jmap:error:limit\r\nX-Injected: header")
  doAssert "\r\n" in re.rawType
  doAssert re.rawType == "urn:ietf:params:jmap:error:limit\r\nX-Injected: header"
  doAssert re.errorType == retUnknown

# =============================================================================
# Real-world server ID formats (interop)
# =============================================================================
# Validates that parseIdFromServer accepts ID formats known to be used by
# real JMAP server implementations.

testCase realWorldIdFastmail:
  ## Fastmail uses base64url without padding for IDs.
  assertOk parseIdFromServer("SGVsbG8gV29ybGQ")
  assertOk parseIdFromServer("u1f5a6e2c")

testCase realWorldIdCyrusImap:
  ## Cyrus IMAP uses decimal modseq values as IDs.
  assertOk parseIdFromServer("18446744073709551615")
  assertOk parseIdFromServer("12345678")

testCase realWorldIdApacheJames:
  ## Apache James uses UUID format for IDs.
  assertOk parseIdFromServer("550e8400-e29b-41d4-a716-446655440000")

testCase realWorldIdStalwart:
  ## Stalwart uses path-like IDs with colons and hash characters.
  assertOk parseIdFromServer("user/mailbox/msg:12345")
  assertOk parseIdFromServer("INBOX.Draft#123")

testCase realWorldIdGenericSpecialChars:
  ## Various servers use IDs containing @, +, and dot characters.
  assertOk parseIdFromServer("user@host")
  assertOk parseIdFromServer("msg+tag")
  assertOk parseIdFromServer("folder.subfolder")

# =============================================================================
# Capability URI edge cases
# =============================================================================

testCase capabilityUriTypo:
  ## A typo in the capability URI ("cor" instead of "core") maps to ckUnknown.
  doAssert parseCapabilityKind("urn:ietf:params:jmap:cor") == ckUnknown

testCase capabilityUriVendorFragment:
  ## A vendor URI with a fragment identifier maps to ckUnknown.
  doAssert parseCapabilityKind("https://vendor.example.com/ext#v2") == ckUnknown

testCase capabilityUriCaseVariation:
  ## Full-uppercase URI: first character 'U' differs from 'u' in the backing
  ## string "urn:ietf:params:jmap:core", so nimIdentNormalize does not match.
  doAssert parseCapabilityKind("URN:IETF:PARAMS:JMAP:CORE") == ckUnknown

# =============================================================================
# Error type cross-context enum mapping
# =============================================================================
# Documents that identical rawType strings map to different enum variants
# depending on which error context they appear in.

testCase methodErrorVsSetErrorEnumMapping:
  ## "serverFail" is a valid MethodErrorType but not a SetErrorType.
  let me = methodError("serverFail")
  doAssert me.errorType == metServerFail
  let se = setError("serverFail")
  doAssert se.errorType == setUnknown

testCase requestErrorVsMethodErrorEnumMapping:
  ## Full URIs are valid RequestErrorType values but not MethodErrorType values.
  let re = requestError("urn:ietf:params:jmap:error:limit")
  doAssert re.errorType == retLimit
  let me = methodError("urn:ietf:params:jmap:error:limit")
  doAssert me.errorType == metUnknown

# =============================================================================
# Type confusion: Id / AccountId validation overlap
# =============================================================================
# Documents that some strings pass both strict Id and lenient AccountId
# validation, which is by design (different type safety at the Nim level).

testCase idAccountIdValidationOverlap:
  ## The full base64url alphabet passes both strict Id and lenient AccountId.
  const overlap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  assertOk parseId(overlap)
  assertOk parseAccountId(overlap)

testCase methodCallIdCreationIdOverlap:
  ## A simple alphanumeric string passes both MethodCallId and CreationId.
  const overlap = "ref42"
  assertOk parseMethodCallId(overlap)
  assertOk parseCreationId(overlap)

# =============================================================================
# Account name Unicode control sequences
# =============================================================================
# Documents that Layer 1 preserves Unicode control sequences in Account.name.
# UI layers must handle rendering safely.

testCase accountNameZeroWidthSpace:
  ## Zero-width space U+200B (\xE2\x80\x8B) embedded in Account.name is preserved.
  let acct = Account(
    name: "admin\xE2\x80\x8Bbackup@co.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[],
  )
  doAssert acct.name.len == 21
  doAssert "\xE2\x80\x8B" in acct.name

testCase accountNameRightToLeftOverride:
  ## Right-to-left override U+202E (\xE2\x80\xAE) in Account.name is preserved.
  let acct = Account(
    name: "admin\xE2\x80\xAErof@co.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[],
  )
  doAssert acct.name.len == 18
  doAssert "\xE2\x80\xAE" in acct.name

testCase accountNameBom:
  ## BOM U+FEFF (\xEF\xBB\xBF) at start of Account.name is preserved.
  let acct = Account(
    name: "\xEF\xBB\xBFadmin@co.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[],
  )
  doAssert acct.name.len == 15
  doAssert acct.name[0 .. 2] == "\xEF\xBB\xBF"

# =============================================================================
# 6a) Full control character range
# =============================================================================

testCase controlCharRangeInLenientValidators:
  ## Every byte in 0x00..0x1F and 0x7F must be rejected by lenient validators.
  for i in 0x00 .. 0x1F:
    let ch = char(i)
    let s = "abc" & $ch & "def"
    assertErr parseIdFromServer(s)
    assertErr parseAccountId(s)
    assertErr parseJmapState(s)
  ## DEL (0x7F)
  const delStr = "abc\x7Fdef"
  assertErr parseIdFromServer(delStr)
  assertErr parseAccountId(delStr)
  assertErr parseJmapState(delStr)

testCase controlCharBoundarySpaceAccepted:
  ## 0x20 (space) is the boundary — must be accepted by lenient validators.
  assertOk parseIdFromServer(" ")
  assertOk parseAccountId(" ")
  assertOk parseJmapState(" ")

# =============================================================================
# 6b) Multi-position control char injection
# =============================================================================

testCase nulAtMultiplePositionsInStrictId:
  ## NUL at start, middle, and end of max-length strict Id.
  for pos in [0, 127, 254]:
    var s = "A".repeat(255)
    s[pos] = '\x00'
    assertErr parseId(s)

testCase delAtMultiplePositionsInLenientId:
  ## DEL at start, middle, and end of lenient Id.
  for pos in [0, 127, 254]:
    var s = "A".repeat(255)
    s[pos] = '\x7F'
    assertErr parseIdFromServer(s)

testCase controlCharAtPosition254InAccountId:
  ## Control char at position 254 in max-length AccountId.
  var s = "A".repeat(255)
  s[254] = '\x01'
  assertErr parseAccountId(s)

# =============================================================================
# 6d) Filter tree edge cases
# =============================================================================

testCase filterNotWithMultipleChildren:
  ## NOT with multiple children — semantically wrong per RFC, but Layer 1 allows.
  let a = filterCondition(1)
  let b = filterCondition(2)
  let f = filterOperator[int](foNot, @[a, b])
  doAssert f.kind == fkOperator
  doAssert f.operator == foNot
  doAssert f.conditions.len == 2

testCase filterEmptyConditionsList:
  ## Operator with empty conditions list — Layer 1 does not restrict this.
  let f = filterOperator[int](foAnd, @[])
  doAssert f.kind == fkOperator
  doAssert f.conditions.len == 0

testCase filterMixedOperatorNesting:
  ## (a AND b) OR (NOT c) — complex nesting is valid.
  let a = filterCondition(1)
  let b = filterCondition(2)
  let c = filterCondition(3)
  let andNode = filterOperator[int](foAnd, @[a, b])
  let notNode = filterOperator[int](foNot, @[c])
  let orNode = filterOperator[int](foOr, @[andNode, notNode])
  doAssert orNode.operator == foOr
  doAssert orNode.conditions.len == 2
  doAssert orNode.conditions[0].operator == foAnd
  doAssert orNode.conditions[1].operator == foNot

# =============================================================================
# 6e) Error type edge cases
# =============================================================================

testCase httpStatusErrorLargeAndNegative:
  ## Unusual HTTP status codes are not validated at Layer 1.
  let te999 = httpStatusError(999, "unusual")
  doAssert te999.httpStatus == 999
  let teNeg = httpStatusError(-1, "negative")
  doAssert teNeg.httpStatus == -1

testCase setErrorDefensiveFallbackInvalidProperties:
  ## Generic setError with rawType="invalidProperties" falls to setUnknown.
  let se = setError("invalidProperties")
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "invalidProperties"

testCase setErrorDefensiveFallbackAlreadyExists:
  ## Generic setError with rawType="alreadyExists" falls to setUnknown.
  let se = setError("alreadyExists")
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "alreadyExists"

# =============================================================================
# SetError variant field confusion
# =============================================================================

testCase setErrorAlreadyExistsWithExtrasContainingProperties:
  ## Construct alreadyExists with extras containing a "properties" key.
  ## The extras field holds arbitrary JSON; it does not interfere with the
  ## variant-specific existingId field.
  let extras = newJObject()
  extras["properties"] = %*["from", "subject"]
  let se =
    setErrorAlreadyExists("alreadyExists", makeId("exist1"), extras = Opt.some(extras))
  doAssert se.errorType == setAlreadyExists
  doAssert $se.existingId == "exist1"
  doAssert se.extras.isSome
  doAssert se.extras.get()["properties"].len == 2

testCase setErrorInvalidPropertiesWithExtrasContainingExistingId:
  ## Construct invalidProperties with extras containing an "existingId" key.
  ## The extras field holds arbitrary JSON; it does not interfere with the
  ## variant-specific properties field.
  let extras = newJObject()
  extras["existingId"] = %"fake-id"
  let se = setErrorInvalidProperties(
    "invalidProperties", @["badProp"], extras = Opt.some(extras)
  )
  doAssert se.errorType == setInvalidProperties
  doAssert se.properties == @["badProp"]
  doAssert se.extras.isSome
  doAssert se.extras.get()["existingId"].getStr() == "fake-id"

# =============================================================================
# 5.1) JsonNode ref-sharing documentation tests
# =============================================================================
# Under ARC, JsonNode is a ref type. Storing a ref in a type and then mutating
# the original means the mutation is visible through the type. These tests
# document this behaviour for three ref-holding types.

testCase jsonNodeAliasingInAccountCapability:
  ## AccountCapabilityEntry.data is a JsonNode ref — mutations after
  ## construction are visible. Documented ARC behaviour.
  let data = newJObject()
  data["original"] = newJString("value")
  let entry = AccountCapabilityEntry(
    kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: data
  )
  data["injected"] = newJString("evil")
  doAssert entry.data.hasKey("injected")

testCase jsonNodeAliasingInServerCapability:
  ## ServerCapability.rawData (non-ckCore variant) is a JsonNode ref —
  ## mutations after construction are visible. Documented ARC behaviour.
  let rawData = newJObject()
  rawData["original"] = newJString("value")
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: rawData
  )
  rawData["injected"] = newJString("evil")
  doAssert cap.rawData.hasKey("injected")

testCase jsonNodeAliasingInMethodErrorExtras:
  ## MethodError.extras (when Opt.some(jsonNode)) is a JsonNode ref —
  ## mutations after construction are visible. Documented ARC behaviour.
  let extras = newJObject()
  extras["original"] = newJString("value")
  let me = methodError("serverFail", extras = Opt.some(extras))
  extras["injected"] = newJString("evil")
  doAssert me.extras.isSome
  doAssert me.extras.get().hasKey("injected")

# =============================================================================
# 5.2) Session adversarial scenarios
# =============================================================================

testCase sessionDuplicateCkCore:
  ## Duplicate ckCore: parseSession accepts two ckCore ServerCapabilities
  ## with different CoreCapabilities. coreCapabilities() returns the FIRST one.
  let coreCaps1 = CoreCapabilities(
    maxSizeUpload: parseUnsignedInt(100).get(),
    maxConcurrentUpload: parseUnsignedInt(1).get(),
    maxSizeRequest: parseUnsignedInt(100).get(),
    maxConcurrentRequests: parseUnsignedInt(1).get(),
    maxCallsInRequest: parseUnsignedInt(1).get(),
    maxObjectsInGet: parseUnsignedInt(1).get(),
    maxObjectsInSet: parseUnsignedInt(1).get(),
    collationAlgorithms: initHashSet[CollationAlgorithm](),
  )
  let coreCaps2 = CoreCapabilities(
    maxSizeUpload: parseUnsignedInt(999).get(),
    maxConcurrentUpload: parseUnsignedInt(99).get(),
    maxSizeRequest: parseUnsignedInt(999).get(),
    maxConcurrentRequests: parseUnsignedInt(99).get(),
    maxCallsInRequest: parseUnsignedInt(99).get(),
    maxObjectsInGet: parseUnsignedInt(99).get(),
    maxObjectsInSet: parseUnsignedInt(99).get(),
    collationAlgorithms: initHashSet[CollationAlgorithm](),
  )
  let cap1 =
    ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: coreCaps1)
  let cap2 =
    ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: coreCaps2)
  let args = makeSessionArgs()
  let res = parseSession(
    @[cap1, cap2],
    args.accounts,
    args.primaryAccounts,
    args.username,
    args.apiUrl,
    args.downloadUrl,
    args.uploadUrl,
    args.eventSourceUrl,
    args.state,
  )
  let session = res.get()
  ## coreCapabilities() iterates and returns the first ckCore match.
  let cc = session.coreCapabilities()
  doAssert cc.maxSizeUpload == parseUnsignedInt(100).get()
  doAssert cc.maxConcurrentUpload == parseUnsignedInt(1).get()

testCase sessionFindCapabilityCkUnknown:
  ## findCapability(session, ckUnknown) returns the first ckUnknown entry.
  ## findCapabilityByUri returns the correct specific one.
  let vendor1 = ServerCapability(
    rawUri: "https://vendor.example.com/ext1", kind: ckUnknown, rawData: newJObject()
  )
  let vendor2 = ServerCapability(
    rawUri: "https://vendor.example.com/ext2", kind: ckUnknown, rawData: newJObject()
  )
  let vendor3 = ServerCapability(
    rawUri: "https://vendor.example.com/ext3", kind: ckUnknown, rawData: newJObject()
  )
  let args = makeSessionArgs()
  let res = parseSession(
    @[makeCoreServerCap(), vendor1, vendor2, vendor3],
    args.accounts,
    args.primaryAccounts,
    args.username,
    args.apiUrl,
    args.downloadUrl,
    args.uploadUrl,
    args.eventSourceUrl,
    args.state,
  )
  let session = res.get()
  ## findCapability returns the first ckUnknown.
  let first = session.findCapability(ckUnknown)
  assertSome first
  doAssert first.get().rawUri == "https://vendor.example.com/ext1"
  ## findCapabilityByUri returns the exact match.
  let specific = session.findCapabilityByUri("https://vendor.example.com/ext2")
  assertSome specific
  doAssert specific.get().rawUri == "https://vendor.example.com/ext2"

testCase uriTemplateNestedBracesRejected:
  ## Nested braces ``{{accountId}}`` are rejected at parse time: the
  ## inner ``{`` is an invalid variable-name character. The previous
  ## substring-based ``hasVariable`` silently accepted this edge case;
  ## the parsed-once representation tightens the contract.
  let res = parseUriTemplate("https://e.com/{{accountId}}")
  doAssert res.isErr
  doAssert res.error.typeName == "UriTemplate"
  doAssert "invalid variable character" in res.error.message

testCase uriTemplateNulInFullTemplate:
  ## A template with NUL passes both parseUriTemplate and parseSession because
  ## Nim sees the full string. Documents the FFI boundary implication: C
  ## strlen() would truncate at the NUL.
  const tmplStr = "https://e.com/\x00/{accountId}/{blobId}/{name}?accept={type}"
  let tmpl = parseUriTemplate(tmplStr).get()
  assertOk tmpl
  ## The template passes session-level variable validation.
  doAssert tmpl.hasVariable("accountId")
  doAssert tmpl.hasVariable("blobId")
  doAssert tmpl.hasVariable("name")
  doAssert tmpl.hasVariable("type")
  ## Verify it works in parseSession too.
  let args = makeSessionArgs()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    tmpl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertOk res

# =============================================================================
# 5.3) Unicode adversarial expansion
# =============================================================================

testCase unicodeNfcVsNfdAccountId:
  ## NFC vs NFD: Latin "e with grave" (\xC3\xA8, 2 bytes NFC) vs "e" +
  ## combining grave accent (\x65\xCC\x80, 3 bytes NFD) produce different
  ## AccountIds. Layer 1 operates at byte level, no Unicode normalisation.
  let nfc = parseAccountId("\xC3\xA8").get()
  let nfd = parseAccountId("\x65\xCC\x80").get()
  doAssert nfc != nfd

testCase unicodeHomoglyphTablePoisoning:
  ## Latin "admin" vs Cyrillic-a "admin" (\xD0\xB0dmin) are distinct Table
  ## keys. Building an accounts table with both produces len == 2.
  let latinId = parseAccountId("admin").get()
  let cyrillicId = parseAccountId("\xD0\xB0dmin").get()
  doAssert latinId != cyrillicId
  var accounts = initTable[AccountId, Account]()
  accounts[latinId] = Account(
    name: "latin", isPersonal: true, isReadOnly: false, accountCapabilities: @[]
  )
  accounts[cyrillicId] = Account(
    name: "cyrillic", isPersonal: true, isReadOnly: false, accountCapabilities: @[]
  )
  doAssert accounts.len == 2

testCase unicodeZeroWidthSpaceAtStart:
  ## parseAccountId("\xE2\x80\x8Badmin").get() (ZWSP + "admin") is different from
  ## parseAccountId("admin").get(). Byte-level comparison, no normalisation.
  let withZwsp = parseAccountId("\xE2\x80\x8Badmin").get()
  let plain = parseAccountId("admin").get()
  doAssert withZwsp != plain

testCase unicodeLroCharacterInId:
  ## parseIdFromServer("admin\xE2\x80\xADtest").get() — LRO U+202D (\xE2\x80\xAD),
  ## all bytes >= 0x80, accepted by lenient parser.
  assertOk parseIdFromServer("admin\xE2\x80\xADtest")

testCase unicodeBidiIsolateInId:
  ## parseIdFromServer("a\xE2\x81\xA6b").get() — LRI U+2066 (\xE2\x81\xA6),
  ## all bytes >= 0x80, accepted by lenient parser.
  assertOk parseIdFromServer("a\xE2\x81\xA6b")

# =============================================================================
# 5.4) Calendar-invalid but structurally valid dates
# =============================================================================
# Layer 1 validates structural RFC 3339 format only — not calendar semantics.
# These are documented as intentional design decisions.

testCase dateImpossibleMonth99:
  ## Month 99 passes structural validation: Layer 1 does not validate
  ## calendar semantics.
  assertOk parseDate("2024-99-01T12:00:00Z")

testCase dateImpossibleDay99:
  ## Day 99 passes structural validation: Layer 1 does not validate
  ## calendar semantics.
  assertOk parseDate("2024-01-99T12:00:00Z")

testCase dateImpossibleHour99:
  ## Hour 99 passes structural validation: Layer 1 does not validate
  ## calendar semantics.
  assertOk parseDate("2024-01-01T99:00:00Z")

testCase dateAllZeros:
  ## All zeros "0000-00-00T00:00:00Z" passes structural validation: Layer 1
  ## does not validate calendar semantics.
  assertOk parseDate("0000-00-00T00:00:00Z")

testCase dateFeb30:
  ## February 30 passes structural validation: Layer 1 does not validate
  ## calendar semantics.
  assertOk parseDate("2024-02-30T12:00:00Z")

testCase dateImpossibleTimezone9999:
  ## Timezone "+99:99" passes structural validation: Layer 1 does not validate
  ## timezone offset range semantics.
  assertOk parseDate("2024-01-01T12:00:00+99:99")

# =============================================================================
# 5.5) Error information leakage
# =============================================================================

testCase validationErrorPreservesFullInput:
  ## ValidationError.value echoes the complete raw input. Layer 5 FFI must
  ## sanitise before exposing to C callers if input may contain credentials.
  let r = parseId("Bearer eyJhbGciOiJIUzI1NiJ9")
  doAssert r.isErr, "expected Err result"
  doAssert "Bearer" in r.error.value

testCase crlfInMethodErrorDescription:
  ## CRLF in description is preserved — no sanitisation at Layer 1.
  let me = methodError("serverFail", description = Opt.some("desc\r\nInjected: yes"))
  doAssert "\r\n" in me.description.get()

# =============================================================================
# Phase 5B: Unbounded collection size stress tests
# =============================================================================
# These tests verify the library can parse JSON with very large collections
# without crashing. 100,000 entries exercise memory allocation and iteration
# paths. The library must return Ok (no artificial limits).

testCase stressResponseMethodResponses100k:
  ## Response with 100,000 methodResponses entries -> must succeed.
  ## Documents memory usage implications for large batch responses.
  var methodResponses = newJArray()
  for i in 0 ..< 100_000:
    methodResponses.add(%*["Method/" & $i, {}, "c" & $i])
  var j = newJObject()
  j["methodResponses"] = methodResponses
  j["sessionState"] = %"s1"
  let r = Response.fromJson(j).get()
  assertEq r.methodResponses.len, 100_000

testCase stressSessionAccounts100k:
  ## Session with 100,000 accounts -> must succeed. Each account has minimal
  ## fields. Documents that the library imposes no artificial account limit.
  var j = validSessionJson()
  var accts = newJObject()
  for i in 0 ..< 100_000:
    var acctCaps = newJObject()
    var acct = newJObject()
    acct["name"] = %("user" & $i)
    acct["isPersonal"] = %true
    acct["isReadOnly"] = %false
    acct["accountCapabilities"] = acctCaps
    accts["acct" & $i] = acct
  j["accounts"] = accts
  let r = Session.fromJson(j).get()
  assertEq r.accounts.len, 100_000

testCase stressRequestCreatedIds100k:
  ## Request with 100,000 createdIds entries -> must succeed.
  var j = validRequestJson()
  var ids = newJObject()
  for i in 0 ..< 100_000:
    ids["k" & $i] = newJString("id" & $i)
  j["createdIds"] = ids
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 100_000

testCase stressSessionCapabilities100k:
  ## Session with 100,000 vendor capabilities -> must succeed. Documents
  ## that the library imposes no artificial capability count limit.
  var j = validSessionJson()
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  for i in 0 ..< 100_000:
    caps["https://vendor.example/ext/" & $i] = newJObject()
  j["capabilities"] = caps
  let r = Session.fromJson(j).get()
  assertGe r.capabilities.len, 100_001

testCase stressSessionAccountCapabilities100k:
  ## Single account with 100,000 accountCapabilities -> must succeed.
  var j = validSessionJson()
  var acctCaps = newJObject()
  for i in 0 ..< 100_000:
    acctCaps["https://vendor.example/acap/" & $i] = newJObject()
  var accts = newJObject()
  var acct = newJObject()
  acct["name"] = %"user"
  acct["isPersonal"] = %true
  acct["isReadOnly"] = %false
  acct["accountCapabilities"] = acctCaps
  accts["a1"] = acct
  j["accounts"] = accts
  let r = Session.fromJson(j).get()
  let parsedAccounts = r.accounts
  for acctId, account in parsedAccounts:
    assertGe account.accountCapabilities.len, 100_000

# =============================================================================
# RFC 6901 JSON Pointer composition under deep nesting
# =============================================================================
# SerdeViolation path composition must survive every descent step. These
# tests submit malformed JSON at a specific deep location, then assert the
# translated ValidationError message ends with the expected pointer.

testCase responsePointerNestedCallIdFailure:
  ## A malformed methodCallId (integer where string expected) inside the
  ## first Invocation of a Response surfaces with the full path
  ## ``/methodResponses/0/2`` — Response → methodResponses[0] (Invocation)
  ## → element[2] (callId position).
  let j = %*{"methodResponses": [["Mailbox/get", {}, 42]], "sessionState": "s1"}
  let res = Response.fromJson(j)
  doAssert res.isErr
  let sv = res.error
  doAssert sv.kind == svkWrongKind
  doAssert $sv.path == "/methodResponses/0/2",
    "path must compose through all nesting levels: got " & $sv.path

testCase requestPointerCreatedIdsValue:
  ## A non-string value inside Request.createdIds must surface with the
  ## full path ``/createdIds/k1``.
  let j = %*{
    "using": ["urn:ietf:params:jmap:core"], "methodCalls": [], "createdIds": {"k1": 42}
  }
  let res = Request.fromJson(j)
  doAssert res.isErr
  let sv = res.error
  doAssert sv.kind == svkWrongKind
  doAssert $sv.path == "/createdIds/k1",
    "path must compose through the createdIds descent: got " & $sv.path

testCase invocationPointerWrongArity:
  ## Invocation array with 2 elements (should be 3) surfaces as
  ## ``svkArrayLength`` with a descent-aware path.
  let j = %*{"methodResponses": [["Mailbox/get", {}]], "sessionState": "s1"}
  let res = Response.fromJson(j)
  doAssert res.isErr
  let sv = res.error
  doAssert sv.kind == svkArrayLength
  doAssert sv.expectedLen == 3
  doAssert sv.actualLen == 2
  doAssert $sv.path == "/methodResponses/0"
