# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Email, ParsedEmail, EmailComparator, and
## EmailBodyFetchOptions (RFC 8621 sections 4.1-4.9).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils
import std/tables

import ../serialisation/serde
import ../serialisation/serde_field_echo
import ../serialisation/serde_errors
import ../types
import ./addresses
import ./keyword
import ./mailbox
import ./headers
import ./body
import ./email
import ./serde_addresses
import ./serde_keyword
import ./serde_mailbox
import ./serde_headers
import ./serde_body

# Re-export the sibling serde modules and the L1 ``body`` adapter so that
# ``PartialEmail.fromJson`` resolves transitively through
# ``MailboxIdSet.fromJson``, ``KeywordSet.fromJson``,
# ``EmailHeader.fromJson``, ``EmailBodyPart.fromJson``,
# ``parseFromString*(typedesc[PartId], string)`` at every callsite — the
# generic ``mixin``-driven chain via ``SetResponse[T, U].fromJson`` and
# the generic ``Table[K, V].fromJson`` / ``seq[T].fromJson`` helpers
# resolves at the outermost instantiation site, so every dependency must
# be reachable there.
export serde
export serde_field_echo
export serde_addresses
export serde_keyword
export serde_mailbox
export serde_headers
export serde_body
export body

# =============================================================================
# Internal Helper Types
# =============================================================================

type ConvenienceHeaders {.ruleOff: "objects".} = object
  ## Groups 11 convenience header fields shared by emailFromJson and
  ## parsedEmailFromJson. Not exported — internal to this module (D7).
  messageId: Opt[seq[string]]
  inReplyTo: Opt[seq[string]]
  references: Opt[seq[string]]
  sender: Opt[seq[EmailAddress]]
  fromAddr: Opt[seq[EmailAddress]]
  to: Opt[seq[EmailAddress]]
  cc: Opt[seq[EmailAddress]]
  bcc: Opt[seq[EmailAddress]]
  replyTo: Opt[seq[EmailAddress]]
  subject: Opt[string]
  sentAt: Opt[Date]

type BodyFields {.ruleOff: "objects".} = object
  ## Groups 7 body fields shared by emailFromJson and parsedEmailFromJson.
  ## Not exported — internal to this module (D7). ``bodyStructure`` is
  ## ``Opt[EmailBodyPart]`` because property-filtered ``Email/get``
  ## responses may omit it.
  bodyStructure: Opt[EmailBodyPart]
  bodyValues: Table[PartId, EmailBodyValue]
  textBody: seq[EmailBodyPart]
  htmlBody: seq[EmailBodyPart]
  attachments: seq[EmailBodyPart]
  hasAttachment: bool
  preview: string

# =============================================================================
# Parsing Helpers
# =============================================================================

func parseOptStringSeq(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[seq[string]], SerdeViolation] =
  ## Parses an optional array of strings: absent/null yields Opt.none,
  ## JArray of JString yields Opt.some(seq). Used for messageId, inReplyTo,
  ## references convenience headers.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[string]))
  ?expectKind(field, JArray, path / key)
  var strs: seq[string] = @[]
  for i, elem in field.getElems(@[]):
    ?expectKind(elem, JString, path / key / i)
    strs.add(elem.getStr(""))
  return ok(Opt.some(strs))

func parseOptAddresses(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[seq[EmailAddress]], SerdeViolation] =
  ## Parses an optional array of EmailAddress: absent/null yields Opt.none,
  ## JArray yields Opt.some(seq). Used for sender, from, to, cc, bcc, replyTo
  ## convenience headers.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[EmailAddress]))
  ?expectKind(field, JArray, path / key)
  var addrs: seq[EmailAddress] = @[]
  for i, elem in field.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem, path / key / i)
    addrs.add(ea)
  return ok(Opt.some(addrs))

func parseOptString(node: JsonNode, key: string): Opt[string] =
  ## Extracts an optional string field: absent, null, or wrong kind yields none.
  let f = optJsonField(node, key, JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  return Opt.none(string)

func parseOptDate(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[Date], SerdeViolation] =
  ## Parses an optional Date field: absent/null yields Opt.none,
  ## JString yields parsed Date (may fail).
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Date))
  let d = ?Date.fromJson(field, path / key)
  return ok(Opt.some(d))

func parseOptId(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[Id], SerdeViolation] =
  ## Parses an optional Id field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Id))
  return ok(Opt.some(?Id.fromJson(field, path / key)))

func parseOptBlobId(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[BlobId], SerdeViolation] =
  ## Parses an optional BlobId field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(BlobId))
  return ok(Opt.some(?BlobId.fromJson(field, path / key)))

func parseOptUnsignedInt(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[UnsignedInt], SerdeViolation] =
  ## Parses an optional UnsignedInt field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(UnsignedInt))
  return ok(Opt.some(?UnsignedInt.fromJson(field, path / key)))

func parseOptUTCDate(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[UTCDate], SerdeViolation] =
  ## Parses an optional UTCDate field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(UTCDate))
  return ok(Opt.some(?UTCDate.fromJson(field, path / key)))

func parseOptMailboxIdSet(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[MailboxIdSet], SerdeViolation] =
  ## Parses an optional MailboxIdSet field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(MailboxIdSet))
  return ok(Opt.some(?MailboxIdSet.fromJson(field, path / key)))

