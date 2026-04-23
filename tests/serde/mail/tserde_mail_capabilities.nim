# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for MailCapabilities and SubmissionCapabilities (scenarios 45-55).

import std/json
import std/sets
import std/tables

import jmap_client/mail/mail_capabilities
import jmap_client/mail/serde_mail_capabilities
import jmap_client/mail/submission_atoms
import jmap_client/validation
import jmap_client/primitives
import jmap_client/capabilities
import jmap_client/serde

import ../../massertions

# =============================================================================
# Helper: valid JSON templates
# =============================================================================

func validMailCapJson(): JsonNode =
  ## Returns a valid MailCapabilities JSON object for test construction.
  %*{
    "maxMailboxesPerEmail": 10,
    "maxMailboxDepth": 5,
    "maxSizeMailboxName": 200,
    "maxSizeAttachmentsPerEmail": 50000000,
    "emailQuerySortOptions": ["receivedAt", "from", "to", "subject", "size"],
    "mayCreateTopLevelMailbox": true,
  }

func validSubmissionCapJson(): JsonNode =
  ## Returns a valid SubmissionCapabilities JSON object for test construction.
  %*{
    "maxDelayedSend": 300,
    "submissionExtensions": {"DELIVERBY": ["240"], "SIZE": ["50000000"]},
  }

# =============================================================================
# A. MailCapabilities — valid parsing
# =============================================================================

block parseMailCapabilitiesValid: # scenario 45
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: validMailCapJson()
  )
  let res = parseMailCapabilities(cap)
  assertOk res
  let mc = res.get()
  assertSome mc.maxMailboxesPerEmail
  assertEq int64(mc.maxMailboxesPerEmail.get()), 10'i64
  assertSome mc.maxMailboxDepth
  assertEq int64(mc.maxMailboxDepth.get()), 5'i64
  assertEq int64(mc.maxSizeMailboxName), 200'i64
  assertEq int64(mc.maxSizeAttachmentsPerEmail), 50000000'i64
  doAssert "receivedAt" in mc.emailQuerySortOptions
  doAssert "from" in mc.emailQuerySortOptions
  doAssert "to" in mc.emailQuerySortOptions
  doAssert "subject" in mc.emailQuerySortOptions
  doAssert "size" in mc.emailQuerySortOptions
  assertEq mc.emailQuerySortOptions.len, 5
  assertEq mc.mayCreateTopLevelMailbox, true

# =============================================================================
# B. MailCapabilities — wrong kind
# =============================================================================

block parseMailCapabilitiesWrongKind: # scenario 46
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission",
    kind: ckSubmission,
    rawData: validMailCapJson(),
  )
  assertErr parseMailCapabilities(cap)

# =============================================================================
# C. MailCapabilities — maxMailboxesPerEmail boundaries
# =============================================================================

block maxMailboxesPerEmailBoundaryOk: # scenario 47
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = %1
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertSome res.get().maxMailboxesPerEmail
  assertEq int64(res.get().maxMailboxesPerEmail.get()), 1'i64

block maxMailboxesPerEmailZero: # scenario 48
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = %0
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  assertErr parseMailCapabilities(cap)

block maxMailboxesPerEmailNull: # scenario 49
  var j = validMailCapJson()
  j["maxMailboxesPerEmail"] = newJNull()
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertNone res.get().maxMailboxesPerEmail

# =============================================================================
# D. MailCapabilities — maxSizeMailboxName boundaries
# =============================================================================

block maxSizeMailboxNameTooLow: # scenario 50
  var j = validMailCapJson()
  j["maxSizeMailboxName"] = %99
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  assertErr parseMailCapabilities(cap)

block maxSizeMailboxNameBoundaryOk: # scenario 51
  var j = validMailCapJson()
  j["maxSizeMailboxName"] = %100
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertEq int64(res.get().maxSizeMailboxName), 100'i64

# =============================================================================
# E. SubmissionCapabilities — valid parsing
# =============================================================================

block parseSubmissionCapabilitiesValid: # scenario 52
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission",
    kind: ckSubmission,
    rawData: validSubmissionCapJson(),
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  let sc = res.get()
  assertEq int64(sc.maxDelayedSend), 300'i64
  let extensions = OrderedTable[RFC5321Keyword, seq[string]](sc.submissionExtensions)
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  let kwSize = parseRFC5321Keyword("SIZE").unsafeGet()
  assertEq extensions.len, 2
  assertEq extensions[kwDeliverby], @["240"]
  assertEq extensions[kwSize], @["50000000"]

