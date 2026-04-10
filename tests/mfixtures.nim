# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared test fixture factories. Returns fresh instances to avoid module-level
## mutation risk. Imported by t-prefixed test files.
##
## When adding a new type <T>:
## 1. Add parse<T>() smart constructor in Layer 1 source module
## 2. Add make<T>() factory function below
## 3. Add toJson/fromJson in Layer 2 serde module
## 4. Add unit tests in tests/unit/t<module>.nim
## 5. Add serde round-trip tests in tests/serde/tserde_<module>.nim
## 6. Add property tests + generator in tests/property/tprop_<module>.nim
## 7. Add gen<T>() generator to tests/mproperty.nim

import std/sets
import std/tables
import std/json

{.push ruleOff: "hasDoc".}

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/framework
import jmap_client/envelope
import jmap_client/errors

import jmap_client/mail/types
import jmap_client/mail/email
import jmap_client/mail/snippet
import jmap_client/mail/serde_email
import jmap_client/mail/serde_snippet

proc zeroUint*(): UnsignedInt =
  parseUnsignedInt(0).get()

proc makeMaxChanges*(n: int64 = 100): MaxChanges =
  parseMaxChanges(parseUnsignedInt(n).get()).get()

proc makeId*(s = "testId"): Id =
  parseId(s).get()

proc makeMcid*(s = "c0"): MethodCallId =
  parseMethodCallId(s).get()

proc makeCreationId*(s = "k0"): CreationId =
  parseCreationId(s).get()

proc makeState*(s = "state0"): JmapState =
  parseJmapState(s).get()

proc makeAccountId*(s = "acct1"): AccountId =
  parseAccountId(s).get()

proc makePropertyName*(s = "subject"): PropertyName =
  parsePropertyName(s).get()

proc makeUriTemplate*(s = "https://example.com/{accountId}"): UriTemplate =
  parseUriTemplate(s).get()

proc zeroCoreCaps*(): CoreCapabilities =
  let z = zeroUint()
  CoreCapabilities(
    maxSizeUpload: z,
    maxConcurrentUpload: z,
    maxSizeRequest: z,
    maxConcurrentRequests: z,
    maxCallsInRequest: z,
    maxObjectsInGet: z,
    maxObjectsInSet: z,
    collationAlgorithms: initHashSet[string](),
  )

proc realisticCoreCaps*(): CoreCapabilities =
  CoreCapabilities(
    maxSizeUpload: parseUnsignedInt(50_000_000).get(),
    maxConcurrentUpload: parseUnsignedInt(4).get(),
    maxSizeRequest: parseUnsignedInt(10_000_000).get(),
    maxConcurrentRequests: parseUnsignedInt(8).get(),
    maxCallsInRequest: parseUnsignedInt(32).get(),
    maxObjectsInGet: parseUnsignedInt(1000).get(),
    maxObjectsInSet: parseUnsignedInt(500).get(),
    collationAlgorithms: toHashSet(["i;ascii-casemap", "i;unicode-casemap"]),
  )

proc makeCoreCapsWithLimits*(
    maxCallsInRequest: int64 = 32,
    maxObjectsInGet: int64 = 1000,
    maxObjectsInSet: int64 = 500,
): CoreCapabilities =
  ## CoreCapabilities with caller-specified limit fields; zeroes elsewhere.
  CoreCapabilities(
    maxSizeUpload: zeroUint(),
    maxConcurrentUpload: zeroUint(),
    maxSizeRequest: zeroUint(),
    maxConcurrentRequests: zeroUint(),
    maxCallsInRequest: parseUnsignedInt(maxCallsInRequest).get(),
    maxObjectsInGet: parseUnsignedInt(maxObjectsInGet).get(),
    maxObjectsInSet: parseUnsignedInt(maxObjectsInSet).get(),
    collationAlgorithms: initHashSet[string](),
  )

proc makeCoreServerCap*(caps = zeroCoreCaps()): ServerCapability =
  ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: caps)

proc makeGoldenDownloadUrl*(): UriTemplate =
  parseUriTemplate(
    "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}"
  )
    .get()

proc makeGoldenUploadUrl*(): UriTemplate =
  parseUriTemplate("https://jmap.example.com/upload/{accountId}/").get()

proc makeGoldenEventSourceUrl*(): UriTemplate =
  parseUriTemplate(
    "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}"
  )
    .get()

