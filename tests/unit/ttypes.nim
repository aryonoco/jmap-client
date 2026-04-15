# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 1 re-export hub.

import std/json
import std/tables

import jmap_client/types
import jmap_client/framework {.all.}

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
  let comp = parseComparator(pn)
  doAssert comp.isAscending

  # envelope
  let inv = parseInvocation("Foo/get", %*{}, mcid).get()
  doAssert inv.rawName == "Foo/get"
  let rref = initResultReference(resultOf = mcid, name = mnEmailQuery, path = rpIds)
  doAssert rref.path == rpIds
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
