# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for header sub-types (scenarios 1–7, 4a–4b, 10–29, 29a–29e,
## 53–62, 60a, 68–69, 69a).

import std/strutils

import jmap_client/internal/mail/headers
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. HeaderForm (scenarios 1–4, 4a–4b) =============

testCase parseAllHeaderForms: # scenario 1
  assertOkEq parseHeaderForm("asRaw"), hfRaw
  assertOkEq parseHeaderForm("asText"), hfText
  assertOkEq parseHeaderForm("asAddresses"), hfAddresses
  assertOkEq parseHeaderForm("asGroupedAddresses"), hfGroupedAddresses
  assertOkEq parseHeaderForm("asMessageIds"), hfMessageIds
  assertOkEq parseHeaderForm("asDate"), hfDate
  assertOkEq parseHeaderForm("asURLs"), hfUrls

testCase nimIdentNormalizeVerification: # scenario 2
  # "asURLs" normalises via nimIdentNormalize — confirm wrapper produces hfUrls
  assertOkEq parseHeaderForm("asURLs"), hfUrls

testCase unknownFormSuffix: # scenario 3
  assertErrFields parseHeaderForm("asUnknown"),
    "HeaderForm", "unknown header form suffix", "asUnknown"

testCase headerFormDollar: # scenario 4
  assertEq $hfRaw, "asRaw"
  assertEq $hfText, "asText"
  assertEq $hfAddresses, "asAddresses"
  assertEq $hfGroupedAddresses, "asGroupedAddresses"
  assertEq $hfMessageIds, "asMessageIds"
  assertEq $hfDate, "asDate"
  assertEq $hfUrls, "asURLs"

testCase headerFormEmpty: # scenario 4a
  assertErrFields parseHeaderForm(""), "HeaderForm", "empty form suffix", ""

testCase headerFormUnderscore: # scenario 4b
  # nimIdentNormalize strips underscores: "as_Addresses" → "asaddresses"
  # matches "asAddresses" → "asaddresses"
  assertOkEq parseHeaderForm("as_Addresses"), hfAddresses

# ============= B. EmailHeader (scenarios 5–7, 10–11) =============

testCase parseEmailHeaderValid: # scenario 5
  let res = parseEmailHeader("From", "joe@example.com")
  assertOk res
  let eh = res.get()
  assertEq eh.name, "From"
  assertEq eh.value, "joe@example.com"

testCase parseEmailHeaderEmptyName: # scenario 6
  assertErrFields parseEmailHeader("", "value"),
    "EmailHeader", "name must not be empty", ""

testCase parseEmailHeaderEmptyValue: # scenario 7
  let res = parseEmailHeader("X-Custom", "")
  assertOk res
  assertEq res.get().value, ""

testCase parseEmailHeaderControlChar: # scenario 10
  assertOk parseEmailHeader("From\x00", "value")
  assertOk parseEmailHeader("X\x1F", "value")

testCase parseEmailHeaderWhitespace: # scenario 11
  assertOk parseEmailHeader("   ", "value")

# ============= C. HeaderPropertyKey (scenarios 12–29, 29a–29e) =============

testCase parseWithForm: # scenario 12
  let res = parseHeaderPropertyName("header:From:asAddresses")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfAddresses
  assertEq key.isAll, false

testCase parseWithTextForm: # scenario 13
  let res = parseHeaderPropertyName("header:Subject:asText")
  assertOk res
  let key = res.get()
  assertEq key.name, "subject"
  assertEq key.form, hfText
  assertEq key.isAll, false

testCase parseWithFormAndAll: # scenario 14
  let res = parseHeaderPropertyName("header:From:asAddresses:all")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfAddresses
  assertEq key.isAll, true

testCase parseNameOnly: # scenario 15
  let res = parseHeaderPropertyName("header:From")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfRaw
  assertEq key.isAll, false

testCase parseAllWithoutForm: # scenario 16
  let res = parseHeaderPropertyName("header:From:all")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfRaw
  assertEq key.isAll, true

testCase parseMissingPrefix: # scenario 17
  assertErr parseHeaderPropertyName("From:asAddresses")

testCase parseEmptyName: # scenario 18
  assertErr parseHeaderPropertyName("header::asAddresses")

testCase parseUnknownForm: # scenario 19
  assertErr parseHeaderPropertyName("header:From:asUnknown")

testCase parseNameNormalisedLowercase: # scenario 20
  let res = parseHeaderPropertyName("header:FROM:asRaw")
  assertOk res
  assertEq res.get().name, "from"

testCase toPropertyStringWithForm: # scenario 21
  let key = parseHeaderPropertyName("header:From:asAddresses").get()
  assertEq key.toPropertyString(), "header:from:asAddresses"

testCase toPropertyStringHfRawOmitted: # scenario 22
  let key = parseHeaderPropertyName("header:From").get()
  assertEq key.toPropertyString(), "header:from"

testCase toPropertyStringWithAll: # scenario 23
  let key = parseHeaderPropertyName("header:From:asAddresses:all").get()
  assertEq key.toPropertyString(), "header:from:asAddresses:all"

testCase toPropertyStringRoundTrip: # scenario 24
  const original = "header:From:asAddresses:all"
  let key = parseHeaderPropertyName(original).get()
  let wire = key.toPropertyString()
  let key2 = parseHeaderPropertyName(wire).get()
  assertEq key, key2

testCase parseExplicitHfRaw: # scenario 25
  let res = parseHeaderPropertyName("header:From:asRaw")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfRaw
  assertEq key.isAll, false

