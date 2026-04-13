# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Header sub-types for RFC 8621 (JMAP Mail) section 4.1.2. Shared bounded
## context used by Email, EmailBodyPart, and BlueprintBodyPart.

{.push raises: [], noSideEffect.}

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

# =============================================================================
# Creation-Model Header Vocabulary (RFC 8621 §4.6 / Design §4.3–4.5, §5.3)
# =============================================================================
# Unidirectional client-to-server vocabulary used by ``EmailBlueprint``
# (top-level ``extraHeaders``) and ``BlueprintBodyPart`` (body-part
# ``extraHeaders``). Parallel to the query vocabulary above
# (``HeaderPropertyKey`` / ``HeaderValue``) but with two intentional
# asymmetries: (a) no ``*FromServer`` lenient sibling — the server never
# sends these back; (b) name-only Table key identity with the form living
# on the paired value (``BlueprintHeaderMultiValue``), so intra-Table
# duplicates are structurally impossible.

# =============================================================================
# BlueprintEmailHeaderName (Design §4.3)
# =============================================================================

type BlueprintEmailHeaderName* = distinct string
  ## Lowercase-normalised header name for ``EmailBlueprint.extraHeaders``.
  ## Construct via ``parseBlueprintEmailHeaderName``. Forbids names
  ## starting with ``content-`` (RFC 8621 §4.6 constraint 4 — the
  ## Content-* family is managed by JMAP itself). Identity is name-only.

defineStringDistinctOps(BlueprintEmailHeaderName)

func parseBlueprintEmailHeaderName*(
    name: string
): Result[BlueprintEmailHeaderName, ValidationError] =
  ## Strict smart constructor (client-constructed data). Rejects empty
  ## input, bytes outside 0x21..0x7E (non-printable ASCII), colon
  ## (RFC 5322 §3.6.8 ftext), and names starting with ``content-`` after
  ## lowercase normalisation. No ``*FromServer`` sibling: creation-model
  ## vocabulary is unidirectional (R1-3, §5.3 E28).
  if name.len == 0:
    return
      err(validationError("BlueprintEmailHeaderName", "name must not be empty", name))
  for ch in name:
    if ch notin {'\x21' .. '\x7E'}:
      return err(
        validationError(
          "BlueprintEmailHeaderName", "name contains non-printable byte", name
        )
      )
  if ':' in name:
    return err(
      validationError("BlueprintEmailHeaderName", "name must not contain a colon", name)
    )
  let normalised = name.toLowerAscii()
  if normalised.startsWith("content-"):
    return err(
      validationError(
        "BlueprintEmailHeaderName", "name must not start with 'content-'", name
      )
    )
  let hn = BlueprintEmailHeaderName(normalised)
  doAssert hn.len > 0
  doAssert not string(hn).startsWith("content-")
  return ok(hn)

# =============================================================================
# BlueprintBodyHeaderName (Design §4.4)
# =============================================================================

type BlueprintBodyHeaderName* = distinct string
  ## Lowercase-normalised header name for ``BlueprintBodyPart.extraHeaders``.
  ## Construct via ``parseBlueprintBodyHeaderName``. Forbids only the
  ## exact name ``content-transfer-encoding`` (RFC 8621 §4.6 constraint 9
  ## — JMAP chooses the encoding); other ``Content-*`` headers are
  ## permitted on body parts. Identity is name-only.

defineStringDistinctOps(BlueprintBodyHeaderName)

func parseBlueprintBodyHeaderName*(
    name: string
): Result[BlueprintBodyHeaderName, ValidationError] =
  ## Strict smart constructor (client-constructed data). Rejects empty
  ## input, bytes outside 0x21..0x7E (non-printable ASCII), colon
  ## (RFC 5322 §3.6.8 ftext), and the exact lowercase name
  ## ``content-transfer-encoding``. No ``*FromServer`` sibling.
  if name.len == 0:
    return
      err(validationError("BlueprintBodyHeaderName", "name must not be empty", name))
  for ch in name:
    if ch notin {'\x21' .. '\x7E'}:
      return err(
        validationError(
          "BlueprintBodyHeaderName", "name contains non-printable byte", name
        )
      )
  if ':' in name:
    return err(
      validationError("BlueprintBodyHeaderName", "name must not contain a colon", name)
    )
  let normalised = name.toLowerAscii()
  if normalised == "content-transfer-encoding":
    return err(
      validationError(
        "BlueprintBodyHeaderName", "name must not be 'content-transfer-encoding'", name
      )
    )
  let hn = BlueprintBodyHeaderName(normalised)
  doAssert hn.len > 0
  doAssert string(hn) != "content-transfer-encoding"
  return ok(hn)

# =============================================================================
# NonEmptySeq op-template instantiations (Design §4.5.1 / §4.6)
# =============================================================================
# Five instantiations cover the seven BlueprintHeaderMultiValue variants —
# ``string`` backs hfRaw+hfText, ``seq[string]`` backs hfMessageIds+hfUrls.
# Instantiated at the consumer module (mirrors mailbox.nim's treatment of
# ``defineNonEmptyHashSetDistinctOps``) to keep the creation vocabulary
# self-contained.

