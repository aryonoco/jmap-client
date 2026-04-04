# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for JmapClient type, constructors, accessors, and mutators
## (Layer 4 Step 1). Design doc scenarios 1–15 plus additional edge cases.

import std/options
import std/strutils

from std/net import TimeoutError
when defined(ssl):
  from std/net import SslError

import jmap_client/client
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures

# --- initJmapClient ---

block initJmapClientHttpsValid:
  ## Scenario 1: valid HTTPS URL and token.
  let c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "test-token")
  assertEq c.sessionUrl(), "https://example.com/jmap"
  assertEq c.bearerToken(), "test-token"
  assertNone c.session()

block initJmapClientHttpValid:
  ## Scenario 2: valid HTTP URL (allowed for testing).
  let c = initJmapClient(
    sessionUrl = "http://localhost:8080/jmap", bearerToken = "test-token"
  )
  assertEq c.sessionUrl(), "http://localhost:8080/jmap"

block initJmapClientEmptyUrl:
  ## Scenario 3: empty sessionUrl rejected.
  assertErrFields initJmapClient(sessionUrl = "", bearerToken = "test-token"),
    "JmapClient", "sessionUrl must not be empty", ""

block initJmapClientNoScheme:
  ## Scenario 4: URL without scheme prefix rejected.
  assertErrFields initJmapClient(
    sessionUrl = "example.com/jmap", bearerToken = "test-token"
  ), "JmapClient", "sessionUrl must start with https:// or http://", "example.com/jmap"

block initJmapClientEmptyToken:
  ## Scenario 5: empty bearerToken rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = ""
  ), "JmapClient", "bearerToken must not be empty", ""

block initJmapClientTimeoutNoLimit:
  ## Scenario 6: timeout = -1 (no timeout) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = -1
  )

block initJmapClientTimeoutInvalid:
  ## Scenario 7: timeout = -2 rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = -2
  ), "JmapClient", "timeout must be >= -1", "-2"

block initJmapClientMaxRedirectsZero:
  ## Scenario 8: maxRedirects = 0 (no redirects) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxRedirects = 0,
  )

block initJmapClientMaxResponseBytesZero:
  ## Scenario 9: maxResponseBytes = 0 (no limit) is valid.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxResponseBytes = 0,
  )

# --- discoverJmapClient ---

block discoverJmapClientValid:
  ## Scenario 10: valid domain constructs correct .well-known URL.
  let c = discoverJmapClient(domain = "jmap.example.com", bearerToken = "test-token")
  assertEq c.sessionUrl(), "https://jmap.example.com/.well-known/jmap"

block discoverJmapClientEmptyDomain:
  ## Scenario 11: empty domain rejected.
  assertErrFields discoverJmapClient(domain = "", bearerToken = "test-token"),
    "JmapClient", "domain must not be empty", ""

block discoverJmapClientSlash:
  ## Scenario 12: domain with '/' rejected (path injection prevention).
  assertErrFields discoverJmapClient(domain = "ex/ample", bearerToken = "test-token"),
    "JmapClient", "domain must not contain '/'", "ex/ample"

block discoverJmapClientWhitespace:
  ## Scenario 13: domain with whitespace rejected (header injection prevention).
  assertErrFields discoverJmapClient(domain = "ex ample", bearerToken = "test-token"),
    "JmapClient", "domain must not contain whitespace", "ex ample"

# --- setBearerToken ---

block setBearerTokenValid:
  ## Scenario 14: update token, verify accessor returns new value.
  var c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "old-token")
  c.setBearerToken("new-token")
  assertEq c.bearerToken(), "new-token"

block setBearerTokenEmpty:
  ## Scenario 15: empty token rejected.
  var c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "test-token")
  var caught = false
  try:
    c.setBearerToken("")
  except ValidationError as e:
    caught = true
    doAssert e.typeName == "JmapClient"
    doAssert e.msg == "bearerToken must not be empty"
    doAssert e.value == ""
  doAssert caught, "expected ValidationError"

# --- Additional edge cases ---

block initJmapClientSessionNone:
  ## Session accessor returns none before fetch.
  let c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "test-token")
  doAssert c.session().isNone

block initJmapClientMaxRedirectsNegative:
  ## Negative maxRedirects rejected (prevents RangeDefect on Natural field).
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxRedirects = -1,
  ), "JmapClient", "maxRedirects must be >= 0", "-1"

block initJmapClientMaxResponseBytesNegative:
  ## Negative maxResponseBytes rejected.
  assertErrFields initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    maxResponseBytes = -1,
  ), "JmapClient", "maxResponseBytes must be >= 0", "-1"

block closeIdempotent:
  ## Close can be called multiple times without error.
  var c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "test-token")
  c.close()
  c.close()

# --- RFC 8620 compliance edge cases ---

block discoverJmapClientWithPort:
  ## RFC 8620 §2.2: URL template includes [:${port}] — ports in hostname valid.
  let c = discoverJmapClient(domain = "example.com:8080", bearerToken = "test-token")
  assertEq c.sessionUrl(), "https://example.com:8080/.well-known/jmap"

block discoverJmapClientFromEmailDomain:
  ## RFC 8620 §2.2: "MAY use the domain portion of [email address]".
  let c = discoverJmapClient(domain = "fastmail.com", bearerToken = "test-token")
  assertEq c.sessionUrl(), "https://fastmail.com/.well-known/jmap"

block discoverJmapClientAlwaysHttps:
  ## RFC 8620 §1.7: "All HTTP requests MUST use the 'https://' scheme."
  ## discoverJmapClient always constructs https:// URLs.
  let c = discoverJmapClient(domain = "jmap.example.com", bearerToken = "test-token")
  doAssert c.sessionUrl().startsWith("https://"),
    "discovery URL must use https:// per RFC 8620 §1.7"

