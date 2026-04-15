# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Email, ParsedEmail, EmailComparator, and
## EmailBodyFetchOptions (RFC 8621 sections 4.1-4.9).

{.push raises: [], noSideEffect.}

import std/json
import std/strutils
import std/tables

import ../serde
import ../serde_errors
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
  ## Not exported — internal to this module (D7).
  bodyStructure: EmailBodyPart
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
    node: JsonNode, key: string
): Result[Opt[seq[string]], ValidationError] =
  ## Parses an optional array of strings: absent/null yields Opt.none,
  ## JArray of JString yields Opt.some(seq). Used for messageId, inReplyTo,
  ## references convenience headers.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[string]))
  ?checkJsonKind(field, JArray, "Email", key & " must be array or null")
  var strs: seq[string] = @[]
  for elem in field.getElems(@[]):
    ?checkJsonKind(elem, JString, "Email", key & " element must be string")
    strs.add(elem.getStr(""))
  return ok(Opt.some(strs))

func parseOptAddresses(
    node: JsonNode, key: string
): Result[Opt[seq[EmailAddress]], ValidationError] =
  ## Parses an optional array of EmailAddress: absent/null yields Opt.none,
  ## JArray yields Opt.some(seq). Used for sender, from, to, cc, bcc, replyTo
  ## convenience headers.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[EmailAddress]))
  ?checkJsonKind(field, JArray, "Email", key & " must be array or null")
  var addrs: seq[EmailAddress] = @[]
  for elem in field.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem)
    addrs.add(ea)
  return ok(Opt.some(addrs))

func parseOptString(node: JsonNode, key: string): Opt[string] =
  ## Extracts an optional string field: absent, null, or wrong kind yields none.
  let f = optJsonField(node, key, JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  return Opt.none(string)

func parseOptDate(node: JsonNode, key: string): Result[Opt[Date], ValidationError] =
  ## Parses an optional Date field: absent/null yields Opt.none,
  ## JString yields parsed Date (may fail).
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Date))
  let d = ?Date.fromJson(field)
  return ok(Opt.some(d))

func parseOptId(node: JsonNode, key: string): Result[Opt[Id], ValidationError] =
  ## Parses an optional Id field: absent/null yields Opt.none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Id))
  return ok(Opt.some(?Id.fromJson(field)))

func parseConvenienceHeaders(
    node: JsonNode
): Result[ConvenienceHeaders, ValidationError] =
  ## Extracts the 11 convenience header fields from a JSON object.
  ## Shared by emailFromJson and parsedEmailFromJson.
  ## JSON ``"from"`` key maps to ``fromAddr`` field (``from`` is a Nim keyword).
  let messageId = ?parseOptStringSeq(node, "messageId")
  let inReplyTo = ?parseOptStringSeq(node, "inReplyTo")
  let references = ?parseOptStringSeq(node, "references")
  let sender = ?parseOptAddresses(node, "sender")
  let fromAddr = ?parseOptAddresses(node, "from")
  let to = ?parseOptAddresses(node, "to")
  let cc = ?parseOptAddresses(node, "cc")
  let bcc = ?parseOptAddresses(node, "bcc")
  let replyTo = ?parseOptAddresses(node, "replyTo")
  let subject = parseOptString(node, "subject")
  let sentAt = ?parseOptDate(node, "sentAt")
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

func parseRawHeaders(node: JsonNode): Result[seq[EmailHeader], ValidationError] =
  ## Extracts the headers field (seq[EmailHeader]). Absent key yields empty seq.
  var hdrs: seq[EmailHeader] = @[]
  let headersNode = node{"headers"}
  if not headersNode.isNil and headersNode.kind == JArray:
    for elem in headersNode.getElems(@[]):
      hdrs.add(?EmailHeader.fromJson(elem))
  return ok(hdrs)

