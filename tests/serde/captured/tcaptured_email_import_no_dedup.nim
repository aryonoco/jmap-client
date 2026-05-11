# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/import`` second-
## of-two response when Stalwart's ``MAY``-permits dedup path is
## taken (RFC 8621 §4.8 lines 3031-3038,
## ``tests/testdata/captured/email-import-no-dedup-stalwart.json``).
## The captured wire records the second invocation issued with a
## dedup-tuple-identical creation; under Stalwart 0.15.5 this
## succeeds with a fresh server-assigned id rather than erroring
## with ``setAlreadyExists``.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailImportNoDedup:
  let j = loadCapturedFixture("email-import-no-dedup-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/import", "expected Email/import, got " & inv.rawName
  let importResp =
    EmailImportResponse.fromJson(inv.arguments).expect("EmailImportResponse.fromJson")
  let cid = parseCreationId("import28b").expect("parseCreationId import28b")
  var sawOk = false
  importResp.createResults.withValue(cid, outcome):
    doAssert outcome.isOk,
      "RFC 8621 §4.8 MAY-permits path: second import succeeds with fresh id " &
        "(got rawType=" & outcome.error.rawType & ")"
    doAssert string(outcome.unsafeValue.id).len > 0,
      "imported email id must be non-empty"
    sawOk = true
  do:
    doAssert false, "Email/import must report an outcome for creation id import28b"
  doAssert sawOk
