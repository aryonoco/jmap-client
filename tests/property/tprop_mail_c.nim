# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Mail Part C header and body sub-types.
## Covers round-trip identity, totality (never crashes on arbitrary input),
## idempotence, and invariant properties for HeaderForm, EmailHeader,
## HeaderPropertyKey, HeaderValue, PartId, EmailBodyPart, and EmailBodyValue.

import std/json
import std/random
import std/strutils

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/mail/headers
import jmap_client/mail/body
import jmap_client/mail/serde_headers
import jmap_client/mail/serde_body

import ../mproperty

# =============================================================================
# Helpers — custom equality for case objects (doAssert uses $ which triggers
# parallel fields iterator error on case objects)
# =============================================================================

proc bodyPartMetaEq(a, b: EmailBodyPart): bool =
  ## Compares discriminant and content-type fields of EmailBodyPart.
  a.contentType == b.contentType and a.isMultipart == b.isMultipart and
    a.headers == b.headers and a.name == b.name and a.size == b.size

proc bodyPartOptEq(a, b: EmailBodyPart): bool =
  ## Compares optional fields of EmailBodyPart.
  a.charset == b.charset and a.disposition == b.disposition and a.cid == b.cid and
    a.language == b.language and a.location == b.location

proc bodyPartEq(a, b: EmailBodyPart): bool =
  ## Recursive structural equality for EmailBodyPart.
  if not bodyPartMetaEq(a, b) or not bodyPartOptEq(a, b):
    return false
  if a.isMultipart:
    if a.subParts.len != b.subParts.len:
      return false
    for i in 0 ..< a.subParts.len:
      if not bodyPartEq(a.subParts[i], b.subParts[i]):
        return false
    return true
  a.partId == b.partId and a.blobId == b.blobId

# =============================================================================
# A. Round-trip identity properties (DefaultTrials = 500)
# =============================================================================

block propRoundTripEmailHeader:
  checkProperty "EmailHeader round-trip: fromJson(toJson(h)) == h":
    let eh = rng.genEmailHeader(trial)
    lastInput = eh.name & ": " & eh.value
    let j = eh.toJson()
    let rt = EmailHeader.fromJson(j).get()
    doAssert rt.name == eh.name, "EmailHeader name mismatch"
    doAssert rt.value == eh.value, "EmailHeader value mismatch"

block propRoundTripPartId:
  checkProperty "PartId round-trip: fromJson(toJson(pid)) == pid":
    let pid = rng.genPartId(trial)
    lastInput = $pid
    let j = pid.toJson()
    let rt = PartId.fromJson(j).get()
    doAssert rt == pid, "PartId round-trip identity violated"

block propRoundTripEmailBodyValue:
  checkProperty "EmailBodyValue round-trip: fromJson(toJson(bv)) == bv":
    let bv = rng.genEmailBodyValue()
    lastInput = bv.value
    let j = bv.toJson()
    let rt = EmailBodyValue.fromJson(j).get()
    doAssert rt.value == bv.value, "EmailBodyValue value mismatch"
    doAssert rt.isEncodingProblem == bv.isEncodingProblem,
      "EmailBodyValue isEncodingProblem mismatch"
    doAssert rt.isTruncated == bv.isTruncated, "EmailBodyValue isTruncated mismatch"

block propRoundTripHeaderValue:
  checkProperty "HeaderValue round-trip: parseHeaderValue(form, toJson(v)) == v":
    let form = rng.genHeaderForm()
    let v = rng.genHeaderValue(form)
    lastInput = $form
    let j = v.toJson()
    let rt = parseHeaderValue(form, j).get()
    doAssert rt.form == v.form, "HeaderValue form mismatch"
    case form
    of hfRaw:
      doAssert rt.rawValue == v.rawValue, "HeaderValue rawValue mismatch"
    of hfText:
      doAssert rt.textValue == v.textValue, "HeaderValue textValue mismatch"
    of hfAddresses:
      doAssert rt.addresses.len == v.addresses.len, "HeaderValue addresses len mismatch"
      for i in 0 ..< v.addresses.len:
        doAssert rt.addresses[i].email == v.addresses[i].email
        doAssert rt.addresses[i].name == v.addresses[i].name
    of hfGroupedAddresses:
      doAssert rt.groups.len == v.groups.len, "HeaderValue groups len mismatch"
      for i in 0 ..< v.groups.len:
        doAssert rt.groups[i].name == v.groups[i].name
        doAssert rt.groups[i].addresses.len == v.groups[i].addresses.len
    of hfMessageIds:
      doAssert rt.messageIds == v.messageIds, "HeaderValue messageIds mismatch"
    of hfDate:
      doAssert rt.date == v.date, "HeaderValue date mismatch"
    of hfUrls:
      doAssert rt.urls == v.urls, "HeaderValue urls mismatch"

block propRoundTripEmailBodyPart:
  checkProperty "EmailBodyPart round-trip: fromJson(toJson(part)) == part":
    let part = rng.genEmailBodyPart(3)
    lastInput = part.contentType & " multipart=" & $part.isMultipart
    let j = part.toJson()
    let rt = EmailBodyPart.fromJson(j).get()
    doAssert bodyPartEq(rt, part), "EmailBodyPart round-trip identity violated"

# =============================================================================
# B. Totality — never crashes (ThoroughTrials = 2000)
# =============================================================================

block propParseHeaderPropertyNameTotality:
  checkPropertyN "parseHeaderPropertyName never crashes on arbitrary strings",
    ThoroughTrials:
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseHeaderPropertyName(s)

block propParseHeaderPropertyNameMaliciousTotality:
  checkPropertyN "parseHeaderPropertyName never crashes on malicious input",
    ThoroughTrials:
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseHeaderPropertyName(s)

