# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for SearchSnippet (§12.9, scenarios 64–65) plus a fixture
## round-trip. EmailParseResponse (§4.9) and SearchSnippetGetResponse
## (§5.1) response-type serde is exercised in
## ``tmail_methods_whitebox.nim`` — those parsers are module-private to
## ``mail_methods.nim`` and reached by whitebox ``include``.

{.push raises: [].}

import std/json

import jmap_client/internal/mail/snippet
import jmap_client/internal/mail/serde_snippet
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# ============= A. searchSnippetFromJson =============

testCase fromJsonValid: # scenario 64
  let j = %*{"emailId": "e1", "subject": "Re: hi", "preview": "body fragment"}
  let res = searchSnippetFromJson(j)
  assertOk res
  let ss = res.get()
  assertEq ss.emailId, parseIdFromServer("e1").get()
  assertSomeEq ss.subject, "Re: hi"
  assertSomeEq ss.preview, "body fragment"

testCase fromJsonNullSubjectPreview: # scenario 65
  let j = %*{"emailId": "e1", "subject": nil, "preview": nil}
  let res = searchSnippetFromJson(j)
  assertOk res
  let ss = res.get()
  assertEq ss.emailId, parseIdFromServer("e1").get()
  assertNone ss.subject
  assertNone ss.preview

# ============= B. Fixture round-trip =============

testCase fixtureRoundTrip:
  let original = makeSearchSnippet()
  let j = makeSearchSnippetJson()
  let res = searchSnippetFromJson(j)
  assertOk res
  let rt = res.get()
  assertEq rt.emailId, original.emailId
  doAssert rt.subject == original.subject, "subject mismatch"
  doAssert rt.preview == original.preview, "preview mismatch"

testCase toJsonFields:
  let ss = makeSearchSnippet(
    subject = Opt.some("test subj"), preview = Opt.some("preview text")
  )
  let node = ss.toJson()
  assertJsonFieldEq node, "emailId", %"email1"
  assertJsonFieldEq node, "subject", %"test subj"
  assertJsonFieldEq node, "preview", %"preview text"

testCase toJsonNullFields:
  let ss = makeSearchSnippet()
  let node = ss.toJson()
  assertJsonFieldEq node, "emailId", %"email1"
  assertJsonFieldEq node, "subject", newJNull()
  assertJsonFieldEq node, "preview", newJNull()
