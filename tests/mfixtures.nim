# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

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

import results

{.push ruleOff: "hasDoc".}

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/framework
import jmap_client/envelope
import jmap_client/errors
import jmap_client/serde

func zeroUint*(): UnsignedInt =
  parseUnsignedInt(0).get()

func makeMaxChanges*(n: int64 = 100): MaxChanges =
  parseMaxChanges(parseUnsignedInt(n).get()).get()

func makeId*(s = "testId"): Id =
  parseId(s).get()

func makeMcid*(s = "c0"): MethodCallId =
  parseMethodCallId(s).get()

func makeCreationId*(s = "k0"): CreationId =
  parseCreationId(s).get()

func makeState*(s = "state0"): JmapState =
  parseJmapState(s).get()

func makeAccountId*(s = "acct1"): AccountId =
  parseAccountId(s).get()

func makePropertyName*(s = "subject"): PropertyName =
  parsePropertyName(s).get()

func makeUriTemplate*(s = "https://example.com/{accountId}"): UriTemplate =
  parseUriTemplate(s).get()

func zeroCoreCaps*(): CoreCapabilities =
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

func realisticCoreCaps*(): CoreCapabilities =
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

func makeCoreServerCap*(caps = zeroCoreCaps()): ServerCapability =
  ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: caps)

func makeGoldenDownloadUrl*(): UriTemplate =
  parseUriTemplate(
    "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}"
  )
    .get()

func makeGoldenUploadUrl*(): UriTemplate =
  parseUriTemplate("https://jmap.example.com/upload/{accountId}/").get()

func makeGoldenEventSourceUrl*(): UriTemplate =
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

func parseSessionFromArgs*(args: SessionArgs): Result[Session, ValidationError] =
  ## Convenience wrapper around the 9-argument parseSession.
  parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )

func makeSessionArgs*(): SessionArgs =
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

func makeInvocation*(name = "Mailbox/get", mcid = makeMcid("c0")): Invocation =
  initInvocation(name, newJObject(), mcid)

func makeRequest*(
    `using`: seq[string] = @["urn:ietf:params:jmap:core"],
    methodCalls: seq[Invocation] = @[makeInvocation()],
    createdIds = Opt.none(Table[CreationId, Id]),
): Request =
  Request(`using`: `using`, methodCalls: methodCalls, createdIds: createdIds)

func makeResponse*(
    methodResponses: seq[Invocation] = @[makeInvocation()],
    state = makeState("rs1"),
    createdIds = Opt.none(Table[CreationId, Id]),
): Response =
  Response(
    methodResponses: methodResponses, createdIds: createdIds, sessionState: state
  )

func makeResultReference*(
    mcid = makeMcid("c0"), name = "Mailbox/get", path = RefPathIds
): ResultReference =
  ResultReference(resultOf: mcid, name: name, path: path)

# ---------------------------------------------------------------------------
# Error factories
# ---------------------------------------------------------------------------

func makeRequestError*(
    rawType = "urn:ietf:params:jmap:error:unknownCapability"
): RequestError =
  requestError(rawType)

func makeMethodError*(rawType = "serverFail"): MethodError =
  methodError(rawType)

# ---------------------------------------------------------------------------
# Server fixture factories
# ---------------------------------------------------------------------------

func makeFastmailSession*(): SessionArgs =
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

func makeMinimalSession*(): SessionArgs =
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

func makeSetErrorInvalidProperties*(
    properties: seq[string] = @["from", "subject"],
    description: Opt[string] = Opt.none(string),
): SetError =
  setErrorInvalidProperties("invalidProperties", properties, description)

func makeSetErrorAlreadyExists*(
    existingId: Id = makeId("existing1"), description: Opt[string] = Opt.none(string)
): SetError =
  setErrorAlreadyExists("alreadyExists", existingId, description)

# ---------------------------------------------------------------------------
# Framework factories
# ---------------------------------------------------------------------------

func makeComparator*(
    property: PropertyName = makePropertyName("subject"), isAscending = true
): Comparator =
  parseComparator(property, isAscending).get()

func makeComparatorWithCollation*(
    property: PropertyName = makePropertyName("subject"),
    isAscending = true,
    collation = "i;unicode-casemap",
): Comparator =
  parseComparator(property, isAscending, Opt.some(collation)).get()

func makeAddedItem*(id: Id = makeId("item1"), index: int64 = 0): AddedItem =
  initAddedItem(id, parseUnsignedInt(index).get())

# ---------------------------------------------------------------------------
# Filter factories
# ---------------------------------------------------------------------------

func makeFilterCondition*(condition = 42): Filter[int] =
  filterCondition(condition)

func makeFilterAnd*(children: seq[Filter[int]]): Filter[int] =
  filterOperator[int](foAnd, children)

func makeFilterOr*(children: seq[Filter[int]]): Filter[int] =
  filterOperator[int](foOr, children)

# ---------------------------------------------------------------------------
# Additional session fixture
# ---------------------------------------------------------------------------

func makeCyrusSession*(): SessionArgs =
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

func coreCapEq*(a, b: CoreCapabilities): bool =
  ## Field-by-field equality for CoreCapabilities, using subset check for
  ## HashSet collationAlgorithms (avoids megatest == resolution issues).
  a.maxSizeUpload == b.maxSizeUpload and a.maxConcurrentUpload == b.maxConcurrentUpload and
    a.maxSizeRequest == b.maxSizeRequest and
    a.maxConcurrentRequests == b.maxConcurrentRequests and
    a.maxCallsInRequest == b.maxCallsInRequest and a.maxObjectsInGet == b.maxObjectsInGet and
    a.maxObjectsInSet == b.maxObjectsInSet and
    a.collationAlgorithms.len == b.collationAlgorithms.len and
    a.collationAlgorithms <= b.collationAlgorithms

func capEq*(a, b: ServerCapability): bool =
  ## Deep value equality for ServerCapability (case object).
  if a.kind != b.kind or a.rawUri != b.rawUri:
    return false
  case a.kind
  of ckCore:
    coreCapEq(a.core, b.core)
  else:
    a.rawData == b.rawData

func capsEq*(a, b: seq[ServerCapability]): bool =
  ## Compares two sequences of ServerCapability by value.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if not capEq(a[i], b[i]):
      return false
  true

func sessionEq*(a, b: Session): bool =
  ## Deep value equality for Session (contains seq[ServerCapability]).
  capsEq(a.capabilities, b.capabilities) and a.accounts == b.accounts and
    a.primaryAccounts == b.primaryAccounts and a.username == b.username and
    a.apiUrl == b.apiUrl and a.downloadUrl == b.downloadUrl and
    a.uploadUrl == b.uploadUrl and a.eventSourceUrl == b.eventSourceUrl and
    a.state == b.state

func invEq*(a, b: Invocation): bool =
  ## Structural equality for Invocation including arguments.
  a.name == b.name and a.methodCallId == b.methodCallId and a.arguments == b.arguments

func reqEq*(a, b: Request): bool =
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

func respEq*(a, b: Response): bool =
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

func filterEq*(a, b: Filter[int]): bool =
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

func setErrorEq*(a, b: SetError): bool =
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
# Filter callback helpers
# ---------------------------------------------------------------------------

proc intToJson*(c: int): JsonNode {.noSideEffect, raises: [].} =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  {.cast(noSideEffect).}:
    %*{"value": c}

proc fromIntCondition*(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise a JSON object to int for Filter[int] tests.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))
