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

import std/hashes
import std/os
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
import jmap_client/methods_enum
import jmap_client/errors

import jmap_client/mail/types
import jmap_client/mail/email
import jmap_client/mail/snippet
import jmap_client/mail/serde_email
import jmap_client/mail/serde_snippet
import jmap_client/mail/email_blueprint
import jmap_client/mail/mail_builders
import jmap_client/mail/submission_atoms
import jmap_client/mail/submission_mailbox
import jmap_client/mail/submission_param
import jmap_client/mail/submission_envelope
import jmap_client/mail/submission_status
import jmap_client/mail/email_submission
import jmap_client/methods
import jmap_client/dispatch

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

proc makeBlobId*(s = "blob0"): BlobId =
  parseBlobId(s).get()

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
    collationAlgorithms: initHashSet[CollationAlgorithm](),
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
    collationAlgorithms: toHashSet([CollationAsciiCasemap, CollationUnicodeCasemap]),
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
    collationAlgorithms: initHashSet[CollationAlgorithm](),
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

proc makeInvocation*(name = mnMailboxGet, mcid = makeMcid("c0")): Invocation =
  initInvocation(name, newJObject(), mcid)

proc makeInvocation*(name: string, mcid = makeMcid("c0")): Invocation =
  ## Wire-boundary variant for tests exercising forward-compat method names
  ## (e.g. "A/get", "error" response tag) that don't belong in the
  ## MethodName enum. Delegates to parseInvocation and unwraps on success.
  parseInvocation(name, newJObject(), mcid).get()

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
    mcid = makeMcid("c0"), name = mnMailboxGet, path = rpIds
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
    collation: CollationAlgorithm = CollationUnicodeCasemap,
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
    blobId: makeBlobId("blob1"),
    headers: @[],
    name: Opt.none(string),
    charset: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

proc makeEmail*(): Email =
  ## Minimal Email fixture. Every metadata field populated with
  ## ``Opt.some(...)`` to mirror the default-properties wire shape.
  let leaf = makeLeafBodyPart()
  Email(
    id: Opt.some(makeId("email1")),
    blobId: Opt.some(makeBlobId("blob1")),
    threadId: Opt.some(makeId("thread1")),
    mailboxIds: Opt.some(initMailboxIdSet(@[makeId("mbx1")])),
    keywords: Opt.some(initKeywordSet(@[])),
    size: Opt.some(zeroUint()),
    receivedAt: Opt.some(parseUtcDate("2025-01-15T09:00:00Z").get()),
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
    bodyStructure: Opt.some(leaf),
    bodyValues: initTable[PartId, EmailBodyValue](),
    textBody: @[],
    htmlBody: @[],
    attachments: @[],
    hasAttachment: false,
    preview: "",
  )

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
    bodyStructure: Opt.some(leaf),
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

proc optBodyPartEq(a, b: Opt[EmailBodyPart]): bool =
  ## ``bodyStructure`` is ``Opt[EmailBodyPart]``; both none → equal,
  ## both some → defer to ``bodyPartEq``, mixed → not equal.
  if a.isSome and b.isSome:
    return bodyPartEq(a.unsafeGet, b.unsafeGet)
  return a.isSome == b.isSome

proc bodyFieldsEq[T](a, b: T): bool =
  ## Compares body fields (7 fields). Delegates to ``bodyPartEq`` and
  ## ``bodyPartSeqEq`` for case-object fields.
  optBodyPartEq(a.bodyStructure, b.bodyStructure) and a.bodyValues == b.bodyValues and
    bodyPartSeqEq(a.textBody, b.textBody) and bodyPartSeqEq(a.htmlBody, b.htmlBody) and
    bodyPartSeqEq(a.attachments, b.attachments) and a.hasAttachment == b.hasAttachment and
    a.preview == b.preview

proc optMailboxIdSetEq(a, b: Opt[MailboxIdSet]): bool =
  ## Distinct ``MailboxIdSet`` excludes ``==`` (from ``defineHashSetDistinctOps``);
  ## unwrap to ``HashSet[Id]`` for comparison when both sides are some.
  if a.isSome and b.isSome:
    return HashSet[Id](a.unsafeGet) == HashSet[Id](b.unsafeGet)
  return a.isSome == b.isSome

proc optKeywordSetEq(a, b: Opt[KeywordSet]): bool =
  ## Same shape as ``optMailboxIdSetEq`` for ``KeywordSet``.
  if a.isSome and b.isSome:
    return HashSet[Keyword](a.unsafeGet) == HashSet[Keyword](b.unsafeGet)
  return a.isSome == b.isSome

proc emailMetadataEq(a, b: Email): bool =
  ## Compares Email metadata fields (7 ``Opt`` fields). Distinct HashSet
  ## types are unwrapped because ``defineHashSetDistinctOps`` omits ``==``.
  a.id == b.id and a.blobId == b.blobId and a.threadId == b.threadId and
    optMailboxIdSetEq(a.mailboxIds, b.mailboxIds) and
    optKeywordSetEq(a.keywords, b.keywords) and a.size == b.size and
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
  ## An error invocation for dispatch tests. The literal "error" wire tag
  ## is a JMAP response marker (RFC 8620 §3.6.1), not a method name — goes
  ## through parseInvocation (the string-taking wire-boundary constructor).
  parseInvocation("error", %*{"type": errorType}, mcid).get()

proc makeTypedResponse*(
    methodName: string,
    args: JsonNode,
    mcid: MethodCallId = makeMcid("c0"),
    state: JmapState = makeState("rs1"),
): Response =
  ## Builds a Response with a single successful method invocation.
  ## Takes the method name as a string so fixtures can target forward-compat
  ## or unknown methods alongside those in the MethodName enum.
  let inv = parseInvocation(methodName, args, mcid).get()
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

# ---------------------------------------------------------------------------
# Mail Part E factories
# ---------------------------------------------------------------------------

proc makeEmailAddress*(
    email: string = "user@example.com", name: string = ""
): EmailAddress =
  ## Convenience wrapper around ``parseEmailAddress``. When ``name`` is
  ## the empty string, the EmailAddress has ``Opt.none`` for its name.
  let nameOpt =
    if name.len > 0:
      Opt.some(name)
    else:
      Opt.none(string)
  parseEmailAddress(email, nameOpt).get()

# I-1 ------------------------------------------------------------------------
proc makeBlueprintEmailHeaderName*(s = "x-custom"): BlueprintEmailHeaderName =
  parseBlueprintEmailHeaderName(s).get()

# I-2 ------------------------------------------------------------------------
proc makeBlueprintBodyHeaderName*(s = "x-body-custom"): BlueprintBodyHeaderName =
  parseBlueprintBodyHeaderName(s).get()

# I-3 — makeBhmv* family (seven forms × {multi, single} = fourteen procs). --
# Multi constructors return ``Result[...,ValidationError]`` so ``.get()``
# unwraps on the happy-path default. Single constructors return the value
# directly per headers.nim lines 439-471.

proc makeBhmvRaw*(values: seq[string] = @["v1"]): BlueprintHeaderMultiValue =
  rawMulti(values).get()

proc makeBhmvText*(values: seq[string] = @["v1"]): BlueprintHeaderMultiValue =
  textMulti(values).get()

proc makeBhmvAddresses*(
    values: seq[seq[EmailAddress]] = @[@[makeEmailAddress()]]
): BlueprintHeaderMultiValue =
  addressesMulti(values).get()

