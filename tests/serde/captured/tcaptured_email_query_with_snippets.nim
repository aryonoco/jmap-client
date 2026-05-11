# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query +
## SearchSnippet/get`` chained response (RFC 8620 §3.7 + RFC 8621
## §5.1, ``tests/testdata/captured/email-query-with-snippets-stalwart.json``).
## Two invocations (``c0`` ``Email/query``, ``c1``
## ``SearchSnippet/get``) parse independently; the snippet payload
## carries ``<mark>``-bracketed highlights for the matched search
## term.

{.push raises: [].}

import std/strutils

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailQueryWithSnippets:
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
