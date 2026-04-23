# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JSON serialisation for EmailSubmission envelope types — RFC 5321
## address primitives, SMTP parameters, envelope composites, and
## recipient lists. Implements RFC 8621 §7.3 ``Address`` and
## ``Envelope`` wire formats.
##
## Sibling serde modules (Steps 11 and 12) build on this one:
##   - ``serde_submission_status.nim`` consumes ``RFC5321Mailbox``
##     serde for ``DeliveryStatusMap`` keys.
##   - ``serde_email_submission.nim`` consumes ``Envelope`` serde
##     for the entity read model and creation blueprint.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils
import std/tables

import ../serde
import ../types
import ./submission_envelope

# =============================================================================
# Local helpers — decimal parsing, error-rail bridging, NOTIFY join/split
# =============================================================================

func parseUnsignedDecimal(
    raw: string, typeName: string
): Result[int64, ValidationError] =
  ## Parse a decimal-digit string to ``int64`` rejecting leading sign.
  ## RFC 8621 §7.3.2 carries SIZE / HOLDFOR as JSON strings, not ints.
  if raw.len == 0 or raw[0] == '+' or raw[0] == '-':
    return err(validationError(typeName, "not a valid decimal", raw))
  try:
    return ok(parseBiggestInt(raw))
  except ValueError:
    return err(validationError(typeName, "not a valid decimal", raw))

func parseSignedDecimal(raw: string, typeName: string): Result[int64, ValidationError] =
  ## Parse a signed decimal-digit string to ``int64`` rejecting an explicit
  ## leading ``+`` (RFC 6710 ABNF disallows it for MT-PRIORITY).
  if raw.len == 0 or raw[0] == '+':
    return err(validationError(typeName, "not a valid decimal", raw))
  try:
    return ok(parseBiggestInt(raw))
  except ValueError:
    return err(validationError(typeName, "not a valid decimal", raw))

func wrapFirstInner[T](
    r: Result[T, seq[ValidationError]], path: JsonPath
): Result[T, SerdeViolation] =
  ## Bridge ``parseSubmissionParams``' accumulating error rail into the
  ## serde railway. The first violation is preserved verbatim;
  ## ``parseSubmissionParams`` only fails when ``errs.len >= 1``.
  if r.isOk:
    return ok(r.get())
  let errs = r.error
  return err(SerdeViolation(kind: svkFieldParserFailed, path: path, inner: errs[0]))

func notifyFlagsToWire(flags: set[DsnNotifyFlag]): string =
  ## Joins the NOTIFY flag set to the RFC 3461 §4.1 wire form.
  ## ``dnfNever`` short-circuits because ``notifyParam`` has already
  ## enforced its mutex with the other three; if the set somehow carries
  ## both, returning ``NEVER`` alone is the only spec-valid serialisation.
  if dnfNever in flags:
    return "NEVER"
  var parts: seq[string] = @[]
  for f in flags - {dnfNever}:
    parts.add($f)
  return parts.join(",")

func notifyFlagsFromWire(s: string): Result[set[DsnNotifyFlag], ValidationError] =
  ## Splits a NOTIFY wire string into a flag set. Case-insensitive per
  ## RFC 3461. Mutex (``NEVER`` vs others) is enforced by ``notifyParam``
  ## downstream — this helper accepts any combination structurally.
  var flags: set[DsnNotifyFlag] = {}
  for raw in s.split(','):
    let token = raw.strip()
    var matched = false
    for f in DsnNotifyFlag:
      if cmpIgnoreCase($f, token) == 0:
        flags.incl(f)
        matched = true
        break
    if not matched:
      return err(validationError("DsnNotifyFlag", "unrecognised NOTIFY token", token))
  return ok(flags)

# =============================================================================
# Distinct primitive ser/de — RFC5321Mailbox, RFC5321Keyword
# =============================================================================

defineDistinctStringToJson(RFC5321Mailbox)
defineDistinctStringFromJson(RFC5321Mailbox, parseRFC5321MailboxFromServer)

defineDistinctStringToJson(RFC5321Keyword)
defineDistinctStringFromJson(RFC5321Keyword, parseRFC5321Keyword)