proc makeBhmvGroupedAddresses*(
    values: seq[seq[EmailAddressGroup]] = @[newSeq[EmailAddressGroup]()]
): BlueprintHeaderMultiValue =
  groupedAddressesMulti(values).get()

proc makeBhmvMessageIds*(
    values: seq[seq[string]] = @[@["<id@host>"]]
): BlueprintHeaderMultiValue =
  messageIdsMulti(values).get()

proc makeBhmvDate*(
    values: seq[Date] = @[parseDate("2025-01-15T09:00:00Z").get()]
): BlueprintHeaderMultiValue =
  dateMulti(values).get()

proc makeBhmvUrls*(
    values: seq[seq[string]] = @[@["https://example.com"]]
): BlueprintHeaderMultiValue =
  urlsMulti(values).get()

proc makeBhmvRawSingle*(value = "v1"): BlueprintHeaderMultiValue =
  rawSingle(value)

proc makeBhmvTextSingle*(value = "v1"): BlueprintHeaderMultiValue =
  textSingle(value)

proc makeBhmvAddressesSingle*(
    value: seq[EmailAddress] = @[makeEmailAddress()]
): BlueprintHeaderMultiValue =
  addressesSingle(value)

proc makeBhmvGroupedAddressesSingle*(
    value: seq[EmailAddressGroup] = @[]
): BlueprintHeaderMultiValue =
  groupedAddressesSingle(value)

proc makeBhmvMessageIdsSingle*(
    value: seq[string] = @["<id@host>"]
): BlueprintHeaderMultiValue =
  messageIdsSingle(value)

proc makeBhmvDateSingle*(
    value: Date = parseDate("2025-01-15T09:00:00Z").get()
): BlueprintHeaderMultiValue =
  dateSingle(value)

proc makeBhmvUrlsSingle*(
    value: seq[string] = @["https://example.com"]
): BlueprintHeaderMultiValue =
  urlsSingle(value)

# I-4 ------------------------------------------------------------------------
proc makeNonEmptyMailboxIdSet*(
    ids: seq[Id] = @[makeId("mbx1"), makeId("mbx2")]
): NonEmptyMailboxIdSet =
  ## Default is a 2-element set so tests that exercise cardinality-sensitive
  ## paths don't accidentally mask "len = 1" bugs.
  parseNonEmptyMailboxIdSet(ids).get()

# I-5 ------------------------------------------------------------------------
proc makeNonEmptySeq*[T](s: seq[T]): NonEmptySeq[T] =
  parseNonEmptySeq(s).get()

# I-6 ------------------------------------------------------------------------
proc makeBlueprintBodyValue*(value = "hi"): BlueprintBodyValue =
  BlueprintBodyValue(value: value)

# I-7 ------------------------------------------------------------------------
proc makeBlueprintBodyPartInline*(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = makeBlueprintBodyValue(),
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  BlueprintBodyPart(
    isMultipart: false,
    leaf: BlueprintLeafPart(source: bpsInline, partId: partId, value: value),
    contentType: contentType,
    extraHeaders: extraHeaders,
    name: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

# I-8 ------------------------------------------------------------------------
proc makeBlueprintBodyPartBlobRef*(
    blobId = makeBlobId("blob1"),
    contentType = "image/png",
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  BlueprintBodyPart(
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: blobId,
      size: Opt.none(UnsignedInt),
      charset: Opt.none(string),
    ),
    contentType: contentType,
    extraHeaders: extraHeaders,
    name: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

# I-9 ------------------------------------------------------------------------
proc makeBlueprintBodyPartMultipart*(
    subParts: seq[BlueprintBodyPart] = @[],
    contentType = "multipart/mixed",
    extraHeaders: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
      initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
): BlueprintBodyPart =
  BlueprintBodyPart(
    isMultipart: true,
    subParts: subParts,
    contentType: contentType,
    extraHeaders: extraHeaders,
    name: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )

# I-10a ----------------------------------------------------------------------
proc makeEmailBlueprint*(
    mailboxIds: NonEmptyMailboxIdSet = makeNonEmptyMailboxIdSet()
): EmailBlueprint =
  parseEmailBlueprint(mailboxIds = mailboxIds).get()

# I-10b ----------------------------------------------------------------------
proc makeFullEmailBlueprint*(): EmailBlueprint =
  ## Populates every 11 convenience fields, one top-level extraHeaders
  ## entry, and a flat body with a text-plain inline leaf plus two
  ## attachments (one inline PDF, one blob-ref PNG). Two inline entries
  ## means ``bodyValues`` has exactly two keys — enough to exercise the
  ## derived-map walker without being adversarially complex.
  let alice = makeEmailAddress("alice@example.com", "Alice")
  let bob = makeEmailAddress("bob@example.com", "Bob")
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[makeBlueprintEmailHeaderName("x-marker")] = makeBhmvTextSingle("full")
  let textInline = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    value = BlueprintBodyValue(value: "text leaf"),
  )
  let attachInline = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("2").get(),
    contentType = "application/pdf",
    value = BlueprintBodyValue(value: "pdf leaf"),
  )
  let attachBlob = makeBlueprintBodyPartBlobRef(
    blobId = makeBlobId("blobA"), contentType = "image/png"
  )
  let body =
    flatBody(textBody = Opt.some(textInline), attachments = @[attachInline, attachBlob])
  parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    body = body,
    keywords = initKeywordSet(@[parseKeyword("$seen").get()]),
    receivedAt = Opt.some(parseUtcDate("2025-01-15T09:00:00Z").get()),
    fromAddr = Opt.some(@[alice]),
    to = Opt.some(@[bob]),
    cc = Opt.some(@[alice]),
    bcc = Opt.some(@[bob]),
    replyTo = Opt.some(@[alice]),
    sender = Opt.some(alice),
    subject = Opt.some("hello"),
    sentAt = Opt.some(parseDate("2025-01-15T08:00:00Z").get()),
    messageId = Opt.some(@["<id1@host>"]),
    inReplyTo = Opt.some(@["<id0@host>"]),
    references = Opt.some(@["<id0@host>"]),
    extraHeaders = extra,
  )
    .get()

# I-11a ----------------------------------------------------------------------
proc makeFlatBody*(
    textBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    htmlBody: Opt[BlueprintBodyPart] = Opt.none(BlueprintBodyPart),
    attachments: seq[BlueprintBodyPart] = @[],
): EmailBlueprintBody =
  ## Thin wrapper over the module helper — tests delegate rather than
  ## reconstructing the case object by hand (design §6.5.2).
  flatBody(textBody, htmlBody, attachments)

# I-11b ----------------------------------------------------------------------
proc makeStructuredBody*(
    root: BlueprintBodyPart = makeBlueprintBodyPartInline()
): EmailBlueprintBody =
  ## Thin wrapper over the module helper.
  structuredBody(root)

