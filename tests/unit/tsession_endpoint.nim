# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``SessionEndpoint`` — the sealed JMAP session-locator ADT
## (direct URL or ``.well-known/jmap`` discovery domain; RFC 8620 §2). Covers
## construction validation (relocated from the old ``tclient.nim`` rejection
## cases), the public ``kind`` discriminator, arm-dispatched ``==``, and ``$``.
## All symbols are public — ``import jmap_client`` only, no internal leaf.

import jmap_client

import ../mtestblock

# --- direct URL construction ---

testCase directHttpsValid:
  let e = directEndpoint("https://example.com/jmap").get()
  doAssert e.kind == sekDirectUrl

testCase directHttpValid:
  let e = directEndpoint("http://localhost:8080/jmap").get()
  doAssert e.kind == sekDirectUrl

testCase directSchemeOnlyAccepted:
  ## Design §1.2 validates the scheme prefix only; the server rejects a
  ## bare-scheme URL at runtime.
  doAssert directEndpoint("https://").get().kind == sekDirectUrl

testCase directRejectsEmpty:
  let r = directEndpoint("")
  doAssert r.isErr
  doAssert r.error.typeName == "SessionEndpoint"
  doAssert r.error.reason == "url must not be empty"
  doAssert r.error.value == ""

testCase directRejectsNoScheme:
  let r = directEndpoint("example.com/jmap")
  doAssert r.isErr
  doAssert r.error.reason == "url must start with https:// or http://"
  doAssert r.error.value == "example.com/jmap"

testCase directRejectsNewline:
  let r = directEndpoint("https://example.com/jmap\r\nEvil: header")
  doAssert r.isErr
  doAssert r.error.reason == "url must not contain newline characters"
  doAssert r.error.value == "https://example.com/jmap\r\nEvil: header"

# --- discovery domain construction ---

testCase discoveryValid:
  let e = discoveryEndpoint("jmap.example.com").get()
  doAssert e.kind == sekDiscoveryDomain

testCase discoveryWithPortValid:
  ## RFC 8620 §2.2: the URL template includes an optional ``[:${port}]``.
  doAssert discoveryEndpoint("example.com:8080").get().kind == sekDiscoveryDomain

testCase discoveryRejectsEmpty:
  let r = discoveryEndpoint("")
  doAssert r.isErr
  doAssert r.error.typeName == "SessionEndpoint"
  doAssert r.error.reason == "domain must not be empty"
  doAssert r.error.value == ""

testCase discoveryRejectsWhitespace:
  let r = discoveryEndpoint("ex ample")
  doAssert r.isErr
  doAssert r.error.reason == "domain must not contain whitespace"
  doAssert r.error.value == "ex ample"

testCase discoveryRejectsSlash:
  let r = discoveryEndpoint("ex/ample")
  doAssert r.isErr
  doAssert r.error.reason == "domain must not contain '/'"
  doAssert r.error.value == "ex/ample"

# --- equality and rendering ---

testCase equalDirectEndpoints:
  doAssert directEndpoint("https://a").get() == directEndpoint("https://a").get()

testCase directNeverEqualsDiscovery:
  doAssert directEndpoint("https://a").get() != discoveryEndpoint("a").get()

testCase differingDirectUnequal:
  doAssert directEndpoint("https://a").get() != directEndpoint("https://b").get()

testCase dollarRendering:
  doAssert $directEndpoint("https://example.com/jmap").get() ==
    "SessionEndpoint(url: https://example.com/jmap)"
  doAssert $discoveryEndpoint("jmap.example.com").get() ==
    "SessionEndpoint(domain: jmap.example.com)"