type SessionArgs* =
  tuple[
    capabilities: seq[ServerCapability],
    accounts: Table[AccountId, Account],
    primaryAccounts: Table[string, AccountId],
    username: string,
    apiUrl: string,
    downloadUrl: UriTemplate,
    uploadUrl: UriTemplate,
    eventSourceUrl: UriTemplate,
    state: JmapState,
  ]

proc tryParseSessionFromArgs*(args: SessionArgs): Result[Session, ValidationError] =
  ## Convenience wrapper returning Result for error tests.
  parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )

proc parseSessionFromArgs*(args: SessionArgs): Session =
  ## Convenience wrapper around the 9-argument parseSession.
  tryParseSessionFromArgs(args).get()

proc makeSessionArgs*(): SessionArgs =
  var accounts = initTable[AccountId, Account]()
  accounts[makeAccountId("A1")] =
    Account(name: "test", isPersonal: true, isReadOnly: false, accountCapabilities: @[])
  var primaryAccounts = initTable[string, AccountId]()
  primaryAccounts["urn:ietf:params:jmap:mail"] = makeAccountId("A1")
  result = (
    capabilities: @[makeCoreServerCap()],
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: "test@example.com",
    apiUrl: "https://jmap.example.com/api/",
    downloadUrl: makeGoldenDownloadUrl(),
    uploadUrl: makeGoldenUploadUrl(),
    eventSourceUrl: makeGoldenEventSourceUrl(),
    state: makeState("s1"),
  )

# ---------------------------------------------------------------------------
# Envelope factories
# ---------------------------------------------------------------------------

proc makeInvocation*(name = "Mailbox/get", mcid = makeMcid("c0")): Invocation =
  initInvocation(name, newJObject(), mcid).get()

proc makeRequest*(
    `using`: seq[string] = @["urn:ietf:params:jmap:core"],
    methodCalls: seq[Invocation] = @[makeInvocation()],
    createdIds = Opt.none(Table[CreationId, Id]),
): Request =
  Request(`using`: `using`, methodCalls: methodCalls, createdIds: createdIds)

proc makeResponse*(
    methodResponses: seq[Invocation] = @[makeInvocation()],
    state = makeState("rs1"),
    createdIds = Opt.none(Table[CreationId, Id]),
): Response =
  Response(
    methodResponses: methodResponses, createdIds: createdIds, sessionState: state
  )

proc makeResultReference*(
    mcid = makeMcid("c0"), name = "Mailbox/get", path = RefPathIds
): ResultReference =
  initResultReference(resultOf = mcid, name = name, path = path)

# ---------------------------------------------------------------------------
# Error factories
# ---------------------------------------------------------------------------

proc makeRequestError*(
    rawType = "urn:ietf:params:jmap:error:unknownCapability"
): RequestError =
  requestError(rawType)

proc makeMethodError*(rawType = "serverFail"): MethodError =
  methodError(rawType)

# ---------------------------------------------------------------------------
# Server fixture factories
# ---------------------------------------------------------------------------

proc makeFastmailSession*(): SessionArgs =
  ## Realistic Fastmail-style session with vendor extensions.
  var accounts = initTable[AccountId, Account]()
  let acctId = makeAccountId("u1f5a6e2c")
  accounts[acctId] = Account(
    name: "user@fastmail.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[
      AccountCapabilityEntry(
        kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJObject()
      ),
      AccountCapabilityEntry(
        kind: ckSubmission,
        rawUri: "urn:ietf:params:jmap:submission",
        data: newJObject(),
      ),
      AccountCapabilityEntry(
        kind: ckUnknown,
        rawUri: "https://www.fastmail.com/dev/contacts",
        data: newJObject(),
      ),
    ],
  )
  var primaryAccounts = initTable[string, AccountId]()
  primaryAccounts["urn:ietf:params:jmap:mail"] = acctId
  primaryAccounts["urn:ietf:params:jmap:submission"] = acctId
  primaryAccounts["https://www.fastmail.com/dev/contacts"] = acctId
  result = (
    capabilities: @[
      makeCoreServerCap(realisticCoreCaps()),
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJObject()
      ),
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:submission",
        kind: ckSubmission,
        rawData: newJObject(),
      ),
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:vacationresponse",
        kind: ckVacationResponse,
        rawData: newJObject(),
      ),
      ServerCapability(
        rawUri: "https://www.fastmail.com/dev/contacts",
        kind: ckUnknown,
        rawData: newJObject(),
      ),
      ServerCapability(
        rawUri: "https://www.fastmail.com/dev/blob",
        kind: ckUnknown,
        rawData: newJObject(),
      ),
    ],
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: "user@fastmail.com",
    apiUrl: "https://api.fastmail.com/jmap/",
    downloadUrl: makeGoldenDownloadUrl(),
    uploadUrl: makeGoldenUploadUrl(),
    eventSourceUrl: makeGoldenEventSourceUrl(),
    state: makeState("cyrus-12345"),
  )