# I-12 -----------------------------------------------------------------------
proc makeBlueprintWithDuplicateAt*(
    dupName = "from",
    dupKind = ebcEmailTopLevelHeaderDuplicate,
    loc: Opt[BodyPartLocation] = Opt.none(BodyPartLocation),
): Result[EmailBlueprint, EmailBlueprintErrors] =
  ## Collapses the three duplicate-trigger scenarios (top-level,
  ## bodyStructure, body-part) into one factory. Returns the raw
  ## ``Result`` so tests can assert on ``.isErr`` / ``.error`` payloads.
  ## Callers for non-duplicate variants (text/html content-type,
  ## allowed-form) build inputs directly — the ``else`` branch fires
  ## ``raiseAssert`` on misuse (test-author error, not a domain concern).
  discard loc ## reserved for future fine-grained BodyPartLocation targeting
  case dupKind
  of ebcEmailTopLevelHeaderDuplicate:
    var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extra[makeBlueprintEmailHeaderName(dupName)] = makeBhmvTextSingle()
    parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      fromAddr = Opt.some(@[makeEmailAddress()]),
      extraHeaders = extra,
    )
  of ebcBodyStructureHeaderDuplicate:
    # Root bodyStructure's extraHeaders duplicates a top-level name.
    var rootExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    rootExtra[makeBlueprintBodyHeaderName(dupName)] = makeBhmvTextSingle()
    let root = makeBlueprintBodyPartMultipart(
      subParts = @[makeBlueprintBodyPartInline()], extraHeaders = rootExtra
    )
    var topExtra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    topExtra[makeBlueprintEmailHeaderName(dupName)] = makeBhmvTextSingle()
    parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = structuredBody(root),
      extraHeaders = topExtra,
    )
  of ebcBodyPartHeaderDuplicate:
    # Body part's extraHeaders duplicates a domain field on the same part.
    # "content-type" is always a domain header, guaranteeing a collision
    # regardless of ``dupName``.
    var partExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    partExtra[makeBlueprintBodyHeaderName("content-type")] = makeBhmvTextSingle()
    let leaf = makeBlueprintBodyPartInline(extraHeaders = partExtra)
    parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leaf)),
    )
  else:
    raiseAssert "makeBlueprintWithDuplicateAt: unsupported dupKind " & $dupKind

# I-13 -----------------------------------------------------------------------
proc makeBodyPartLocationInline*(
    partId = parsePartIdFromServer("1").get()
): BodyPartLocation =
  BodyPartLocation(kind: bplInline, partId: partId)

proc makeBodyPartLocationBlobRef*(blobId = makeBlobId("blob1")): BodyPartLocation =
  BodyPartLocation(kind: bplBlobRef, blobId: blobId)

proc makeBodyPartLocationMultipart*(
    path: BodyPartPath = BodyPartPath(@[])
): BodyPartLocation =
  BodyPartLocation(kind: bplMultipart, path: path)

# I-14 deferred to Step 18 (Phase 4) alongside toJson.

# I-15 -----------------------------------------------------------------------
proc makeBlueprintEmailHeaderMap*(
    entries: seq[(BlueprintEmailHeaderName, BlueprintHeaderMultiValue)] = @[]
): Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] =
  result = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  for (k, v) in entries:
    result[k] = v

proc makeBlueprintBodyHeaderMap*(
    entries: seq[(BlueprintBodyHeaderName, BlueprintHeaderMultiValue)] = @[]
): Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
  result = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  for (k, v) in entries:
    result[k] = v

# I-16 -----------------------------------------------------------------------
proc makeBodyPartPath*(s: seq[int] = @[]): BodyPartPath =
  BodyPartPath(s)

# I-17 -----------------------------------------------------------------------
proc makeSpineBodyPart*(
    depth: int = 3, leafKind: BodyPartLocationKind = bplInline
): BlueprintBodyPart =
  ## Deterministic spine: wraps ``depth`` multipart containers around a
  ## single leaf. ``bplMultipart`` degenerates to ``bplInline`` at the
  ## leaf level since leaves can't be multipart.
  doAssert depth >= 0
  result =
    case leafKind
    of bplInline:
      makeBlueprintBodyPartInline()
    of bplBlobRef:
      makeBlueprintBodyPartBlobRef()
    of bplMultipart:
      makeBlueprintBodyPartInline()
  for _ in 0 ..< depth:
    result = makeBlueprintBodyPartMultipart(subParts = @[result])

# I-18 -----------------------------------------------------------------------
template withLocale*(locale: string, body: untyped) =
  ## Sets LC_CTYPE and LC_ALL for the duration of ``body``, restoring
  ## the prior values on exit. Used by locale-sensitive scenarios (e.g.
  ## Turkish dotted-i round-trip).
  let prevCtype = getEnv("LC_CTYPE")
  let prevAll = getEnv("LC_ALL")
  putEnv("LC_CTYPE", locale)
  putEnv("LC_ALL", locale)
  try:
    body
  finally:
    putEnv("LC_CTYPE", prevCtype)
    putEnv("LC_ALL", prevAll)

# I-19 -----------------------------------------------------------------------
proc adversarialHashCollisionNames*(n: int): seq[string] =
  ## Produces ``n`` distinct strings whose ``std/hashes.hash(string)``
  ## values coincide (or share a low-order-byte bucket) with the hash of
  ## ``"hdos-0"``. Exact collision-set construction depends on the
  ## runtime-randomised seed, so we brute-force-scan up to 1e6 candidates.
  doAssert n >= 0
  if n == 0:
    return @[]
  let target = hash("hdos-0")
  result = @[]
  var i = 0
  while result.len < n and i < 1_000_000:
    let s = "hdos-" & $i
    if hash(s) == target or (hash(s) and 0xFF) == (target and 0xFF):
      if s notin result:
        result.add(s)
    inc i
  doAssert result.len == n, "insufficient hash collisions found"

# ---------------------------------------------------------------------------
# Mail Part E equality helpers
# ---------------------------------------------------------------------------
#
# Defined in strict dependency order: each helper only references
# helpers declared above it. The K-series numbering in the design doc
# (§6.5.4) is preserved in the banner comments, but the source order
# is K-6, K-8, K-3, K-5 helpers, K-5, K-4, K-1, K-2, K-9, K-7 meta,
# K-7 so forward declarations are unnecessary.

# K-6 ------------------------------------------------------------------------
proc blueprintHeaderMultiValueEq*(a, b: BlueprintHeaderMultiValue): bool =
  ## Case-object equality on the ``HeaderForm`` discriminant; each arm
  ## compares the ``NonEmptySeq[T]`` via its borrowed ``==``.
  if a.form != b.form:
    return false
  case a.form
  of hfRaw:
    a.rawValues == b.rawValues
  of hfText:
    a.textValues == b.textValues
  of hfAddresses:
    a.addressLists == b.addressLists
  of hfGroupedAddresses:
    a.groupLists == b.groupLists
  of hfMessageIds:
    a.messageIdLists == b.messageIdLists
  of hfDate:
    a.dateValues == b.dateValues
  of hfUrls:
    a.urlLists == b.urlLists

# K-8 ------------------------------------------------------------------------
proc nonEmptyMailboxIdSetEq*(a, b: NonEmptyMailboxIdSet): bool =
  ## Unwraps the distinct ``HashSet[Id]`` — ``==`` is intentionally not
  ## borrowed at the type level (``defineHashSetDistinctOps`` omits it).
  HashSet[Id](a) == HashSet[Id](b)

# K-3 ------------------------------------------------------------------------
proc bodyPartLocationEq*(a, b: BodyPartLocation): bool =
  ## Discriminant first, then variant-specific identifier field.
  ## ``path`` comparison uses the borrowed ``==`` on ``BodyPartPath``.
  if a.kind != b.kind:
    return false
  case a.kind
  of bplInline:
    a.partId == b.partId
  of bplBlobRef:
    a.blobId == b.blobId
  of bplMultipart:
    a.path == b.path