func parseOptKeywordSet(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[KeywordSet], SerdeViolation] =
  ## Parses an optional KeywordSet field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(KeywordSet))
  return ok(Opt.some(?KeywordSet.fromJson(field, path / key)))

func parseOptBodyPart(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[EmailBodyPart], SerdeViolation] =
  ## Parses an optional EmailBodyPart field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(EmailBodyPart))
  return ok(Opt.some(?EmailBodyPart.fromJson(field, path / key)))

func parseConvenienceHeaders(
    node: JsonNode, path: JsonPath
): Result[ConvenienceHeaders, SerdeViolation] =
  ## Extracts the 11 convenience header fields from a JSON object.
  ## Shared by emailFromJson and parsedEmailFromJson.
  ## JSON ``"from"`` key maps to ``fromAddr`` field (``from`` is a Nim keyword).
  let messageId = ?parseOptStringSeq(node, "messageId", path)
  let inReplyTo = ?parseOptStringSeq(node, "inReplyTo", path)
  let references = ?parseOptStringSeq(node, "references", path)
  let sender = ?parseOptAddresses(node, "sender", path)
  let fromAddr = ?parseOptAddresses(node, "from", path)
  let to = ?parseOptAddresses(node, "to", path)
  let cc = ?parseOptAddresses(node, "cc", path)
  let bcc = ?parseOptAddresses(node, "bcc", path)
  let replyTo = ?parseOptAddresses(node, "replyTo", path)
  let subject = parseOptString(node, "subject")
  let sentAt = ?parseOptDate(node, "sentAt", path)
  return ok(
    ConvenienceHeaders(
      messageId: messageId,
      inReplyTo: inReplyTo,
      references: references,
      sender: sender,
      fromAddr: fromAddr,
      to: to,
      cc: cc,
      bcc: bcc,
      replyTo: replyTo,
      subject: subject,
      sentAt: sentAt,
    )
  )

func parseRawHeaders(
    node: JsonNode, path: JsonPath
): Result[seq[EmailHeader], SerdeViolation] =
  ## Extracts the headers field (seq[EmailHeader]). Absent key yields empty seq.
  var hdrs: seq[EmailHeader] = @[]
  let headersNode = node{"headers"}
  if not headersNode.isNil and headersNode.kind == JArray:
    for i, elem in headersNode.getElems(@[]):
      hdrs.add(?EmailHeader.fromJson(elem, path / "headers" / i))
  return ok(hdrs)

func parseBodyValues(
    node: JsonNode, path: JsonPath
): Result[Table[PartId, EmailBodyValue], SerdeViolation] =
  ## Parses bodyValues as Table[PartId, EmailBodyValue]. Absent/non-object
  ## yields empty table. Keys parsed via parsePartIdFromServer for typed
  ## PartId keys (D19).
  var bv = initTable[PartId, EmailBodyValue]()
  let bvNode = node{"bodyValues"}
  if not bvNode.isNil and bvNode.kind == JObject:
    for key, val in bvNode.pairs:
      let pid = ?wrapInner(parsePartIdFromServer(key), path / "bodyValues" / key)
      let ebv = ?EmailBodyValue.fromJson(val, path / "bodyValues" / key)
      bv[pid] = ebv
  return ok(bv)

func parseBodyPartArray(
    node: JsonNode, key: string, path: JsonPath
): Result[seq[EmailBodyPart], SerdeViolation] =
  ## Parses an optional array of EmailBodyPart: absent/non-array yields empty seq.
  var parts: seq[EmailBodyPart] = @[]
  let arrNode = node{key}
  if not arrNode.isNil and arrNode.kind == JArray:
    for i, elem in arrNode.getElems(@[]):
      parts.add(?EmailBodyPart.fromJson(elem, path / key / i))
  return ok(parts)

func parseBodyFields(
    node: JsonNode, path: JsonPath
): Result[BodyFields, SerdeViolation] =
  ## Extracts the 7 body fields from a JSON object.
  ## Shared by emailFromJson and parsedEmailFromJson.
  ## ``bodyStructure`` is optional: absent/null yields ``Opt.none``.
  let bodyStructure = ?parseOptBodyPart(node, "bodyStructure", path)
  let bodyVals = ?parseBodyValues(node, path)
  let textBody = ?parseBodyPartArray(node, "textBody", path)
  let htmlBody = ?parseBodyPartArray(node, "htmlBody", path)
  let attachments = ?parseBodyPartArray(node, "attachments", path)

  # hasAttachment: absent/null defaults to false; non-bool rejected
  let haNode = node{"hasAttachment"}
  if not haNode.isNil and haNode.kind != JNull and haNode.kind != JBool:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / "hasAttachment",
        expectedKind: JBool,
        actualKind: haNode.kind,
      )
    )
  let hasAttachment = haNode.getBool(false)

  # preview: absent/null defaults to ""
  let prevNode = node{"preview"}
  let preview =
    if not prevNode.isNil and prevNode.kind == JString:
      prevNode.getStr("")
    else:
      ""

  return ok(
    BodyFields(
      bodyStructure: bodyStructure,
      bodyValues: bodyVals,
      textBody: textBody,
      htmlBody: htmlBody,
      attachments: attachments,
      hasAttachment: hasAttachment,
      preview: preview,
    )
  )