proc makeMinimalSession*(): SessionArgs =
  ## Bare minimum valid session: ckCore only, empty accounts.
  result = (
    capabilities: @[makeCoreServerCap()],
    accounts: initTable[AccountId, Account](),
    primaryAccounts: initTable[string, AccountId](),
    username: "",
    apiUrl: "https://jmap.example.com/api/",
    downloadUrl: makeGoldenDownloadUrl(),
    uploadUrl: makeGoldenUploadUrl(),
    eventSourceUrl: makeGoldenEventSourceUrl(),
    state: makeState("s0"),
  )

# ---------------------------------------------------------------------------
# SetError variant factories
# ---------------------------------------------------------------------------

proc makeSetErrorInvalidProperties*(
    properties: seq[string] = @["from", "subject"],
    description: Opt[string] = Opt.none(string),
): SetError =
  setErrorInvalidProperties("invalidProperties", properties, description)

proc makeSetErrorAlreadyExists*(
    existingId: Id = makeId("existing1"), description: Opt[string] = Opt.none(string)
): SetError =
  setErrorAlreadyExists("alreadyExists", existingId, description)

# ---------------------------------------------------------------------------
# Framework factories
# ---------------------------------------------------------------------------

proc makeComparator*(
    property: PropertyName = makePropertyName("subject"), isAscending = true
): Comparator =
  parseComparator(property, isAscending)

proc makeComparatorWithCollation*(
    property: PropertyName = makePropertyName("subject"),
    isAscending = true,
    collation = "i;unicode-casemap",
): Comparator =
  parseComparator(property, isAscending, Opt.some(collation))

proc makeAddedItem*(id: Id = makeId("item1"), index: int64 = 0): AddedItem =
  initAddedItem(id, parseUnsignedInt(index).get())

# ---------------------------------------------------------------------------
# Filter factories
# ---------------------------------------------------------------------------

proc makeFilterCondition*(condition = 42): Filter[int] =
  filterCondition(condition)

proc makeFilterAnd*(children: seq[Filter[int]]): Filter[int] =
  filterOperator[int](foAnd, children)

proc makeFilterOr*(children: seq[Filter[int]]): Filter[int] =
  filterOperator[int](foOr, children)

# ---------------------------------------------------------------------------
# Additional session fixture
# ---------------------------------------------------------------------------

proc makeCyrusSession*(): SessionArgs =
  ## Cyrus IMAP style session with lenient account IDs.
  var accounts = initTable[AccountId, Account]()
  let acctId = makeAccountId("uid=12345")
  accounts[acctId] = Account(
    name: "admin@cyrus.example.com",
    isPersonal: true,
    isReadOnly: false,
    accountCapabilities: @[
      AccountCapabilityEntry(
        kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJObject()
      )
    ],
  )
  var primaryAccounts = initTable[string, AccountId]()
  primaryAccounts["urn:ietf:params:jmap:mail"] = acctId
  result = (
    capabilities: @[
      makeCoreServerCap(realisticCoreCaps()),
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJObject()
      ),
    ],
    accounts: accounts,
    primaryAccounts: primaryAccounts,
    username: "admin@cyrus.example.com",
    apiUrl: "https://cyrus.example.com/.well-known/jmap",
    downloadUrl: makeGoldenDownloadUrl(),
    uploadUrl: makeGoldenUploadUrl(),
    eventSourceUrl: makeGoldenEventSourceUrl(),
    state: makeState("cyrus-abcdef"),
  )

# ---------------------------------------------------------------------------
# Mail Part D factories
# ---------------------------------------------------------------------------