# K-5 sub-helpers ------------------------------------------------------------

proc blueprintBodyExtraHeadersEq(
    a, b: Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]
): bool =
  ## Value-level Table equality: names must match, values compared via K-6.
  if a.len != b.len:
    return false
  for k, v in a:
    if k notin b:
      return false
    if not blueprintHeaderMultiValueEq(v, b[k]):
      return false
  true

proc blueprintBodyPartCoreFieldsEq(a, b: BlueprintBodyPart): bool =
  ## Shared-field group: contentType, isMultipart discriminant, and
  ## extraHeaders table. Kept under the complexity budget by pulling
  ## these out of the recursive helper.
  a.contentType == b.contentType and a.isMultipart == b.isMultipart and
    blueprintBodyExtraHeadersEq(a.extraHeaders, b.extraHeaders)

proc blueprintBodyPartOptFieldsEq(a, b: BlueprintBodyPart): bool =
  ## Optional-field group: MIME metadata fields present on both variants.
  a.name == b.name and a.disposition == b.disposition and a.cid == b.cid and
    a.language == b.language and a.location == b.location

proc blueprintLeafPartEq(a, b: BlueprintLeafPart): bool =
  ## Leaf variant equality: ``source`` discriminant plus the
  ## variant-specific identifier fields. Takes the extracted
  ## ``BlueprintLeafPart`` directly (no outer ``isMultipart`` context
  ## needed).
  case a.source
  of bpsInline:
    case b.source
    of bpsInline:
      a.partId == b.partId and a.value == b.value
    of bpsBlobRef:
      false
  of bpsBlobRef:
    case b.source
    of bpsInline:
      false
    of bpsBlobRef:
      a.blobId == b.blobId and a.size == b.size and a.charset == b.charset

# K-5 ------------------------------------------------------------------------
proc blueprintBodyPartEq*(a, b: BlueprintBodyPart): bool =
  ## Recursive case-object equality. Delegates shared fields to the two
  ## sub-helpers and leaf variants to ``blueprintLeafPartEq``,
  ## keeping each helper under the nimalyzer complexity budget.
  if not blueprintBodyPartCoreFieldsEq(a, b):
    return false
  if not blueprintBodyPartOptFieldsEq(a, b):
    return false
  case a.isMultipart
  of true:
    case b.isMultipart
    of true:
      if a.subParts.len != b.subParts.len:
        return false
      for i in 0 ..< a.subParts.len:
        if not blueprintBodyPartEq(a.subParts[i], b.subParts[i]):
          return false
      true
    of false:
      false
  of false:
    case b.isMultipart
    of true:
      false
    of false:
      blueprintLeafPartEq(a.leaf, b.leaf)

# K-4 sub-helpers ------------------------------------------------------------

proc flatTextBodyEq(a, b: EmailBlueprintBody): bool =
  ## ``ebkFlat`` textBody slot equality — both ``isSome``-parity and
  ## (when both populated) the leaf comparison.
  if a.textBody.isSome != b.textBody.isSome:
    return false
  for ta in a.textBody:
    for tb in b.textBody:
      if not blueprintBodyPartEq(ta, tb):
        return false
  true

proc flatHtmlBodyEq(a, b: EmailBlueprintBody): bool =
  ## ``ebkFlat`` htmlBody slot equality.
  if a.htmlBody.isSome != b.htmlBody.isSome:
    return false
  for ha in a.htmlBody:
    for hb in b.htmlBody:
      if not blueprintBodyPartEq(ha, hb):
        return false
  true

proc flatAttachmentsEq(a, b: EmailBlueprintBody): bool =
  ## ``ebkFlat`` attachments slot equality — element-wise.
  if a.attachments.len != b.attachments.len:
    return false
  for i in 0 ..< a.attachments.len:
    if not blueprintBodyPartEq(a.attachments[i], b.attachments[i]):
      return false
  true

proc flatBodyPartsEq(a, b: EmailBlueprintBody): bool =
  ## ``ebkFlat`` variant equality — composes the three slot helpers.
  flatTextBodyEq(a, b) and flatHtmlBodyEq(a, b) and flatAttachmentsEq(a, b)

# K-4 ------------------------------------------------------------------------
proc emailBlueprintBodyEq*(a, b: EmailBlueprintBody): bool =
  ## Case-object equality on the ``EmailBodyKind`` discriminant.
  if a.kind != b.kind:
    return false
  case a.kind
  of ebkStructured:
    blueprintBodyPartEq(a.bodyStructure, b.bodyStructure)
  of ebkFlat:
    flatBodyPartsEq(a, b)

# K-1 ------------------------------------------------------------------------
proc emailBlueprintErrorEq*(a, b: EmailBlueprintError): bool =
  ## Case-object equality on the constraint enum. ``where`` delegates
  ## to K-3 (``bodyPartLocationEq``).
  if a.constraint != b.constraint:
    return false
  case a.constraint
  of ebcEmailTopLevelHeaderDuplicate:
    a.dupName == b.dupName
  of ebcBodyStructureHeaderDuplicate:
    a.bodyStructureDupName == b.bodyStructureDupName
  of ebcBodyPartHeaderDuplicate:
    a.bodyPartDupName == b.bodyPartDupName and bodyPartLocationEq(a.where, b.where)
  of ebcTextBodyNotTextPlain:
    a.actualTextType == b.actualTextType
  of ebcHtmlBodyNotTextHtml:
    a.actualHtmlType == b.actualHtmlType
  of ebcAllowedFormRejected:
    a.rejectedName == b.rejectedName and a.rejectedForm == b.rejectedForm
  of ebcBodyPartDepthExceeded:
    a.observedDepth == b.observedDepth and
      bodyPartLocationEq(a.depthLocation, b.depthLocation)

# K-2 ------------------------------------------------------------------------
proc emailBlueprintErrorsSetEq*(a, b: EmailBlueprintErrors): bool =
  ## Multiset equality — order-insensitive, duplicate-sensitive. Used
  ## for variant-coverage scenarios where emission order is incidental
  ## (e.g., design scenarios 7i, 101, 101a-c).
  if a.len != b.len:
    return false
  var bUsed = newSeq[bool](b.len)
  for x in a:
    var found = false
    for j, elem in b.pairs:
      if not bUsed[j] and emailBlueprintErrorEq(x, elem):
        bUsed[j] = true
        found = true
        break
    if not found:
      return false
  true

# K-9 ------------------------------------------------------------------------
proc emailBlueprintErrorsOrderedEq*(a, b: EmailBlueprintErrors): bool =
  ## Element-wise, order-sensitive. Contrast with K-2: used for the
  ## error-ordering determinism property (scenario 94) where the order
  ## of emission IS the thing being verified.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    # i ∈ [0, a.len) — loop bounds prove non-negativity, so parseIdx.get
    # cannot Err at runtime.
    let ix = parseIdx(i).get()
    if not emailBlueprintErrorEq(a[ix], b[ix]):
      return false
  true

# K-7 sub-helpers ------------------------------------------------------------

proc blueprintTopExtraHeadersEq(
    a, b: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
): bool =
  ## Value-level Table equality at the top-level (email) header-name axis.
  if a.len != b.len:
    return false
  for k, v in a:
    if k notin b:
      return false
    if not blueprintHeaderMultiValueEq(v, b[k]):
      return false
  true