func parseBodyValues(
    node: JsonNode
): Result[Table[PartId, EmailBodyValue], ValidationError] =
  ## Parses bodyValues as Table[PartId, EmailBodyValue]. Absent/non-object
  ## yields empty table. Keys parsed via parsePartIdFromServer for typed
  ## PartId keys (D19).
  var bv = initTable[PartId, EmailBodyValue]()
  let bvNode = node{"bodyValues"}
  if not bvNode.isNil and bvNode.kind == JObject:
    for key, val in bvNode.pairs:
      let pid = ?parsePartIdFromServer(key)
      let ebv = ?EmailBodyValue.fromJson(val)
      bv[pid] = ebv
  return ok(bv)

func parseBodyPartArray(
    node: JsonNode, key: string
): Result[seq[EmailBodyPart], ValidationError] =
  ## Parses an optional array of EmailBodyPart: absent/non-array yields empty seq.
  var parts: seq[EmailBodyPart] = @[]
  let arrNode = node{key}
  if not arrNode.isNil and arrNode.kind == JArray:
    for elem in arrNode.getElems(@[]):
      parts.add(?EmailBodyPart.fromJson(elem))
  return ok(parts)

func parseBodyFields(node: JsonNode): Result[BodyFields, ValidationError] =
  ## Extracts the 7 body fields from a JSON object.
  ## Shared by emailFromJson and parsedEmailFromJson.
  let bodyStructure = ?EmailBodyPart.fromJson(node{"bodyStructure"})
  let bodyVals = ?parseBodyValues(node)
  let textBody = ?parseBodyPartArray(node, "textBody")
  let htmlBody = ?parseBodyPartArray(node, "htmlBody")
  let attachments = ?parseBodyPartArray(node, "attachments")

  # hasAttachment: absent/null defaults to false; non-bool rejected
  let haNode = node{"hasAttachment"}
  if not haNode.isNil and haNode.kind != JNull and haNode.kind != JBool:
    return err(parseError("Email", "hasAttachment must be boolean"))
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
    node: JsonNode, form: HeaderForm
): Result[seq[HeaderValue], ValidationError] =
  ## Parses a JSON array of header values for ``:all`` dynamic header properties.
  ## Each element parsed via parseHeaderValue with the given form.
  ?checkJsonKind(node, JArray, "Email", "header:*:all value must be array")
  var values: seq[HeaderValue] = @[]
  for elem in node.getElems(@[]):
    values.add(?parseHeaderValue(form, elem))
  return ok(values)

# =============================================================================
# emailFromJson
# =============================================================================

func emailFromJson*(node: JsonNode): Result[Email, ValidationError] =
  ## Deserialises a complete Email object from server JSON using two-phase
  ## strategy (D4). Phase 1: structured extraction of all standard properties.
  ## Phase 2: dynamic header discovery for ``header:`` prefixed keys.
  ## Does NOT call ``parseEmail`` — constructs Email directly (D15: lenient
  ## at server-to-client boundary, trust RFC contract).
  const typeName = "Email"
  ?checkJsonKind(node, JObject, typeName)

  # == Phase 1: Structured extraction ==

  # Metadata
  let id = ?Id.fromJson(node{"id"})
  let blobId = ?Id.fromJson(node{"blobId"})
  let threadId = ?Id.fromJson(node{"threadId"})
  let mailboxIds = ?MailboxIdSet.fromJson(node{"mailboxIds"})
  let keywords = block:
    let kwNode = node{"keywords"}
    if kwNode.isNil or kwNode.kind == JNull:
      initKeywordSet(newSeq[Keyword]())
    else:
      ?KeywordSet.fromJson(kwNode)
  let size = ?UnsignedInt.fromJson(node{"size"})
  let receivedAt = ?UTCDate.fromJson(node{"receivedAt"})

  # Convenience headers (shared helper)
  let convHeaders = ?parseConvenienceHeaders(node)

  # Raw headers
  let hdrs = ?parseRawHeaders(node)

  # Body (shared helper)
  let bf = ?parseBodyFields(node)

  # == Phase 2: Dynamic header discovery ==
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?parseHeaderPropertyName(key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val)

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