proc makeSearchSnippet*(
    emailId: Id = makeId("email1"),
    subject: Opt[string] = Opt.none(string),
    preview: Opt[string] = Opt.none(string),
): SearchSnippet =
  SearchSnippet(emailId: emailId, subject: subject, preview: preview)

proc makeEmailHeaderFilter*(
    name = "Subject", value: Opt[string] = Opt.none(string)
): EmailHeaderFilter =
  parseEmailHeaderFilter(name, value).get()

proc makeEmailFilterCondition*(): EmailFilterCondition =
  ## All-none filter — matches everything. Baseline for toJson tests.
  default(EmailFilterCondition)

proc makeEmailComparator*(): EmailComparator =
  plainComparator(pspReceivedAt)

proc makeKeywordComparator*(): EmailComparator =
  keywordComparator(kspHasKeyword, kwSeen)

proc makeEmailBodyFetchOptions*(): EmailBodyFetchOptions =
  default(EmailBodyFetchOptions)

proc makeLeafBodyPart*(): EmailBodyPart =
  ## Minimal leaf EmailBodyPart for Email fixture construction.
  EmailBodyPart(
    isMultipart: false,
    contentType: "text/plain",
    size: zeroUint(),
    partId: parsePartIdFromServer("1").get(),
    blobId: makeId("blob1"),
    headers: @[],
    name: Opt.none(string),
    charset: Opt.none(string),
    disposition: Opt.none(string),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

proc makeEmail*(): Email =
  ## Minimal valid Email satisfying parseEmail (non-empty mailboxIds).
  let leaf = makeLeafBodyPart()
  parseEmail(
    Email(
      id: makeId("email1"),
      blobId: makeId("blob1"),
      threadId: makeId("thread1"),
      mailboxIds: initMailboxIdSet(@[makeId("mbx1")]),
      keywords: initKeywordSet(@[]),
      size: zeroUint(),
      receivedAt: parseUtcDate("2025-01-15T09:00:00Z").get(),
      messageId: Opt.none(seq[string]),
      inReplyTo: Opt.none(seq[string]),
      references: Opt.none(seq[string]),
      sender: Opt.none(seq[EmailAddress]),
      fromAddr: Opt.none(seq[EmailAddress]),
      to: Opt.none(seq[EmailAddress]),
      cc: Opt.none(seq[EmailAddress]),
      bcc: Opt.none(seq[EmailAddress]),
      replyTo: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      sentAt: Opt.none(Date),
      headers: @[],
      requestedHeaders: initTable[HeaderPropertyKey, HeaderValue](),
      requestedHeadersAll: initTable[HeaderPropertyKey, seq[HeaderValue]](),
      bodyStructure: leaf,
      bodyValues: initTable[PartId, EmailBodyValue](),
      textBody: @[],
      htmlBody: @[],
      attachments: @[],
      hasAttachment: false,
      preview: "",
    )
  )
    .get()

proc makeParsedEmail*(): ParsedEmail =
  ## Minimal ParsedEmail (threadId = Opt.none).
  let leaf = makeLeafBodyPart()
  ParsedEmail(
    threadId: Opt.none(Id),
    messageId: Opt.none(seq[string]),
    inReplyTo: Opt.none(seq[string]),
    references: Opt.none(seq[string]),
    sender: Opt.none(seq[EmailAddress]),
    fromAddr: Opt.none(seq[EmailAddress]),
    to: Opt.none(seq[EmailAddress]),
    cc: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    replyTo: Opt.none(seq[EmailAddress]),
    subject: Opt.none(string),
    sentAt: Opt.none(Date),
    headers: @[],
    requestedHeaders: initTable[HeaderPropertyKey, HeaderValue](),
    requestedHeadersAll: initTable[HeaderPropertyKey, seq[HeaderValue]](),
    bodyStructure: leaf,
    bodyValues: initTable[PartId, EmailBodyValue](),
    textBody: @[],
    htmlBody: @[],
    attachments: @[],
    hasAttachment: false,
    preview: "",
  )

# ---------------------------------------------------------------------------
# Layer 2 JSON fixtures (for serde tests)
# ---------------------------------------------------------------------------

proc validCoreCapsJson*(): JsonNode =
  ## Minimal valid CoreCapabilities JSON (all fields = 1, empty collation).
  %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
  }