func parseHeaderValueArray(
    node: JsonNode, form: HeaderForm, path: JsonPath
): Result[seq[HeaderValue], SerdeViolation] =
  ## Parses a JSON array of header values for ``:all`` dynamic header properties.
  ## Each element parsed via parseHeaderValue with the given form.
  ?expectKind(node, JArray, path)
  var values: seq[HeaderValue] = @[]
  for i, elem in node.getElems(@[]):
    values.add(?parseHeaderValue(form, elem, path / i))
  return ok(values)

# =============================================================================
# emailFromJson
# =============================================================================

func emailFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Email, SerdeViolation] =
  ## Deserialises an Email object from server JSON using two-phase
  ## strategy (D4). Phase 1: structured extraction of all standard properties;
  ## every field is ``Opt`` so property-filtered ``Email/get`` responses
  ## (sparse JSON) parse without error. Phase 2: dynamic header discovery
  ## for ``header:`` prefixed keys. Constructs Email directly (D15: lenient
  ## at server-to-client boundary, trust RFC contract).
  ?expectKind(node, JObject, path)

  # == Phase 1: Structured extraction ==

  # Metadata — every field is Opt to admit property-filter responses.
  let id = ?parseOptId(node, "id", path)
  let blobId = ?parseOptBlobId(node, "blobId", path)
  let threadId = ?parseOptId(node, "threadId", path)
  let mailboxIds = ?parseOptMailboxIdSet(node, "mailboxIds", path)
  let keywords = ?parseOptKeywordSet(node, "keywords", path)
  let size = ?parseOptUnsignedInt(node, "size", path)
  let receivedAt = ?parseOptUTCDate(node, "receivedAt", path)

  # Convenience headers (shared helper)
  let convHeaders = ?parseConvenienceHeaders(node, path)

  # Raw headers
  let hdrs = ?parseRawHeaders(node, path)

  # Body (shared helper)
  let bf = ?parseBodyFields(node, path)

  # == Phase 2: Dynamic header discovery ==
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?wrapInner(parseHeaderPropertyName(key), path / key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form, path / key)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val, path / key)

  return ok(
    Email(
      id: id,
      blobId: blobId,
      threadId: threadId,
      mailboxIds: mailboxIds,
      keywords: keywords,
      size: size,
      receivedAt: receivedAt,
      messageId: convHeaders.messageId,
      inReplyTo: convHeaders.inReplyTo,
      references: convHeaders.references,
      sender: convHeaders.sender,
      fromAddr: convHeaders.fromAddr,
      to: convHeaders.to,
      cc: convHeaders.cc,
      bcc: convHeaders.bcc,
      replyTo: convHeaders.replyTo,
      subject: convHeaders.subject,
      sentAt: convHeaders.sentAt,
      headers: hdrs,
      requestedHeaders: reqHeaders,
      requestedHeadersAll: reqHeadersAll,
      bodyStructure: bf.bodyStructure,
      bodyValues: bf.bodyValues,
      textBody: bf.textBody,
      htmlBody: bf.htmlBody,
      attachments: bf.attachments,
      hasAttachment: bf.hasAttachment,
      preview: bf.preview,
    )
  )

func fromJson*(
    T: typedesc[Email], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Email, SerdeViolation] =
  ## Typedesc-dispatch wrapper around ``emailFromJson``. Enables the
  ## canonical ``Email.fromJson(node)`` idiom at consumer sites,
  ## parallel to ``EmailBodyPart.fromJson`` / ``KeywordSet.fromJson`` /
  ## ``MailboxIdSet.fromJson``.
  discard $T # consumed for nimalyzer params rule
  return emailFromJson(node, path)

# =============================================================================
# PartialEmail (A4 + A3.6)
# =============================================================================

