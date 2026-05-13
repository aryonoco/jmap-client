# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for JmapClient type, constructors, accessors, mutators, pure helpers,
## pre-flight validation, and session staleness (Layer 4 Steps 1–4).
## Design doc scenarios 1–36, 37–50.

import std/json
import std/strutils

from std/net import TimeoutError
when defined(ssl):
  from std/net import SslError

import jmap_client/client
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/envelope
import jmap_client/internal/types/errors
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/primitives
import jmap_client/internal/types/session
import jmap_client/internal/types/validation
import jmap_client/internal/protocol/builder
import jmap_client/internal/protocol/call_meta
import jmap_client/internal/mail/email
import jmap_client/internal/mail/mail_entities

import ../massertions
import ../mfixtures
import ../mtestblock

# --- initJmapClient ---

testCase initJmapClientHttpsValid:
  ## Scenario 1: valid HTTPS URL and token.
  let c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  assertEq c.sessionUrl(), "https://example.com/jmap"
  assertEq c.bearerToken(), "test-token"
  assertNone c.session()

testCase initJmapClientHttpValid:
  ## Scenario 2: valid HTTP URL (allowed for testing).
  let c = initJmapClient(
      sessionUrl = "http://localhost:8080/jmap", bearerToken = "test-token"
    )
    .get()
  assertEq c.sessionUrl(), "http://localhost:8080/jmap"

testCase initJmapClientEmptyUrl:
  ## Scenario 3: empty sessionUrl rejected.
  assertErrFields initJmapClient(sessionUrl = "", bearerToken = "test-token"),
    "JmapClient", "sessionUrl must not be empty", ""

testCase initJmapClientNoScheme:
  ## Scenario 4: URL without scheme prefix rejected.
  assertErrFields initJmapClient(
    sessionUrl = "example.com/jmap", bearerToken = "test-token"
  ), "JmapClient", "sessionUrl must start with https:// or http://", "example.com/jmap"

testCase initJmapClientEmptyToken:
  ## Scenario 5: empty bearerToken rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = ""
  ), "JmapClient", "bearerToken must not be empty", ""

testCase initJmapClientTimeoutNoLimit:
  ## Scenario 6: timeout = -1 (no timeout) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = -1
  )

testCase initJmapClientTimeoutInvalid:
  ## Scenario 7: timeout = -2 rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = -2
  ), "JmapClient", "timeout must be >= -1", "-2"

testCase initJmapClientMaxRedirectsZero:
  ## Scenario 8: maxRedirects = 0 (no redirects) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxRedirects = 0,
  )

testCase initJmapClientMaxResponseBytesZero:
  ## Scenario 9: maxResponseBytes = 0 (no limit) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxResponseBytes = 0,
  )

# --- discoverJmapClient ---

testCase discoverJmapClientValid:
  ## Scenario 10: valid domain constructs correct .well-known URL.
  let c =
    discoverJmapClient(domain = "jmap.example.com", bearerToken = "test-token").get()
  assertEq c.sessionUrl(), "https://jmap.example.com/.well-known/jmap"

testCase discoverJmapClientEmptyDomain:
  ## Scenario 11: empty domain rejected.
  assertErrFields discoverJmapClient(domain = "", bearerToken = "test-token"),
    "JmapClient", "domain must not be empty", ""

testCase discoverJmapClientSlash:
  ## Scenario 12: domain with '/' rejected (path injection prevention).
  assertErrFields discoverJmapClient(domain = "ex/ample", bearerToken = "test-token"),
    "JmapClient", "domain must not contain '/'", "ex/ample"

testCase discoverJmapClientWhitespace:
  ## Scenario 13: domain with whitespace rejected (header injection prevention).
  assertErrFields discoverJmapClient(domain = "ex ample", bearerToken = "test-token"),
    "JmapClient", "domain must not contain whitespace", "ex ample"

# --- setBearerToken ---

testCase setBearerTokenValid:
  ## Scenario 14: update token, verify accessor returns new value.
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "old-token"
    )
    .get()
  c.setBearerToken("new-token").get()
  assertEq c.bearerToken(), "new-token"