proc goldenRequestJson*(): JsonNode =
  ## RFC 8620 section 3.3.1 golden Request JSON.
  %*{
    "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    "methodCalls": [
      ["method1", {"arg1": "arg1data", "arg2": "arg2data"}, "c1"],
      ["method2", {"arg1": "arg1data"}, "c2"],
      ["method3", {}, "c3"],
    ],
  }

proc goldenResponseJson*(): JsonNode =
  ## RFC 8620 section 3.4.1 golden Response JSON.
  %*{
    "methodResponses": [
      ["method1", {"arg1": 3, "arg2": "foo"}, "c1"],
      ["method2", {"isBlah": true}, "c2"],
      ["anotherResponseFromMethod2", {"data": 10, "yetmoredata": "Hello"}, "c2"],
      ["error", {"type": "unknownMethod"}, "c3"],
    ],
    "sessionState": "75128aab4b1b",
  }

proc validRequestJson*(): JsonNode =
  ## Minimal valid Request JSON.
  %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": [["Mailbox/get", {}, "c0"]]}

proc validResponseJson*(): JsonNode =
  ## Minimal valid Response JSON.
  %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": "s1"}

proc goldenSessionJson*(): JsonNode =
  ## RFC 8620 section 2.1 golden Session JSON.
  %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 50000000,
        "maxConcurrentUpload": 8,
        "maxSizeRequest": 10000000,
        "maxConcurrentRequest": 8,
        "maxCallsInRequest": 32,
        "maxObjectsInGet": 256,
        "maxObjectsInSet": 128,
        "collationAlgorithms":
          ["i;ascii-numeric", "i;ascii-casemap", "i;unicode-casemap"],
      },
      "urn:ietf:params:jmap:mail": {},
      "urn:ietf:params:jmap:contacts": {},
      "https://example.com/apis/foobar": {"maxFoosFinangled": 42},
    },
    "accounts": {
      "A13824": {
        "name": "john@example.com",
        "isPersonal": true,
        "isReadOnly": false,
        "accountCapabilities":
          {"urn:ietf:params:jmap:mail": {}, "urn:ietf:params:jmap:contacts": {}},
      },
      "A97813": {
        "name": "jane@example.com",
        "isPersonal": false,
        "isReadOnly": true,
        "accountCapabilities": {"urn:ietf:params:jmap:mail": {}},
      },
    },
    "primaryAccounts":
      {"urn:ietf:params:jmap:mail": "A13824", "urn:ietf:params:jmap:contacts": "A13824"},
    "username": "john@example.com",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "75128aab4b1b",
  }

proc validSessionJson*(): JsonNode =
  ## Minimal valid Session JSON for edge-case modifications.
  %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 1,
        "maxConcurrentUpload": 1,
        "maxSizeRequest": 1,
        "maxConcurrentRequests": 1,
        "maxCallsInRequest": 1,
        "maxObjectsInGet": 1,
        "maxObjectsInSet": 1,
        "collationAlgorithms": [],
      }
    },
    "accounts": {},
    "primaryAccounts": {},
    "username": "",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "s1",
  }

# ---------------------------------------------------------------------------
# Case object equality helpers
# ---------------------------------------------------------------------------

proc coreCapEq*(a, b: CoreCapabilities): bool =
  ## Field-by-field equality for CoreCapabilities, using subset check for
  ## HashSet collationAlgorithms (avoids megatest == resolution issues).
  a.maxSizeUpload == b.maxSizeUpload and a.maxConcurrentUpload == b.maxConcurrentUpload and
    a.maxSizeRequest == b.maxSizeRequest and
    a.maxConcurrentRequests == b.maxConcurrentRequests and
    a.maxCallsInRequest == b.maxCallsInRequest and a.maxObjectsInGet == b.maxObjectsInGet and
    a.maxObjectsInSet == b.maxObjectsInSet and
    a.collationAlgorithms.len == b.collationAlgorithms.len and
    a.collationAlgorithms <= b.collationAlgorithms

proc capEq*(a, b: ServerCapability): bool =
  ## Deep value equality for ServerCapability (case object).
  if a.kind != b.kind or a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckCore:
    coreCapEq(a.core, b.core)
  else:
    a.rawData == b.rawData

proc capsEq*(a, b: seq[ServerCapability]): bool =
  ## Compares two sequences of ServerCapability by value.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if not capEq(a[i], b[i]):
      return false
  true