testCase parseExplicitHfRawAll: # scenario 26
  let res = parseHeaderPropertyName("header:From:asRaw:all")
  assertOk res
  let key = res.get()
  assertEq key.name, "from"
  assertEq key.form, hfRaw
  assertEq key.isAll, true

testCase parseColonInName: # scenario 27
  # "header:X-My:Custom:asText" → segments ["X-My", "Custom", "asText"]
  # "Custom" is parsed as an unrecognised form suffix → err
  assertErr parseHeaderPropertyName("header:X-My:Custom:asText")

testCase parseFullUppercaseName: # scenario 28
  let res = parseHeaderPropertyName("header:FROM:asAddresses")
  assertOk res
  assertEq res.get().name, "from"

testCase parseFormCaseVariants: # scenario 29
  # "asaddresses" — nimIdentNormalize("asaddresses") = "asaddresses"
  # matches nimIdentNormalize("asAddresses") = "asaddresses"
  assertOkEq parseHeaderPropertyName("header:From:asaddresses").map(
    proc(k: HeaderPropertyKey): HeaderForm =
      k.form
  ), hfAddresses
  # "ASADDRESSES" — nimIdentNormalize("ASADDRESSES") = "Asaddresses"
  # does NOT match "asaddresses" (first-char case preserved)
  assertErr parseHeaderPropertyName("header:From:ASADDRESSES")

testCase parseEmptyString: # scenario 29a
  assertErr parseHeaderPropertyName("")

testCase parseTrailingColonAfterForm: # scenario 29b
  # "header:From:asAddresses:" → segments ["From", "asAddresses", ""]
  # third segment is "" which is not "all" → err
  assertErr parseHeaderPropertyName("header:From:asAddresses:")

testCase parseAllUppercase: # scenario 29c
  # ":all" suffix is case-insensitive via cmpIgnoreCase
  let res = parseHeaderPropertyName("header:From:asAddresses:ALL")
  assertOk res
  assertEq res.get().isAll, true

testCase parseUnderscoreInForm: # scenario 29d
  # nimIdentNormalize strips underscores: "as_Addresses" → "asaddresses"
  let res = parseHeaderPropertyName("header:From:as_Addresses")
  assertOk res
  assertEq res.get().form, hfAddresses

testCase headerPropertyKeyEqualityAfterNorm: # scenario 29e
  let key1 = parseHeaderPropertyName("header:FROM:asAddresses").get()
  let key2 = parseHeaderPropertyName("header:from:asAddresses").get()
  assertEq key1, key2
  assertEq hash(key1), hash(key2)

# ============= D. allowedForms + validateHeaderForm (53–62, 60a, 68–69, 69a) =============

testCase allowedFormsFrom: # scenario 53
  assertEq allowedForms("from"), {hfAddresses, hfGroupedAddresses, hfRaw}

testCase allowedFormsSubject: # scenario 54
  assertEq allowedForms("subject"), {hfText, hfRaw}

testCase allowedFormsDate: # scenario 55
  assertEq allowedForms("date"), {hfDate, hfRaw}

testCase allowedFormsMessageId: # scenario 56
  assertEq allowedForms("message-id"), {hfMessageIds, hfRaw}

testCase allowedFormsUnknown: # scenario 57
  assertEq allowedForms("x-custom-header"), {hfRaw .. hfUrls}

testCase validateHeaderFormValid: # scenario 58
  let key = parseHeaderPropertyName("header:from:asAddresses").get()
  assertOk validateHeaderForm(key)

testCase validateHeaderFormInvalid: # scenario 59
  let key = parseHeaderPropertyName("header:subject:asAddresses").get()
  assertErr validateHeaderForm(key)

testCase allowedFormsResentFrom: # scenario 60
  assertEq allowedForms("resent-from"), {hfAddresses, hfGroupedAddresses, hfRaw}

testCase tableCompleteness: # scenario 60a
  let allForms = {hfRaw .. hfUrls}
  const knownHeaders = [
    "from", "sender", "reply-to", "to", "cc", "bcc", "resent-from", "resent-sender",
    "resent-reply-to", "resent-to", "resent-cc", "resent-bcc", "subject", "comments",
    "keywords", "list-id", "date", "resent-date", "message-id", "in-reply-to",
    "references", "resent-message-id", "list-help", "list-unsubscribe",
    "list-subscribe", "list-post", "list-owner", "list-archive", "return-path",
    "received",
  ]
  assertEq knownHeaders.len, 30
  for header in knownHeaders:
    let forms = allowedForms(header)
    doAssert forms != allForms, "known header should have restricted forms: " & header
    doAssert hfRaw in forms, "hfRaw must be in forms for: " & header
    doAssert header == header.toLowerAscii, "table key must be lowercase: " & header

testCase allowedFormsListUnsubscribe: # scenario 61
  assertEq allowedForms("list-unsubscribe"), {hfUrls, hfRaw}

testCase allowedFormsReturnPath: # scenario 62
  assertEq allowedForms("return-path"), {hfRaw}

testCase validateHeaderFormUnknownHeader: # scenario 68
  let key = parseHeaderPropertyName("header:x-custom:asAddresses").get()
  assertOk validateHeaderForm(key)

testCase validateHeaderFormRawAlwaysAllowed: # scenario 69
  let key = parseHeaderPropertyName("header:from:asRaw").get()
  assertOk validateHeaderForm(key)

testCase allowedFormsNonLowercase: # scenario 69a
  # Non-lowercase input misses the table lookup → returns all forms
  assertEq allowedForms("FROM"), {hfRaw .. hfUrls}
