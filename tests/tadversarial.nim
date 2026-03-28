# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Adversarial and edge-case tests probing byte-level validation semantics,
## UTF-8 boundary behaviour, NUL-byte acceptance in permissive types,
## nimIdentNormalize false matches in enum parsing, and 255-byte boundary
## conditions with multi-byte characters.

import std/json
import std/strutils
import std/tables

import pkg/results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/framework
import jmap_client/errors
import jmap_client/session
import jmap_client/envelope

import ./massertions
import ./mfixtures

# =============================================================================
# a) Multi-byte UTF-8 at 255-byte boundary
# =============================================================================
# Validates byte-not-character semantics: the length check counts octets, not
# Unicode code points.

block idFromServerTwoByteCharsAt255Bytes:
  ## 127 x \xC3\xA9 (2 bytes each) + 1 ASCII char = 255 bytes: ACCEPTED.
  let input = "\xC3\xA9".repeat(127) & "a"
  doAssert input.len == 255
  let r = parseIdFromServer(input)
  assertOk r

block accountIdTwoByteCharsAt255Bytes:
  ## Same 255-byte string accepted by parseAccountId.
  let input = "\xC3\xA9".repeat(127) & "a"
  doAssert input.len == 255
  let r = parseAccountId(input)
  assertOk r

block idFromServerTwoByteCharsAt256Bytes:
  ## 128 x \xC3\xA9 = 256 bytes: REJECTED (byte-not-character semantics).
  let input = "\xC3\xA9".repeat(128)
  doAssert input.len == 256
  let r = parseIdFromServer(input)
  assertErr r

block accountIdTwoByteCharsAt256Bytes:
  ## 128 x \xC3\xA9 = 256 bytes: REJECTED.
  let input = "\xC3\xA9".repeat(128)
  doAssert input.len == 256
  let r = parseAccountId(input)
  assertErr r

# =============================================================================
# b) Invalid UTF-8 acceptance (Layer 1 validates bytes, not Unicode)
# =============================================================================
# These document intentional behaviour: the validators check byte values
# against control-character ranges, not Unicode well-formedness.

block idFromServerOverlongNul:
  ## Overlong NUL encoding \xC0\x80: ACCEPTED by lenient parser.
  ## Both bytes are >= 0x20 so they pass the control-character check.
  const input = "abc\xC0\x80def"
  let r = parseIdFromServer(input)
  assertOk r

block accountIdOverlongNul:
  ## Overlong NUL encoding \xC0\x80: ACCEPTED by parseAccountId.
  const input = "abc\xC0\x80def"
  let r = parseAccountId(input)
  assertOk r

block idFromServerUtf16Surrogate:
  ## UTF-16 surrogate \xED\xA0\x80: ACCEPTED (all bytes >= 0x20, none == 0x7F).
  const input = "abc\xED\xA0\x80def"
  let r = parseIdFromServer(input)
  assertOk r

block idFromServerTruncatedMultibyte:
  ## Truncated multi-byte sequence "abc\xC3": ACCEPTED by lenient parser.
  ## 0xC3 is >= 0x20 and not 0x7F.
  const input = "abc\xC3"
  let r = parseIdFromServer(input)
  assertOk r

block accountIdTruncatedMultibyte:
  ## Truncated multi-byte sequence: ACCEPTED by parseAccountId.
  const input = "abc\xC3"
  let r = parseAccountId(input)
  assertOk r

# =============================================================================
# c) C1 control codes (0x80-0x9F)
# =============================================================================
# These are Unicode control characters (C1 block) but at byte level they are
# >= 0x20 and not 0x7F, so the validators accept them.

block idFromServerC1NextLine:
  ## NEL (U+0085) encoded as \xC2\x85: ACCEPTED.
  ## Both 0xC2 and 0x85 are >= 0x20 and not 0x7F.
  const input = "abc\xC2\x85def"
  let r = parseIdFromServer(input)
  assertOk r

block accountIdC1Byte9F:
  ## Raw byte 0x9F: ACCEPTED (>= 0x20, not 0x7F).
  ## This is the APC control character in Unicode, but the check is byte-level.
  const input = "abc\x9Fdef"
  let r = parseAccountId(input)
  assertOk r

block idFromServerC1Byte80:
  ## Raw byte 0x80: ACCEPTED (>= 0x20, not 0x7F).
  const input = "abc\x80def"
  let r = parseIdFromServer(input)
  assertOk r

block jmapStateC1Byte85:
  ## Raw byte 0x85 in JmapState: ACCEPTED.
  const input = "abc\x85def"
  let r = parseJmapState(input)
  assertOk r