proc sessionEq*(a, b: Session): bool =
  ## Deep value equality for Session (contains seq[ServerCapability]).
  capsEq(a.capabilities, b.capabilities) and a.accounts == b.accounts and
    a.primaryAccounts == b.primaryAccounts and a.username == b.username and
    a.apiUrl == b.apiUrl and a.downloadUrl == b.downloadUrl and
    a.uploadUrl == b.uploadUrl and a.eventSourceUrl == b.eventSourceUrl and
    a.state == b.state

proc invEq*(a, b: Invocation): bool =
  ## Structural equality for Invocation including arguments.
  a.name == b.name and a.methodCallId == b.methodCallId and a.arguments == b.arguments

proc reqEq*(a, b: Request): bool =
  ## Structural equality for Request including methodCalls order.
  if a.using != b.using:
    return false
  if a.methodCalls.len != b.methodCalls.len:
    return false
  for i in 0 ..< a.methodCalls.len:
    if not invEq(a.methodCalls[i], b.methodCalls[i]):
      return false
  if a.createdIds.isSome != b.createdIds.isSome:
    return false
  if a.createdIds.isSome:
    if a.createdIds.get().len != b.createdIds.get().len:
      return false
  true

proc respEq*(a, b: Response): bool =
  ## Structural equality for Response including methodResponses order.
  if a.sessionState != b.sessionState:
    return false
  if a.methodResponses.len != b.methodResponses.len:
    return false
  for i in 0 ..< a.methodResponses.len:
    if not invEq(a.methodResponses[i], b.methodResponses[i]):
      return false
  if a.createdIds.isSome != b.createdIds.isSome:
    return false
  true

proc filterEq*(a, b: Filter[int]): bool =
  ## Recursive structural equality for Filter[int] trees.
  if a.kind != b.kind:
    return false
  case a.kind
  of fkCondition:
    a.condition == b.condition
  of fkOperator:
    if a.operator != b.operator:
      return false
    if a.conditions.len != b.conditions.len:
      return false
    for i in 0 ..< a.conditions.len:
      if not filterEq(a.conditions[i], b.conditions[i]):
        return false
    true

proc setErrorEq*(a, b: SetError): bool =
  ## Deep value equality for SetError (case object), including extras.
  if a.rawType != b.rawType or a.errorType != b.errorType or
      a.description != b.description or a.extras != b.extras:
    return false
  case a.errorType
  of setInvalidProperties:
    a.properties == b.properties
  of setAlreadyExists:
    a.existingId == b.existingId
  else:
    true

# ---------------------------------------------------------------------------
# Mail Part D equality helpers
# ---------------------------------------------------------------------------

proc headerValueEq*(a, b: HeaderValue): bool =
  ## Deep value equality for HeaderValue (case object discriminated by
  ## HeaderForm). Case objects lack reliable auto-generated ``==``.
  if a.form != b.form:
    return false
  case a.form
  of hfRaw:
    a.rawValue == b.rawValue
  of hfText:
    a.textValue == b.textValue
  of hfAddresses:
    a.addresses == b.addresses
  of hfGroupedAddresses:
    a.groups == b.groups
  of hfMessageIds:
    a.messageIds == b.messageIds
  of hfDate:
    a.date == b.date
  of hfUrls:
    a.urls == b.urls

proc bodyPartCoreFieldsEq(a, b: EmailBodyPart): bool =
  ## Compares discriminant, content-type, and structural fields.
  a.contentType == b.contentType and a.isMultipart == b.isMultipart and
    a.headers == b.headers and a.name == b.name and a.size == b.size

proc bodyPartOptFieldsEq(a, b: EmailBodyPart): bool =
  ## Compares optional MIME metadata fields.
  a.charset == b.charset and a.disposition == b.disposition and a.cid == b.cid and
    a.language == b.language and a.location == b.location

proc bodyPartEq*(a, b: EmailBodyPart): bool =
  ## Recursive structural equality for EmailBodyPart (case object
  ## discriminated by ``isMultipart``). Delegates shared fields to
  ## ``bodyPartSharedFieldsEq``, then compares branch-specific fields.
  if not bodyPartCoreFieldsEq(a, b) or not bodyPartOptFieldsEq(a, b):
    return false
  if a.isMultipart:
    if a.subParts.len != b.subParts.len:
      return false
    for i in 0 ..< a.subParts.len:
      if not bodyPartEq(a.subParts[i], b.subParts[i]):
        return false
    return true
  a.partId == b.partId and a.blobId == b.blobId