func fromJson*(
    T: typedesc[PartialEmail], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[PartialEmail, SerdeViolation] =
  ## Deserialise a partial Email echo (RFC 8621 §4). Lenient on missing
  ## fields; strict on wrong-kind present fields and strict-on-wire-token
  ## for closed-enum fields (D4). Dynamic ``header:`` keys share a single
  ## top-level scan (lifted from ``emailFromJson``); other Table/seq
  ## fields delegate to the generic ``seq[T].fromJson`` /
  ## ``Table[K, V].fromJson`` helpers in ``serialisation/serde.nim``.
  discard $T
  ?expectKind(node, JObject, path)

  # Metadata (wire-non-nullable → Opt[T])
  let id = ?parsePartialOptField[Id](node, "id", path)
  let blobId = ?parsePartialOptField[BlobId](node, "blobId", path)
  let threadId = ?parsePartialOptField[Id](node, "threadId", path)
  let mailboxIds = ?parsePartialOptField[MailboxIdSet](node, "mailboxIds", path)
  let keywords = ?parsePartialOptField[KeywordSet](node, "keywords", path)
  let size = ?parsePartialOptField[UnsignedInt](node, "size", path)
  let receivedAt = ?parsePartialOptField[UTCDate](node, "receivedAt", path)

  # Convenience headers (wire-nullable → FieldEcho[T]). JSON ``"from"``
  # key maps to the Nim ``fromAddr`` field (``from`` is a Nim keyword).
  let messageId = ?parsePartialFieldEcho[seq[string]](node, "messageId", path)
  let inReplyTo = ?parsePartialFieldEcho[seq[string]](node, "inReplyTo", path)
  let references = ?parsePartialFieldEcho[seq[string]](node, "references", path)
  let sender = ?parsePartialFieldEcho[seq[EmailAddress]](node, "sender", path)
  let fromAddr = ?parsePartialFieldEcho[seq[EmailAddress]](node, "from", path)
  let to = ?parsePartialFieldEcho[seq[EmailAddress]](node, "to", path)
  let cc = ?parsePartialFieldEcho[seq[EmailAddress]](node, "cc", path)
  let bcc = ?parsePartialFieldEcho[seq[EmailAddress]](node, "bcc", path)
  let replyTo = ?parsePartialFieldEcho[seq[EmailAddress]](node, "replyTo", path)
  let subject = ?parsePartialFieldEcho[string](node, "subject", path)
  let sentAt = ?parsePartialFieldEcho[Date](node, "sentAt", path)

  # Raw headers (wire-non-nullable → Opt[T])
  let headers = ?parsePartialOptField[seq[EmailHeader]](node, "headers", path)

  # Dynamic ``header:`` discovery — lifted from ``emailFromJson`` §4.1.3.
  # Promote each accumulator to ``Opt.some(tbl)`` when non-empty, else
  # ``Opt.none``: the partial parser distinguishes "no dynamic headers
  # requested" from "requested but the server omitted them".
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?wrapInner(parseHeaderPropertyName(key), path / key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form, path / key)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val, path / key)
  let requestedHeaders =
    if reqHeaders.len == 0:
      Opt.none(Table[HeaderPropertyKey, HeaderValue])
    else:
      Opt.some(reqHeaders)
  let requestedHeadersAll =
    if reqHeadersAll.len == 0:
      Opt.none(Table[HeaderPropertyKey, seq[HeaderValue]])
    else:
      Opt.some(reqHeadersAll)

  # Body (bodyStructure wire-nullable; others wire-non-nullable)
  let bodyStructure = ?parsePartialFieldEcho[EmailBodyPart](node, "bodyStructure", path)
  let bodyValues =
    ?parsePartialOptField[Table[PartId, EmailBodyValue]](node, "bodyValues", path)
  let textBody = ?parsePartialOptField[seq[EmailBodyPart]](node, "textBody", path)
  let htmlBody = ?parsePartialOptField[seq[EmailBodyPart]](node, "htmlBody", path)
  let attachments = ?parsePartialOptField[seq[EmailBodyPart]](node, "attachments", path)
  let hasAttachment = ?parsePartialOptField[bool](node, "hasAttachment", path)
  let preview = ?parsePartialOptField[string](node, "preview", path)

  return ok(
    PartialEmail(
      id: id,
      blobId: blobId,
      threadId: threadId,
      mailboxIds: mailboxIds,
      keywords: keywords,
      size: size,
      receivedAt: receivedAt,
      messageId: messageId,
      inReplyTo: inReplyTo,
      references: references,
      sender: sender,
      fromAddr: fromAddr,
      to: to,
      cc: cc,
      bcc: bcc,
      replyTo: replyTo,
      subject: subject,
      sentAt: sentAt,
      headers: headers,
      requestedHeaders: requestedHeaders,
      requestedHeadersAll: requestedHeadersAll,
      bodyStructure: bodyStructure,
      bodyValues: bodyValues,
      textBody: textBody,
      htmlBody: htmlBody,
      attachments: attachments,
      hasAttachment: hasAttachment,
      preview: preview,
    )
  )

func emitPartialEmailMetadata(node: JsonNode, p: PartialEmail) =
  ## Metadata-block emission for ``PartialEmail.toJson``. Extracted so
  ## the public ``toJson`` stays under the cyclomatic complexity ceiling.
  for v in p.id:
    node["id"] = v.toJson()
  for v in p.blobId:
    node["blobId"] = v.toJson()
  for v in p.threadId:
    node["threadId"] = v.toJson()
  for v in p.mailboxIds:
    node["mailboxIds"] = v.toJson()
  for v in p.keywords:
    node["keywords"] = v.toJson()
  for v in p.size:
    node["size"] = v.toJson()
  for v in p.receivedAt:
    node["receivedAt"] = v.toJson()

func emitPartialEmailConvenienceHeaders(node: JsonNode, p: PartialEmail) =
  ## Convenience-header block emission for ``PartialEmail.toJson``. The
  ## Nim field ``fromAddr`` maps to JSON key ``"from"`` (``from`` is a
  ## Nim keyword).
  emitPartialFieldEcho[seq[string]](node, "messageId", p.messageId)
  emitPartialFieldEcho[seq[string]](node, "inReplyTo", p.inReplyTo)
  emitPartialFieldEcho[seq[string]](node, "references", p.references)
  emitPartialFieldEcho[seq[EmailAddress]](node, "sender", p.sender)
  emitPartialFieldEcho[seq[EmailAddress]](node, "from", p.fromAddr)
  emitPartialFieldEcho[seq[EmailAddress]](node, "to", p.to)
  emitPartialFieldEcho[seq[EmailAddress]](node, "cc", p.cc)
  emitPartialFieldEcho[seq[EmailAddress]](node, "bcc", p.bcc)
  emitPartialFieldEcho[seq[EmailAddress]](node, "replyTo", p.replyTo)
  emitPartialFieldEcho[string](node, "subject", p.subject)
  emitPartialFieldEcho[Date](node, "sentAt", p.sentAt)