# =============================================================================
# d) Unicode special characters
# =============================================================================

block idStrictRejectsBom:
  ## BOM \xEF\xBB\xBF contains bytes outside Base64UrlChars: REJECTED by strict.
  const input = "\xEF\xBB\xBFabc"
  let r = parseId(input)
  assertErr r

block idFromServerAcceptsBom:
  ## BOM bytes are all >= 0x20: ACCEPTED by lenient parser.
  const input = "\xEF\xBB\xBFabc"
  let r = parseIdFromServer(input)
  assertOk r

block idFromServerZeroWidthSpace:
  ## Zero-width space U+200B encoded as \xE2\x80\x8B: ACCEPTED.
  ## All 3 bytes are >= 0x20 and not 0x7F.
  const input = "\xE2\x80\x8B"
  doAssert input.len == 3
  let r = parseIdFromServer(input)
  assertOk r

block accountIdAcceptsBom:
  ## BOM accepted by parseAccountId (bytes >= 0x20, not 0x7F).
  const input = "\xEF\xBB\xBFabc"
  let r = parseAccountId(input)
  assertOk r

# =============================================================================
# e) NUL bytes in permissive types (FFI concern)
# =============================================================================
# parseMethodCallId and parsePropertyName only check non-empty. parseCreationId
# checks non-empty and first char != '#'. None perform control-character checks.

block methodCallIdNulByte:
  ## parseMethodCallId("\x00"): ACCEPTED (only checks non-empty).
  let r = parseMethodCallId("\x00")
  assertOk r

block creationIdNulFirstChar:
  ## parseCreationId("\x00abc"): ACCEPTED (first char is \x00, not '#').
  let r = parseCreationId("\x00abc")
  assertOk r

block propertyNameNulByte:
  ## parsePropertyName("\x00"): ACCEPTED (only checks non-empty).
  let r = parsePropertyName("\x00")
  assertOk r

block methodCallIdEmbeddedNul:
  ## "c1\x00hidden": ACCEPTED (no control-character check in MethodCallId).
  let r = parseMethodCallId("c1\x00hidden")
  assertOk r

block creationIdEmbeddedNul:
  ## "abc\x00def": ACCEPTED (only first char is checked against '#').
  let r = parseCreationId("abc\x00def")
  assertOk r

block propertyNameEmbeddedNul:
  ## "foo\x00bar": ACCEPTED (only non-empty check).
  let r = parsePropertyName("foo\x00bar")
  assertOk r

# =============================================================================
# f) nimIdentNormalize false matches in enum parsing
# =============================================================================
# strutils.parseEnum uses nimIdentNormalize which strips underscores (except
# leading) and lowercases everything except the first character. This produces
# surprising matches when underscores appear in input strings.

block methodErrorTypeUnderscoreStripped:
  ## "server_Fail" normalises to "serverfail", matching "serverFail" -> metServerFail.
  doAssert parseMethodErrorType("server_Fail") == metServerFail

block methodErrorTypeCaseInsensitiveAfterFirst:
  ## "serverfail" normalises same as "serverFail": both become "serverfail".
  doAssert parseMethodErrorType("serverfail") == metServerFail

block methodErrorTypeFirstCharCaseSensitive:
  ## "SERVERFAIL": first char 'S' differs from 's' in "serverFail" -> metUnknown.
  doAssert parseMethodErrorType("SERVERFAIL") == metUnknown

block setErrorTypeUnderscoreStripped:
  ## "over_Quota" normalises to "overquota", matching "overQuota" -> setOverQuota.
  doAssert parseSetErrorType("over_Quota") == setOverQuota

block setErrorTypeMixedCaseAndUnderscore:
  ## "too_large" normalises to "toolarge", matching "tooLarge" -> setTooLarge.
  doAssert parseSetErrorType("too_large") == setTooLarge

block capabilityKindUnderscoreFalseMatch:
  ## "urn:ietf:params:jmap:co_re" normalises to "urn:ietf:params:jmap:core",
  ## matching ckCore's backing string. This is a nimIdentNormalize artefact.
  doAssert parseCapabilityKind("urn:ietf:params:jmap:co_re") == ckCore

block requestErrorTypeUnderscoreFalseMatch:
  ## "urn:ietf:params:jmap:error:not_JSON" normalises to
  ## "urn:ietf:params:jmap:error:notjson", matching retNotJson's backing.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:not_JSON") == retNotJson

block requestErrorTypeUnderscoreInLimit:
  ## "urn:ietf:params:jmap:error:li_mit" normalises to
  ## "urn:ietf:params:jmap:error:limit", matching retLimit.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:li_mit") == retLimit