# =============================================================================
# parsedEmailFromJson
# =============================================================================

func parsedEmailFromJson*(node: JsonNode): Result[ParsedEmail, ValidationError] =
  ## Deserialises a ParsedEmail from server JSON (Email/parse response).
  ## Same two-phase strategy as emailFromJson but only threadId from metadata.
  ## Missing metadata fields (id, blobId, mailboxIds, keywords, size,
  ## receivedAt) are structurally absent — not extracted.
  const typeName = "ParsedEmail"
  ?checkJsonKind(node, JObject, typeName)

  # == Phase 1: Structured extraction ==

  # Metadata: only threadId survives
  let threadId = ?parseOptId(node, "threadId")

  # Convenience headers (shared helper)
  let convHeaders = ?parseConvenienceHeaders(node)

  # Raw headers
  let hdrs = ?parseRawHeaders(node)

  # Body (shared helper)
  let bf = ?parseBodyFields(node)

  # == Phase 2: Dynamic header discovery ==
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for key, val in node.pairs:
    if key.startsWith("header:"):
      let hpk = ?parseHeaderPropertyName(key)
      if hpk.isAll:
        reqHeadersAll[hpk] = ?parseHeaderValueArray(val, hpk.form)
      else:
        reqHeaders[hpk] = ?parseHeaderValue(hpk.form, val)

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

  # Metadata
  node["id"] = e.id.toJson()
  node["blobId"] = e.blobId.toJson()
  node["threadId"] = e.threadId.toJson()
  node["mailboxIds"] = e.mailboxIds.toJson()
  node["keywords"] = e.keywords.toJson()
  node["size"] = e.size.toJson()
  node["receivedAt"] = e.receivedAt.toJson()

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
  node["bodyStructure"] = e.bodyStructure.toJson()
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
  node["bodyStructure"] = pe.bodyStructure.toJson()
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
    node: JsonNode
): Result[EmailComparator, ValidationError] =
  ## Deserialises an EmailComparator by synthesising the discriminant from
  ## the property string value (D8). Tries KeywordSortProperty values first
  ## (require ``keyword`` field present), then PlainSortProperty values.
  ## Case-sensitive exact match on backing strings.
  const typeName = "EmailComparator"
  ?checkJsonKind(node, JObject, typeName)

  # Required property string
  let propNode = node{"property"}
  ?checkJsonKind(propNode, JString, typeName, "missing or invalid property")
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
      Opt.some(f.get().getStr(""))
    else:
      Opt.none(string)

  # Try keyword sort properties first (exact string match via $enum)
  for ksp in KeywordSortProperty:
    if $ksp == propStr:
      let kw = ?Keyword.fromJson(node{"keyword"})
      return ok(keywordComparator(ksp, kw, isAscending, collation))

  # Try plain sort properties
  for psp in PlainSortProperty:
    if $psp == propStr:
      return ok(plainComparator(psp, isAscending, collation))

  return err(parseError(typeName, "unknown sort property: " & propStr))

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
    node["collation"] = %v
  return node

# =============================================================================
# EmailBodyFetchOptions
# =============================================================================

func emitInto*(opts: EmailBodyFetchOptions, node: var JsonNode) =
  ## Emit body fetch option keys directly into target node.
  ## Shared by addEmailGet and addEmailParse — avoids toJson + merge loop.
  ## Maps ``BodyValueScope`` enum back to the three RFC booleans (D9).

  # bodyProperties: emit array when present
  for props in opts.bodyProperties:
    var arr = newJArray()
    for p in props:
      arr.add(p.toJson())
    node["bodyProperties"] = arr

  # fetchBodyValues enum to RFC booleans
  case opts.fetchBodyValues
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

  # maxBodyValueBytes: emit when present
  for v in opts.maxBodyValueBytes:
    node["maxBodyValueBytes"] = v.toJson()

