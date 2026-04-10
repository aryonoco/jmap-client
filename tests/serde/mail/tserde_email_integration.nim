# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Integration serde tests for Email cross-component interactions
## (section 12.13, scenarios 132–136). Verifies shared helper parity,
## round-trip serialisation with dynamic headers, and builder–serde
## consistency.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/mail/email
import jmap_client/mail/headers
import jmap_client/mail/keyword
import jmap_client/mail/addresses
import jmap_client/mail/mail_filters
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_builders
import jmap_client/mail/mail_methods
import jmap_client/mail/serde_email
import jmap_client/mail/serde_mail_filters
import jmap_client/builder
import jmap_client/framework
import jmap_client/primitives
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# =============================================================================
# A. Shared Helper Parity (scenario 132)
# =============================================================================

block sharedHelperParity: # scenario 132
  ## Identical JSON fed to emailFromJson and parsedEmailFromJson — shared
  ## field groups (convenience headers, body, dynamic headers) must produce
  ## identical results.
  var j = makeEmailJson()
  # Populate convenience headers so they are non-trivial
  j["from"] = %*[{"name": "Alice", "email": "alice@test.com"}]
  j["subject"] = %"Integration test subject"
  j["messageId"] = %*["msg1@test.com"]
  # Dynamic headers: one non-:all and one :all
  j["header:X-Custom:asText"] = %"custom-value"
  j["header:X-List:asText:all"] = %*["list-val-1", "list-val-2"]

  let emailRes = emailFromJson(j)
  let parsedRes = parsedEmailFromJson(j)
  assertOk emailRes
  assertOk parsedRes
  let e = emailRes.get()
  let pe = parsedRes.get()

  # Convenience string headers (5 fields)
  doAssert e.messageId == pe.messageId, "messageId mismatch"
  doAssert e.inReplyTo == pe.inReplyTo, "inReplyTo mismatch"
  doAssert e.references == pe.references, "references mismatch"
  doAssert e.subject == pe.subject, "subject mismatch"
  doAssert e.sentAt == pe.sentAt, "sentAt mismatch"

  # Convenience address headers (6 fields)
  doAssert e.sender == pe.sender, "sender mismatch"
  doAssert e.fromAddr == pe.fromAddr, "fromAddr mismatch"
  doAssert e.to == pe.to, "to mismatch"
  doAssert e.cc == pe.cc, "cc mismatch"
  doAssert e.bcc == pe.bcc, "bcc mismatch"
  doAssert e.replyTo == pe.replyTo, "replyTo mismatch"

  # Raw headers
  doAssert e.headers == pe.headers, "raw headers mismatch"

  # Dynamic headers
  doAssert headerTableEq(e.requestedHeaders, pe.requestedHeaders),
    "requestedHeaders mismatch"
  doAssert headerTableAllEq(e.requestedHeadersAll, pe.requestedHeadersAll),
    "requestedHeadersAll mismatch"

  # Body fields
  doAssert bodyPartEq(e.bodyStructure, pe.bodyStructure), "bodyStructure mismatch"
  doAssert e.bodyValues == pe.bodyValues, "bodyValues mismatch"
  doAssert bodyPartSeqEq(e.textBody, pe.textBody), "textBody mismatch"
  doAssert bodyPartSeqEq(e.htmlBody, pe.htmlBody), "htmlBody mismatch"
  doAssert bodyPartSeqEq(e.attachments, pe.attachments), "attachments mismatch"
  doAssert e.hasAttachment == pe.hasAttachment, "hasAttachment mismatch"
  doAssert e.preview == pe.preview, "preview mismatch"

# =============================================================================
# B. Email Round-Trip with Dynamic Headers (scenario 133)
# =============================================================================

block emailRoundTripWithDynamicHeaders: # scenario 133
  ## emailFromJson(email.toJson()) == email for a fully-populated Email
  ## including entries in both requestedHeaders and requestedHeadersAll.
  var e = makeEmail()

  # makeEmail's bodyStructure has charset=Opt.none for text/plain; parsing
  # applies RFC 2046 default "us-ascii" (Decision C20). Set explicitly so
  # the round-trip is stable.
  e.bodyStructure.charset = Opt.some("us-ascii")

  # Set convenience headers to non-trivial values
  e.fromAddr =
    Opt.some(@[EmailAddress(name: Opt.some("Alice"), email: "alice@test.com")])
  e.subject = Opt.some("Round-trip subject")
  e.messageId = Opt.some(@["msg-rt@test.com"])

  # Populate requestedHeaders with two entries
  let hpkText = parseHeaderPropertyName("header:X-Custom:asText").get()
  e.requestedHeaders[hpkText] =
    HeaderValue(form: hfText, textValue: "custom text value")
  let hpkAddr = parseHeaderPropertyName("header:X-Sender:asAddresses").get()
  e.requestedHeaders[hpkAddr] = HeaderValue(
    form: hfAddresses,
    addresses: @[EmailAddress(name: Opt.none(string), email: "bob@test.com")],
  )

  # Populate requestedHeadersAll with one entry
  let hpkAll = parseHeaderPropertyName("header:X-Trace:asText:all").get()
  e.requestedHeadersAll[hpkAll] = @[
    HeaderValue(form: hfText, textValue: "trace-1"),
    HeaderValue(form: hfText, textValue: "trace-2"),
  ]

  # Round-trip
  let roundTripped = emailFromJson(e.toJson())
  assertOk roundTripped
  doAssert emailEq(roundTripped.get(), e), "Email round-trip mismatch"

