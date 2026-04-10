# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for SearchSnippet (§12.9, scenarios 64–65).
## Response-type scenarios (66–74) deferred to Phase 3 Step 22.

{.push raises: [].}

import std/json

import jmap_client/mail/snippet
import jmap_client/mail/serde_snippet
import jmap_client/validation
import jmap_client/primitives

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