block methodErrorTypeMultipleUnderscores:
  ## "invalid__Arguments" -> "invalidarguments" matches metInvalidArguments.
  doAssert parseMethodErrorType("invalid__Arguments") == metInvalidArguments

block methodErrorTypeTrailingUnderscore:
  ## "forbidden_" -> "forbidden" matches metForbidden.
  doAssert parseMethodErrorType("forbidden_") == metForbidden

block setErrorTypeFirstCharMismatch:
  ## "Forbidden" -> first char 'F' differs from 'f' in "forbidden" -> setUnknown.
  doAssert parseSetErrorType("Forbidden") == setUnknown

block capabilityKindFirstCharMismatch:
  ## "URN:..." first char 'U' differs from 'u' in "urn:..." -> ckUnknown.
  doAssert parseCapabilityKind("URN:IETF:PARAMS:JMAP:CORE") == ckUnknown

# =============================================================================
# g) CreationId edge case: bare '#'
# =============================================================================

block creationIdBareHash:
  ## Bare "#" is rejected: starts with '#'.
  let r = parseCreationId("#")
  assertErr r
  assertErrFields r, "CreationId", "must not include '#' prefix", "#"

block creationIdHashOnly:
  ## Multiple hashes: first char is '#', so rejected.
  let r = parseCreationId("###")
  assertErr r

# =============================================================================
# h) NUL byte injection in additional types (FFI surface)
# =============================================================================
# Types that accept bare strings without control-character checking may contain
# NUL bytes. When these strings cross FFI to C, strlen() truncates at the NUL,
# making the C side see a different (shorter) string than the Nim side.

block uriTemplateAcceptsNul:
  ## parseUriTemplate only checks non-empty; NUL bytes pass validation.
  assertOk parseUriTemplate("https://evil.com\x00/{accountId}")

block uriTemplateNulAtStart:
  ## NUL as the first character: non-empty, so accepted.
  assertOk parseUriTemplate("\x00valid")

block invocationNameAcceptsNul:
  ## Invocation.name is a bare string with no validation.
  let inv = Invocation(
    name: "Email/get\x00Evil/set", arguments: newJObject(), methodCallId: makeMcid("c0")
  )
  doAssert inv.name.len == 18

block resultReferencePathAcceptsNul:
  ## ResultReference.path is a bare string; NUL bytes are preserved.
  let rr =
    ResultReference(resultOf: makeMcid("c0"), name: "Email/get", path: "/ids\x00/evil")
  doAssert rr.path.len == 10

block resultReferenceNameAcceptsNul:
  ## ResultReference.name is a bare string; NUL bytes are preserved.
  let rr =
    ResultReference(resultOf: makeMcid("c0"), name: "Email/get\x00hidden", path: "/ids")
  doAssert rr.name.len == 16

