# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/import`` happy
## path (RFC 8621 §4.8,
## ``tests/testdata/captured/email-import-from-blob-stalwart.json``).
## A single invocation carries an ``EmailImportResponse`` with one
## successful create under creation id ``"import27"``.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailImportFromBlob:
  let j = loadCapturedFixture("email-import-from-blob-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/import", "expected Email/import, got " & inv.rawName
  let importResp =
    EmailImportResponse.fromJson(inv.arguments).expect("EmailImportResponse.fromJson")
  let cid = parseCreationId("import27").expect("parseCreationId import27")
  var sawOk = false
  importResp.createResults.withValue(cid, outcome):
    doAssert outcome.isOk,
      "import27 must be Ok (got rawType=" & outcome.error.rawType & ")"
    doAssert string(outcome.unsafeValue.id).len > 0,
      "imported email id must be non-empty"
    sawOk = true
  do:
    doAssert false, "Email/import must report an outcome for creation id import27"
  doAssert sawOk
  doAssert importResp.newState.isSome, "newState must be present in this fixture"
