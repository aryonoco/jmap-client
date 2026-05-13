# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/parse`` response
## (RFC 8621 §4.9,
## ``tests/testdata/captured/email-parse-rfc822-stalwart.json``).
## Verifies that ``EmailParseResponse.fromJson`` (the typedesc-overload
## wrapper landed in commit 434020b) resolves through the mixin path
## and that the ``parsed`` Table maps blob ids to ``ParsedEmail`` records
## carrying the inner Subject / From headers.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailParseRfc822:
  let j = loadCapturedFixture("email-parse-rfc822-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/parse"

  let parseResp =
    EmailParseResponse.fromJson(inv.arguments).expect("EmailParseResponse.fromJson")
  doAssert parseResp.parsed.len == 1,
    "captured fixture parses one blob (got " & $parseResp.parsed.len & ")"
  for blobId, parsed in parseResp.parsed:
    doAssert ($blobId).len > 0, "parsed map keys must be non-empty BlobIds"
    doAssert parsed.subject.isSome,
      "parsed inner email must carry the inner Subject header"
    doAssert parsed.fromAddr.isSome,
      "parsed inner email must carry the inner From header"
    doAssert parsed.fromAddr.unsafeGet.len == 1,
      "parsed.fromAddr must contain one entry (got " & $parsed.fromAddr.unsafeGet.len &
        ")"