block requestUsingAcceptsNul:
  ## Request.using elements are bare strings; NUL bytes are not checked.
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core\x00evil"],
    methodCalls: @[],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`[0].len == 30

block transportErrorMessageAcceptsNul:
  ## TransportError.message is a bare string; NUL bytes are preserved.
  let te = transportError(tekNetwork, "connection\x00refused")
  doAssert te.message.len == 18

block accountNameAcceptsNul:
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

block idFromServerOverlongNewline:
  ## Overlong encoding of newline (0x0A): \xC0\x8A. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x8Adef")

block idFromServerOverlongCarriageReturn:
  ## Overlong encoding of CR (0x0D): \xC0\x8D. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x8Ddef")

block idFromServerOverlongTab:
  ## Overlong encoding of tab (0x09): \xC0\x89. Both bytes >= 0x20.
  assertOk parseIdFromServer("abc\xC0\x89def")

block idFromServerThreeByteOverlongNul:
  ## 3-byte overlong NUL \xE0\x80\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xE0\x80\x80def")

block idFromServerFourByteOverlongNul:
  ## 4-byte overlong NUL \xF0\x80\x80\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xF0\x80\x80\x80def")

block patchObjectOverlongSlash:
  ## Overlong encoding of '/' (0x2F): \xC0\xAF. Both bytes >= 0x20.
  ## Accepted as-is by PatchObject (no RFC 6901 parsing at Layer 1).
  assertOk emptyPatch().setProp("a\xC0\xAFb", %"val")

# =============================================================================
# j) UTF-8 truncation and continuation byte edge cases
# =============================================================================

block idFromServerTruncated3Byte1:
  ## Truncated 3-byte sequence: 1 of 3 bytes. 0xE2 >= 0x20, accepted.
  assertOk parseIdFromServer("abc\xE2")

block idFromServerTruncated3Byte2:
  ## Truncated 3-byte sequence: 2 of 3 bytes. Both >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xE2\x80")

block idFromServerTruncated4Byte1:
  ## Truncated 4-byte sequence: 1 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0")

block idFromServerTruncated4Byte2:
  ## Truncated 4-byte sequence: 2 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0\x9F")

block idFromServerTruncated4Byte3:
  ## Truncated 4-byte sequence: 3 of 4 bytes.
  assertOk parseIdFromServer("abc\xF0\x9F\x98")

block idFromServerLoneLowSurrogate:
  ## Lone low surrogate \xED\xB0\x80: all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("abc\xED\xB0\x80def")

block idFromServerInvalid5ByteSequence:
  ## 5-byte sequence \xF8\x80\x80\x80\x80: never valid UTF-8, but all >= 0x80.
  assertOk parseIdFromServer("\xF8\x80\x80\x80\x80")

block idFromServerInvalid6ByteSequence:
  ## 6-byte sequence \xFC\x80\x80\x80\x80\x80: never valid UTF-8, but all >= 0x80.
  assertOk parseIdFromServer("\xFC\x80\x80\x80\x80\x80")

# =============================================================================
# k) Integer boundary precision
# =============================================================================

block unsignedIntExactly2Pow53:
  ## 2^53 = 9007199254740992 is one above the maximum; rejected.
  assertErr parseUnsignedInt(9_007_199_254_740_992'i64)

block jmapIntNegationOfMinEqualsMax:
  ## -MinJmapInt == MaxJmapInt. Since MinJmapInt = -(2^53-1), this is safe.
  let minVal = parseJmapInt(MinJmapInt).get()
  let negated = -minVal
  let maxVal = parseJmapInt(MaxJmapInt).get()
  doAssert negated == maxVal

block unsignedIntNoNegation:
  ## UnsignedInt does not borrow unary negation.
  doAssert not compiles(-parseUnsignedInt(0).get())

block httpStatusErrorNegative:
  ## httpStatusError accepts any int, including negative values.
  let te = httpStatusError(-1, "negative status")
  doAssert te.kind == tekHttpStatus
  doAssert te.httpStatus == -1

block httpStatusErrorVeryLarge:
  ## httpStatusError accepts very large status codes.
  let te = httpStatusError(99999, "huge status")
  doAssert te.httpStatus == 99999

# =============================================================================
# l) String length extremes for length-unbounded types
# =============================================================================

block methodCallIdVeryLong:
  ## MethodCallId has no upper length bound; 65536 bytes accepted.
  assertOk parseMethodCallId("a".repeat(65536))

block creationIdVeryLong:
  ## CreationId has no upper length bound; 65536 bytes accepted.
  assertOk parseCreationId("a".repeat(65536))

block propertyNameVeryLong:
  ## PropertyName has no upper length bound; 65536 bytes accepted.
  assertOk parsePropertyName("a".repeat(65536))

block accountIdAllControlCharsRejected:
  ## 255 bytes of \x01 (control chars) rejected by AccountId.
  assertErr parseAccountId("\x01".repeat(255))

block methodCallIdAllControlCharsAccepted:
  ## MethodCallId has no control-character restriction; all control chars accepted.
  assertOk parseMethodCallId("\x01".repeat(255))

block allNulBytesForEachType:
  ## 255 bytes of NUL: accepted by permissive types, rejected by strict types.
  assertErr parseId("\x00".repeat(255))
  assertErr parseIdFromServer("\x00".repeat(255))
  assertErr parseAccountId("\x00".repeat(255))
  assertErr parseJmapState("\x00".repeat(255))
  assertOk parseMethodCallId("\x00".repeat(255))
  assertOk parseCreationId("\x00".repeat(255))
  assertOk parsePropertyName("\x00".repeat(255))

block allSpacesForIdTypes:
  ## 255 bytes of space: strict Id rejects, lenient accepts.
  assertErr parseId(" ".repeat(255))
  assertOk parseIdFromServer(" ".repeat(255))
  assertOk parseAccountId(" ".repeat(255))

# =============================================================================
# m) Date/time adversarial edge cases
# =============================================================================

block dateYear10000:
  ## 5-digit year: position 4 is '0' not '-', so date portion check fails.
  assertErr parseDate("10000-01-01T12:00:00Z")

block dateFractionalSecondsWithLowercaseZ:
  ## Fractional seconds followed by lowercase 'z': rejected.
  assertErr parseDate("2024-01-01T12:00:00.123z")

block dateFractionalNoTimezone:
  ## Fractional seconds present but no timezone suffix.
  assertErr parseDate("2024-01-01T12:00:00.123")

block dateDoubleDot:
  ## Double decimal point in fractional seconds position.
  assertErr parseDate("2024-01-01T12:00:00..123Z")

block dateNulInDatePortion:
  ## NUL byte at position 3 in date portion: not a digit, rejected.
  assertErr parseDate("202\x004-01-01T12:00:00Z")

block dateLongFractionalSeconds:
  ## 100000-digit fractional seconds: structurally valid, accepted.
  let frac = "1".repeat(100000)
  let input = "2024-01-01T12:00:00." & frac & "Z"
  assertOk parseDate(input)

# =============================================================================
# n) Enum parsing via nimIdentNormalize — additional edge cases
# =============================================================================

block methodErrorTypeLeadingUnderscore:
  ## Leading underscore is preserved by nimIdentNormalize; no match.
  doAssert parseMethodErrorType("_serverFail") == metUnknown

block methodErrorTypeMultipleLeadingUnderscores:
  ## Multiple leading underscores preserved.
  doAssert parseMethodErrorType("__serverFail") == metUnknown

block methodErrorTypeNulTerminated:
  ## NUL byte is not an underscore; breaks the match.
  doAssert parseMethodErrorType("serverFail\x00extra") == metUnknown

block methodErrorTypeVeryLong:
  ## Very long string: parseEnum iterates all variants without crashing.
  doAssert parseMethodErrorType("a".repeat(10000)) == metUnknown

block methodErrorTypeZeroWidthSpace:
  ## Zero-width space (UTF-8 bytes) embedded in the string breaks matching.
  doAssert parseMethodErrorType("server\xE2\x80\x8BFail") == metUnknown

block capabilityUriUnderscoreFalseMatch:
  ## Underscore between 'o' and 'w' in "unknownCapability" is stripped.
  doAssert parseRequestErrorType("urn:ietf:params:jmap:error:unkno_wnCapability") ==
    retUnknownCapability

# =============================================================================
# o) Session validation attacks
# =============================================================================

block uriTemplateVariableSubstringFalseNegative:
  ## "{accountIdblobId}" does NOT contain "{accountId}" as a variable.
  let tmpl =
    parseUriTemplate("https://e.com/{accountIdblobId}/{name}?accept={type}").get()
  doAssert not tmpl.hasVariable("accountId")
  doAssert tmpl.hasVariable("accountIdblobId")

block uriTemplateEmptyVariableName:
  ## hasVariable("") checks for "{}" as a substring.
  let tmpl = parseUriTemplate("https://e.com/{}/{name}").get()
  doAssert tmpl.hasVariable("")

block sessionCoreCapabilityMismatchedRawUri:
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

block methodCallIdVsCreationIdIsolation:
  ## MethodCallId and CreationId are distinct types; comparison rejected.
  doAssert not compiles(makeMcid("a") == makeCreationId("a"))

block jmapStateVsPropertyNameIsolation:
  doAssert not compiles(makeState("a") == makePropertyName("a"))

block uriTemplateVsPropertyNameIsolation:
  doAssert not compiles(makeUriTemplate("a") == makePropertyName("a"))

block dateVsUtcDateIsolation:
  ## Date and UTCDate are distinct types.
  doAssert not compiles(
    parseDate("2024-01-01T12:00:00Z").get() == parseUtcDate("2024-01-01T12:00:00Z").get()
  )

block directConstructionBypassesSmartConstructor:
  ## distinct types can be directly constructed, bypassing validation.
  ## This documents the limitation: smart constructors are the only safe path.
  doAssert compiles(Id(""))
  doAssert compiles(UnsignedInt(-999'i64))
  doAssert compiles(AccountId(""))

# =============================================================================
# q) Unicode visual confusion characters
# =============================================================================

block idFromServerRtlOverride:
  ## Right-to-left override U+202E: bytes \xE2\x80\xAE, all >= 0x80, accepted.
  assertOk parseIdFromServer("admin\xE2\x80\xAEtoor")

block idFromServerCyrillicHomoglyph:
  ## Cyrillic 'a' (U+0430): \xD0\xB0, both bytes >= 0x80, accepted.
  ## Visually similar to Latin 'a' but a different byte sequence.
  assertOk parseIdFromServer("\xD0\xB0bc")

block idFromServerZeroWidthJoiner:
  ## Zero-width joiner U+200D: \xE2\x80\x8D, all bytes >= 0x80, accepted.
  assertOk parseIdFromServer("a\xE2\x80\x8Db")

block idFromServerBomInMiddle:
  ## BOM \xEF\xBB\xBF in the middle of a string (not just at the start).
  assertOk parseIdFromServer("abc\xEF\xBB\xBFdef")