# =============================================================================
# SubmissionParam value codecs — twelve variants, each ``String|null``
# =============================================================================

func paramValueToJson(p: SubmissionParam): JsonNode =
  ## Emits the wire value side of one ``SubmissionParam``. RFC 8621
  ## §7.3.2 constrains values to ``String|null``; numeric parameters ride
  ## as JSON strings of decimal digits, never JSON ints.
  case p.kind
  of spkBody:
    %($p.bodyEncoding)
  of spkSmtpUtf8:
    newJNull()
  of spkSize:
    %($int64(p.sizeOctets))
  of spkEnvid:
    %p.envid
  of spkRet:
    %($p.retType)
  of spkNotify:
    %notifyFlagsToWire(p.notifyFlags)
  of spkOrcpt:
    %($p.orcptAddrType & ";" & p.orcptOrigRecipient)
  of spkHoldFor:
    %($int64(UnsignedInt(p.holdFor)))
  of spkHoldUntil:
    %($p.holdUntil)
  of spkBy:
    %($int64(p.byDeadline) & ";" & $p.byMode)
  of spkMtPriority:
    %($int(p.mtPriority))
  of spkExtension:
    # `case .isOk of true: .unsafeValue` — strict-safe (case proves the
    # discriminator) AND panic-free (unsafeValue bypasses withAssertOk,
    # no raiseResultDefect path). Using `.get()` here would panic via
    # rawQuit(1) under --panics:on if the invariant failed — catastrophic
    # for the FFI C ABI boundary.
    case p.extValue.isOk
    of true:
      %p.extValue.unsafeValue
    of false:
      newJNull()

# --- Per-variant deserialisers ---------------------------------------------

func parseEnumByBackingString[E: enum](
    raw: string, typeLabel: string
): Result[E, ValidationError] =
  ## Resolves a wire token to an ``enum`` variant by case-insensitive
  ## match against ``$variant``. Returns a ``ValidationError`` on miss so
  ## callers can bridge it through ``wrapInner``.
  for e in E:
    if cmpIgnoreCase($e, raw) == 0:
      return ok(e)
  return err(validationError(typeLabel, "unrecognised value", raw))

func expectStringValue(
    valNode: JsonNode, path: JsonPath
): Result[string, SerdeViolation] =
  ## Asserts the wire value is a ``JString`` and unwraps it. Used by every
  ## non-null parameter variant.
  if valNode.kind != JString:
    return err(
      SerdeViolation(
        kind: svkWrongKind, path: path, expectedKind: JString, actualKind: valNode.kind
      )
    )
  return ok(valNode.getStr(""))

func expectNullValue(valNode: JsonNode, path: JsonPath): Result[void, SerdeViolation] =
  ## Asserts the wire value is ``JNull``. ``SMTPUTF8`` carries no payload.
  if valNode.kind != JNull:
    return err(
      SerdeViolation(
        kind: svkWrongKind, path: path, expectedKind: JNull, actualKind: valNode.kind
      )
    )
  return ok()

