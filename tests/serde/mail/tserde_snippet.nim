# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for SearchSnippet (§12.9, scenarios 64–65) and response types
## EmailParseResponse (§4.9) and SearchSnippetGetResponse (§5.1, scenarios 66–74).

{.push raises: [].}

import std/json
import std/tables

import jmap_client/internal/mail/snippet
import jmap_client/internal/mail/serde_snippet
import jmap_client/internal/mail/mail_methods
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mfixtures

# ============= A. searchSnippetFromJson =============

block fromJsonValid: # scenario 64
  let j = %*{"emailId": "e1", "subject": "Re: hi", "preview": "body fragment"}
  let res = searchSnippetFromJson(j)
  assertOk res
  let ss = res.get()
  assertEq ss.emailId, parseIdFromServer("e1").get()
  assertSomeEq ss.subject, "Re: hi"
  assertSomeEq ss.preview, "body fragment"

block fromJsonNullSubjectPreview: # scenario 65
  let j = %*{"emailId": "e1", "subject": nil, "preview": nil}
  let res = searchSnippetFromJson(j)
  assertOk res
  let ss = res.get()
  assertEq ss.emailId, parseIdFromServer("e1").get()
  assertNone ss.subject
  assertNone ss.preview

# ============= B. Fixture round-trip =============

block fixtureRoundTrip:
  let original = makeSearchSnippet()
  let j = makeSearchSnippetJson()
  let res = searchSnippetFromJson(j)
  assertOk res
  let rt = res.get()
  assertEq rt.emailId, original.emailId
  doAssert rt.subject == original.subject, "subject mismatch"
  doAssert rt.preview == original.preview, "preview mismatch"

block toJsonFields:
  let ss = makeSearchSnippet(
    subject = Opt.some("test subj"), preview = Opt.some("preview text")
  )
  let node = ss.toJson()
  assertJsonFieldEq node, "emailId", %"email1"
  assertJsonFieldEq node, "subject", %"test subj"
  assertJsonFieldEq node, "preview", %"preview text"

block toJsonNullFields:
  let ss = makeSearchSnippet()
  let node = ss.toJson()
  assertJsonFieldEq node, "emailId", %"email1"
  assertJsonFieldEq node, "subject", newJNull()
  assertJsonFieldEq node, "preview", newJNull()

# ============= C. Response type serde =============

block searchSnippetGetResponseNotFoundNull: # scenario 66
  ## notFound: null collapses to empty seq.
  let j = %*{"accountId": "acct1", "list": [], "notFound": nil}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 0

block searchSnippetGetResponseNotFoundArray: # scenario 67
  ## notFound array with entries.
  let j = %*{"accountId": "acct1", "list": [], "notFound": ["id1", "id2"]}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 2

block searchSnippetGetResponseNotFoundAbsent: # scenario 68
  ## notFound key absent collapses to empty seq.
  let j = %*{"accountId": "acct1", "list": []}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().notFound, 0

block emailParseResponseParsedNull: # scenario 69
  ## parsed: null collapses to empty Table.
  let j = %*{"accountId": "acct1", "parsed": nil, "notParsable": [], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 0

block emailParseResponseParsedEntries: # scenario 70
  ## Fixture produces a 1-entry parsed Table.
  let j = makeEmailParseResponseJson()
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 1

block emailParseResponseParsedAbsent: # scenario 71
  ## parsed key absent collapses to empty Table.
  let j = %*{"accountId": "acct1", "notParsable": [], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().parsed, 0

block emailParseResponseNotParsableRfcKey: # scenario 72
  ## RFC wire key "notParsable" populates notParseable field.
  let j = %*{"accountId": "acct1", "parsed": {}, "notParsable": ["b1"], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().notParseable, 1

block emailParseResponseNotParseableNimKeyIgnored: # scenario 73
  ## Nim-spelled key "notParseable" is NOT read — only RFC key is recognised.
  let j = %*{"accountId": "acct1", "parsed": {}, "notParseable": ["b1"], "notFound": []}
  let res = emailParseResponseFromJson(j)
  assertOk res
  assertLen res.get().notParseable, 0

block responseTypesNonObject: # scenario 74
  ## Both fromJson functions reject non-JObject input.
  let arr = newJArray()
  assertErr searchSnippetGetResponseFromJson(arr)
  assertErr emailParseResponseFromJson(arr)