proc headerTableEq*(a, b: Table[HeaderPropertyKey, HeaderValue]): bool =
  ## Value equality for dynamic header tables. Delegates to ``headerValueEq``
  ## for case-object values.
  if a.len != b.len:
    return false
  for key, val in a:
    if key notin b:
      return false
    if not headerValueEq(val, b[key]):
      return false
  true

proc headerTableAllEq*(a, b: Table[HeaderPropertyKey, seq[HeaderValue]]): bool =
  ## Value equality for ``:all`` dynamic header tables. Element-wise
  ## ``headerValueEq`` on each seq.
  if a.len != b.len:
    return false
  for key, vals in a:
    if key notin b:
      return false
    let bVals = b[key]
    if vals.len != bVals.len:
      return false
    for i in 0 ..< vals.len:
      if not headerValueEq(vals[i], bVals[i]):
        return false
  true

proc bodyPartSeqEq*(a, b: seq[EmailBodyPart]): bool =
  ## Element-wise ``bodyPartEq`` for body part sequences.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if not bodyPartEq(a[i], b[i]):
      return false
  true

# Generic sub-helpers for field groups shared between Email and ParsedEmail.
# Mirrors D7's shared serde helper decomposition (parseConvenienceHeaders,
# parseBodyFields). Generic over T so both types use the same comparison logic.

proc convStringHeadersEq[T](a, b: T): bool =
  ## Compares string/date convenience headers (5 fields).
  a.messageId == b.messageId and a.inReplyTo == b.inReplyTo and
    a.references == b.references and a.subject == b.subject and a.sentAt == b.sentAt

proc convAddressHeadersEq[T](a, b: T): bool =
  ## Compares address convenience headers (6 fields).
  a.sender == b.sender and a.fromAddr == b.fromAddr and a.to == b.to and a.cc == b.cc and
    a.bcc == b.bcc and a.replyTo == b.replyTo

proc bodyFieldsEq[T](a, b: T): bool =
  ## Compares body fields (7 fields). Delegates to ``bodyPartEq`` and
  ## ``bodyPartSeqEq`` for case-object fields.
  bodyPartEq(a.bodyStructure, b.bodyStructure) and a.bodyValues == b.bodyValues and
    bodyPartSeqEq(a.textBody, b.textBody) and bodyPartSeqEq(a.htmlBody, b.htmlBody) and
    bodyPartSeqEq(a.attachments, b.attachments) and a.hasAttachment == b.hasAttachment and
    a.preview == b.preview

proc emailMetadataEq(a, b: Email): bool =
  ## Compares Email metadata fields (7 fields). Unwraps distinct HashSet types
  ## that have no ``==`` (excluded by ``defineHashSetDistinctOps``).
  a.id == b.id and a.blobId == b.blobId and a.threadId == b.threadId and
    HashSet[Id](a.mailboxIds) == HashSet[Id](b.mailboxIds) and
    HashSet[Keyword](a.keywords) == HashSet[Keyword](b.keywords) and a.size == b.size and
    a.receivedAt == b.receivedAt

proc emailEq*(a, b: Email): bool =
  ## Deep value equality for Email (28 fields). Decomposes into metadata,
  ## convenience headers, dynamic headers, and body sub-comparisons.
  ## Follows ``sessionEq`` pattern.
  emailMetadataEq(a, b) and convStringHeadersEq(a, b) and convAddressHeadersEq(a, b) and
    a.headers == b.headers and headerTableEq(a.requestedHeaders, b.requestedHeaders) and
    headerTableAllEq(a.requestedHeadersAll, b.requestedHeadersAll) and bodyFieldsEq(
    a, b
  )

proc parsedEmailEq*(a, b: ParsedEmail): bool =
  ## Deep value equality for ParsedEmail (22 fields). Same shared field groups
  ## as ``emailEq`` minus 6 metadata fields, plus ``threadId: Opt[Id]``.
  ## Reuses generic sub-helpers for shared convenience header and body groups.
  a.threadId == b.threadId and convStringHeadersEq(a, b) and convAddressHeadersEq(a, b) and
    a.headers == b.headers and headerTableEq(a.requestedHeaders, b.requestedHeaders) and
    headerTableAllEq(a.requestedHeadersAll, b.requestedHeadersAll) and bodyFieldsEq(
    a, b
  )