func emitPartialEmailRawHeaders(node: JsonNode, p: PartialEmail) =
  ## Raw headers and dynamic header projection for ``PartialEmail.toJson``.
  ## Dynamic ``header:`` keys expand inline as top-level keys when
  ## ``Opt.some``.
  for v in p.headers:
    node["headers"] = v.toJson()
  for tbl in p.requestedHeaders:
    for hpk, hval in tbl:
      node[hpk.toPropertyString()] = hval.toJson()
  for tbl in p.requestedHeadersAll:
    for hpk, hvals in tbl:
      var arr = newJArray()
      for v in hvals:
        arr.add(v.toJson())
      node[hpk.toPropertyString()] = arr

func emitPartialEmailBody(node: JsonNode, p: PartialEmail) =
  ## Body block emission for ``PartialEmail.toJson``.
  emitPartialFieldEcho[EmailBodyPart](node, "bodyStructure", p.bodyStructure)
  for v in p.bodyValues:
    node["bodyValues"] = v.toJson()
  for v in p.textBody:
    node["textBody"] = v.toJson()
  for v in p.htmlBody:
    node["htmlBody"] = v.toJson()
  for v in p.attachments:
    node["attachments"] = v.toJson()
  for v in p.hasAttachment:
    node["hasAttachment"] = v.toJson()
  for v in p.preview:
    node["preview"] = v.toJson()

func toJson*(p: PartialEmail): JsonNode =
  ## Emit a partial Email echo — D5/D3.7 unidirectional serde symmetry.
  ## ``fekAbsent`` and ``Opt.none`` omit the key entirely. Body is
  ## broken into four sub-emitters (metadata, convenience headers, raw +
  ## dynamic headers, body) to stay under the cyclomatic ceiling.
  result = newJObject()
  emitPartialEmailMetadata(result, p)
  emitPartialEmailConvenienceHeaders(result, p)
  emitPartialEmailRawHeaders(result, p)
  emitPartialEmailBody(result, p)

# =============================================================================
# parsedEmailFromJson
# =============================================================================

func parsedEmailFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ParsedEmail, SerdeViolation] =
  ## Deserialises a ParsedEmail from server JSON (Email/parse response).
  ## Same two-phase strategy as emailFromJson but only threadId from metadata.
  ## Missing metadata fields (id, blobId, mailboxIds, keywords, size,
  ## receivedAt) are structurally absent — not extracted.
  ?expectKind(node, JObject, path)

  # == Phase 1: Structured extraction ==

  # Metadata: only threadId survives
  let threadId = ?parseOptId(node, "threadId", path)

  # Convenience headers (shared helper)
  let convHeaders = ?parseConvenienceHeaders(node, path)

  # Raw headers
  let hdrs = ?parseRawHeaders(node, path)

  # Body (shared helper)
  let bf = ?parseBodyFields(node, path)

  # == Phase 2: Dynamic header discovery ==
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?wrapInner(parseHeaderPropertyName(key), path / key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form, path / key)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val, path / key)

  return ok(
    ParsedEmail(
      threadId: threadId,
      messageId: convHeaders.messageId,
      inReplyTo: convHeaders.inReplyTo,
      references: convHeaders.references,
      sender: convHeaders.sender,
      fromAddr: convHeaders.fromAddr,
      to: convHeaders.to,
      cc: convHeaders.cc,
      bcc: convHeaders.bcc,
      replyTo: convHeaders.replyTo,
      subject: convHeaders.subject,
      sentAt: convHeaders.sentAt,
      headers: hdrs,
      requestedHeaders: reqHeaders,
      requestedHeadersAll: reqHeadersAll,
      bodyStructure: bf.bodyStructure,
      bodyValues: bf.bodyValues,
      textBody: bf.textBody,
      htmlBody: bf.htmlBody,
      attachments: bf.attachments,
      hasAttachment: bf.hasAttachment,
      preview: bf.preview,
    )
  )

# =============================================================================
# Email-Specific toJson Emit Helpers
# =============================================================================

func emitOptStringSeqOrNull(node: var JsonNode, key: string, opt: Opt[seq[string]]) =
  ## Emits an optional string sequence as JSON array when present, null when absent.
  if opt.isSome:
    var arr = newJArray()
    for s in opt.get():
      arr.add(%s)
    node[key] = arr
  else:
    node[key] = newJNull()

func emitOptAddressesOrNull(
    node: var JsonNode, key: string, opt: Opt[seq[EmailAddress]]
) =
  ## Emits an optional address sequence as JSON array when present, null when absent.
  if opt.isSome:
    var arr = newJArray()
    for ea in opt.get():
      arr.add(ea.toJson())
    node[key] = arr
  else:
    node[key] = newJNull()

# =============================================================================
# Email.toJson
# =============================================================================