proc blueprintAddrFieldsEq(a, b: EmailBlueprint): bool =
  ## Six RFC 5322 address convenience fields.
  a.fromAddr == b.fromAddr and a.to == b.to and a.cc == b.cc and a.bcc == b.bcc and
    a.replyTo == b.replyTo and a.sender == b.sender

proc blueprintScalarFieldsEq(a, b: EmailBlueprint): bool =
  ## Five non-address convenience fields.
  a.subject == b.subject and a.sentAt == b.sentAt and a.messageId == b.messageId and
    a.inReplyTo == b.inReplyTo and a.references == b.references

proc emailBlueprintMetadataEq(a, b: EmailBlueprint): bool =
  ## Mailbox set, keywords set, receivedAt, and the eleven convenience
  ## fields. Uses UFCS accessors throughout because the ``raw*`` fields
  ## are module-private to ``email_blueprint.nim``. Keywords compared
  ## via HashSet-unwrap since ``KeywordSet`` has no ``==`` by design.
  nonEmptyMailboxIdSetEq(a.mailboxIds, b.mailboxIds) and
    HashSet[Keyword](a.keywords) == HashSet[Keyword](b.keywords) and
    a.receivedAt == b.receivedAt and blueprintAddrFieldsEq(a, b) and
    blueprintScalarFieldsEq(a, b)

# K-7 ------------------------------------------------------------------------
proc emailBlueprintEq*(a, b: EmailBlueprint): bool =
  ## Deep structural equality. Decomposes into metadata, body, and
  ## top-level extraHeaders groups so each sub-helper stays under the
  ## nimalyzer complexity budget — same precedent as ``emailEq`` above.
  emailBlueprintMetadataEq(a, b) and emailBlueprintBodyEq(a.body, b.body) and
    blueprintTopExtraHeadersEq(a.extraHeaders, b.extraHeaders)

# ---------------------------------------------------------------------------
# Mail Part F2 — update algebra factories (Section A: EmailUpdate variants)
# ---------------------------------------------------------------------------

proc makeAddKeyword*(k: Keyword = kwSeen): EmailUpdate =
  addKeyword(k)

proc makeRemoveKeyword*(k: Keyword = kwSeen): EmailUpdate =
  removeKeyword(k)

proc makeSetKeywords*(ks: KeywordSet = initKeywordSet([kwSeen])): EmailUpdate =
  setKeywords(ks)

proc makeAddToMailbox*(id: Id = makeId("mbx1")): EmailUpdate =
  addToMailbox(id)

proc makeRemoveFromMailbox*(id: Id = makeId("mbx1")): EmailUpdate =
  removeFromMailbox(id)

proc makeSetMailboxIds*(
    ids: NonEmptyMailboxIdSet = makeNonEmptyMailboxIdSet()
): EmailUpdate =
  setMailboxIds(ids)

proc makeMarkRead*(): EmailUpdate =
  markRead()

proc makeMarkUnread*(): EmailUpdate =
  markUnread()

proc makeMarkFlagged*(): EmailUpdate =
  markFlagged()

proc makeMarkUnflagged*(): EmailUpdate =
  markUnflagged()

proc makeMoveToMailbox*(id: Id = makeId("mbx1")): EmailUpdate =
  moveToMailbox(id)

# ---------------------------------------------------------------------------
# Section C — MailboxUpdate variant factories
# ---------------------------------------------------------------------------
#
# MailboxUpdate has five RFC 8621 §2 settable properties (name, parentId,
# role, sortOrder, isSubscribed). The implementation-plan wording of "six"
# does not match the F1 source — wrap the five that actually exist.

proc makeSetName*(name: string = "Inbox"): MailboxUpdate =
  mailbox.setName(name)

proc makeSetParentId*(parentId: Opt[Id] = Opt.none(Id)): MailboxUpdate =
  setParentId(parentId)

proc makeSetRole*(role: Opt[MailboxRole] = Opt.none(MailboxRole)): MailboxUpdate =
  setRole(role)

proc makeSetSortOrder*(
    sortOrder: UnsignedInt = parseUnsignedInt(0).get()
): MailboxUpdate =
  setSortOrder(sortOrder)

proc makeSetIsSubscribed*(isSubscribed: bool = true): MailboxUpdate =
  setIsSubscribed(isSubscribed)

# ---------------------------------------------------------------------------
# Section D — VacationResponseUpdate variant factories
# ---------------------------------------------------------------------------

proc makeSetIsEnabled*(isEnabled: bool = true): VacationResponseUpdate =
  setIsEnabled(isEnabled)

proc makeSetFromDate*(
    fromDate: Opt[UTCDate] = Opt.none(UTCDate)
): VacationResponseUpdate =
  setFromDate(fromDate)

proc makeSetToDate*(toDate: Opt[UTCDate] = Opt.none(UTCDate)): VacationResponseUpdate =
  setToDate(toDate)

proc makeSetSubject*(subject: Opt[string] = Opt.none(string)): VacationResponseUpdate =
  setSubject(subject)

proc makeSetTextBody*(
    textBody: Opt[string] = Opt.none(string)
): VacationResponseUpdate =
  setTextBody(textBody)

proc makeSetHtmlBody*(
    htmlBody: Opt[string] = Opt.none(string)
): VacationResponseUpdate =
  setHtmlBody(htmlBody)

# ---------------------------------------------------------------------------
# Section B — update set builders (declared AFTER sections A/C/D because
# defaults reference their factories)
# ---------------------------------------------------------------------------

proc makeEmailUpdateSet*(
    updates: openArray[EmailUpdate] = @[makeAddKeyword()]
): EmailUpdateSet =
  initEmailUpdateSet(updates).get()

proc makeMailboxUpdateSet*(
    updates: openArray[MailboxUpdate] = @[makeSetName()]
): MailboxUpdateSet =
  initMailboxUpdateSet(updates).get()

proc makeVacationResponseUpdateSet*(
    updates: openArray[VacationResponseUpdate] = @[makeSetIsEnabled()]
): VacationResponseUpdateSet =
  initVacationResponseUpdateSet(updates).get()

# ---------------------------------------------------------------------------
# Section E — EmailCopyItem factories
# ---------------------------------------------------------------------------