defineNonEmptySeqOps(string)
defineNonEmptySeqOps(Date)
defineNonEmptySeqOps(seq[EmailAddress])
defineNonEmptySeqOps(seq[EmailAddressGroup])
defineNonEmptySeqOps(seq[string])

# =============================================================================
# BlueprintHeaderMultiValue (Design §4.5.1)
# =============================================================================

type BlueprintHeaderMultiValue* {.ruleOff: "objects".} = object
  ## One or more values for a single header field, all sharing one parsed
  ## form (RFC 8621 §4.1.2). The case discriminant enforces form
  ## uniformity; ``NonEmptySeq[T]`` enforces at-least-one-value. This type
  ## has no standalone wire identity — wire-key composition
  ## (``"header:<name>:as<Form>[:all]"``) lives at the consumer aggregate
  ## (Design §4.5.3 — ``EmailBlueprint.toJson``, ``BlueprintBodyPart.toJson``).
  case form*: HeaderForm
  of hfRaw: rawValues*: NonEmptySeq[string]
  of hfText: textValues*: NonEmptySeq[string]
  of hfAddresses: addressLists*: NonEmptySeq[seq[EmailAddress]]
  of hfGroupedAddresses: groupLists*: NonEmptySeq[seq[EmailAddressGroup]]
  of hfMessageIds: messageIdLists*: NonEmptySeq[seq[string]]
  of hfDate: dateValues*: NonEmptySeq[Date]
  of hfUrls: urlLists*: NonEmptySeq[seq[string]]

# =============================================================================
# BlueprintHeaderMultiValue — *Multi constructors (Design §4.5.2)
# =============================================================================
# One helper per ``HeaderForm`` variant. Each delegates to
# ``parseNonEmptySeq`` for the non-empty invariant, then constructs the
# corresponding case variant.

func rawMulti*(
    values: seq[string]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs a ``hfRaw`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfRaw, rawValues: ne))

func textMulti*(
    values: seq[string]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs a ``hfText`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfText, textValues: ne))

func addressesMulti*(
    values: seq[seq[EmailAddress]]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs an ``hfAddresses`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfAddresses, addressLists: ne))

func groupedAddressesMulti*(
    values: seq[seq[EmailAddressGroup]]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs an ``hfGroupedAddresses`` multi-value. Errs if ``values``
  ## is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfGroupedAddresses, groupLists: ne))

func messageIdsMulti*(
    values: seq[seq[string]]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs an ``hfMessageIds`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfMessageIds, messageIdLists: ne))

func dateMulti*(values: seq[Date]): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs a ``hfDate`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfDate, dateValues: ne))

func urlsMulti*(
    values: seq[seq[string]]
): Result[BlueprintHeaderMultiValue, ValidationError] =
  ## Constructs an ``hfUrls`` multi-value. Errs if ``values`` is empty.
  let ne = ?parseNonEmptySeq(values)
  return ok(BlueprintHeaderMultiValue(form: hfUrls, urlLists: ne))

# =============================================================================
# BlueprintHeaderMultiValue — *Single constructors (Design §4.5.2)
# =============================================================================
# Zero-ceremony constructors for the common single-value case. ``@[value]``
# is statically non-empty, so we take the direct distinct-coercion path
# equivalent to ``parseNonEmptySeq``'s post-validation construction —
# avoiding ``raises:[]``-incompatible ``.tryGet`` ceremony.

func rawSingle*(value: string): BlueprintHeaderMultiValue =
  ## Constructs a ``hfRaw`` single-value.
  BlueprintHeaderMultiValue(form: hfRaw, rawValues: NonEmptySeq[string](@[value]))

func textSingle*(value: string): BlueprintHeaderMultiValue =
  ## Constructs a ``hfText`` single-value.
  BlueprintHeaderMultiValue(form: hfText, textValues: NonEmptySeq[string](@[value]))

func addressesSingle*(value: seq[EmailAddress]): BlueprintHeaderMultiValue =
  ## Constructs an ``hfAddresses`` single-value carrying one address list.
  BlueprintHeaderMultiValue(
    form: hfAddresses, addressLists: NonEmptySeq[seq[EmailAddress]](@[value])
  )

func groupedAddressesSingle*(value: seq[EmailAddressGroup]): BlueprintHeaderMultiValue =
  ## Constructs an ``hfGroupedAddresses`` single-value carrying one group list.
  BlueprintHeaderMultiValue(
    form: hfGroupedAddresses, groupLists: NonEmptySeq[seq[EmailAddressGroup]](@[value])
  )

func messageIdsSingle*(value: seq[string]): BlueprintHeaderMultiValue =
  ## Constructs an ``hfMessageIds`` single-value carrying one message-id list.
  BlueprintHeaderMultiValue(
    form: hfMessageIds, messageIdLists: NonEmptySeq[seq[string]](@[value])
  )

func dateSingle*(value: Date): BlueprintHeaderMultiValue =
  ## Constructs a ``hfDate`` single-value.
  BlueprintHeaderMultiValue(form: hfDate, dateValues: NonEmptySeq[Date](@[value]))

func urlsSingle*(value: seq[string]): BlueprintHeaderMultiValue =
  ## Constructs an ``hfUrls`` single-value carrying one URL list.
  BlueprintHeaderMultiValue(form: hfUrls, urlLists: NonEmptySeq[seq[string]](@[value]))