func toJson*(e: Email): JsonNode =
  ## Serialise Email to JSON. Emits all domain fields always (D5).
  ## ``Opt.none`` emits null, empty seq emits ``[]``, empty Table emits ``{}``.
  ## Dynamic headers emitted as N top-level keys.
  ## ``fromAddr`` emits as ``"from"`` JSON key.
  var node = newJObject()

  # Metadata — every field is Opt; absent emits null.
  node["id"] = e.id.optToJsonOrNull()
  node["blobId"] = e.blobId.optToJsonOrNull()
  node["threadId"] = e.threadId.optToJsonOrNull()
  node["mailboxIds"] = e.mailboxIds.optToJsonOrNull()
  node["keywords"] = e.keywords.optToJsonOrNull()
  node["size"] = e.size.optToJsonOrNull()
  node["receivedAt"] = e.receivedAt.optToJsonOrNull()

  # Convenience headers: Opt.none emits null
  emitOptStringSeqOrNull(node, "messageId", e.messageId)
  emitOptStringSeqOrNull(node, "inReplyTo", e.inReplyTo)
  emitOptStringSeqOrNull(node, "references", e.references)
  emitOptAddressesOrNull(node, "sender", e.sender)
  emitOptAddressesOrNull(node, "from", e.fromAddr)
  emitOptAddressesOrNull(node, "to", e.to)
  emitOptAddressesOrNull(node, "cc", e.cc)
  emitOptAddressesOrNull(node, "bcc", e.bcc)
  emitOptAddressesOrNull(node, "replyTo", e.replyTo)
  node["subject"] = e.subject.optStringToJsonOrNull()
  node["sentAt"] = e.sentAt.optToJsonOrNull()

  # Raw headers
  var headersArr = newJArray()
  for eh in e.headers:
    headersArr.add(eh.toJson())
  node["headers"] = headersArr

  # Body
  node["bodyStructure"] = e.bodyStructure.optToJsonOrNull()
  var bvNode = newJObject()
  for pid, bv in e.bodyValues:
    bvNode[$pid] = bv.toJson()
  node["bodyValues"] = bvNode
  var textBodyArr = newJArray()
  for part in e.textBody:
    textBodyArr.add(part.toJson())
  node["textBody"] = textBodyArr
  var htmlBodyArr = newJArray()
  for part in e.htmlBody:
    htmlBodyArr.add(part.toJson())
  node["htmlBody"] = htmlBodyArr
  var attachmentsArr = newJArray()
  for part in e.attachments:
    attachmentsArr.add(part.toJson())
  node["attachments"] = attachmentsArr
  node["hasAttachment"] = %e.hasAttachment
  node["preview"] = %e.preview

  # Dynamic headers: N top-level keys
  for hpk, val in e.requestedHeaders:
    node[hpk.toPropertyString()] = val.toJson()
  for hpk, vals in e.requestedHeadersAll:
    var arr = newJArray()
    for v in vals:
      arr.add(v.toJson())
    node[hpk.toPropertyString()] = arr

  return node

# =============================================================================
# ParsedEmail.toJson
# =============================================================================

func toJson*(pe: ParsedEmail): JsonNode =
  ## Serialise ParsedEmail to JSON. Omits the 6 absent metadata fields.
  ## Emits threadId (as value or null). Otherwise identical to Email.toJson.
  var node = newJObject()

  # Metadata: only threadId
  node["threadId"] = pe.threadId.optToJsonOrNull()

  # Convenience headers: Opt.none emits null
  emitOptStringSeqOrNull(node, "messageId", pe.messageId)
  emitOptStringSeqOrNull(node, "inReplyTo", pe.inReplyTo)
  emitOptStringSeqOrNull(node, "references", pe.references)
  emitOptAddressesOrNull(node, "sender", pe.sender)
  emitOptAddressesOrNull(node, "from", pe.fromAddr)
  emitOptAddressesOrNull(node, "to", pe.to)
  emitOptAddressesOrNull(node, "cc", pe.cc)
  emitOptAddressesOrNull(node, "bcc", pe.bcc)
  emitOptAddressesOrNull(node, "replyTo", pe.replyTo)
  node["subject"] = pe.subject.optStringToJsonOrNull()
  node["sentAt"] = pe.sentAt.optToJsonOrNull()

  # Raw headers
  var headersArr = newJArray()
  for eh in pe.headers:
    headersArr.add(eh.toJson())
  node["headers"] = headersArr

  # Body
  node["bodyStructure"] = pe.bodyStructure.optToJsonOrNull()
  var bvNode = newJObject()
  for pid, bv in pe.bodyValues:
    bvNode[$pid] = bv.toJson()
  node["bodyValues"] = bvNode
  var textBodyArr = newJArray()
  for part in pe.textBody:
    textBodyArr.add(part.toJson())
  node["textBody"] = textBodyArr
  var htmlBodyArr = newJArray()
  for part in pe.htmlBody:
    htmlBodyArr.add(part.toJson())
  node["htmlBody"] = htmlBodyArr
  var attachmentsArr = newJArray()
  for part in pe.attachments:
    attachmentsArr.add(part.toJson())
  node["attachments"] = attachmentsArr
  node["hasAttachment"] = %pe.hasAttachment
  node["preview"] = %pe.preview

  # Dynamic headers: N top-level keys
  for hpk, val in pe.requestedHeaders:
    node[hpk.toPropertyString()] = val.toJson()
  for hpk, vals in pe.requestedHeadersAll:
    var arr = newJArray()
    for v in vals:
      arr.add(v.toJson())
    node[hpk.toPropertyString()] = arr

  return node

# =============================================================================
# EmailComparator
# =============================================================================

func emailComparatorFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailComparator, SerdeViolation] =
  ## Deserialises an EmailComparator by synthesising the discriminant from
  ## the property string value (D8). Tries KeywordSortProperty values first
  ## (require ``keyword`` field present), then PlainSortProperty values.
  ## Case-sensitive exact match on backing strings.
  ?expectKind(node, JObject, path)

  # Required property string
  let propNode = ?fieldJString(node, "property", path)
  let propStr = propNode.getStr("")

  # Optional shared fields
  let isAscending = block:
    let f = optJsonField(node, "isAscending", JBool)
    if f.isSome:
      Opt.some(f.get().getBool(true))
    else:
      Opt.none(bool)
  let collation = block:
    let f = optJsonField(node, "collation", JString)
    if f.isSome:
      let raw = f.get().getStr("")
      if raw.len > 0:
        # Empty string is the RFC-default sentinel; treat as ``Opt.none``.
        let alg = ?wrapInner(parseCollationAlgorithm(raw), path / "collation")
        Opt.some(alg)
      else:
        Opt.none(CollationAlgorithm)
    else:
      Opt.none(CollationAlgorithm)

  # Try keyword sort properties first (exact string match via $enum)
  for ksp in KeywordSortProperty:
    if $ksp == propStr:
      let kwNode = ?fieldJString(node, "keyword", path)
      let kw = ?Keyword.fromJson(kwNode, path / "keyword")
      return ok(keywordComparator(ksp, kw, isAscending, collation))

  # Try plain sort properties
  for psp in PlainSortProperty:
    if $psp == propStr:
      return ok(plainComparator(psp, isAscending, collation))

  return err(
    SerdeViolation(
      kind: svkEnumNotRecognised,
      path: path / "property",
      enumTypeLabel: "sort property",
      rawValue: propStr,
    )
  )

func toJson*(c: EmailComparator): JsonNode =
  ## Serialise EmailComparator to JSON. Dispatches on kind.
  ## ``isAscending`` and ``collation`` omitted when ``Opt.none``.
  var node = newJObject()
  case c.kind
  of eckPlain:
    node["property"] = %($c.property)
  of eckKeyword:
    node["property"] = %($c.keywordProperty)
    node["keyword"] = %($c.keyword)
  for v in c.isAscending:
    node["isAscending"] = %v
  for v in c.collation:
    node["collation"] = %($v)
  return node

# =============================================================================
# EmailBodyFetchOptions
# =============================================================================

func emitBodyProperties(node: var JsonNode, opt: Opt[seq[PropertyName]]) =
  ## Emit ``bodyProperties`` as a JArray when present. ``Opt.none`` →
  ## omit. Mirrors the address-list / string-list emitters in
  ## ``serde_email_blueprint.nim``.
  for props in opt:
    var arr = newJArray()
    for p in props:
      arr.add(p.toJson())
    node["bodyProperties"] = arr

func emitFetchScope(node: var JsonNode, scope: BodyValueScope) =
  ## Map ``BodyValueScope`` back to the RFC 8621 §4.2 booleans (D9).
  ## ``bvsNone`` omits all fetch keys; ``bvsTextAndHtml`` emits two
  ## keys atomically.
  case scope
  of bvsNone:
    discard
  of bvsText:
    node["fetchTextBodyValues"] = %true
  of bvsHtml:
    node["fetchHTMLBodyValues"] = %true
  of bvsTextAndHtml:
    node["fetchTextBodyValues"] = %true
    node["fetchHTMLBodyValues"] = %true
  of bvsAll:
    node["fetchAllBodyValues"] = %true

func emitMaxBodyValueBytes(node: var JsonNode, opt: Opt[UnsignedInt]) =
  ## Emit ``maxBodyValueBytes`` when present. ``Opt.none`` → omit.
  for v in opt:
    node["maxBodyValueBytes"] = v.toJson()

func emitBodyFetchOptions*(node: var JsonNode, opts: EmailBodyFetchOptions) =
  ## Emit body fetch option keys directly into ``node``. Consumed by
  ## the ``addEmailGet`` / ``addPartialEmailGet`` / ``addEmailParse``
  ## wrappers — mirrors the ``emitOptAddrSeq`` / ``emitOptStringSeq``
  ## helpers in ``serde_email_blueprint.nim``. Insertion order:
  ## ``bodyProperties``, ``fetchTextBodyValues?``,
  ## ``fetchHTMLBodyValues?``, ``fetchAllBodyValues?``,
  ## ``maxBodyValueBytes``.
  emitBodyProperties(node, opts.bodyProperties)
  emitFetchScope(node, opts.fetchBodyValues)
  emitMaxBodyValueBytes(node, opts.maxBodyValueBytes)

func toJson*(opts: EmailBodyFetchOptions): JsonNode =
  ## Serialise EmailBodyFetchOptions to request JSON arguments.
  ## ``bvsNone`` omits all fetch keys; ``default(EmailBodyFetchOptions).toJson``
  ## produces ``{}``.
  result = newJObject()
  emitBodyFetchOptions(result, opts)

# =============================================================================
# EmailCreatedItem
# =============================================================================

func toJson*(item: EmailCreatedItem): JsonNode =
  ## Serialise EmailCreatedItem to JSON (RFC 8621 §§4.6/4.7/4.8).
  ## All four fields required per the RFC — none Opt.
  var node = newJObject()
  node["id"] = item.id.toJson()
  node["blobId"] = item.blobId.toJson()
  node["threadId"] = item.threadId.toJson()
  node["size"] = item.size.toJson()
  return node

func fromJson*(
    T: typedesc[EmailCreatedItem], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailCreatedItem, SerdeViolation] =
  ## Deserialise JSON to EmailCreatedItem. All four fields required per RFC;
  ## missing any field yields err — servers omitting any are malformed
  ## (Design §2.1, F2).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let blobIdNode = ?fieldJString(node, "blobId", path)
  let blobId = ?BlobId.fromJson(blobIdNode, path / "blobId")
  let threadIdNode = ?fieldJString(node, "threadId", path)
  let threadId = ?Id.fromJson(threadIdNode, path / "threadId")
  let sizeNode = ?fieldJInt(node, "size", path)
  let size = ?UnsignedInt.fromJson(sizeNode, path / "size")
  return ok(EmailCreatedItem(id: id, blobId: blobId, threadId: threadId, size: size))