block propParseHeaderPropertyNameArbitraryTotality:
  checkPropertyN "parseHeaderPropertyName never crashes on header-like strings",
    ThoroughTrials:
    let s = genArbitraryHeaderPropertyString(rng, trial)
    lastInput = s
    discard parseHeaderPropertyName(s)

block propParseHeaderValueTotality:
  checkPropertyN "parseHeaderValue never crashes on arbitrary (form, JSON) pairs",
    ThoroughTrials:
    let form = rng.genHeaderForm()
    let node = rng.genArbitraryJsonNode(2)
    lastInput = $form & " " & $node.kind
    discard parseHeaderValue(form, node)

block propEmailBodyPartFromJsonTotality:
  checkPropertyN "EmailBodyPart.fromJson never crashes on arbitrary JSON",
    ThoroughTrials:
    let j = rng.genArbitraryJsonNode(3)
    lastInput = $j.kind
    discard EmailBodyPart.fromJson(j)

block propEmailBodyPartFromJsonDeepTotality:
  checkPropertyN "EmailBodyPart.fromJson never crashes on deep arbitrary JSON",
    QuickTrials:
    let j = rng.genArbitraryJsonObject(5)
    lastInput = $j.kind
    discard EmailBodyPart.fromJson(j)

block propEmailHeaderFromJsonTotality:
  checkPropertyN "EmailHeader.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard EmailHeader.fromJson(j)

block propEmailBodyValueFromJsonTotality:
  checkPropertyN "EmailBodyValue.fromJson never crashes on arbitrary JSON",
    ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard EmailBodyValue.fromJson(j)

block propParsePartIdFromServerTotality:
  checkPropertyN "parsePartIdFromServer never crashes on arbitrary strings",
    ThoroughTrials:
    let s = genArbitraryString(rng)
    lastInput = s
    discard parsePartIdFromServer(s)

# =============================================================================
# C. Idempotence — toJson(fromJson(toJson(x))) == toJson(x)
# =============================================================================

block propIdempotenceEmailBodyPart:
  checkProperty "EmailBodyPart idempotence: toJson(fromJson(toJson(x))) == toJson(x)":
    let part = rng.genEmailBodyPart(3)
    lastInput = part.contentType
    let j1 = part.toJson()
    let rt = EmailBodyPart.fromJson(j1).get()
    let j2 = rt.toJson()
    doAssert j1 == j2, "EmailBodyPart idempotence violated"

block propIdempotenceHeaderValue:
  checkProperty "HeaderValue idempotence: toJson(parseHeaderValue(form, toJson(v))) == toJson(v)":
    let form = rng.genHeaderForm()
    let v = rng.genHeaderValue(form)
    lastInput = $form
    let j1 = v.toJson()
    let rt = parseHeaderValue(form, j1).get()
    let j2 = rt.toJson()
    doAssert j1 == j2, "HeaderValue idempotence violated"

block propIdempotenceEmailHeader:
  checkProperty "EmailHeader idempotence: toJson(fromJson(toJson(h))) == toJson(h)":
    let eh = rng.genEmailHeader(trial)
    lastInput = eh.name
    let j1 = eh.toJson()
    let rt = EmailHeader.fromJson(j1).get()
    let j2 = rt.toJson()
    doAssert j1 == j2, "EmailHeader idempotence violated"

# =============================================================================
# D. Invariant properties
# =============================================================================

block propHeaderPropertyKeyNormalisesName:
  checkProperty "HeaderPropertyKey always normalises name to lowercase":
    let key = rng.genHeaderPropertyKey(trial)
    lastInput = $key
    doAssert key.name == key.name.toLowerAscii(),
      "HeaderPropertyKey name not lowercase: " & key.name

block propHeaderPropertyKeyRoundTripToPropertyString:
  checkProperty "HeaderPropertyKey round-trips through toPropertyString/parse":
    let key = rng.genHeaderPropertyKey(trial)
    let wire = key.toPropertyString()
    lastInput = wire
    let rt = parseHeaderPropertyName(wire).get()
    doAssert rt.name == key.name, "name mismatch: " & rt.name & " vs " & key.name
    doAssert rt.form == key.form, "form mismatch"
    doAssert rt.isAll == key.isAll, "isAll mismatch"

block propAllowedFormsAlwaysIncludesRaw:
  checkProperty "allowedForms always includes hfRaw for any header name":
    const headerPool = [
      "from", "to", "subject", "date", "message-id", "return-path", "received",
      "list-unsubscribe", "x-custom", "x-arbitrary-header",
    ]
    let name = rng.oneOf(headerPool)
    lastInput = name
    doAssert hfRaw in allowedForms(name), "hfRaw not in allowedForms for " & name

block propValidateHeaderFormRespectsAllowedForms:
  checkProperty "validateHeaderForm is consistent with allowedForms":
    let key = rng.genHeaderPropertyKey(trial)
    lastInput = $key
    let allowed = allowedForms(key.name)
    let result = validateHeaderForm(key)
    if key.form in allowed:
      doAssert result.isOk, "validateHeaderForm rejected allowed form"
    else:
      doAssert result.isErr, "validateHeaderForm accepted disallowed form"

block propEmailBodyPartCharsetDefault:
  checkProperty "EmailBodyPart text/* parts always have charset after round-trip":
    let part = rng.genEmailBodyPart(1)
    lastInput = part.contentType
    if not part.isMultipart and part.contentType.toLowerAscii().startsWith("text/"):
      let j = part.toJson()
      let rt = EmailBodyPart.fromJson(j).get()
      doAssert rt.charset.isSome,
        "text/* part lost charset after round-trip: " & part.contentType