proc makeEmailCopyItem*(
    id: Id = makeId("src1"),
    mailboxIds: Opt[NonEmptyMailboxIdSet] = Opt.none(NonEmptyMailboxIdSet),
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailCopyItem =
  initEmailCopyItem(id, mailboxIds, keywords, receivedAt)

proc makeFullEmailCopyItem*(
    id: Id = makeId("src1"),
    mailboxIds: NonEmptyMailboxIdSet = makeNonEmptyMailboxIdSet(),
    keywords: KeywordSet = initKeywordSet([kwSeen]),
    receivedAt: UTCDate = parseUtcDate("2026-01-01T00:00:00Z").get(),
): EmailCopyItem =
  ## "Full" variant: every override populated. The UTC literal mirrors
  ## the precedent in ``makeFullEmailBlueprint`` — Nim rejects required
  ## parameters after defaulted ones, so a fixture default is required.
  initEmailCopyItem(id, Opt.some(mailboxIds), Opt.some(keywords), Opt.some(receivedAt))

# ---------------------------------------------------------------------------
# Section F — EmailImportItem factories
# ---------------------------------------------------------------------------

proc makeEmailImportItem*(
    blobId: BlobId = makeBlobId("blob1"),
    mailboxIds: NonEmptyMailboxIdSet = makeNonEmptyMailboxIdSet(),
    keywords: Opt[KeywordSet] = Opt.none(KeywordSet),
    receivedAt: Opt[UTCDate] = Opt.none(UTCDate),
): EmailImportItem =
  initEmailImportItem(blobId, mailboxIds, keywords, receivedAt)

proc makeFullEmailImportItem*(
    blobId: BlobId = makeBlobId("blob1"),
    mailboxIds: NonEmptyMailboxIdSet = makeNonEmptyMailboxIdSet(),
    keywords: KeywordSet = initKeywordSet([kwSeen]),
    receivedAt: UTCDate = parseUtcDate("2026-01-01T00:00:00Z").get(),
): EmailImportItem =
  ## "Full" variant: every optional populated.
  initEmailImportItem(blobId, mailboxIds, Opt.some(keywords), Opt.some(receivedAt))

# ---------------------------------------------------------------------------
# Section G — NonEmptyEmailImportMap builder
# ---------------------------------------------------------------------------

proc makeNonEmptyEmailImportMap*(
    items: openArray[(CreationId, EmailImportItem)] =
      @[(makeCreationId("k0"), makeEmailImportItem())]
): NonEmptyEmailImportMap =
  initNonEmptyEmailImportMap(items).get()

# ---------------------------------------------------------------------------
# Section H — Email write response builders
# ---------------------------------------------------------------------------
#
# Take typed records, not JsonNode — response types carry public fields
# and no smart constructor exists. Defaults produce a minimal happy-path
# response so tests can override only what they pin.

proc makeEmailSetResponse*(
    accountId: AccountId = makeAccountId(),
    oldState: Opt[JmapState] = Opt.none(JmapState),
    newState: JmapState = makeState("s1"),
    createResults: Table[CreationId, Result[EmailCreatedItem, SetError]] =
      initTable[CreationId, Result[EmailCreatedItem, SetError]](),
    updateResults: Table[Id, Result[Opt[JsonNode], SetError]] =
      initTable[Id, Result[Opt[JsonNode], SetError]](),
    destroyResults: Table[Id, Result[void, SetError]] =
      initTable[Id, Result[void, SetError]](),
): SetResponse[EmailCreatedItem] =
  ## Email/set response fixture — the bespoke ``EmailSetResponse`` was
  ## deleted; ``SetResponse[EmailCreatedItem]`` is the generic instantiation.
  ## The split ``updated``/``notUpdated`` and ``destroyed``/``notDestroyed``
  ## fields collapse into the unified ``updateResults`` / ``destroyResults``
  ## tables (RFC 8620 §5.3 Decision 3.9B).
  SetResponse[EmailCreatedItem](
    accountId: accountId,
    oldState: oldState,
    newState: newState,
    createResults: createResults,
    updateResults: updateResults,
    destroyResults: destroyResults,
  )

proc makeEmailCopyResponse*(
    fromAccountId: AccountId = makeAccountId("src"),
    accountId: AccountId = makeAccountId("dst"),
    oldState: Opt[JmapState] = Opt.none(JmapState),
    newState: JmapState = makeState("s1"),
    createResults: Table[CreationId, Result[EmailCreatedItem, SetError]] =
      initTable[CreationId, Result[EmailCreatedItem, SetError]](),
): CopyResponse[EmailCreatedItem] =
  ## Email/copy response fixture — the bespoke ``EmailCopyResponse`` was
  ## deleted in favour of the generic ``CopyResponse[EmailCreatedItem]``.
  ## No update/destroy fields per RFC 8621 §4.7.
  CopyResponse[EmailCreatedItem](
    fromAccountId: fromAccountId,
    accountId: accountId,
    oldState: oldState,
    newState: newState,
    createResults: createResults,
  )

proc makeEmailImportResponse*(
    accountId: AccountId = makeAccountId(),
    oldState: Opt[JmapState] = Opt.none(JmapState),
    newState: JmapState = makeState("s1"),
    createResults: Table[CreationId, Result[EmailCreatedItem, SetError]] =
      initTable[CreationId, Result[EmailCreatedItem, SetError]](),
): EmailImportResponse =
  EmailImportResponse(
    accountId: accountId,
    oldState: oldState,
    newState: newState,
    createResults: createResults,
  )

# ---------------------------------------------------------------------------
# Section I — EmailCopyHandles compound builder
# ---------------------------------------------------------------------------

proc makeEmailCopyHandles*(
    sharedCallId: MethodCallId = makeMcid("c0")
): EmailCopyHandles =
  ## Both handles share one ``MethodCallId`` per RFC 8620 §5.4 — the
  ## implicit Email/set destroy response shares its call-id with the
  ## parent Email/copy invocation. Phase 4 protocol tests may add a
  ## distinct-MCID overload later if the mismatch case needs exercising.
  EmailCopyHandles(
    primary: ResponseHandle[CopyResponse[EmailCreatedItem]](sharedCallId),
    implicit: NameBoundHandle[SetResponse[EmailCreatedItem]](
      callId: sharedCallId, methodName: mnEmailSet
    ),
  )

# ---------------------------------------------------------------------------
# Section J — Whole-container update wrappers for /set widening
# ---------------------------------------------------------------------------

proc makeNonEmptyMailboxUpdates*(
    items: varargs[(Id, MailboxUpdateSet)]
): NonEmptyMailboxUpdates =
  ## Non-Opt, non-empty wrapper factory. The ``varargs`` contract
  ## (``items.len >= 1`` at every call site) and the per-entry
  ## ``MailboxUpdateSet`` invariant together discharge
  ## ``parseNonEmptyMailboxUpdates``'s preconditions, so ``.get()``
  ## is total in context.
  parseNonEmptyMailboxUpdates(@items).get()

proc makeNonEmptyEmailUpdates*(
    items: varargs[(Id, EmailUpdateSet)]
): NonEmptyEmailUpdates =
  ## Non-Opt, non-empty wrapper factory. Mirrors
  ## ``makeNonEmptyMailboxUpdates``.
  parseNonEmptyEmailUpdates(@items).get()

# ---------------------------------------------------------------------------
# Mail Part G equality helpers
# ---------------------------------------------------------------------------
#
# The Part G source delivery (G1) ships explicit ``func ==`` operators for
# every case-object type covered here, plus borrowed ``==`` on the
# ``SubmissionParams`` and ``DeliveryStatusMap`` distinct tables. These
# wrappers therefore delegate to the source-side ``==`` rather than
# duplicating the arm-dispatch logic — one source of truth per fact (CLAUDE.md).
# The named call sites still exist so Phase 4 assertion wrappers and
# Phase 5/6 property/adversarial tests have stable symbols to consume.

proc anyEmailSubmissionEq*(a, b: AnyEmailSubmission): bool =
  ## Source ``==`` arm-dispatches over ``usPending`` / ``usFinal`` /
  ## ``usCanceled`` (``email_submission.nim:67``).
  a == b

proc submissionParamEq*(a, b: SubmissionParam): bool =
  ## Source ``==`` arm-dispatches over the 12 ``SubmissionParamKind``
  ## branches (``submission_param.nim:234``).
  a == b

proc submissionParamKeyEq*(a, b: SubmissionParamKey): bool =
  ## Source ``==`` dispatches the ``spkExtension`` arm against the 11
  ## nullary arms (``submission_param.nim:284``).
  a == b

proc submissionParamsEq*(a, b: SubmissionParams): bool =
  ## Source borrows ``==`` from the underlying ``OrderedTable``
  ## (``submission_param.nim:338``); insertion order participates in
  ## equality.
  a == b

proc reversePathEq*(a, b: ReversePath): bool =
  ## Source ``==`` arm-dispatches ``rpkNullPath`` vs ``rpkMailbox``
  ## (``submission_envelope.nim:73``).
  a == b

proc deliveryStatusMapEq*(a, b: DeliveryStatusMap): bool =
  ## Source borrows ``==`` from
  ## ``Table[RFC5321Mailbox, DeliveryStatus]`` (``submission_status.nim:264``).
  ## Key equality is byte-equal ``RFC5321Mailbox``.
  a == b

proc idOrCreationRefEq*(a, b: IdOrCreationRef): bool =
  ## Source ``==`` enforces cross-arm inequality even on coincident payload
  ## strings (``email_submission.nim:407``).
  a == b

proc keywordSetEq*(a, b: KeywordSet): bool =
  ## ``KeywordSet`` is ``distinct HashSet[Keyword]`` and deliberately does
  ## NOT borrow ``==`` (Decision B3 in ``defineHashSetDistinctOps`` —
  ## read-model sets are queried, never compared as wholes in the source
  ## domain). Cast through the underlying ``HashSet`` so its stdlib ``==``
  ## dispatches via the borrowed ``Keyword.==``. Required by
  ## ``emailUpdateEq`` for the ``euSetKeywords`` arm.
  HashSet[Keyword](a) == HashSet[Keyword](b)

proc emailUpdateEq*(a, b: EmailUpdate): bool =
  ## Arm-dispatched structural equality for the ``EmailUpdate`` case
  ## object (``email_update.nim:38``). Source provides no ``==`` because
  ## case objects can't auto-derive one (parallel ``fields`` iterator
  ## restriction) and the source code path needs equality nowhere — only
  ## tests do. Required by ``emailUpdateSetEq``.
  if a.kind != b.kind:
    return false
  case a.kind
  of euAddKeyword, euRemoveKeyword:
    a.keyword == b.keyword
  of euSetKeywords:
    keywordSetEq(a.keywords, b.keywords)
  of euAddToMailbox, euRemoveFromMailbox:
    a.mailboxId == b.mailboxId
  of euSetMailboxIds:
    a.mailboxes == b.mailboxes

proc emailUpdateSetEq*(a, b: EmailUpdateSet): bool =
  ## ``EmailUpdateSet`` is ``distinct seq[EmailUpdate]`` without a
  ## borrowed ``==``; the underlying ``seq[EmailUpdate]`` ``==`` would in
  ## turn require ``EmailUpdate.==``, which the source also omits.
  ## Manual element-wise comparison through ``emailUpdateEq``.
  let xs = seq[EmailUpdate](a)
  let ys = seq[EmailUpdate](b)
  if xs.len != ys.len:
    return false
  for i in 0 ..< xs.len:
    if not emailUpdateEq(xs[i], ys[i]):
      return false
  true

proc nonEmptyOnSuccessUpdateEmailEq*(a, b: NonEmptyOnSuccessUpdateEmail): bool =
  ## ``NonEmptyOnSuccessUpdateEmail`` is
  ## ``distinct Table[IdOrCreationRef, EmailUpdateSet]`` without a borrowed
  ## ``==`` in the source. Stdlib ``Table.==`` would require
  ## ``EmailUpdateSet.==`` (also absent), so we walk the underlying table
  ## ourselves: source-defined ``IdOrCreationRef.==`` /
  ## ``IdOrCreationRef.hash`` (``email_submission.nim:407``) drive key
  ## lookup, ``emailUpdateSetEq`` drives value equality.
  let aTable = Table[IdOrCreationRef, EmailUpdateSet](a)
  let bTable = Table[IdOrCreationRef, EmailUpdateSet](b)
  if aTable.len != bTable.len:
    return false
  for k, av in aTable:
    if not bTable.hasKey(k):
      return false
    if not emailUpdateSetEq(av, bTable[k]):
      return false
  true

# ---------------------------------------------------------------------------
# Mail Part G — EmailSubmission factories (RFC 8621 §7)
# ---------------------------------------------------------------------------

# Group 1 — RFC 5321 atom factories

proc makeRFC5321Mailbox*(raw = "user@example.com"): RFC5321Mailbox =
  parseRFC5321Mailbox(raw).get()

proc makeFullRFC5321Mailbox*(): RFC5321Mailbox =
  ## Exercises two non-trivial branches of the RFC 5321 §4.1.2 grammar in
  ## a single fixture: a quoted-string local-part carrying space + dot
  ## (neither legal in a dot-string), and an IPv6 address-literal domain
  ## in compressed form. Serves as the overlong-shape coverage fixture so
  ## edge-case-sensitive tests need not hand-roll the raw string.
  parseRFC5321Mailbox("\"Joe Q. Public\"@[IPv6:2001:db8::1]").get()

proc makeRFC5321Keyword*(raw = "X-VENDOR-FOO"): RFC5321Keyword =
  parseRFC5321Keyword(raw).get()

proc makeOrcptAddrType*(raw = "rfc822"): OrcptAddrType =
  parseOrcptAddrType(raw).get()

# Group 2 — SubmissionParam algebra factories

proc makeSubmissionParam*(kind: SubmissionParamKind): SubmissionParam =
  case kind
  of spkBody:
    bodyParam(beEightBitMime)
  of spkSmtpUtf8:
    smtpUtf8Param()
  of spkSize:
    sizeParam(parseUnsignedInt(1024).get())
  of spkEnvid:
    envidParam("envid-test")
  of spkRet:
    retParam(retFull)
  of spkNotify:
    notifyParam({dnfSuccess}).get()
  of spkOrcpt:
    orcptParam(makeOrcptAddrType(), "user@example.com")
  of spkHoldFor:
    holdForParam(parseHoldForSeconds(parseUnsignedInt(60).get()).get())
  of spkHoldUntil:
    holdUntilParam(parseUtcDate("2026-01-15T09:00:00Z").get())
  of spkBy:
    byParam(parseJmapInt(60).get(), dbmReturn)
  of spkMtPriority:
    mtPriorityParam(parseMtPriority(1).get())
  of spkExtension:
    extensionParam(makeRFC5321Keyword("X-TEST"), Opt.none(string))

proc makeFullSubmissionParams*(): SubmissionParams =
  ## Populates every ``SubmissionParamKind`` variant exactly once — the
  ## eleven IANA-registered well-known parameters plus a single
  ## ``spkExtension``. Chosen so a single fixture exercises every arm of
  ## ``paramKey`` derivation and every branch of ``SubmissionParam.==``
  ## in the tests that build on this one.
  parseSubmissionParams(
    @[
      makeSubmissionParam(spkBody),
      makeSubmissionParam(spkSmtpUtf8),
      makeSubmissionParam(spkSize),
      makeSubmissionParam(spkEnvid),
      makeSubmissionParam(spkRet),
      makeSubmissionParam(spkNotify),
      makeSubmissionParam(spkOrcpt),
      makeSubmissionParam(spkHoldFor),
      makeSubmissionParam(spkHoldUntil),
      makeSubmissionParam(spkBy),
      makeSubmissionParam(spkMtPriority),
      makeSubmissionParam(spkExtension),
    ]
  )
    .get()

proc makeSubmissionAddress*(
    mailbox: RFC5321Mailbox = makeRFC5321Mailbox(),
    parameters: Opt[SubmissionParams] = Opt.none(SubmissionParams),
): SubmissionAddress =
  SubmissionAddress(mailbox: mailbox, parameters: parameters)

proc makeFullSubmissionAddress*(): SubmissionAddress =
  ## Companion to ``makeFullSubmissionParams``. Binds the exhaustive
  ## parameter set onto a concrete mailbox so envelope-level tests reach
  ## every parameter variant through the natural ``Envelope.rcptTo``
  ## traversal rather than by constructing a detached ``SubmissionParams``.
  ##
  ## Mailbox differs from the default ``makeSubmissionAddress`` mailbox so
  ## a ``makeNonEmptyRcptList(@[makeFullSubmissionAddress(),
  ## makeSubmissionAddress()])`` combination satisfies the distinct-mailbox
  ## invariant on ``NonEmptyRcptList`` (RFC 8621 §7 ¶5 forbids duplicate
  ## recipients in the envelope).
  SubmissionAddress(
    mailbox: makeRFC5321Mailbox("rcptFull@example.com"),
    parameters: Opt.some(makeFullSubmissionParams()),
  )

proc makeNullReversePath*(
    params: Opt[SubmissionParams] = Opt.none(SubmissionParams)
): ReversePath =
  nullReversePath(params)

proc makeMailboxReversePath*(
    address: SubmissionAddress = makeSubmissionAddress()
): ReversePath =
  reversePath(address)

# Group 3 — Envelope factories

proc makeNonEmptyRcptList*(
    items: seq[SubmissionAddress] = @[makeSubmissionAddress()]
): NonEmptyRcptList =
  parseNonEmptyRcptList(items).get()

proc makeEnvelope*(
    mailFrom: ReversePath = makeMailboxReversePath(),
    rcptTo: NonEmptyRcptList = makeNonEmptyRcptList(),
): Envelope =
  Envelope(mailFrom: mailFrom, rcptTo: rcptTo)

proc makeFullEnvelope*(): Envelope =
  ## Two wire-shape divergences in one fixture: (a) a null reverse-path
  ## that nonetheless carries Mail-parameters — RFC 5321 §4.1.1.2 permits
  ## parameters on ``<>`` — and (b) a rcpt list mixing one address with
  ## parameters and one without, so the ``Opt[SubmissionParams]`` branch
  ## on ``SubmissionAddress`` is exercised twice in a single envelope.
  Envelope(
    mailFrom: makeNullReversePath(params = Opt.some(makeFullSubmissionParams())),
    rcptTo:
      makeNonEmptyRcptList(@[makeFullSubmissionAddress(), makeSubmissionAddress()]),
  )

# Group 4 — Status-type factories

proc makeSmtpReply*(raw = "250 OK"): ParsedSmtpReply =
  parseSmtpReply(raw).get()

proc makeDeliveryStatus*(
    smtpReply: ParsedSmtpReply = makeSmtpReply(),
    delivered: ParsedDeliveredState = parseDeliveredState("yes"),
    displayed: ParsedDisplayedState = parseDisplayedState("unknown"),
): DeliveryStatus =
  DeliveryStatus(smtpReply: smtpReply, delivered: delivered, displayed: displayed)

proc makeDeliveryStatusMap*(
    entries: seq[(RFC5321Mailbox, DeliveryStatus)] = @[]
): DeliveryStatusMap =
  var t = initTable[RFC5321Mailbox, DeliveryStatus](entries.len)
  for (k, v) in entries:
    t[k] = v
  DeliveryStatusMap(t)

# Group 5 — IdOrCreationRef variant factories

proc makeIdOrCreationRefDirect*(id: Id = makeId("es1")): IdOrCreationRef =
  directRef(id)

proc makeIdOrCreationRefCreation*(
    cid: CreationId = makeCreationId("k0")
): IdOrCreationRef =
  creationRef(cid)

# Group 6 — Phantom-typed EmailSubmission factories

proc makeEmailSubmission*[S: static UndoStatus](
    id: Id = makeId("es1"),
    identityId: Id = makeId("iden1"),
    emailId: Id = makeId("email1"),
    threadId: Id = makeId("thr1"),
    envelope: Opt[Envelope] = Opt.none(Envelope),
    sendAt: UTCDate = parseUtcDate("2026-01-15T09:00:00Z").get(),
    deliveryStatus: Opt[DeliveryStatusMap] = Opt.none(DeliveryStatusMap),
    dsnBlobIds: seq[BlobId] = @[],
    mdnBlobIds: seq[BlobId] = @[],
): EmailSubmission[S] =
  EmailSubmission[S](
    id: id,
    identityId: identityId,
    emailId: emailId,
    threadId: threadId,
    envelope: envelope,
    sendAt: sendAt,
    deliveryStatus: deliveryStatus,
    dsnBlobIds: dsnBlobIds,
    mdnBlobIds: mdnBlobIds,
  )

proc makeAnyEmailSubmission*(state: UndoStatus = usPending): AnyEmailSubmission =
  case state
  of usPending:
    toAny(makeEmailSubmission[usPending]())
  of usFinal:
    toAny(makeEmailSubmission[usFinal]())
  of usCanceled:
    toAny(makeEmailSubmission[usCanceled]())

proc makeEmailSubmissionBlueprint*(
    identityId: Id = makeId("iden1"),
    emailId: Id = makeId("email1"),
    envelope: Opt[Envelope] = Opt.none(Envelope),
): EmailSubmissionBlueprint =
  parseEmailSubmissionBlueprint(
    identityId = identityId, emailId = emailId, envelope = envelope
  )
    .get()

proc makeFullEmailSubmissionBlueprint*(): EmailSubmissionBlueprint =
  ## Non-default values in all three settable fields, binding the
  ## coverage-dense ``makeFullEnvelope`` so blueprint-round-trip tests
  ## reach every envelope arm through a single blueprint fixture rather
  ## than having to compose ``makeEmailSubmissionBlueprint`` by hand.
  parseEmailSubmissionBlueprint(
    identityId = makeId("idenFull"),
    emailId = makeId("emailFull"),
    envelope = Opt.some(makeFullEnvelope()),
  )
    .get()

# Group 7 — Compound handle factory

proc makeEmailSubmissionHandles*(
    submissionMcid: MethodCallId = makeMcid("c0"),
    emailSetMcid: MethodCallId = makeMcid("c0"),
): EmailSubmissionHandles =
  ## Both handles share one ``MethodCallId`` by default per RFC 8620 §5.4 —
  ## the implicit ``Email/set`` triggered by ``onSuccessUpdateEmail`` /
  ## ``onSuccessDestroyEmail`` shares its call-id with the parent
  ## ``EmailSubmission/set`` invocation. The two parameters are separate so
  ## adversarial tests (§8.2.3 Block 6 ``getBothInnerMcIdMismatch``) can
  ## pass divergent ids to exercise the dispatch mismatch branch.
  EmailSubmissionHandles(
    primary: ResponseHandle[EmailSubmissionSetResponse](submissionMcid),
    implicit: NameBoundHandle[SetResponse[EmailCreatedItem]](
      callId: emailSetMcid, methodName: mnEmailSet
    ),
  )