# =============================================================================
# EmailImportResponse-only helpers
# =============================================================================
# Email/set and Email/copy now route through the generic
# ``SetResponse[EmailCreatedItem, PartialEmail]`` /
# ``CopyResponse[EmailCreatedItem]`` serde in ``methods.nim``.
# ``EmailImportResponse`` stays bespoke (no generic ``ImportResponse[T]``
# exists), so the envelope-extraction and create-merge helpers below
# remain for its single caller.

func parseOptJmapStateField(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[JmapState], SerdeViolation] =
  ## Extracts an optional JmapState: absent/null yields none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(JmapState))
  return ok(Opt.some(?JmapState.fromJson(field, path / key)))

func mergeCreatedResults(
    node: JsonNode, path: JsonPath
): Result[Table[CreationId, Result[EmailCreatedItem, SetError]], SerdeViolation] =
  ## Merges wire ``created`` and ``notCreated`` maps into a single Table
  ## keyed by CreationId for EmailImportResponse (RFC 8621 §4.8).
  var tbl = initTable[CreationId, Result[EmailCreatedItem, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "created" / k)
      let item = ?EmailCreatedItem.fromJson(v, path / "created" / k)
      tbl[cid] = Result[EmailCreatedItem, SetError].ok(item)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "notCreated" / k)
      let se = ?SetError.fromJson(v, path / "notCreated" / k)
      tbl[cid] = Result[EmailCreatedItem, SetError].err(se)
  return ok(tbl)

func emitCreateResults(
    createResults: Table[CreationId, Result[EmailCreatedItem, SetError]], node: JsonNode
) =
  ## Splits a merged createResults Table back into the wire
  ## ``created`` and ``notCreated`` maps; omits either key when empty.
  var created = newJObject()
  var notCreated = newJObject()
  for cid, r in createResults:
    if r.isOk:
      created[$cid] = r.get().toJson()
    else:
      notCreated[$cid] = r.error.toJson()
  if created.len > 0:
    node["created"] = created
  if notCreated.len > 0:
    node["notCreated"] = notCreated

# =============================================================================
# EmailImportResponse
# =============================================================================

func toJson*(resp: EmailImportResponse): JsonNode =
  ## Serialise EmailImportResponse (RFC 8621 §4.8). Minimal envelope —
  ## imports have no update/destroy branches.
  var node = newJObject()
  node["accountId"] = resp.accountId.toJson()
  for s in resp.oldState:
    node["oldState"] = s.toJson()
  for s in resp.newState:
    node["newState"] = s.toJson()
  emitCreateResults(resp.createResults, node)
  return node

func fromJson*(
    T: typedesc[EmailImportResponse], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailImportResponse, SerdeViolation] =
  ## Deserialise JSON to EmailImportResponse (RFC 8621 §4.8).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId = ?AccountId.fromJson(accountIdNode, path / "accountId")
  let newState = ?parseOptJmapStateField(node, "newState", path)
  let oldState = ?parseOptJmapStateField(node, "oldState", path)
  let createResults = ?mergeCreatedResults(node, path)
  return ok(
    EmailImportResponse(
      accountId: accountId,
      oldState: oldState,
      newState: newState,
      createResults: createResults,
    )
  )

# =============================================================================
# EmailCopyItem (toJson only — client → server)
# =============================================================================

func toJson*(item: EmailCopyItem): JsonNode =
  ## Serialise EmailCopyItem for Email/copy create entries (RFC 8621 §4.7).
  ## id always emitted; overrides omitted when Opt.none (preserve source).
  var node = newJObject()
  node["id"] = item.id.toJson()
  for mids in item.mailboxIds:
    node["mailboxIds"] = mids.toJson()
  for kws in item.keywords:
    node["keywords"] = kws.toJson()
  for ra in item.receivedAt:
    node["receivedAt"] = ra.toJson()
  return node

# =============================================================================
# EmailImportItem (toJson only — client → server)
# =============================================================================

func toJson*(item: EmailImportItem): JsonNode =
  ## Serialise EmailImportItem for Email/import entries (RFC 8621 §4.8).
  ## blobId and mailboxIds always emitted; keywords omitted both when
  ## Opt.none AND when Opt.some(empty) — an empty keyword set is the
  ## server default (Design §6.1, F16). receivedAt when Opt.some.
  var node = newJObject()
  node["blobId"] = item.blobId.toJson()
  node["mailboxIds"] = item.mailboxIds.toJson()
  for kws in item.keywords:
    if kws.len > 0:
      node["keywords"] = kws.toJson()
  for ra in item.receivedAt:
    node["receivedAt"] = ra.toJson()
  return node

# =============================================================================
# NonEmptyEmailImportMap (toJson only — client → server)
# =============================================================================

func toJson*(m: NonEmptyEmailImportMap): JsonNode =
  ## Serialise NonEmptyEmailImportMap. Smart constructor has already
  ## enforced non-empty and unique-CreationId invariants (Design §6.2, F13).
  let tbl = m.toTable
  var node = newJObject()
  for cid, item in tbl:
    node[$cid] = item.toJson()
  return node