testCase setBearerTokenEmpty:
  ## Scenario 15: empty token rejected.
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  let btR = c.setBearerToken("")
  doAssert btR.isErr, "expected Err for empty token"
  doAssert btR.error.typeName == "JmapClient"
  doAssert btR.error.message == "bearerToken must not be empty"
  doAssert btR.error.value == ""

# --- Additional edge cases ---

testCase initJmapClientSessionNone:
  ## Session accessor returns none before fetch.
  let c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  doAssert c.session().isNone

testCase initJmapClientMaxRedirectsNegative:
  ## Negative maxRedirects rejected (prevents RangeDefect on Natural field).
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxRedirects = -1,
  ), "JmapClient", "maxRedirects must be >= 0", "-1"

testCase initJmapClientMaxResponseBytesNegative:
  ## Negative maxResponseBytes rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxResponseBytes = -1,
  ), "JmapClient", "maxResponseBytes must be >= 0", "-1"

testCase initJmapClientNewlineInUrl:
  ## URL with newline characters rejected (prevents doAssert crash in std/httpclient).
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap\r\nEvil: header", bearerToken = "test-token"
  ),
    "JmapClient",
    "sessionUrl must not contain newline characters",
    "https://example.com/jmap\r\nEvil: header"

testCase initJmapClientCarriageReturnInUrl:
  ## URL with lone carriage return rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap\rpath", bearerToken = "test-token"
  ),
    "JmapClient",
    "sessionUrl must not contain newline characters",
    "https://example.com/jmap\rpath"

testCase initJmapClientLineFeedInUrl:
  ## URL with lone line feed rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap\npath", bearerToken = "test-token"
  ),
    "JmapClient",
    "sessionUrl must not contain newline characters",
    "https://example.com/jmap\npath"

testCase closeIdempotent:
  ## Close can be called multiple times without error.
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  c.close()
  c.close()

# --- RFC 8620 compliance edge cases ---

testCase discoverJmapClientWithPort:
  ## RFC 8620 §2.2: URL template includes [:${port}] — ports in hostname valid.
  let c =
    discoverJmapClient(domain = "example.com:8080", bearerToken = "test-token").get()
  assertEq c.sessionUrl(), "https://example.com:8080/.well-known/jmap"

testCase discoverJmapClientFromEmailDomain:
  ## RFC 8620 §2.2: "MAY use the domain portion of [email address]".
  let c = discoverJmapClient(domain = "fastmail.com", bearerToken = "test-token").get()
  assertEq c.sessionUrl(), "https://fastmail.com/.well-known/jmap"

testCase discoverJmapClientAlwaysHttps:
  ## RFC 8620 §1.7: "All HTTP requests MUST use the 'https://' scheme."
  ## discoverJmapClient always constructs https:// URLs.
  let c =
    discoverJmapClient(domain = "jmap.example.com", bearerToken = "test-token").get()
  doAssert c.sessionUrl().startsWith("https://"),
    "discovery URL must use https:// per RFC 8620 §1.7"

# --- Additional edge-case documentation tests ---

testCase initJmapClientSchemeOnlyUrl:
  ## Design §1.2 validates scheme prefix only; server rejects at runtime.
  assertOk initJmapClient(sessionUrl = "https://", bearerToken = "test-token")

testCase initJmapClientTimeoutZero:
  ## timeout = 0 is valid (>= -1); means "return immediately" per std/httpclient.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = 0
  )

testCase initJmapClientAllEdgeLimits:
  ## Parameter combination: all optional limits at their edge values.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    timeout = 0,
    maxRedirects = 0,
    maxResponseBytes = 0,
  )

testCase closeThenAccessors:
  ## close() affects the HTTP socket only — accessors still return original values.
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  c.close()
  assertEq c.sessionUrl(), "https://example.com/jmap"
  assertEq c.bearerToken(), "test-token"
  assertNone c.session()

# --- expandUriTemplate (scenarios 16–20) ---