proc emailComparatorEq*(a, b: EmailComparator): bool =
  ## Deep value equality for EmailComparator (case object). Follows
  ## ``setErrorEq`` pattern: shared fields then branch comparison.
  if a.kind != b.kind or a.isAscending != b.isAscending or a.collation != b.collation:
    return false
  case a.kind
  of eckPlain:
    a.property == b.property
  of eckKeyword:
    a.keywordProperty == b.keywordProperty and a.keyword == b.keyword

# ---------------------------------------------------------------------------
# Builder / dispatch fixtures
# ---------------------------------------------------------------------------

proc makeGetResponseJson*(accountId = "acct1", state = "s1"): JsonNode =
  ## Minimal valid GetResponse JSON for dispatch tests.
  %*{"accountId": accountId, "state": state, "list": [], "notFound": []}

proc makeChangesResponseJson*(
    accountId = "acct1", oldState = "s1", newState = "s2"
): JsonNode =
  ## Minimal valid ChangesResponse JSON.
  %*{
    "accountId": accountId,
    "oldState": oldState,
    "newState": newState,
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }

proc makeSetResponseJson*(accountId = "acct1", newState = "s2"): JsonNode =
  ## Minimal valid SetResponse JSON (empty results).
  %*{"accountId": accountId, "newState": newState}

proc makeQueryResponseJson*(accountId = "acct1", queryState = "qs1"): JsonNode =
  ## Minimal valid QueryResponse JSON.
  %*{
    "accountId": accountId,
    "queryState": queryState,
    "canCalculateChanges": true,
    "position": 0,
    "ids": [],
  }

proc makeErrorInvocation*(
    mcid: MethodCallId = makeMcid("c0"), errorType = "serverFail"
): Invocation =
  ## An error invocation for dispatch tests.
  initInvocation("error", %*{"type": errorType}, mcid).get()

proc makeTypedResponse*(
    methodName: string,
    args: JsonNode,
    mcid: MethodCallId = makeMcid("c0"),
    state: JmapState = makeState("rs1"),
): Response =
  ## Builds a Response with a single successful method invocation.
  let inv = initInvocation(methodName, args, mcid).get()
  Response(
    methodResponses: @[inv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: state,
  )

proc makeErrorResponse*(
    errorType: string,
    mcid: MethodCallId = makeMcid("c0"),
    state: JmapState = makeState("rs1"),
): Response =
  ## Builds a Response with a single error invocation.
  let inv = makeErrorInvocation(mcid, errorType)
  Response(
    methodResponses: @[inv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: state,
  )

# ---------------------------------------------------------------------------
# Mail Part D JSON fixtures (derived from type factories via toJson)
# ---------------------------------------------------------------------------

proc makeEmailJson*(): JsonNode =
  ## Golden Email JSON with all 28 fields. Derived from ``makeEmail().toJson()``
  ## so the fixture always reflects the current type definition (§12.14).
  makeEmail().toJson()

proc makeParsedEmailJson*(): JsonNode =
  ## Valid ParsedEmail JSON without metadata. Derived from
  ## ``makeParsedEmail().toJson()``.
  makeParsedEmail().toJson()

proc makeSearchSnippetJson*(): JsonNode =
  ## Valid SearchSnippet JSON. Derived from ``makeSearchSnippet().toJson()``.
  makeSearchSnippet().toJson()

# ---------------------------------------------------------------------------
# Mail Part D response JSON fixtures (hand-crafted, server-originated)
# ---------------------------------------------------------------------------

proc makeEmailParseResponseJson*(): JsonNode =
  ## Hand-crafted EmailParseResponse JSON (RFC 8621 §4.9). Wire key is
  ## ``"notParsable"`` (RFC spelling), not ``"notParseable"``.
  %*{
    "accountId": "acct1",
    "parsed": {"blob1": makeParsedEmailJson()},
    "notParsable": [],
    "notFound": [],
  }

proc makeSearchSnippetGetResponseJson*(): JsonNode =
  ## Hand-crafted SearchSnippetGetResponse JSON (RFC 8621 §5.1).
  %*{"accountId": "acct1", "list": [makeSearchSnippetJson()], "notFound": []}
