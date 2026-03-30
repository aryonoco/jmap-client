# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 1 re-export hub and JmapResult outer railway alias.

import std/json
import std/tables

import results

import jmap_client/types

# --- Re-export accessibility ---

block reExportAccessibility:
  # validation
  let ve = validationError("Test", "msg", "raw")
  doAssert ve.typeName == "Test"
  doAssert 'A' in Base64UrlChars

  # primitives
  let id = parseId("abc123").get()
  doAssert $id == "abc123"

  # identifiers
  let aid = parseAccountId("A13824").get()
  doAssert $aid == "A13824"
  let mcid = parseMethodCallId("c1").get()
  doAssert $mcid == "c1"
  let cid = parseCreationId("k1").get()
  doAssert $cid == "k1"

  # capabilities
  doAssert parseCapabilityKind("urn:ietf:params:jmap:core") == ckCore
  doAssert capabilityUri(ckCore).get() == "urn:ietf:params:jmap:core"

  # errors
  let te = transportError(tekTimeout, "timed out")
  doAssert te.kind == tekTimeout
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  let re = requestError("urn:ietf:params:jmap:error:limit")
  doAssert re.errorType == retLimit
  let ce2 = clientError(re)
  doAssert ce2.kind == cekRequest
  doAssert ce2.message == "urn:ietf:params:jmap:error:limit"
  let me = methodError("serverFail")
  doAssert me.errorType == metServerFail
  let se = setError("forbidden")
  doAssert se.rawType == "forbidden"

  # framework
  let pn = parsePropertyName("name").get()
  doAssert $pn == "name"
  doAssert emptyPatch().len == 0
  let comp = parseComparator(pn).get()
  doAssert comp.isAscending

  # envelope
  let inv = Invocation(name: "Foo/get", arguments: %*{}, methodCallId: mcid)
  doAssert inv.name == "Foo/get"
  let rref = ResultReference(resultOf: mcid, name: "Foo/get", path: "/ids")
  doAssert rref.path == "/ids"
  let d = direct(42)
  doAssert d.kind == rkDirect

  # session
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert hasVariable(tmpl, "accountId")

  # std/tables consumption: Request with createdIds
  var tbl = initTable[CreationId, Id]()
  tbl[cid] = id
  let req = Request(`using`: @[], methodCalls: @[], createdIds: Opt.some(tbl))
  doAssert req.createdIds.isSome

# --- JmapResult outer railway ---

block jmapResultOkComposition:
  let mcid = parseMethodCallId("c1").get()
  let state = parseJmapState("75128aab4b1b").get()
  let resp = Response(
    methodResponses:
      @[Invocation(name: "Mailbox/get", arguments: %*{"list": []}, methodCallId: mcid)],
    sessionState: state,
  )
  let r = JmapResult[Response].ok(resp)
  doAssert r.isOk
  let unwrapped = r.get()
  doAssert unwrapped.methodResponses.len == 1
  doAssert unwrapped.methodResponses[0].name == "Mailbox/get"
  doAssert unwrapped.methodResponses[0].methodCallId == mcid
  doAssert unwrapped.sessionState == state

block jmapResultErrClientError:
  # Note: JmapResult[Response].err() cannot be used directly because Response
  # contains JmapState ({.requiresInit.}) which prevents Result.err() from
  # default-constructing the ok branch. Use a T without {.requiresInit.} fields.
  let ce = clientError(transportError(tekNetwork, "connection refused"))
  let r = JmapResult[string].err(ce)
  doAssert r.isErr

# --- ? operator propagation ---

block questionMarkPropagation:
  # Success path: ? unwraps JmapResult[Response] ok value
  func extractState(r: JmapResult[Response]): JmapResult[string] =
    ## Unwraps a Response via ? and returns the session state string.
    let resp = ?r
    ok($resp.sessionState)

  let state = parseJmapState("s1").get()
  let resp = Response(methodResponses: @[], sessionState: state)

  let okResult = extractState(JmapResult[Response].ok(resp))
  doAssert okResult.isOk
  doAssert okResult.get() == "s1"

  # Error path: ? propagates ClientError across different JmapResult[T] types
  func alwaysFails(): JmapResult[string] =
    ## Returns an error on the outer railway.
    err(clientError(transportError(tekNetwork, "fail")))

  func pipeline(): JmapResult[int] =
    ## Uses ? to propagate the error from JmapResult[string] to JmapResult[int].
    let s = ?alwaysFails()
    ok(s.len)

  let errResult = pipeline()
  doAssert errResult.isErr