testCase expandUriTemplateAllVars:
  ## Scenario 16: all variables present — all {name} replaced.
  let tmpl = makeGoldenDownloadUrl()
  let result = expandUriTemplate(
    tmpl,
    {
      "accountId": "A123",
      "blobId": "B456",
      "name": "report.pdf",
      "type": "application/pdf",
    },
  )
  assertEq result,
    "https://jmap.example.com/download/A123/B456/report.pdf?accept=application/pdf"

testCase expandUriTemplateMissingVar:
  ## Scenario 17: missing variable left unexpanded.
  let tmpl = makeUriTemplate("https://example.com/{accountId}/{blobId}")
  let result = expandUriTemplate(tmpl, {"accountId": "A123"})
  assertEq result, "https://example.com/A123/{blobId}"

testCase expandUriTemplateEmptyValue:
  ## Scenario 18: empty value replaces {name} with "".
  let tmpl = makeUriTemplate("https://example.com/{name}")
  let result = expandUriTemplate(tmpl, {"name": ""})
  assertEq result, "https://example.com/"

testCase expandUriTemplateSpecialChars:
  ## Scenario 19: special characters in value preserved (no encoding — D4.11).
  let tmpl = makeUriTemplate("https://example.com/{name}")
  let result = expandUriTemplate(tmpl, {"name": "hello world&foo=bar"})
  assertEq result, "https://example.com/hello world&foo=bar"

testCase expandUriTemplateMultipleOccurrences:
  ## Scenario 20: multiple occurrences of same variable all replaced.
  let tmpl = makeUriTemplate("{x}/{x}")
  let result = expandUriTemplate(tmpl, {"x": "abc"})
  assertEq result, "abc/abc"

# --- classifyException (scenarios 37–44) ---

testCase classifyExceptionTimeout:
  ## Scenario 37: TimeoutError maps to tekTimeout.
  let e = newException(TimeoutError, "Call to 'recv' timed out.")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekTimeout
  doAssert ce.transport.message == "Call to 'recv' timed out."

testCase classifyExceptionOsErrorSsl:
  ## Scenario 38: OSError with "ssl" in message maps to tekTls.
  let e = newException(OSError, "ssl handshake failed")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekTls

testCase classifyExceptionOsErrorTls:
  ## Scenario 39: OSError with "TLS" (case-insensitive) maps to tekTls.
  let e = newException(OSError, "TLS protocol error")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekTls

testCase classifyExceptionOsErrorCertificate:
  ## Scenario 40: OSError with "certificate" maps to tekTls.
  let e = newException(OSError, "certificate verification failed")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekTls

testCase classifyExceptionOsErrorNetwork:
  ## Scenario 41: OSError without TLS keywords maps to tekNetwork.
  let e = newException(OSError, "connection refused")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekNetwork

testCase classifyExceptionIoError:
  ## Scenario 42: IOError maps to tekNetwork.
  let e = newException(IOError, "connection reset by peer")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekNetwork

testCase classifyExceptionValueError:
  ## Scenario 43: ValueError maps to tekNetwork with "protocol error:" prefix.
  let e = newException(ValueError, "unparseable URL")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekNetwork
  doAssert "protocol error:" in ce.transport.message

testCase classifyExceptionCatchAll:
  ## Scenario 44: other CatchableError maps to tekNetwork with "unexpected error:" prefix.
  let ce = classifyException((ref CatchableError)(msg: "something unknown"))
  doAssert ce.transport.kind == tekNetwork
  doAssert "unexpected error:" in ce.transport.message

when defined(ssl):
  block classifyExceptionSslError:
    ## SslError (from std/net, inherits CatchableError directly) maps to tekTls.
    let e = newException(SslError, "error:1416F086:SSL routines")
    let ce = classifyException(e)
    doAssert ce.kind == cekTransport
    doAssert ce.transport.kind == tekTls
    doAssert ce.transport.message == "error:1416F086:SSL routines"

# --- enforceBodySizeLimit (scenarios 45–47) ---

testCase enforceBodySizeLimitWithin:
  ## Scenario 45: body within limit — no error.
  enforceBodySizeLimit(100, "short body", rcSession).get()

