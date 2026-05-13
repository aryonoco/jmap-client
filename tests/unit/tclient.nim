# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for JmapClient construction, mutators, pre-flight validation,
## and session staleness. Accessor-replacement tests drive behaviour
## through a recording Transport so the public surface is exercised
## end-to-end (no read accessors exist post-refactor).

import std/json
import std/strutils

from std/net import TimeoutError
when defined(ssl):
  from std/net import SslError

import jmap_client
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
import ../mtransport

# --- initJmapClient (default-transport convenience overload) ---

testCase initJmapClientHttpsValid:
  ## Scenario 1: valid HTTPS URL and token. Behaviour-tested via a
  ## RecordingTransport — the next ``fetchSession`` is observed to fire
  ## with the correct URL and Authorization header.
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = initJmapClient(
      transport = recordingTransport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.url, "https://example.com/jmap"
  assertEq recorder.lastRequest.authorization, "Bearer test-token"
  doAssert recorder.lastRequest.httpMethod == hmGet

testCase initJmapClientHttpValid:
  ## Scenario 2: valid HTTP URL (allowed for testing).
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = initJmapClient(
      transport = recordingTransport,
      sessionUrl = "http://localhost:8080/jmap",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.url, "http://localhost:8080/jmap"

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

# --- discoverJmapClient ---

testCase discoverJmapClientValid:
  ## Scenario 10: valid domain constructs the ``.well-known/jmap`` URL
  ## and ``fetchSession`` is observed to hit it.
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = discoverJmapClient(
      transport = recordingTransport,
      domain = "jmap.example.com",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.url, "https://jmap.example.com/.well-known/jmap"

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
  ## Scenario 14: update token, verify subsequent fetchSession carries
  ## the new Authorization header.
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = initJmapClient(
      transport = recordingTransport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "old-token",
    )
    .get()
  c.setBearerToken("new-token").get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.authorization, "Bearer new-token"

testCase setBearerTokenEmpty:
  ## Scenario 15: empty token rejected.
  let (recordingTransport, _) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = initJmapClient(
      transport = recordingTransport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "test-token",
    )
    .get()
  let btR = c.setBearerToken("")
  doAssert btR.isErr, "expected Err for empty token"
  doAssert btR.error.typeName == "JmapClient"
  doAssert btR.error.message == "bearerToken must not be empty"
  doAssert btR.error.value == ""

testCase initJmapClientNewlineInUrl:
  ## URL with newline characters rejected.
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

# --- RFC 8620 compliance edge cases ---

testCase discoverJmapClientWithPort:
  ## RFC 8620 §2.2: URL template includes [:${port}] — ports valid.
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = discoverJmapClient(
      transport = recordingTransport,
      domain = "example.com:8080",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.url, "https://example.com:8080/.well-known/jmap"

testCase discoverJmapClientFromEmailDomain:
  ## RFC 8620 §2.2: "MAY use the domain portion of [email address]".
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = discoverJmapClient(
      transport = recordingTransport,
      domain = "fastmail.com",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  assertEq recorder.lastRequest.url, "https://fastmail.com/.well-known/jmap"

testCase discoverJmapClientAlwaysHttps:
  ## RFC 8620 §1.7: "All HTTP requests MUST use the 'https://' scheme."
  let (recordingTransport, recorder) =
    newRecordingTransport(newCannedTransport(makeDefaultSessionJson(), "{}"))
  let c = discoverJmapClient(
      transport = recordingTransport,
      domain = "jmap.example.com",
      bearerToken = "test-token",
    )
    .get()
  discard c.fetchSession().get()
  doAssert recorder.lastRequest.url.startsWith("https://"),
    "discovery URL must use https:// per RFC 8620 §1.7"

# --- Additional edge-case documentation tests ---

testCase initJmapClientSchemeOnlyUrl:
  ## Design §1.2 validates scheme prefix only; server rejects at runtime.
  assertOk initJmapClient(sessionUrl = "https://", bearerToken = "test-token")

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
# Post-refactor: enforceBodySizeLimit returns Result[void, TransportError]
# and takes no RequestContext (the size check lives inside the Transport).

testCase enforceBodySizeLimitWithin:
  ## Scenario 45: body within limit — no error.
  enforceBodySizeLimit(100, "short body").get()

testCase enforceBodySizeLimitExceeds:
  ## Scenario 46: body exceeds limit — TransportError returned directly.
  let bslR = enforceBodySizeLimit(10, "this body exceeds ten bytes")
  doAssert bslR.isErr, "expected Err for body exceeds limit"
  doAssert bslR.error.kind == tekNetwork
  doAssert "exceeds limit" in bslR.error.message

testCase enforceBodySizeLimitAtLimit:
  ## Boundary: body length exactly at limit — no error (uses strict >).
  enforceBodySizeLimit(10, "0123456789").get()

testCase enforceBodySizeLimitDisabled:
  ## Scenario 47: limit = 0 (disabled) — no error even for large body.
  enforceBodySizeLimit(0, "any size body is fine").get()

# ---------------------------------------------------------------------------
# Pre-flight limit validation — drives client.send() through a canned-session
# Transport so the entire pipeline (validateLimits + classify + decode) is
# exercised end-to-end. The diagnostic strings live on ClientError, populated
# by validationToClientError when validateLimits rejects.
# ---------------------------------------------------------------------------

testCase validateLimitsZeroCalls:
  ## Scenario 21: 0 calls with maxCallsInRequest = 1 — within limits.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let client = newClientWithSessionCaps(caps)
  let req = makeBuiltRequest(methodCalls = @[])
  let res = client.send(req)
  doAssert res.isOk, "expected Ok within limits"

testCase validateLimitsAtCallLimit:
  ## Scenario 22: 1 call with maxCallsInRequest = 1 — exactly at limit.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let client = newClientWithSessionCaps(caps)
  let req = makeBuiltRequest(methodCalls = @[makeInvocation()])
  let res = client.send(req)
  doAssert res.isOk, "expected Ok at limit"

testCase validateLimitsExceedsCallLimit:
  ## Scenario 23: 2 calls with maxCallsInRequest = 1 — exceeds limit.
  let caps = makeCoreCapsWithLimits(maxCallsInRequest = 1)
  let client = newClientWithSessionCaps(caps)
  let req = makeBuiltRequest(
    methodCalls = @[
      makeInvocation("Mailbox/get", makeMcid("c0")),
      makeInvocation("Email/get", makeMcid("c1")),
    ]
  )
  let res = client.send(req)
  doAssert res.isErr, "expected Err for exceeding maxCallsInRequest"
  doAssert "maxCallsInRequest" in res.error.message

testCase validateLimitsGetWithinLimit:
  ## Scenario 24: /get with 5 direct ids, maxObjectsInGet = 10 — within.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  let client = newClientWithSessionCaps(caps)
  var ids = newSeq[Id](5)
  for i in 0 ..< 5:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    client.newBuilder(), accountId = parseAccountId("a1").get(), ids = directIds(ids)
  )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok within /get limit"

testCase validateLimitsGetExceedsLimit:
  ## Scenario 25: /get with 11 direct ids, maxObjectsInGet = 10 — exceeds.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  let client = newClientWithSessionCaps(caps)
  var ids = newSeq[Id](11)
  for i in 0 ..< 11:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    client.newBuilder(), accountId = parseAccountId("a1").get(), ids = directIds(ids)
  )
  let res = client.send(b.freeze())
  doAssert res.isErr, "expected Err for exceeding maxObjectsInGet"
  doAssert "maxObjectsInGet" in res.error.message

testCase validateLimitsGetReferenceIds:
  ## Scenario 26: /get with reference ids — count unknown, skipped.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let client = newClientWithSessionCaps(caps)
  let rr = initResultReference(
    resultOf = parseMethodCallId("c0").get(), name = mnEmailQuery, path = rpIds
  )
  let (b, _) = addGet[Email](
    client.newBuilder(),
    accountId = parseAccountId("a1").get(),
    ids = Opt.some(referenceTo[seq[Id]](rr)),
  )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for reference ids"

testCase validateLimitsGetNullIds:
  ## Scenario 27: /get with no ids parameter — idCount = 0.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let client = newClientWithSessionCaps(caps)
  let (b, _) =
    addGet[Email](client.newBuilder(), accountId = parseAccountId("a1").get())
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for null ids"

testCase validateLimitsSetWithinLimit:
  ## Scenario 28: /set with combined object count 9, limit 10 — within.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(9)),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok within /set limit"

testCase validateLimitsSetExceedsLimit:
  ## Scenario 29: /set with combined object count 11, limit 10 — exceeds.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(11)),
    )
  let res = client.send(b.freeze())
  doAssert res.isErr, "expected Err for exceeding maxObjectsInSet"
  doAssert "maxObjectsInSet" in res.error.message

testCase validateLimitsSetReferenceDestroy:
  ## Scenario 30: /set with reference destroy — objectCount = Opt.none, skipped.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 1)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.none(int)),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for reference destroy"

testCase validateLimitsEmptyRequest:
  ## Scenario 31: empty Request with no method calls — trivially valid.
  let caps = realisticCoreCaps()
  let client = newClientWithSessionCaps(caps)
  let req = makeBuiltRequest(methodCalls = @[])
  let res = client.send(req)
  doAssert res.isOk, "expected Ok for empty request"

testCase validateLimitsMixedWithinLimits:
  ## Scenario 32: mixed /get and /set invocations, all within limits.
  let caps = makeCoreCapsWithLimits(
    maxCallsInRequest = 3, maxObjectsInGet = 10, maxObjectsInSet = 10
  )
  let client = newClientWithSessionCaps(caps)
  var ids = newSeq[Id](5)
  for i in 0 ..< 5:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b1, _) = addGet[Email](
    client.newBuilder(), accountId = parseAccountId("a1").get(), ids = directIds(ids)
  )
  let (b2, _) = b1.addInvocation(
    mnEmailSet,
    newJObject(),
    parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
    CallLimitMeta(kind: clmSet, objectCount: Opt.some(3)),
  )
  let res = client.send(b2.freeze())
  doAssert res.isOk, "expected Ok for mixed within limits"

testCase validateLimitsNonStandardMethod:
  ## Scenario 33: non-standard method name carries clmOther meta;
  ## no per-call /get or /set check applied.
  let caps = makeCoreCapsWithLimits(
    maxCallsInRequest = 10, maxObjectsInGet = 1, maxObjectsInSet = 1
  )
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnUnknown,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:core").get(),
      CallLimitMeta(kind: clmOther),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for non-standard method"

# ---------------------------------------------------------------------------
# validateLimits — additional boundary and edge-case tests
# ---------------------------------------------------------------------------

testCase validateLimitsGetAtLimit:
  ## Boundary: /get with exactly 10 direct ids, maxObjectsInGet = 10 — at limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 10)
  let client = newClientWithSessionCaps(caps)
  var ids = newSeq[Id](10)
  for i in 0 ..< 10:
    ids[i] = parseIdFromServer("id" & $i).get()
  let (b, _) = addGet[Email](
    client.newBuilder(), accountId = parseAccountId("a1").get(), ids = directIds(ids)
  )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok at /get limit"

testCase validateLimitsSetAtLimit:
  ## Boundary: /set with combined object count exactly 10, limit 10 — at limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 10)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(10)),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok at /set limit"

testCase validateLimitsGetEmptyIds:
  ## Edge case: /get with empty ids array — idCount = 0.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = addGet[Email](
    client.newBuilder(),
    accountId = parseAccountId("a1").get(),
    ids = directIds(newSeq[Id]()),
  )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for empty ids"

