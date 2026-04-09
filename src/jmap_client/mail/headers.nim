# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Header sub-types for RFC 8621 (JMAP Mail) section 4.1.2. Shared bounded
## context used by Email, EmailBodyPart, and BlueprintBodyPart.

{.push raises: [].}

import std/hashes
import std/strutils
import std/tables

import ../validation
import ../primitives
import ./addresses

# =============================================================================
# HeaderForm
# =============================================================================

type HeaderForm* = enum
  ## Parsed form suffix for header property names (RFC 8621 §4.1.2).
  hfRaw = "asRaw"
  hfText = "asText"
  hfAddresses = "asAddresses"
  hfGroupedAddresses = "asGroupedAddresses"
  hfMessageIds = "asMessageIds"
  hfDate = "asDate"
  hfUrls = "asURLs"

func parseHeaderForm*(raw: string): Result[HeaderForm, ValidationError] =
  ## Parses a header form suffix string into a HeaderForm variant.
  ## Uses nimIdentNormalize for case-insensitive matching (preserving
  ## first-char case).
  if raw.len == 0:
    return err(validationError("HeaderForm", "empty form suffix", raw))
  let normalized = nimIdentNormalize(raw)
  for form in HeaderForm:
    if nimIdentNormalize($form) == normalized:
      return ok(form)
  return err(validationError("HeaderForm", "unknown header form suffix", raw))

# =============================================================================
# EmailHeader
# =============================================================================

type EmailHeader* {.ruleOff: "objects".} = object
  ## A raw email header name-value pair (RFC 8621 §4.1.2).
  name*: string ## Non-empty (enforced by parseEmailHeader).
  value*: string ## Raw header value (may be empty).

func parseEmailHeader*(
    name: string, value: string
): Result[EmailHeader, ValidationError] =
  ## Smart constructor: validates non-empty name, constructs EmailHeader.
  if name.len == 0:
    return err(validationError("EmailHeader", "name must not be empty", name))
  let eh = EmailHeader(name: name, value: value)
  doAssert eh.name.len > 0
  return ok(eh)

# =============================================================================
# HeaderPropertyKey
# =============================================================================

# nimalyzer: HeaderPropertyKey intentionally has no public fields. Fields are
# module-private to enforce non-empty lowercase name, valid form, and
# structural invariants via parseHeaderPropertyName. Public accessor funcs
# below provide read access; UFCS makes k.field syntax work unchanged.
type HeaderPropertyKey* {.ruleOff: "objects".} = object
  ## Parsed header property name encoding ``header:Name:asForm:all``
  ## (RFC 8621 §4.1.3). Fields are module-private; external access via
  ## UFCS accessor funcs.
  rawName: string ## Module-private, lowercase, non-empty.
  rawForm: HeaderForm ## Module-private.
  rawIsAll: bool ## Module-private.

func name*(k: HeaderPropertyKey): string =
  ## Header field name (lowercase).
  return k.rawName

func form*(k: HeaderPropertyKey): HeaderForm =
  ## Parsed form suffix.
  return k.rawForm

func isAll*(k: HeaderPropertyKey): bool =
  ## Whether the ``:all`` suffix was present.
  return k.rawIsAll

func hash*(k: HeaderPropertyKey): Hash =
  ## Hash for use as Table key (e.g., BlueprintBodyPart.extraHeaders).
  var h: Hash = 0
  h = h !& hash(k.rawName)
  h = h !& hash(ord(k.rawForm))
  h = h !& hash(k.rawIsAll)
  result = !$h

func parseHeaderPropertyName*(raw: string): Result[HeaderPropertyKey, ValidationError] =
  ## Parses a full wire-format header property name including the ``header:``
  ## prefix. Validates structural correctness only — does not check whether
  ## the form is allowed for the header name (see ``validateHeaderForm``).
  ## Normalises the header name to lowercase.
  if not raw.startsWith("header:"):
    return err(validationError("HeaderPropertyKey", "missing 'header:' prefix", raw))
  let rest = raw[7 .. ^1]
  let segments = rest.split(':')
  if segments.len == 0 or segments[0].len == 0:
    return err(validationError("HeaderPropertyKey", "empty header name", raw))
  let name = segments[0].toLowerAscii()
  case segments.len
  of 1:
    let key = HeaderPropertyKey(rawName: name, rawForm: hfRaw, rawIsAll: false)
    doAssert key.rawName.len > 0
    return ok(key)
  of 2:
    if cmpIgnoreCase(segments[1], "all") == 0:
      let key = HeaderPropertyKey(rawName: name, rawForm: hfRaw, rawIsAll: true)
      doAssert key.rawName.len > 0
      return ok(key)
    let form = ?parseHeaderForm(segments[1])
    let key = HeaderPropertyKey(rawName: name, rawForm: form, rawIsAll: false)
    doAssert key.rawName.len > 0
    return ok(key)
  of 3:
    let form = ?parseHeaderForm(segments[1])
    if cmpIgnoreCase(segments[2], "all") != 0:
      return err(
        validationError(
          "HeaderPropertyKey", "expected ':all' suffix, got ':" & segments[2] & "'", raw
        )
      )
    let key = HeaderPropertyKey(rawName: name, rawForm: form, rawIsAll: true)
    doAssert key.rawName.len > 0
    return ok(key)
  else:
    return err(validationError("HeaderPropertyKey", "too many segments", raw))

