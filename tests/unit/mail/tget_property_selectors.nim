# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the seven typed get-property selectors (A3.6):
## ``MailboxGetProperty``, ``ThreadGetProperty``, ``IdentityGetProperty``,
## ``EmailSubmissionGetProperty``, ``VacationResponseGetProperty``,
## ``EmailGetProperty``, ``EmailBodyProperty``. Each is a sealed Pattern-A
## case object flowing client -> server only: named constants round-trip
## through ``wireName``; ``parseX`` classifies known wire names and captures
## unknown ones in the ``…Other`` escape arm; the two Email selectors carry a
## ``…Header`` arm; and ``NonEmptySeq`` iteration compiles per element type.

import jmap_client
import results

import ../../massertions
import ../../mtestblock

# ============= A. MailboxGetProperty =============

testCase mailboxGetPropertyWireNames:
  assertEq mgpId.wireName, "id"
  assertEq mgpUnreadEmails.wireName, "unreadEmails"
  assertEq mgpIsSubscribed.wireName, "isSubscribed"
  assertEq $mgpRole, "role"

testCase mailboxGetPropertyParseKnown:
  assertEq parseMailboxGetProperty("totalEmails").get(), mgpTotalEmails
  assertEq parseMailboxGetProperty("myRights").get().kind, mgkMyRights

testCase mailboxGetPropertyParseOther:
  let p = parseMailboxGetProperty("x-vendor-flag").get()
  assertEq p.kind, mgkOther
  assertEq p.wireName, "x-vendor-flag"

testCase mailboxGetPropertyParseRejectsControl:
  assertErr parseMailboxGetProperty("bad\x01name")

# ============= B. ThreadGetProperty =============

testCase threadGetPropertyWireNames:
  assertEq tgpId.wireName, "id"
  assertEq tgpEmailIds.wireName, "emailIds"

testCase threadGetPropertyParse:
  assertEq parseThreadGetProperty("emailIds").get(), tgpEmailIds
  assertEq parseThreadGetProperty("x-ext").get().kind, tgkOther

# ============= C. IdentityGetProperty =============

testCase identityGetPropertyWireNames:
  assertEq igpEmail.wireName, "email"
  assertEq igpHtmlSignature.wireName, "htmlSignature"
  assertEq igpMayDelete.wireName, "mayDelete"

testCase identityGetPropertyParse:
  assertEq parseIdentityGetProperty("replyTo").get(), igpReplyTo
  assertEq parseIdentityGetProperty("x-ext").get().wireName, "x-ext"

# ============= D. EmailSubmissionGetProperty =============

testCase emailSubmissionGetPropertyWireNames:
  assertEq esgpUndoStatus.wireName, "undoStatus"
  assertEq esgpDeliveryStatus.wireName, "deliveryStatus"
  assertEq esgpMdnBlobIds.wireName, "mdnBlobIds"

testCase emailSubmissionGetPropertyParse:
  assertEq parseEmailSubmissionGetProperty("envelope").get(), esgpEnvelope
  assertEq parseEmailSubmissionGetProperty("x-ext").get().kind, esgkOther

# ============= E. VacationResponseGetProperty =============

testCase vacationResponseGetPropertyWireNames:
  assertEq vrgpIsEnabled.wireName, "isEnabled"
  assertEq vrgpFromDate.wireName, "fromDate"
  assertEq vrgpHtmlBody.wireName, "htmlBody"

testCase vacationResponseGetPropertyParse:
  assertEq parseVacationResponseGetProperty("subject").get(), vrgpSubject
  assertEq parseVacationResponseGetProperty("x-ext").get().wireName, "x-ext"

# ============= F. EmailGetProperty =============

testCase emailGetPropertyWireNames:
  assertEq egpId.wireName, "id"
  assertEq egpFrom.wireName, "from"
  assertEq egpHeaders.wireName, "headers"
  assertEq egpHasAttachment.wireName, "hasAttachment"
  assertEq egpBodyValues.wireName, "bodyValues"

testCase emailGetPropertyParseKnown:
  assertEq parseEmailGetProperty("subject").get(), egpSubject
  assertEq parseEmailGetProperty("preview").get().kind, egkPreview

testCase emailGetPropertyParseOther:
  let p = parseEmailGetProperty("x-thread-score").get()
  assertEq p.kind, egkOther
  assertEq p.wireName, "x-thread-score"

testCase emailGetPropertyHeaderArm:
  let key = parseHeaderPropertyName("header:from:asAddresses:all").get()
  let p = emailGetHeader(key)
  assertEq p.kind, egkHeader
  assertEq p.wireName, "header:from:asAddresses:all"

testCase emailGetPropertyParseHeaderRoundTrip:
  let p = parseEmailGetProperty("header:Subject:asText").get()
  assertEq p.kind, egkHeader
  assertEq p.wireName, "header:subject:asText"

# ============= G. EmailBodyProperty =============

testCase emailBodyPropertyWireNames:
  assertEq ebpPartId.wireName, "partId"
  assertEq ebpType.wireName, "type"
  assertEq ebpSubParts.wireName, "subParts"
  assertEq ebpHeaders.wireName, "headers"

testCase emailBodyPropertyParseKnown:
  assertEq parseEmailBodyProperty("disposition").get(), ebpDisposition
  assertEq parseEmailBodyProperty("x-ext").get().kind, ebpkOther

testCase emailBodyPropertyHeaderArm:
  let key = parseHeaderPropertyName("header:content-type").get()
  let p = emailBodyHeader(key)
  assertEq p.kind, ebpkHeader
  assertEq p.wireName, "header:content-type"

# ============= H. Distinct ``headers`` vs dynamic ``header:`` arms =============

testCase emailHeadersDistinctFromHeaderArm:
  ## ``egkHeaders`` (whole header list, wire "headers") is distinct from the
  ## dynamic single-header ``egkHeader`` form.
  doAssert egpHeaders.kind == egkHeaders
  doAssert egpHeaders != parseEmailGetProperty("header:to").get()

# ============= I. NonEmptySeq selector ops compile and iterate =============

testCase selectorNonEmptySeqIterates:
  let sel = parseNonEmptySeq(@[mgpId, mgpName, mgpTotalEmails]).get()
  assertEq sel.len, 3
  var wires: seq[string] = @[]
  for p in sel:
    wires.add(p.wireName)
  assertEq wires, @["id", "name", "totalEmails"]
  doAssert mgpName in sel

testCase emailSelectorNonEmptySeqIterates:
  let sel = parseNonEmptySeq(@[egpId, egpSubject, egpFrom]).get()
  assertEq sel.len, 3
  doAssert egpSubject in sel