func toJson*(opts: EmailBodyFetchOptions): JsonNode =
  ## Serialise EmailBodyFetchOptions to request JSON arguments.
  ## ``bvsNone`` omits all fetch keys; ``default(EmailBodyFetchOptions).toJson``
  ## produces ``{}``.
  var node = newJObject()
  opts.emitInto(node)
  return node

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
    T: typedesc[EmailCreatedItem], node: JsonNode
): Result[EmailCreatedItem, ValidationError] =
  ## Deserialise JSON to EmailCreatedItem. All four fields required per RFC;
  ## missing any field yields err — servers omitting any are malformed
  ## (Design §2.1, F2).
  ?checkJsonKind(node, JObject, $T)
  let id = ?Id.fromJson(node{"id"})
  let blobId = ?Id.fromJson(node{"blobId"})
  let threadId = ?Id.fromJson(node{"threadId"})
  let size = ?UnsignedInt.fromJson(node{"size"})
  return ok(EmailCreatedItem(id: id, blobId: blobId, threadId: threadId, size: size))

# =============================================================================
# UpdatedEntry
# =============================================================================

func toJson*(entry: UpdatedEntry): JsonNode =
  ## Serialise UpdatedEntry. uekUnchanged emits null (RFC 8620 §5.3 Foo|null
  ## inner split); uekChanged emits the raw changedProperties JsonNode.
  case entry.kind
  of uekUnchanged:
    newJNull()
  of uekChanged:
    entry.changedProperties

func fromJson*(
    T: typedesc[UpdatedEntry], node: JsonNode
): Result[UpdatedEntry, ValidationError] =
  ## Deserialise JSON to UpdatedEntry. null → uekUnchanged; object →
  ## uekChanged with the object as changedProperties.
  if node.isNil or node.kind == JNull:
    return ok(UpdatedEntry(kind: uekUnchanged))
  if node.kind == JObject:
    return ok(UpdatedEntry(kind: uekChanged, changedProperties: node))
  return err(validationError($T, "expected object or null", $node.kind))

# =============================================================================
# Email write-response shared helpers
# =============================================================================
# The three Email write responses (/set, /copy, /import) share envelope
# pieces: oldState, merged created/notCreated, and /set's four split maps.
# Extracting these as named helpers keeps each response's toJson/fromJson
# under the complexity budget while keeping intent at the call site.

func parseOptJmapStateField(
    node: JsonNode, key: string
): Result[Opt[JmapState], ValidationError] =
  ## Extracts an optional JmapState: absent/null yields none.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(JmapState))
  return ok(Opt.some(?JmapState.fromJson(field)))