# =============================================================================
# C. Dynamic Header Phase 2 Round-Trip (scenario 134)
# =============================================================================

block dynamicHeaderPhase2RoundTrip: # scenario 134
  ## JSON with both :all and non-:all header:* keys -> emailFromJson ->
  ## Email.toJson -> keys preserved with correct (lowercase) names and values.
  var j = makeEmailJson()
  j["header:Subject:asText"] = %"My Subject"
  j["header:X-Trace:asText:all"] = %*["trace-a", "trace-b"]

  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.requestedHeaders.len, 1
  assertEq e.requestedHeadersAll.len, 1

  # Re-serialise and verify keys are lowercase-normalised
  let serialised = e.toJson()

  # parseHeaderPropertyName normalises to lowercase: "Subject" -> "subject"
  const textKey = "header:subject:asText"
  doAssert serialised{textKey} != nil, "expected key " & textKey & " in output JSON"
  assertEq serialised{textKey}.getStr(""), "My Subject"

  const allKey = "header:x-trace:asText:all"
  doAssert serialised{allKey} != nil, "expected key " & allKey & " in output JSON"
  doAssert serialised{allKey}.kind == JArray, "expected JArray for :all key"
  assertLen serialised{allKey}.getElems(@[]), 2
  assertEq serialised{allKey}.getElems(@[])[0].getStr(""), "trace-a"
  assertEq serialised{allKey}.getElems(@[])[1].getStr(""), "trace-b"

# =============================================================================
# D. Builder Body Fetch Options Parity (scenario 135)
# =============================================================================

block builderBodyFetchOptionsParity: # scenario 135
  ## addEmailGet and addEmailParse with identical non-default
  ## EmailBodyFetchOptions produce identical body-related keys in request args.
  let opts = EmailBodyFetchOptions(
    fetchBodyValues: bvsTextAndHtml,
    maxBodyValueBytes: Opt.some(parseUnsignedInt(1024).get()),
  )

  # Build Email/get request
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"), bodyFetchOptions = opts)
  let getReq = b1.build()
  let getArgs = getReq.methodCalls[0].arguments

  # Build Email/parse request
  let b2 = initRequestBuilder()
  let (b3, _) =
    b2.addEmailParse(makeAccountId("a1"), @[makeId("blob1")], bodyFetchOptions = opts)
  let parseReq = b3.build()
  let parseArgs = parseReq.methodCalls[0].arguments

  # bvsTextAndHtml -> both fetchTextBodyValues and fetchHTMLBodyValues true
  doAssert getArgs{"fetchTextBodyValues"}.getBool(false),
    "Email/get: fetchTextBodyValues must be true"
  doAssert getArgs{"fetchHTMLBodyValues"}.getBool(false),
    "Email/get: fetchHTMLBodyValues must be true"
  doAssert getArgs{"fetchAllBodyValues"}.isNil,
    "Email/get: fetchAllBodyValues must be absent"
  assertJsonFieldEq getArgs, "maxBodyValueBytes", %1024

  # Same keys in Email/parse
  doAssert parseArgs{"fetchTextBodyValues"}.getBool(false),
    "Email/parse: fetchTextBodyValues must be true"
  doAssert parseArgs{"fetchHTMLBodyValues"}.getBool(false),
    "Email/parse: fetchHTMLBodyValues must be true"
  doAssert parseArgs{"fetchAllBodyValues"}.isNil,
    "Email/parse: fetchAllBodyValues must be absent"
  assertJsonFieldEq parseArgs, "maxBodyValueBytes", %1024

# =============================================================================
# E. Builder–Filter Chain (scenario 136)
# =============================================================================

block builderFilterChain: # scenario 136
  ## addEmailQuery with non-trivial EmailFilterCondition -> serialised filter
  ## in request args matches EmailFilterCondition.toJson output.
  var fc = makeEmailFilterCondition()
  fc.inMailbox = Opt.some(makeId("inbox1"))
  fc.hasKeyword = Opt.some(kwSeen)
  fc.subject = Opt.some("important")

  let leafFilter = filterCondition(fc)

  # Build request via addEmailQuery
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(
    makeAccountId("a1"), filterConditionToJson, filter = Opt.some(leafFilter)
  )
  let req = b1.build()
  let argsFilter = req.methodCalls[0].arguments{"filter"}
  doAssert argsFilter != nil, "filter must be present in request args"
  doAssert argsFilter.kind == JObject, "filter must be JObject"

  # Direct serialisation of the condition (fkCondition leaf delegates to
  # filterConditionToJson(f.condition) which is fc.toJson())
  let directFilter = fc.toJson()

  # Structural equality: builder path == direct serialisation path
  doAssert argsFilter == directFilter, "builder filter must match direct serialisation"

  # Verify specific field values in serialised filter
  assertEq argsFilter{"inMailbox"}.getStr(""), "inbox1"
  assertEq argsFilter{"hasKeyword"}.getStr(""), "$seen"
  assertEq argsFilter{"subject"}.getStr(""), "important"