# =============================================================================
# F. SubmissionCapabilities — wrong kind
# =============================================================================

block parseSubmissionCapabilitiesWrongKind: # scenario 53
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: validSubmissionCapJson()
  )
  assertErr parseSubmissionCapabilities(cap)

# =============================================================================
# G. SubmissionCapabilities — maxDelayedSend zero
# =============================================================================

block maxDelayedSendZero: # scenario 54
  var j = validSubmissionCapJson()
  j["maxDelayedSend"] = %0
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  assertEq int64(res.get().maxDelayedSend), 0'i64

# =============================================================================
# H. SubmissionCapabilities — multiple extensions with empty args
# =============================================================================

block submissionExtensionsMultiple: # scenario 55
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    %*{"DELIVERBY": ["240"], "SIZE": ["50000000"], "8BITMIME": []}
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  let sc = res.get()
  let extensions = OrderedTable[RFC5321Keyword, seq[string]](sc.submissionExtensions)
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  let kwSize = parseRFC5321Keyword("SIZE").unsafeGet()
  let kw8bitmime = parseRFC5321Keyword("8BITMIME").unsafeGet()
  assertEq extensions.len, 3
  assertEq extensions[kwDeliverby], @["240"]
  assertEq extensions[kwSize], @["50000000"]
  assertEq extensions[kw8bitmime], newSeq[string]()

# =============================================================================
# I. MailCapabilities — absent field yields Opt.none
# =============================================================================

block maxMailboxesPerEmailAbsent:
  var j = validMailCapJson()
  j.delete("maxMailboxesPerEmail")
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertNone res.get().maxMailboxesPerEmail

block maxMailboxDepthNull:
  var j = validMailCapJson()
  j["maxMailboxDepth"] = newJNull()
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertNone res.get().maxMailboxDepth

# =============================================================================
# J. MailCapabilities — missing required field
# =============================================================================

block missingRequiredField:
  var j = validMailCapJson()
  j.delete("maxSizeMailboxName")
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  assertErr parseMailCapabilities(cap)

# =============================================================================
# K. Non-object rawData
# =============================================================================

block nonObjectRawData:
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJArray()
  )
  assertErr parseMailCapabilities(cap)

# =============================================================================
# L. Empty emailQuerySortOptions
# =============================================================================

block emptyEmailQuerySortOptions:
  var j = validMailCapJson()
  j["emailQuerySortOptions"] = newJArray()
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: j)
  let res = parseMailCapabilities(cap)
  assertOk res
  assertEq res.get().emailQuerySortOptions.len, 0

# =============================================================================
# M. SubmissionCapabilities — non-array extension value
# =============================================================================

block submissionExtensionsNonArray:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"DELIVERBY": "not-array"}
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  assertErr parseSubmissionCapabilities(cap)

# =============================================================================
# M2. SubmissionCapabilities — invalid RFC5321Keyword in extension key
# =============================================================================

block submissionExtensionsInvalidKeyword:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"bad!key": ["x"]}
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertSvKind res, svkFieldParserFailed
  assertSvInner res, "RFC5321Keyword"
  assertSvPath res, "/submissionExtensions/bad!key"

# =============================================================================
# M3. SubmissionCapabilities — empty RFC5321Keyword in extension key
# =============================================================================

block submissionExtensionsEmptyKeyword:
  var j = validSubmissionCapJson()
  j["submissionExtensions"] = %*{"": []}
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertSvKind res, svkFieldParserFailed
  assertSvInner res, "RFC5321Keyword"

# =============================================================================
# N. ckCore kind rejected for both parse functions
# =============================================================================