func mergeCreatedResults(
    node: JsonNode
): Result[Table[CreationId, Result[EmailCreatedItem, SetError]], ValidationError] =
  ## Merges wire ``created`` and ``notCreated`` maps into a single Table
  ## keyed by CreationId, with per-entry Result carrying either the typed
  ## EmailCreatedItem (ok) or SetError (err). Design §2.1, F2.
  var tbl = initTable[CreationId, Result[EmailCreatedItem, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?parseCreationId(k)
      let item = ?EmailCreatedItem.fromJson(v)
      tbl[cid] = Result[EmailCreatedItem, SetError].ok(item)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?parseCreationId(k)
      let se = ?SetError.fromJson(v)
      tbl[cid] = Result[EmailCreatedItem, SetError].err(se)
  return ok(tbl)

func parseOptUpdatedMap(
    node: JsonNode, key, typeName: string
): Result[Opt[Table[Id, UpdatedEntry]], ValidationError] =
  ## Parses RFC 8620 §5.3 ``Id[Foo|null]|null`` — outer Opt = map
  ## absent/null; per-entry ``UpdatedEntry`` encodes the inner split.
  let sub = node{key}
  if sub.isNil or sub.kind == JNull:
    return ok(Opt.none(Table[Id, UpdatedEntry]))
  ?checkJsonKind(sub, JObject, typeName, key & " must be object or null")
  var tbl = initTable[Id, UpdatedEntry]()
  for k, v in sub.pairs:
    let id = ?parseIdFromServer(k)
    tbl[id] = ?UpdatedEntry.fromJson(v)
  return ok(Opt.some(tbl))

func parseOptSetErrorMap(
    node: JsonNode, key, typeName: string
): Result[Opt[Table[Id, SetError]], ValidationError] =
  ## Parses ``notUpdated`` / ``notDestroyed`` maps: absent/null yields
  ## none; object yields ``Table[Id, SetError]``.
  let sub = node{key}
  if sub.isNil or sub.kind == JNull:
    return ok(Opt.none(Table[Id, SetError]))
  ?checkJsonKind(sub, JObject, typeName, key & " must be object or null")
  var tbl = initTable[Id, SetError]()
  for k, v in sub.pairs:
    let id = ?parseIdFromServer(k)
    tbl[id] = ?SetError.fromJson(v)
  return ok(Opt.some(tbl))

func parseOptDestroyedIds(
    node: JsonNode, typeName: string
): Result[Opt[seq[Id]], ValidationError] =
  ## Parses the ``destroyed`` array: absent/null yields none.
  let sub = node{"destroyed"}
  if sub.isNil or sub.kind == JNull:
    return ok(Opt.none(seq[Id]))
  ?checkJsonKind(sub, JArray, typeName, "destroyed must be array or null")
  var ids: seq[Id] = @[]
  for elem in sub.getElems(@[]):
    ids.add(?parseIdFromServer(elem.getStr("")))
  return ok(Opt.some(ids))

func emitCreateResults(
    createResults: Table[CreationId, Result[EmailCreatedItem, SetError]], node: JsonNode
) =
  ## Splits a merged createResults Table back into the wire
  ## ``created`` and ``notCreated`` maps; omits either key when empty.
  var created = newJObject()
  var notCreated = newJObject()
  for cid, r in createResults:
    if r.isOk:
      created[string(cid)] = r.get().toJson()
    else:
      notCreated[string(cid)] = r.error.toJson()
  if created.len > 0:
    node["created"] = created
  if notCreated.len > 0:
    node["notCreated"] = notCreated

func emitOptIdUpdatedMap(
    node: JsonNode, key: string, tbl: Opt[Table[Id, UpdatedEntry]]
) =
  ## Emits the ``updated`` map when present; omits the key otherwise.
  for t in tbl:
    var obj = newJObject()
    for id, entry in t:
      obj[string(id)] = entry.toJson()
    node[key] = obj

func emitOptIdSetErrorMap(node: JsonNode, key: string, tbl: Opt[Table[Id, SetError]]) =
  ## Emits ``notUpdated`` / ``notDestroyed`` maps when present; omits
  ## the key otherwise.
  for t in tbl:
    var obj = newJObject()
    for id, se in t:
      obj[string(id)] = se.toJson()
    node[key] = obj

func emitOptDestroyedIds(node: JsonNode, ids: Opt[seq[Id]]) =
  ## Emits the ``destroyed`` array when present; omits the key otherwise.
  for xs in ids:
    var arr = newJArray()
    for id in xs:
      arr.add(id.toJson())
    node["destroyed"] = arr

# =============================================================================
# EmailSetResponse
# =============================================================================

func toJson*(resp: EmailSetResponse): JsonNode =
  ## Serialise EmailSetResponse (RFC 8621 §4.6, envelope RFC 8620 §5.3).
  ## Splits createResults back into wire created/notCreated maps.
  var node = newJObject()
  node["accountId"] = resp.accountId.toJson()
  for s in resp.oldState:
    node["oldState"] = s.toJson()
  node["newState"] = resp.newState.toJson()
  emitCreateResults(resp.createResults, node)
  emitOptIdUpdatedMap(node, "updated", resp.updated)
  emitOptIdSetErrorMap(node, "notUpdated", resp.notUpdated)
  emitOptDestroyedIds(node, resp.destroyed)
  emitOptIdSetErrorMap(node, "notDestroyed", resp.notDestroyed)
  return node

func fromJson*(
    T: typedesc[EmailSetResponse], node: JsonNode
): Result[EmailSetResponse, ValidationError] =
  ## Deserialise JSON to EmailSetResponse (RFC 8621 §4.6).
  ## Merges wire created/notCreated into typed createResults. updated/
  ## notUpdated and destroyed/notDestroyed stay split per the typed response
  ## shape (Design §2.2, F2.1).
  ?checkJsonKind(node, JObject, $T)
  let accountId = ?AccountId.fromJson(node{"accountId"})
  let newState = ?JmapState.fromJson(node{"newState"})
  let oldState = ?parseOptJmapStateField(node, "oldState")
  let createResults = ?mergeCreatedResults(node)
  let updated = ?parseOptUpdatedMap(node, "updated", $T)
  let notUpdated = ?parseOptSetErrorMap(node, "notUpdated", $T)
  let destroyed = ?parseOptDestroyedIds(node, $T)
  let notDestroyed = ?parseOptSetErrorMap(node, "notDestroyed", $T)
  return ok(
    EmailSetResponse(
      accountId: accountId,
      oldState: oldState,
      newState: newState,
      createResults: createResults,
      updated: updated,
      notUpdated: notUpdated,
      destroyed: destroyed,
      notDestroyed: notDestroyed,
    )
  )

# =============================================================================
# EmailCopyResponse
# =============================================================================

func toJson*(resp: EmailCopyResponse): JsonNode =
  ## Serialise EmailCopyResponse (RFC 8621 §4.7). Splits createResults back
  ## into wire created/notCreated; no updated/destroyed fields.
  var node = newJObject()
  node["fromAccountId"] = resp.fromAccountId.toJson()
  node["accountId"] = resp.accountId.toJson()
  for s in resp.oldState:
    node["oldState"] = s.toJson()
  node["newState"] = resp.newState.toJson()
  emitCreateResults(resp.createResults, node)
  return node

func fromJson*(
    T: typedesc[EmailCopyResponse], node: JsonNode
): Result[EmailCopyResponse, ValidationError] =
  ## Deserialise JSON to EmailCopyResponse (RFC 8621 §4.7).
  ?checkJsonKind(node, JObject, $T)
  let fromAccountId = ?AccountId.fromJson(node{"fromAccountId"})
  let accountId = ?AccountId.fromJson(node{"accountId"})
  let newState = ?JmapState.fromJson(node{"newState"})
  let oldState = ?parseOptJmapStateField(node, "oldState")
  let createResults = ?mergeCreatedResults(node)
  return ok(
    EmailCopyResponse(
      fromAccountId: fromAccountId,
      accountId: accountId,
      oldState: oldState,
      newState: newState,
      createResults: createResults,
    )
  )

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
  node["newState"] = resp.newState.toJson()
  emitCreateResults(resp.createResults, node)
  return node

func fromJson*(
    T: typedesc[EmailImportResponse], node: JsonNode
): Result[EmailImportResponse, ValidationError] =
  ## Deserialise JSON to EmailImportResponse (RFC 8621 §4.8).
  ?checkJsonKind(node, JObject, $T)
  let accountId = ?AccountId.fromJson(node{"accountId"})
  let newState = ?JmapState.fromJson(node{"newState"})
  let oldState = ?parseOptJmapStateField(node, "oldState")
  let createResults = ?mergeCreatedResults(node)
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
  let tbl = Table[CreationId, EmailImportItem](m)
  var node = newJObject()
  for cid, item in tbl:
    node[string(cid)] = item.toJson()
  return node
