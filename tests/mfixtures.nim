# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Shared test fixture factories. Returns fresh instances to avoid module-level
## mutation risk. Imported by t-prefixed test files.

import std/sets
import std/tables
from std/json import newJObject, JsonNode

import pkg/results

{.push ruleOff: "hasDoc".}

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/framework
import jmap_client/envelope
import jmap_client/errors

func zeroUint*(): UnsignedInt =
  parseUnsignedInt(0).get()

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
  Invocation(name: name, arguments: newJObject(), methodCallId: mcid)

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

func makeTransportError*(
    kind = tekNetwork, message = "connection refused"
): TransportError =
  case kind
  of tekHttpStatus:
    httpStatusError(500, message)
  of tekNetwork, tekTls, tekTimeout:
    transportError(kind, message)

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