block coreKindRejected:
  let coreCap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:core",
    kind: ckCore,
    core: CoreCapabilities(
      maxSizeUpload: parseUnsignedInt(1).get(),
      maxConcurrentUpload: parseUnsignedInt(1).get(),
      maxSizeRequest: parseUnsignedInt(1).get(),
      maxConcurrentRequests: parseUnsignedInt(1).get(),
      maxCallsInRequest: parseUnsignedInt(1).get(),
      maxObjectsInGet: parseUnsignedInt(1).get(),
      maxObjectsInSet: parseUnsignedInt(1).get(),
      collationAlgorithms: initHashSet[CollationAlgorithm](),
    ),
  )
  assertErr parseMailCapabilities(coreCap)
  assertErr parseSubmissionCapabilities(coreCap)

# =============================================================================
# W. SubmissionExtensionMap — insertion order preserved through parse
# =============================================================================

block submissionExtensionMapRoundTripPreservesOrder:
  ## G25 (§1.3.2): SubmissionExtensionMap is a distinct OrderedTable;
  ## capabilities are server-advertised only (no toJson), so the
  ## round-trip observable is parse-order fidelity — iterating the
  ## parsed OrderedTable via ``pairs`` yields keys in input-JSON order.
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    parseJson("""{"SIZE": ["50000000"], "8BITMIME": [], "DELIVERBY": ["240"]}""")
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  let extensions =
    OrderedTable[RFC5321Keyword, seq[string]](res.get().submissionExtensions)
  var observed: seq[string] = @[]
  for key, _ in extensions.pairs:
    observed.add($key)
  assertEq observed, @["SIZE", "8BITMIME", "DELIVERBY"]

# =============================================================================
# X. SubmissionExtensionMap — case-differing keys collapse to one slot
# =============================================================================

block submissionExtensionMapCaseInsensitiveKey:
  ## G8a: RFC5321Keyword has case-fold ``==``/``hash`` per RFC 5321
  ## §2.4, so inserting two case-differing keys into the backing
  ## OrderedTable collapses them to a single slot. The pre-parse
  ## ``extNode.len == 2`` assertion guards against a future std/json
  ## change that silently deduplicates JObject duplicate keys — without
  ## that guard, the block would false-pass on one iteration.
  var j = validSubmissionCapJson()
  let extNode = parseJson("""{"X-FOO": ["a"], "x-foo": ["b"]}""")
  assertEq extNode.len, 2
  j["submissionExtensions"] = extNode
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  let extensions =
    OrderedTable[RFC5321Keyword, seq[string]](res.get().submissionExtensions)
  assertEq extensions.len, 1
  # OrderedTable.[]= updates value in place: last-writer-wins on value,
  # first-writer-wins on the key slot (so $key would still be "X-FOO").
  let lookupUpper = parseRFC5321Keyword("X-FOO").unsafeGet()
  let lookupLower = parseRFC5321Keyword("x-foo").unsafeGet()
  assertEq extensions[lookupUpper], @["b"]
  assertEq extensions[lookupLower], @["b"]

# =============================================================================
# Y. SubmissionExtensionMap — all three RFC value-list shapes parse
# =============================================================================

block submissionExtensionMapParsesLegacyWireShape:
  ## G25 migration pin: the wire is unchanged by the distinct-wrapper
  ## introduction. Exercises the three value-list shapes permitted by
  ## RFC 5321 §4.1.1.1 ESMTP-parameter syntax in one payload — empty
  ## list, one-element empty-string, and multi-element list — proving
  ## the new parser keeps accepting every legacy-wire form.
  var j = validSubmissionCapJson()
  j["submissionExtensions"] =
    parseJson("""{"8BITMIME": [], "SMTPUTF8": [""], "DELIVERBY": ["240", "RT"]}""")
  let cap = ServerCapability(
    rawUri: "urn:ietf:params:jmap:submission", kind: ckSubmission, rawData: j
  )
  let res = parseSubmissionCapabilities(cap)
  assertOk res
  let extensions =
    OrderedTable[RFC5321Keyword, seq[string]](res.get().submissionExtensions)
  let kw8bitmime = parseRFC5321Keyword("8BITMIME").unsafeGet()
  let kwSmtpUtf8 = parseRFC5321Keyword("SMTPUTF8").unsafeGet()
  let kwDeliverby = parseRFC5321Keyword("DELIVERBY").unsafeGet()
  assertEq extensions.len, 3
  assertEq extensions[kw8bitmime], newSeq[string]()
  assertEq extensions[kwSmtpUtf8], @[""]
  assertEq extensions[kwDeliverby], @["240", "RT"]