# --- Additional edge-case documentation tests ---

block initJmapClientSchemeOnlyUrl:
  ## Design §1.2 validates scheme prefix only; server rejects at runtime.
  assertOk initJmapClient(sessionUrl = "https://", bearerToken = "test-token")

block initJmapClientTimeoutZero:
  ## timeout = 0 is valid (>= -1); means "return immediately" per std/httpclient.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap", bearerToken = "test-token", timeout = 0
  )

block initJmapClientAllEdgeLimits:
  ## Parameter combination: all optional limits at their edge values.
  assertOk initJmapClient(
    sessionUrl = "https://example.com/jmap",
    bearerToken = "test-token",
    timeout = 0,
    maxRedirects = 0,
    maxResponseBytes = 0,
  )

block closeThenAccessors:
  ## close() affects the HTTP socket only — accessors still return original values.
  var c =
    initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "test-token")
  c.close()
  assertEq c.sessionUrl(), "https://example.com/jmap"
  assertEq c.bearerToken(), "test-token"
  assertNone c.session()

# --- expandUriTemplate (scenarios 16–20) ---

block expandUriTemplateAllVars:
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

block expandUriTemplateMissingVar:
  ## Scenario 17: missing variable left unexpanded.
  let tmpl = makeUriTemplate("https://example.com/{accountId}/{blobId}")
  let result = expandUriTemplate(tmpl, {"accountId": "A123"})
  assertEq result, "https://example.com/A123/{blobId}"

block expandUriTemplateEmptyValue:
  ## Scenario 18: empty value replaces {name} with "".
  let tmpl = makeUriTemplate("https://example.com/{name}")
  let result = expandUriTemplate(tmpl, {"name": ""})
  assertEq result, "https://example.com/"

block expandUriTemplateSpecialChars:
  ## Scenario 19: special characters in value preserved (no encoding — D4.11).
  let tmpl = makeUriTemplate("https://example.com/{name}")
  let result = expandUriTemplate(tmpl, {"name": "hello world&foo=bar"})
  assertEq result, "https://example.com/hello world&foo=bar"

block expandUriTemplateMultipleOccurrences:
  ## Scenario 20: multiple occurrences of same variable all replaced.
  let tmpl = makeUriTemplate("{x}/{x}")
  let result = expandUriTemplate(tmpl, {"x": "abc"})
  assertEq result, "abc/abc"

# --- classifyException (scenarios 37–44) ---

block classifyExceptionTimeout:
  ## Scenario 37: TimeoutError maps to tekTimeout.
  let e = newException(TimeoutError, "Call to 'recv' timed out.")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekTimeout
  doAssert ce.transport.msg == "Call to 'recv' timed out."

block classifyExceptionOsErrorSsl:
  ## Scenario 38: OSError with "ssl" in message maps to tekTls.
  let e = newException(OSError, "ssl handshake failed")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekTls

block classifyExceptionOsErrorTls:
  ## Scenario 39: OSError with "TLS" (case-insensitive) maps to tekTls.
  let e = newException(OSError, "TLS protocol error")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekTls

block classifyExceptionOsErrorCertificate:
  ## Scenario 40: OSError with "certificate" maps to tekTls.
  let e = newException(OSError, "certificate verification failed")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekTls

block classifyExceptionOsErrorNetwork:
  ## Scenario 41: OSError without TLS keywords maps to tekNetwork.
  let e = newException(OSError, "connection refused")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekNetwork

block classifyExceptionIoError:
  ## Scenario 42: IOError maps to tekNetwork.
  let e = newException(IOError, "connection reset by peer")
  let ce = classifyException(e)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekNetwork

block classifyExceptionValueError:
  ## Scenario 43: ValueError maps to tekNetwork with "protocol error:" prefix.
  let e = newException(ValueError, "unparseable URL")
  let ce = classifyException(e)
  doAssert ce.transport.kind == tekNetwork
  doAssert "protocol error:" in ce.transport.msg

block classifyExceptionCatchAll:
  ## Scenario 44: other CatchableError maps to tekNetwork with "unexpected error:" prefix.
  let ce = classifyException((ref CatchableError)(msg: "something unknown"))
  doAssert ce.transport.kind == tekNetwork
  doAssert "unexpected error:" in ce.transport.msg

when defined(ssl):
  block classifyExceptionSslError:
    ## SslError (from std/net, inherits CatchableError directly) maps to tekTls.
    let e = newException(SslError, "error:1416F086:SSL routines")
    let ce = classifyException(e)
    doAssert ce.kind == cekTransport
    doAssert ce.transport.kind == tekTls
    doAssert ce.transport.msg == "error:1416F086:SSL routines"

# --- enforceBodySizeLimit (scenarios 45–47) ---

block enforceBodySizeLimitWithin:
  ## Scenario 45: body within limit — no error.
  enforceBodySizeLimit(100, "short body", "test")

block enforceBodySizeLimitExceeds:
  ## Scenario 46: body exceeds limit — ClientError raised.
  var caught = false
  try:
    enforceBodySizeLimit(10, "this body exceeds ten bytes", "test")
  except ClientError as e:
    caught = true
    doAssert e.kind == cekTransport
    doAssert e.transport.kind == tekNetwork
    doAssert "exceeds limit" in e.transport.msg
  doAssert caught, "expected ClientError"

block enforceBodySizeLimitAtLimit:
  ## Boundary: body length exactly at limit — no error (uses strict >).
  enforceBodySizeLimit(10, "0123456789", "test")

block enforceBodySizeLimitDisabled:
  ## Scenario 47: limit = 0 (disabled) — no error even for large body.
  enforceBodySizeLimit(0, "any size body is fine", "test")