testCase enforceBodySizeLimitExceeds:
  ## Scenario 46: body exceeds limit — ClientError returned.
  let bslR = enforceBodySizeLimit(10, "this body exceeds ten bytes", rcSession)
  doAssert bslR.isErr, "expected Err for body exceeds limit"
  doAssert bslR.error.kind == cekTransport
  doAssert bslR.error.transport.kind == tekNetwork
  doAssert "exceeds limit" in bslR.error.transport.message

testCase enforceBodySizeLimitAtLimit:
  ## Boundary: body length exactly at limit — no error (uses strict >).
  enforceBodySizeLimit(10, "0123456789", rcSession).get()

testCase enforceBodySizeLimitDisabled:
  ## Scenario 47: limit = 0 (disabled) — no error even for large body.
  enforceBodySizeLimit(0, "any size body is fine", rcSession).get()

# ---------------------------------------------------------------------------
# validateLimits — design doc scenarios 21–33
# ---------------------------------------------------------------------------

testCase validateLimitsZeroCalls:
  ## Scenario 21: 0 calls with maxCallsInRequest = 1 — within limits.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let req = makeBuiltRequest(methodCalls = @[])
  validateLimits(req, caps).get()

testCase validateLimitsAtCallLimit:
  ## Scenario 22: 1 call with maxCallsInRequest = 1 — exactly at limit.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let req = makeBuiltRequest(methodCalls = @[makeInvocation()])
  validateLimits(req, caps).get()

testCase validateLimitsExceedsCallLimit:
  ## Scenario 23: 2 calls with maxCallsInRequest = 1 — exceeds limit.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let req = makeBuiltRequest(
    methodCalls = @[
      makeInvocation("Mailbox/get", makeMcid("c0")),
      makeInvocation("Email/get", makeMcid("c1")),
    ]
  )
  let limR1 = validateLimits(req, caps)
  doAssert limR1.isErr, "expected Err for exceeding maxCallsInRequest"
  doAssert limR1.error.typeName == "Request"
  doAssert "maxCallsInRequest" in limR1.error.message

testCase validateLimitsGetWithinLimit:
  ## Scenario 24: /get with 5 direct ids, maxObjectsInGet = 10 — within limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  var ids = newSeq[Id](5)
  for i in 0 ..< 5:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = directIds(ids),
  )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsGetExceedsLimit:
  ## Scenario 25: /get with 11 direct ids, maxObjectsInGet = 10 — exceeds limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  var ids = newSeq[Id](11)
  for i in 0 ..< 11:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = directIds(ids),
  )
  let limR2 = validateLimits(b.freeze(), caps)
  doAssert limR2.isErr, "expected Err for exceeding maxObjectsInGet"
  doAssert limR2.error.typeName == "Request"
  doAssert "maxObjectsInGet" in limR2.error.message

testCase validateLimitsGetReferenceIds:
  ## Scenario 26: /get with reference ids — count unknown, skipped.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let rr = initResultReference(
    resultOf = parseMethodCallId("c0").get(), name = mnEmailQuery, path = rpIds
  )
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = Opt.some(referenceTo[seq[Id]](rr)),
  )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsGetNullIds:
  ## Scenario 27: /get with no ids parameter — idCount = 0.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()), accountId = parseAccountId("a1").get()
  )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsSetWithinLimit:
  ## Scenario 28: /set with combined object count 9, limit 10 — within.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(9)),
    )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsSetExceedsLimit:
  ## Scenario 29: /set with combined object count 11, limit 10 — exceeds.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(11)),
    )
  let limR3 = validateLimits(b.freeze(), caps)
  doAssert limR3.isErr, "expected Err for exceeding maxObjectsInSet"
  doAssert limR3.error.typeName == "Request"
  doAssert "maxObjectsInSet" in limR3.error.message

testCase validateLimitsSetReferenceDestroy:
  ## Scenario 30: /set with reference destroy — objectCount = Opt.none, skipped.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 1)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.none(int)),
    )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsEmptyRequest:
  ## Scenario 31: empty Request with no method calls — trivially valid.
  let caps = realisticCoreCaps()
  let req = makeBuiltRequest(methodCalls = @[])
  validateLimits(req, caps).get()