testCase validateLimitsSetEmptyArguments:
  ## Edge case: /set with object count 0 — within any limit.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 1)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(0)),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for empty set"

testCase validateLimitsSetOnlyDestroy:
  ## Edge case: /set with only destroy entries — count = 3.
  let caps = makeCoreCapsWithLimits(maxObjectsInSet = 5)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnMailboxSet,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:mail").get(),
      CallLimitMeta(kind: clmSet, objectCount: Opt.some(3)),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for destroy-only"

testCase validateLimitsMethodPartialMatch:
  ## Edge case: a non-standard method name carrying clmOther meta is
  ## not subject to per-call /get or /set enforcement.
  let caps = makeCoreCapsWithLimits(maxObjectsInGet = 1, maxObjectsInSet = 1)
  let client = newClientWithSessionCaps(caps)
  let (b, _) = client.newBuilder().addInvocation(
      mnUnknown,
      newJObject(),
      parseCapabilityUri("urn:ietf:params:jmap:core").get(),
      CallLimitMeta(kind: clmOther),
    )
  let res = client.send(b.freeze())
  doAssert res.isOk, "expected Ok for non-standard method"

# --- isSessionStale ---

testCase isSessionStaleSameState:
  ## Scenario 34: same state -> false. The canned transport returns the
  ## default session JSON whose state is "s1"; a DispatchedResponse
  ## carrying the same state is not stale.
  let client = newClientWithSessionCaps(realisticCoreCaps())
  let resp = makeResponse(state = makeState("s1"))
  assertEq client.isSessionStale(makeDispatchedResponse(resp)), false

testCase isSessionStaleDifferentState:
  ## Scenario 35: different state -> true.
  let client = newClientWithSessionCaps(realisticCoreCaps())
  let resp = makeResponse(state = makeState("different-state"))
  assertEq client.isSessionStale(makeDispatchedResponse(resp)), true

testCase isSessionStaleNoSession:
  ## Scenario 36: no cached session -> false. Builds the client through
  ## the primary constructor with a canned transport but does NOT call
  ## ``fetchSession``, so no session is cached.
  let transport = newCannedTransport(makeDefaultSessionJson(), "{}")
  let c = initJmapClient(
      transport = transport,
      sessionUrl = "https://example.com/jmap",
      bearerToken = "test-token",
    )
    .get()
  let resp = makeResponse(state = makeState("any-state"))
  assertEq c.isSessionStale(makeDispatchedResponse(resp)), false