func toPropertyString*(k: HeaderPropertyKey): string =
  ## Reconstructs the wire-format property string from component fields.
  ## Omits the form suffix when ``hfRaw`` (the default).
  result = "header:" & k.rawName
  if k.rawForm != hfRaw:
    result &= ":" & $k.rawForm
  if k.rawIsAll:
    result &= ":all"

func `$`*(k: HeaderPropertyKey): string =
  ## String representation delegates to ``toPropertyString``.
  return k.toPropertyString()

# =============================================================================
# HeaderValue
# =============================================================================

type HeaderValue* {.ruleOff: "objects".} = object
  ## Parsed header content discriminated by form (RFC 8621 §4.1.2).
  ## ``Opt.none`` on nullable variants means "server could not parse."
  case form*: HeaderForm
  of hfRaw: rawValue*: string
  of hfText: textValue*: string
  of hfAddresses: addresses*: seq[EmailAddress]
  of hfGroupedAddresses: groups*: seq[EmailAddressGroup]
  of hfMessageIds: messageIds*: Opt[seq[string]]
  of hfDate: date*: Opt[Date]
  of hfUrls: urls*: Opt[seq[string]]

# =============================================================================
# allowedForms
# =============================================================================

# 30 entries: 12 address, 4 text, 2 date, 4 message-id, 6 URL, 2 raw-only.
const allowedHeaderFormsTable = {
  # Address headers (RFC 5322 §3.6.2–3.6.3, §3.6.6, §4.5.6)
  "from": {hfAddresses, hfGroupedAddresses, hfRaw},
  "sender": {hfAddresses, hfGroupedAddresses, hfRaw},
  "reply-to": {hfAddresses, hfGroupedAddresses, hfRaw},
  "to": {hfAddresses, hfGroupedAddresses, hfRaw},
  "cc": {hfAddresses, hfGroupedAddresses, hfRaw},
  "bcc": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-from": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-sender": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-reply-to": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-to": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-cc": {hfAddresses, hfGroupedAddresses, hfRaw},
  "resent-bcc": {hfAddresses, hfGroupedAddresses, hfRaw},
  # Text headers (RFC 5322 §3.6.5, RFC 2919)
  "subject": {hfText, hfRaw},
  "comments": {hfText, hfRaw},
  "keywords": {hfText, hfRaw},
  "list-id": {hfText, hfRaw},
  # Date headers (RFC 5322 §3.6.1, §3.6.6)
  "date": {hfDate, hfRaw},
  "resent-date": {hfDate, hfRaw},
  # Message-id headers (RFC 5322 §3.6.4, §3.6.6)
  "message-id": {hfMessageIds, hfRaw},
  "in-reply-to": {hfMessageIds, hfRaw},
  "references": {hfMessageIds, hfRaw},
  "resent-message-id": {hfMessageIds, hfRaw},
  # URL headers (RFC 2369)
  "list-help": {hfUrls, hfRaw},
  "list-unsubscribe": {hfUrls, hfRaw},
  "list-subscribe": {hfUrls, hfRaw},
  "list-post": {hfUrls, hfRaw},
  "list-owner": {hfUrls, hfRaw},
  "list-archive": {hfUrls, hfRaw},
  # Raw-only headers (RFC 5322 §3.6.7)
  "return-path": {hfRaw},
  "received": {hfRaw},
}.toTable

func allowedForms*(name: string): set[HeaderForm] =
  ## Returns permitted forms for a header name. Precondition: ``name`` must be
  ## lowercase (typically from ``HeaderPropertyKey.name``, which normalises to
  ## lowercase). Unknown or non-lowercase names return all forms per RFC 8621.
  result = allowedHeaderFormsTable.getOrDefault(name, {hfRaw .. hfUrls})

# =============================================================================
# validateHeaderForm
# =============================================================================

func validateHeaderForm*(
    key: HeaderPropertyKey
): Result[HeaderPropertyKey, ValidationError] =
  ## Validates that the form is permitted for the header name per the
  ## allowedForms table. Separate from ``parseHeaderPropertyName`` which
  ## validates structural correctness only.
  if key.form notin allowedForms(key.name):
    return err(
      validationError(
        "HeaderPropertyKey",
        "form " & $key.form & " not allowed for header " & key.name,
        $key,
      )
    )
  return ok(key)
