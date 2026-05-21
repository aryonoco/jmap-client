# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Whitebox tests for the module-private Email/parse (RFC 8621 §4.9) and
## SearchSnippet/get (§5.1) response parsers in
## ``internal/mail/mail_methods.nim``. ``emailParseResponseFromJson``,
## ``searchSnippetGetResponseFromJson`` and the two typedesc ``fromJson``
## overloads carry no ``*`` — application developers receive
## ``EmailParseResponse`` / ``SearchSnippetGetResponse`` through
## ``dr.get(handle)``, never by parsing raw JSON. Nim's ``include``
## directive brings the ``*``-stripped parsers into scope for tests; H10
## lint exempts ``tests/`` from the internal-boundary rule and ``include``
## is the textual counterpart for private symbols (the A1b precedent —
## see ``tests/protocol/tdispatch_whitebox.nim``).

include jmap_client/internal/mail/mail_methods
{.pop.}

import std/strutils

import jmap_client/internal/types/envelope
import ../captured/mloader
import ../../massertions
import ../../mfixtures
import ../../mtestblock

# =============================================================================
# A. SearchSnippetGetResponse / EmailParseResponse parser unit tests
# =============================================================================

testCase searchSnippetGetResponseNotFoundNull: # scenario 66
  ## notFound: null collapses to empty seq.
  let j = %*{"accountId": "acct1", "list": [], "notFound": nil}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 0

testCase searchSnippetGetResponseNotFoundArray: # scenario 67
  ## notFound array with entries.
  let j = %*{"accountId": "acct1", "list": [], "notFound": ["id1", "id2"]}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 2

testCase searchSnippetGetResponseNotFoundAbsent: # scenario 68
  ## notFound key absent collapses to empty seq.
  let j = %*{"accountId": "acct1", "list": []}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 0

testCase snippetGetResponseListNull: # scenario 111
  ## list: null — implementation is lenient (ok with empty list), not err.
  let j = %*{"accountId": "acct1", "list": nil, "notFound": []}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().list, 0

testCase emailParseResponseParsedNull: # scenario 69
  ## parsed: null collapses to empty Table.
  let j = %*{"accountId": "acct1", "parsed": nil, "notParsable": [], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 0

testCase emailParseResponseParsedEntries: # scenario 70
  ## Fixture produces a 1-entry parsed Table.
  let j = makeEmailParseResponseJson()
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 1

testCase emailParseResponseParsedAbsent: # scenario 71
  ## parsed key absent collapses to empty Table.
  let j = %*{"accountId": "acct1", "notParsable": [], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 0

testCase emailParseResponseNotParsableRfcKey: # scenario 72
  ## RFC wire key "notParsable" populates notParseable field.
  let j = %*{"accountId": "acct1", "parsed": {}, "notParsable": ["b1"], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().notParseable, 1

testCase emailParseResponseNotParseableNimKeyIgnored: # scenario 73
  ## Nim-spelled key "notParseable" is NOT read — only RFC key is recognised.
  let j = %*{"accountId": "acct1", "parsed": {}, "notParseable": ["b1"], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().notParseable, 0

testCase responseTypesNonObject: # scenario 74
  ## Both fromJson functions reject non-JObject input.
  let arr = newJArray()
  assertErr searchSnippetGetResponseFromJson(arr)
  assertErr emailParseResponseFromJson(arr)

# =============================================================================
# B. Captured-fixture replay
# =============================================================================

testCase tcapturedEmailParseRfc822:
  ## Parser-only replay for the captured ``Email/parse`` response
  ## (``tests/testdata/captured/email-parse-rfc822-stalwart.json``).
  ## ``EmailParseResponse.fromJson`` resolves through the typedesc
  ## overload; the ``parsed`` Table maps blob ids to ``ParsedEmail``
  ## records carrying the inner Subject / From headers.
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

testCase tcapturedEmailQueryWithSnippets:
  ## Parser-only replay for the captured ``Email/query +
  ## SearchSnippet/get`` chained response (RFC 8620 §3.7 + RFC 8621
  ## §5.1). Two invocations parse independently; the snippet payload
  ## carries ``<mark>``-bracketed highlights for the matched term.
  forEachCapturedServer("email-query-with-snippets", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 2,
      "expected two chained invocations (got " & $resp.methodResponses.len & ")"

    let queryInv = resp.methodResponses[0]
    doAssert queryInv.rawName == "Email/query", "first invocation must be Email/query"
    let queryResp = QueryResponse[Email].fromJson(queryInv.arguments).expect(
        "QueryResponse[Email].fromJson"
      )
    doAssert queryResp.ids.len >= 1, "Email/query must surface the seeded matches"

    let snipInv = resp.methodResponses[1]
    doAssert snipInv.rawName == "SearchSnippet/get",
      "second invocation must be SearchSnippet/get"
    let snipResp = SearchSnippetGetResponse.fromJson(snipInv.arguments).expect(
        "SearchSnippetGetResponse.fromJson"
      )
    doAssert snipResp.list.len >= 1, "SearchSnippet/get must surface at least one entry"
    var sawMark = false
    for snippet in snipResp.list:
      let raw = snippet.subject.unsafeGet
      if "<mark>" in raw and "</mark>" in raw:
        sawMark = true
    doAssert sawMark,
      "at least one snippet must carry RFC 8621 §5.1 <mark>...</mark> highlight markup"