func parseParamBody(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``BODY=`` value (RFC 1652 / RFC 6152).
  let raw = ?expectStringValue(valNode, path)
  let enc =
    ?wrapInner(parseEnumByBackingString[BodyEncoding](raw, "BodyEncoding"), path)
  return ok(bodyParam(enc))

func parseParamSmtpUtf8(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode the valueless ``SMTPUTF8`` parameter (RFC 6531 §3.4).
  ?expectNullValue(valNode, path)
  return ok(smtpUtf8Param())

func parseParamSize(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``SIZE=<octets>`` advisory count (RFC 1870).
  let raw = ?expectStringValue(valNode, path)
  let n = ?wrapInner(parseUnsignedDecimal(raw, "UnsignedInt"), path)
  let octets = ?wrapInner(parseUnsignedInt(n), path)
  return ok(sizeParam(octets))

func parseParamEnvid(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``ENVID=`` envelope identifier (RFC 3461 §4.4); plain UTF-8
  ## on the JMAP wire (xtext stripped at the server boundary).
  let raw = ?expectStringValue(valNode, path)
  return ok(envidParam(raw))

func parseParamRet(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``RET=FULL|HDRS`` (RFC 3461 §4.3).
  let raw = ?expectStringValue(valNode, path)
  let t = ?wrapInner(parseEnumByBackingString[DsnRetType](raw, "DsnRetType"), path)
  return ok(retParam(t))

func parseParamNotify(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``NOTIFY=<flag[,flag...]>`` (RFC 3461 §4.1). Mutex enforcement
  ## is delegated to ``notifyParam``.
  let raw = ?expectStringValue(valNode, path)
  let flags = ?wrapInner(notifyFlagsFromWire(raw), path)
  return wrapInner(notifyParam(flags), path)

func parseParamOrcpt(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``ORCPT=<addr-type>;<orig-recipient>`` (RFC 3461 §4.2).
  let raw = ?expectStringValue(valNode, path)
  let semi = raw.find(';')
  if semi <= 0 or semi >= raw.high:
    return err(
      SerdeViolation(
        kind: svkFieldParserFailed,
        path: path,
        inner: validationError(
          "SubmissionParam", "ORCPT must be '<addr-type>;<orig-recipient>'", raw
        ),
      )
    )
  let addrType = ?wrapInner(parseOrcptAddrType(raw[0 ..< semi]), path)
  return ok(orcptParam(addrType, raw[semi + 1 .. raw.high]))

func parseParamHoldFor(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``HOLDFOR=<seconds>`` (RFC 4865 FUTURERELEASE delay form).
  let raw = ?expectStringValue(valNode, path)
  let n = ?wrapInner(parseUnsignedDecimal(raw, "UnsignedInt"), path)
  let secsBase = ?wrapInner(parseUnsignedInt(n), path)
  let secs = ?wrapInner(parseHoldForSeconds(secsBase), path)
  return ok(holdForParam(secs))

func parseParamHoldUntil(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``HOLDUNTIL=<RFC 3339 Zulu>`` (RFC 4865 FUTURERELEASE
  ## absolute-time form).
  let raw = ?expectStringValue(valNode, path)
  let d = ?wrapInner(parseUtcDate(raw), path)
  return ok(holdUntilParam(d))

func parseParamBy(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``BY=<deadline>;<mode>`` (RFC 2852 §3 deliver-by).
  let raw = ?expectStringValue(valNode, path)
  let semi = raw.find(';')
  if semi < 0 or semi >= raw.high:
    return err(
      SerdeViolation(
        kind: svkFieldParserFailed,
        path: path,
        inner: validationError("SubmissionParam", "BY must be '<deadline>;<mode>'", raw),
      )
    )
  let deadlineI64 = ?wrapInner(parseSignedDecimal(raw[0 ..< semi], "JmapInt"), path)
  let deadline = ?wrapInner(parseJmapInt(deadlineI64), path)
  let mode = ?wrapInner(
    parseEnumByBackingString[DeliveryByMode](
      raw[semi + 1 .. raw.high], "DeliveryByMode"
    ),
    path,
  )
  return ok(byParam(deadline, mode))

func parseParamMtPriority(
    valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode ``MT-PRIORITY=<-9..9>`` (RFC 6710 §2). Rejects an explicit
  ## leading ``+`` per the ABNF.
  let raw = ?expectStringValue(valNode, path)
  let n = ?wrapInner(parseSignedDecimal(raw, "MtPriority"), path)
  # Defensive: int cast can overflow on 32-bit platforms when n is outside
  # int's range. parseMtPriority's -9..9 bound is far narrower, so any
  # value that would overflow the cast is also out of MT-PRIORITY range.
  if n < -9'i64 or n > 9'i64:
    return err(
      SerdeViolation(
        kind: svkFieldParserFailed,
        path: path,
        inner: validationError("MtPriority", "must be in range -9..9", $n),
      )
    )
  let pri = ?wrapInner(parseMtPriority(int(n)), path)
  return ok(mtPriorityParam(pri))

func parseParamExtension(
    rawKey: string, valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Decode an unregistered / vendor parameter (RFC 8621 §7 ¶5). The
  ## wire key is parsed as ``RFC5321Keyword``; the value is ``Opt.none``
  ## for ``null``, ``Opt.some`` for any JSON string.
  let name = ?wrapInner(parseRFC5321Keyword(rawKey), path)
  case valNode.kind
  of JNull:
    return ok(extensionParam(name, Opt.none(string)))
  of JString:
    return ok(extensionParam(name, Opt.some(valNode.getStr(""))))
  else:
    return err(
      SerdeViolation(
        kind: svkWrongKind, path: path, expectedKind: JString, actualKind: valNode.kind
      )
    )

func parseOneParam(
    rawKey: string, valNode: JsonNode, path: JsonPath
): Result[SubmissionParam, SerdeViolation] =
  ## Dispatches one wire ``(key, value)`` pair to the matching variant
  ## parser. Iterates ``SubmissionParamKind`` (skipping ``spkExtension``)
  ## case-insensitively against ``$variant``; falls back to extension on
  ## no match. ``rawKey`` is the wire string post-`pairs` extraction.
  for k in SubmissionParamKind:
    if k == spkExtension:
      continue
    if cmpIgnoreCase($k, rawKey) != 0:
      continue
    case k
    of spkBody:
      return parseParamBody(valNode, path)
    of spkSmtpUtf8:
      return parseParamSmtpUtf8(valNode, path)
    of spkSize:
      return parseParamSize(valNode, path)
    of spkEnvid:
      return parseParamEnvid(valNode, path)
    of spkRet:
      return parseParamRet(valNode, path)
    of spkNotify:
      return parseParamNotify(valNode, path)
    of spkOrcpt:
      return parseParamOrcpt(valNode, path)
    of spkHoldFor:
      return parseParamHoldFor(valNode, path)
    of spkHoldUntil:
      return parseParamHoldUntil(valNode, path)
    of spkBy:
      return parseParamBy(valNode, path)
    of spkMtPriority:
      return parseParamMtPriority(valNode, path)
    of spkExtension:
      discard
  return parseParamExtension(rawKey, valNode, path)

# =============================================================================
# SubmissionParams ser/de
# =============================================================================

func toJson*(params: SubmissionParams): JsonNode =
  ## Emits the ``parameters`` wire object: one ``key: value`` entry per
  ## ``SubmissionParam``, with the wire key from ``SubmissionParamKind``
  ## backing strings (or ``extName`` for the open-world variant).
  var obj = newJObject()
  for key, param in pairs(OrderedTable[SubmissionParamKey, SubmissionParam](params)):
    let wireKey =
      case key.kind
      of spkExtension:
        $key.extName
      of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt,
          spkHoldFor, spkHoldUntil, spkBy, spkMtPriority:
        $key.kind
    obj[wireKey] = paramValueToJson(param)
  return obj

func fromJson*(
    T: typedesc[SubmissionParams], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SubmissionParams, SerdeViolation] =
  ## Deserialise a JSON object into a validated ``SubmissionParams``. Each
  ## ``(key, value)`` pair is dispatched to its variant parser; the
  ## resulting list is funnelled through ``parseSubmissionParams`` so the
  ## L1 invariants (no duplicate keys) hold for the returned value.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  var built: seq[SubmissionParam] = @[]
  for rawKey, valNode in node.pairs:
    let param = ?parseOneParam(rawKey, valNode, path / rawKey)
    built.add(param)
  return wrapFirstInner(parseSubmissionParams(built), path)

# =============================================================================
# parameters-field helper for SubmissionAddress / ReversePath null path
# =============================================================================

func parseOptParameters(
    node: JsonNode, path: JsonPath
): Result[Opt[SubmissionParams], SerdeViolation] =
  ## Reads a nullable ``parameters`` object: absent or ``null`` collapses
  ## to ``Opt.none``; an empty object yields ``Opt.some({})``.
  let field = node{"parameters"}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(SubmissionParams))
  let params = ?SubmissionParams.fromJson(field, path / "parameters")
  return ok(Opt.some(params))

# =============================================================================
# SubmissionAddress ser/de
# =============================================================================

func toJson*(a: SubmissionAddress): JsonNode =
  ## Serialise ``SubmissionAddress`` as RFC 8621 §7.3 ``Address`` object:
  ## ``{"email": <mailbox>, "parameters": <object|null>}``.
  var obj = newJObject()
  obj["email"] = toJson(a.mailbox)
  # Strict-safe & panic-free — see spkExtension serialiser above.
  case a.parameters.isOk
  of true:
    obj["parameters"] = toJson(a.parameters.unsafeValue)
  of false:
    obj["parameters"] = newJNull()
  return obj

func fromJson*(
    T: typedesc[SubmissionAddress], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SubmissionAddress, SerdeViolation] =
  ## Deserialise an Address object: lenient ``parseRFC5321MailboxFromServer``
  ## on ``email``, ``parseOptParameters`` on ``parameters``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let emailNode = ?fieldJString(node, "email", path)
  let mailbox =
    ?wrapInner(parseRFC5321MailboxFromServer(emailNode.getStr("")), path / "email")
  let parameters = ?parseOptParameters(node, path)
  return ok(SubmissionAddress(mailbox: mailbox, parameters: parameters))

# =============================================================================
# ReversePath ser/de
# =============================================================================

func toJson*(p: ReversePath): JsonNode =
  ## Serialise the ``mailFrom`` reverse path. The null path renders as
  ## ``{"email": "", "parameters": <object|null>}``; a concrete mailbox
  ## delegates to ``SubmissionAddress.toJson``.
  case p.kind
  of rpkNullPath:
    var obj = newJObject()
    obj["email"] = %""
    # Strict-safe & panic-free — see spkExtension serialiser above.
    case p.nullPathParams.isOk
    of true:
      obj["parameters"] = toJson(p.nullPathParams.unsafeValue)
    of false:
      obj["parameters"] = newJNull()
    return obj
  of rpkMailbox:
    return toJson(p.sender)

func fromJson*(
    T: typedesc[ReversePath], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ReversePath, SerdeViolation] =
  ## Discriminate on the ``email`` field: empty string → null path
  ## (RFC 5321 §4.1.1.2 permits Mail-parameters here); non-empty →
  ## delegate to ``SubmissionAddress.fromJson`` and lift via
  ## ``reversePath``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let emailNode = ?fieldJString(node, "email", path)
  if emailNode.getStr("") == "":
    let parameters = ?parseOptParameters(node, path)
    return ok(nullReversePath(parameters))
  let sa = ?SubmissionAddress.fromJson(node, path)
  return ok(reversePath(sa))

# =============================================================================
# NonEmptyRcptList ser/de
# =============================================================================

func toJson*(nr: NonEmptyRcptList): JsonNode =
  ## Serialise as a JSON array of ``Address`` objects.
  var arr = newJArray()
  for a in items(nr):
    arr.add(toJson(a))
  return arr

func fromJson*(
    T: typedesc[NonEmptyRcptList], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[NonEmptyRcptList, SerdeViolation] =
  ## Deserialise a JSON array of Address objects through the lenient
  ## server-side constructor (rejects empty list only — per-element
  ## structure already validated upstream).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JArray, path)
  var addrs: seq[SubmissionAddress] = @[]
  for i, elem in node.getElems(@[]):
    let a = ?SubmissionAddress.fromJson(elem, path / i)
    addrs.add(a)
  return wrapInner(parseNonEmptyRcptListFromServer(addrs), path)

# =============================================================================
# Envelope ser/de
# =============================================================================

func toJson*(e: Envelope): JsonNode =
  ## RFC 8621 §7.3 ``Envelope``: ``{"mailFrom": ..., "rcptTo": [...]}``.
  var obj = newJObject()
  obj["mailFrom"] = toJson(e.mailFrom)
  obj["rcptTo"] = toJson(e.rcptTo)
  return obj

func fromJson*(
    T: typedesc[Envelope], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Envelope, SerdeViolation] =
  ## Deserialise an Envelope object. Both ``mailFrom`` and ``rcptTo`` are
  ## required; missing fields produce ``svkMissingField``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let mfNode = ?fieldJObject(node, "mailFrom", path)
  let mailFrom = ?ReversePath.fromJson(mfNode, path / "mailFrom")
  let rcNode = ?fieldJArray(node, "rcptTo", path)
  let rcptTo = ?NonEmptyRcptList.fromJson(rcNode, path / "rcptTo")
  return ok(Envelope(mailFrom: mailFrom, rcptTo: rcptTo))