testCase validateLimitsMixedWithinLimits:
  ## Scenario 32: mixed /get and /set invocations, all within limits.
  let caps = makeCoreCapsWithLimits(
    maxCallsInRequest = 3, maxObjectsInGet = 10, maxObjectsInSet = 10
  )
  var ids = newSeq[Id](5)
  for i in 0 ..< 5:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b1, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = directIds(ids),
  )
  let (b2, _) = b1.addInvocation(
    mnEmailSet,
    newJObject(),
    parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
    CallLimitMeta(kind: clmSet, objectCount: Opt.some(3)),
  )
  validateLimits(b2.freeze(), caps).get()

testCase validateLimitsNonStandardMethod:
  ## Scenario 33: non-standard method name carries clmOther meta;
  ## no per-call /get or /set check applied.
  let caps = makeCoreCapsWithLimits(
    maxCallsInRequest = 10, maxObjectsInGet = 1, maxObjectsInSet = 1
  )
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnUnknown,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:core").get(),
      CallLimitMeta(kind: clmOther),
    )
  validateLimits(b.freeze(), caps).get()

# ---------------------------------------------------------------------------
# validateLimits — additional boundary and edge-case tests
# ---------------------------------------------------------------------------

testCase validateLimitsGetAtLimit:
  ## Boundary: /get with exactly 10 direct ids, maxObjectsInGet = 10 — at limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  var ids = newSeq[Id](10)
  for i in 0 ..< 10:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = directIds(ids),
  )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsSetAtLimit:
  ## Boundary: /set with combined object count exactly 10, limit 10 — at limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(10)),
    )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsGetEmptyIds:
  ## Edge case: /get with empty ids array — idCount = 0.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let (b, _) = addGet[Email](
    initRequestBuilder(makeBuilderId()),
    accountId = parseAccountId("a1").get(),
    ids = directIds(newSeq[Id]()),
  )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsSetEmptyArguments:
  ## Edge case: /set with object count 0 — within any limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 1)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(0)),
    )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsSetOnlyDestroy:
  ## Edge case: /set with only destroy entries — count = 3.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 5)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(3)),
    )
  validateLimits(b.freeze(), caps).get()

testCase validateLimitsMethodPartialMatch:
  ## Edge case: a non-standard method name carrying clmOther meta is
  ## not subject to per-call /get or /set enforcement, regardless of
  ## the wire-name shape.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1, maxObjectsInSet = 1)
  let (b, _) = initRequestBuilder(makeBuilderId()).addInvocation(
      mnUnknown,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:core").get(),
      CallLimitMeta(kind: clmOther),
    )
  validateLimits(b.freeze(), caps).get()

# --- setSessionForTest ---

testCase setSessionForTestVerify:
  ## setSessionForTest injects a session accessible via session() accessor.
  let args = makeSessionArgs()
  let session = parseSessionFromArgs(args)
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  assertNone c.session()
  c.setSessionForTest(session)
  doAssert c.session().isSome
  doAssert $c.session().get().state == $args.state

# --- isSessionStale ---

testCase isSessionStaleSameState:
  ## Scenario 34: same state -> false.
  let args = makeSessionArgs()
  let session = parseSessionFromArgs(args)
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  c.setSessionForTest(session)
  let resp = makeResponse(state = args.state)
  assertEq c.isSessionStale(makeDispatchedResponse(resp)), false

testCase isSessionStaleDifferentState:
  ## Scenario 35: different state -> true.
  let args = makeSessionArgs()
  let session = parseSessionFromArgs(args)
  var c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  c.setSessionForTest(session)
  let resp = makeResponse(state = makeState("different-state"))
  assertEq c.isSessionStale(makeDispatchedResponse(resp)), true

testCase isSessionStaleNoSession:
  ## Scenario 36: no cached session -> false.
  let c = initJmapClient(
      sessionUrl = "https://example.com/jmap", bearerToken = "test-token"
    )
    .get()
  let resp = makeResponse(state = makeState("any-state"))
  assertEq c.isSessionStale(makeDispatchedResponse(resp)), false
