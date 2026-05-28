# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for MailAccountCapabilities and SubmissionAccountCapabilities
## (RFC 8621 §1.3.1 and §1.3.2). The fromJson overloads delegate to the L1
## smart constructors via ``wrapInner``; the L1 constructors enforce
## minValue invariants (maxMailboxesPerEmail ≥ 1, maxSizeMailboxName ≥ 100).

import std/json
import std/sets
import std/tables

import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/primitives
import jmap_client/internal/types/submission_atoms
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# =============================================================================
# Helper: valid JSON templates
# =============================================================================

func validMailCapJson(): JsonNode =
  ## Returns a valid MailAccountCapabilities JSON object for test construction.
  %*{
    "maxMailboxesPerEmail": 10,
    "maxMailboxDepth": 5,
    "maxSizeMailboxName": 200,
    "maxSizeAttachmentsPerEmail": 50000000,
    "emailQuerySortOptions": ["receivedAt", "from", "to", "subject", "size"],
    "mayCreateTopLevelMailbox": true,
  }

func validSubmissionCapJson(): JsonNode =
  ## Returns a valid SubmissionAccountCapabilities JSON object.
  %*{
    "maxDelayedSend": 300,
    "submissionExtensions": {"DELIVERBY": ["240"], "SIZE": ["50000000"]},
  }

# =============================================================================
# A. MailAccountCapabilities — valid parsing
# =============================================================================

testCase parseMailAccountCapabilitiesValid:
  let res = MailAccountCapabilities.fromJson(validMailCapJson())
  assertOk res
  let mc = res.get()
  assertSome mc.maxMailboxesPerEmail()
  assertEq mc.maxMailboxesPerEmail().get().toInt64, 10'i64
  assertSome mc.maxMailboxDepth()
  assertEq mc.maxMailboxDepth().get().toInt64, 5'i64
  assertSome mc.maxSizeMailboxName()
  assertEq mc.maxSizeMailboxName().get().toInt64, 200'i64
  assertEq mc.maxSizeAttachmentsPerEmail().toInt64, 50000000'i64
  doAssert "receivedAt" in mc.emailQuerySortOptions()
  doAssert "from" in mc.emailQuerySortOptions()
  assertEq mc.emailQuerySortOptions().len, 5
  assertEq mc.mayCreateTopLevelMailbox(), true

# =============================================================================
# B. MailAccountCapabilities — maxMailboxesPerEmail invariant
# =============================================================================

testCase maxMailboxesPerEmailBoundaryOk:
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = %1
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertSome res.get().maxMailboxesPerEmail()
  assertEq res.get().maxMailboxesPerEmail().get().toInt64, 1'i64

testCase maxMailboxesPerEmailZero:
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = %0
  assertErr MailAccountCapabilities.fromJson(j)

testCase maxMailboxesPerEmailNull:
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = newJNull()
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertNone res.get().maxMailboxesPerEmail()

testCase maxMailboxesPerEmailAbsent:
  var j = validMailCapJson()
  j.delete("maxMailboxesPerEmail")
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertNone res.get().maxMailboxesPerEmail()

# =============================================================================
# C. MailAccountCapabilities — maxSizeMailboxName invariant
# =============================================================================

testCase maxSizeMailboxNameTooLow:
  var j = validMailCapJson()
  j["maxSizeMailboxName"] = %99
  assertErr MailAccountCapabilities.fromJson(j)

testCase maxSizeMailboxNameBoundaryOk:
  var j = validMailCapJson()
  j["maxSizeMailboxName"] = %100
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertSome res.get().maxSizeMailboxName()
  assertEq res.get().maxSizeMailboxName().get().toInt64, 100'i64

testCase missingMaxSizeMailboxNameIsOptional:
  ## RFC 8621 §1.3.1 lists ``maxSizeMailboxName`` as informational, not
  ## MUST. Cyrus 3.12.2 omits it (`imap/jmap_mail.c:340-347`); the
  ## Postel-receive parser surfaces absence as ``Opt.none``.
  var j = validMailCapJson()
  j.delete("maxSizeMailboxName")
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertNone res.get().maxSizeMailboxName()

testCase maxMailboxDepthNull:
  var j = validMailCapJson()
  j["maxMailboxDepth"] = newJNull()
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertNone res.get().maxMailboxDepth()

# =============================================================================
# D. MailAccountCapabilities — emailQuerySortOptions
# =============================================================================

testCase missingEmailQuerySortOptionsDefaultsEmpty:
  ## Cyrus 3.12.2 emits ``emailsListSortOptions`` rather than the RFC-
  ## canonical ``emailQuerySortOptions``. The parser accepts absence of
  ## the canonical name as an empty set, never dispatching by alternative-
  ## name (which would be a compatibility shim).
  var j = validMailCapJson()
  j.delete("emailQuerySortOptions")
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertEq res.get().emailQuerySortOptions().len, 0

testCase emptyEmailQuerySortOptions:
  var j = validMailCapJson()
  j["emailQuerySortOptions"] = newJArray()
  let res = MailAccountCapabilities.fromJson(j)
  assertOk res
  assertEq res.get().emailQuerySortOptions().len, 0

# =============================================================================
# E. MailAccountCapabilities — non-object input rejected
# =============================================================================

testCase nonObjectInputRejected:
  assertErr MailAccountCapabilities.fromJson(newJArray())

# =============================================================================
# F. SubmissionAccountCapabilities — valid parsing
# =============================================================================

testCase parseSubmissionAccountCapabilitiesValid:
  let res = SubmissionAccountCapabilities.fromJson(validSubmissionCapJson())
  assertOk res
  let sc = res.get()
  assertEq sc.maxDelayedSend().toInt64, 300'i64
  let extensions = sc.submissionExtensions().toOrderedTable()
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  let kwSize = parseRFC5321Keyword("SIZE").unsafeGet()
  assertEq extensions.len, 2
  assertEq extensions[kwDeliverby], @["240"]
  assertEq extensions[kwSize], @["50000000"]

testCase maxDelayedSendZero:
  var j = validSubmissionCapJson()
  j["maxDelayedSend"] = %0
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertOk res
  assertEq res.get().maxDelayedSend().toInt64, 0'i64

testCase submissionExtensionsMultiple:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    %*{"DELIVERBY": ["240"], "SIZE": ["50000000"], "8BITMIME": []}
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertOk res
  let extensions = res.get().submissionExtensions().toOrderedTable()
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  let kwSize = parseRFC5321Keyword("SIZE").unsafeGet()
  let kw8bitmime = parseRFC5321Keyword("8BITMIME").unsafeGet()
  assertEq extensions.len, 3
  assertEq extensions[kwDeliverby], @["240"]
  assertEq extensions[kwSize], @["50000000"]
  assertEq extensions[kw8bitmime], newSeq[string]()

# =============================================================================
# G. SubmissionAccountCapabilities — invalid extension key
# =============================================================================

testCase submissionExtensionsNonArray:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"DELIVERBY": "not-array"}
  assertErr SubmissionAccountCapabilities.fromJson(j)

testCase submissionExtensionsInvalidKeyword:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"bad!key": ["x"]}
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertSvKind res, svkFieldParserFailed
  assertSvInner res, "RFC5321Keyword"
  assertSvPath res, "/submissionExtensions/bad!key"

testCase submissionExtensionsEmptyKeyword:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"": []}
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertSvKind res, svkFieldParserFailed
  assertSvInner res, "RFC5321Keyword"

# =============================================================================
# H. SubmissionExtensionMap — wire-order fidelity
# =============================================================================

testCase submissionExtensionMapRoundTripPreservesOrder:
  ## G25 (§1.3.2): SubmissionExtensionMap is a distinct OrderedTable;
  ## iterating the parsed table via ``pairs`` yields keys in input-JSON
  ## order.
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    parseJson("""{"SIZE": ["50000000"], "8BITMIME": [], "DELIVERBY": ["240"]}""")
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertOk res
  let extensions = res.get().submissionExtensions().toOrderedTable()
  var observed: seq[string] = @[]
  for key, _ in extensions.pairs:
    observed.add($key)
  assertEq observed, @["SIZE", "8BITMIME", "DELIVERBY"]

testCase submissionExtensionMapCaseInsensitiveKey:
  ## G8a: RFC5321Keyword has case-fold ``==``/``hash`` per RFC 5321 §2.4,
  ## so two case-differing keys collapse to a single slot.
  var j = validSubmissionCapJson()
  let extNode = parseJson("""{"X-FOO": ["a"], "x-foo": ["b"]}""")
  assertEq extNode.len, 2
  j["submissionExtensions"] = extNode
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertOk res
  let extensions = res.get().submissionExtensions().toOrderedTable()
  assertEq extensions.len, 1
  let lookupUpper = parseRFC5321Keyword("X-FOO").unsafeGet()
  let lookupLower = parseRFC5321Keyword("x-foo").unsafeGet()
  assertEq extensions[lookupUpper], @["b"]
  assertEq extensions[lookupLower], @["b"]

testCase submissionExtensionMapParsesLegacyWireShape:
  ## G25 migration pin: exercises the three value-list shapes permitted
  ## by RFC 5321 §4.1.1.1 ESMTP-parameter syntax — empty, one-element
  ## empty-string, multi-element.
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    parseJson("""{"8BITMIME": [], "SMTPUTF8": [""], "DELIVERBY": ["240", "RT"]}""")
  let res = SubmissionAccountCapabilities.fromJson(j)
  assertOk res
  let extensions = res.get().submissionExtensions().toOrderedTable()
  let kw8bitmime = parseRFC5321Keyword("8BITMIME").unsafeGet()
  let kwSmtpUtf8 = parseRFC5321Keyword("SMTPUTF8").unsafeGet()
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  assertEq extensions.len, 3
  assertEq extensions[kw8bitmime], newSeq[string]()
  assertEq extensions[kwSmtpUtf8], @[""]
  assertEq extensions[kwDeliverby], @["240", "RT"]
