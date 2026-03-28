# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for JMAP Session resource types.

import std/hashes
import std/json
import std/sets
import std/tables

import pkg/results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session

import ./massertions
import ./mfixtures

# Shared fixture values used across multiple test blocks.

let zero = parseUnsignedInt(0).get()

let testCoreCaps = CoreCapabilities(
  maxSizeUpload: zero,
  maxConcurrentUpload: zero,
  maxSizeRequest: zero,
  maxConcurrentRequests: zero,
  maxCallsInRequest: zero,
  maxObjectsInGet: zero,
  maxObjectsInSet: zero,
  collationAlgorithms: initHashSet[string](),
)

let testAccount = Account(
  name: "Test",
  isPersonal: true,
  isReadOnly: false,
  accountCapabilities: @[
    AccountCapabilityEntry(
      kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJNull()
    ),
    AccountCapabilityEntry(
      kind: ckUnknown, rawUri: "https://vendor1.example/ext", data: %*{"v": 1}
    ),
    AccountCapabilityEntry(
      kind: ckUnknown, rawUri: "https://vendor2.example/ext", data: %*{"v": 2}
    ),
  ],
)

# Golden test session built at module level so accessor tests can reference it.

let acctId1 = parseAccountId("A13824").get()
let acctId2 = parseAccountId("A97813").get()

let goldenAccount1 = Account(
  name: "john@example.com",
  isPersonal: true,
  isReadOnly: false,
  accountCapabilities: @[
    AccountCapabilityEntry(
      kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: %*{}
    ),
    AccountCapabilityEntry(
      kind: ckContacts, rawUri: "urn:ietf:params:jmap:contacts", data: %*{}
    ),
    AccountCapabilityEntry(
      kind: ckUnknown, rawUri: "https://example.com/apis/foobar", data: %*{"maxFoo": 42}
    ),
  ],
)

let goldenAccount2 = Account(
  name: "jane@example.com",
  isPersonal: false,
  isReadOnly: true,
  accountCapabilities: @[
    AccountCapabilityEntry(
      kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: %*{}
    )
  ],
)

let goldenAccounts = block:
  var t = initTable[AccountId, Account]()
  t[acctId1] = goldenAccount1
  t[acctId2] = goldenAccount2
  t

let goldenPrimaryAccounts = block:
  var t = initTable[string, AccountId]()
  t["urn:ietf:params:jmap:mail"] = acctId1
  t["urn:ietf:params:jmap:contacts"] = acctId1
  t

let goldenDownloadUrl = parseUriTemplate(
    "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}"
  )
  .get()

let goldenUploadUrl =
  parseUriTemplate("https://jmap.example.com/upload/{accountId}/").get()

let goldenEventSourceUrl = parseUriTemplate(
    "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}"
  )
  .get()

let goldenState = parseJmapState("75128aab4b1b").get()

let goldenCaps = @[
  ServerCapability(
    rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: testCoreCaps
  ),
  ServerCapability(
    rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJNull()
  ),
  ServerCapability(
    rawUri: "urn:ietf:params:jmap:contacts", kind: ckContacts, rawData: newJNull()
  ),
  ServerCapability(
    rawUri: "https://example.com/apis/foobar",
    kind: ckUnknown,
    rawData: %*{"maxFoo": 42},
  ),
  ServerCapability(
    rawUri: "https://vendor2.example/ext", kind: ckUnknown, rawData: %*{"v": 2}
  ),
]

let goldenSession = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  .get()

# --- UriTemplate ---

block parseUriTemplateEmpty:
  assertErrFields parseUriTemplate(""), "UriTemplate", "must not be empty", ""

block parseUriTemplateValid:
  let result = parseUriTemplate("https://example.com/{accountId}")
  doAssert result.isOk
  doAssert $result.get() == "https://example.com/{accountId}"

block uriTemplateBorrowedOps:
  let a = parseUriTemplate("https://example.com/{id}").get()
  let b = parseUriTemplate("https://example.com/{id}").get()
  let c = parseUriTemplate("https://other.com/").get()
  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "https://example.com/{id}"
  doAssert hash(a) == hash(b)
  doAssert a.len == 24

block hasVariablePresent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert tmpl.hasVariable("accountId")

block hasVariableAbsent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert not tmpl.hasVariable("nonexistent")

block hasVariablePartialMatch:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert not tmpl.hasVariable("account")

# --- Account helpers ---

block accountFindCapabilityByKind:
  let result = findCapability(testAccount, ckMail)
  doAssert result.isOk
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

block accountFindCapabilityNotFound:
  doAssert findCapability(testAccount, ckBlob).isErr

block accountFindCapabilityFirstCkUnknown:
  let result = findCapability(testAccount, ckUnknown)
  doAssert result.isOk
  doAssert result.get().rawUri == "https://vendor1.example/ext"

block accountFindCapabilityByUri:
  let result = findCapabilityByUri(testAccount, "urn:ietf:params:jmap:mail")
  doAssert result.isOk
  doAssert result.get().kind == ckMail

block accountFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(testAccount, "urn:nonexistent").isErr

block accountHasCapability:
  doAssert hasCapability(testAccount, ckMail)
  doAssert not hasCapability(testAccount, ckBlob)

# --- parseSession validation ---

block parseSessionMissingCkCore:
  let noCoreResult = parseSession(
    capabilities = @[
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJNull()
      )
    ],
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields noCoreResult,
    "Session", "capabilities must include urn:ietf:params:jmap:core", ""

block parseSessionEmptyApiUrl:
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result, "Session", "apiUrl must not be empty", ""

block parseSessionDownloadUrlMissingBlobId:
  let badDownload =
    parseUriTemplate("https://example.com/{accountId}/{name}?accept={type}").get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = badDownload,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "downloadUrl missing {blobId}",
    "https://example.com/{accountId}/{name}?accept={type}"

block parseSessionDownloadUrlMissingAccountId:
  let badDownload =
    parseUriTemplate("https://example.com/{blobId}/{name}?accept={type}").get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = badDownload,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "downloadUrl missing {accountId}",
    "https://example.com/{blobId}/{name}?accept={type}"

block parseSessionUploadUrlMissingAccountId:
  let badUpload = parseUriTemplate("https://example.com/upload/").get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = badUpload,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "uploadUrl missing {accountId}", "https://example.com/upload/"

block parseSessionEventSourceUrlMissingTypes:
  let badEvent = parseUriTemplate(
      "https://example.com/events?closeafter={closeafter}&ping={ping}"
    )
    .get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = badEvent,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "eventSourceUrl missing {types}",
    "https://example.com/events?closeafter={closeafter}&ping={ping}"

block parseSessionEventSourceUrlMissingPing:
  let badEvent = parseUriTemplate(
      "https://example.com/events?types={types}&closeafter={closeafter}"
    )
    .get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = badEvent,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "eventSourceUrl missing {ping}",
    "https://example.com/events?types={types}&closeafter={closeafter}"

block parseSessionValid:
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  doAssert result.isOk
  let s = result.get()
  doAssert s.username == "john@example.com"
  doAssert s.apiUrl == "https://jmap.example.com/api/"
  doAssert s.state == goldenState
  doAssert s.capabilities.len == 5
  doAssert s.accounts.len == 2

# --- Session accessor helpers ---

block coreCapabilitiesAccess:
  let core = coreCapabilities(goldenSession)
  doAssert core.maxSizeUpload == zero

block sessionFindCapabilityByKind:
  let result = findCapability(goldenSession, ckMail)
  doAssert result.isOk
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

block sessionFindCapabilityByKindNotFound:
  doAssert findCapability(goldenSession, ckBlob).isErr

block sessionFindCapabilityFirstCkUnknown:
  let result = findCapability(goldenSession, ckUnknown)
  doAssert result.isOk
  doAssert result.get().rawUri == "https://example.com/apis/foobar"

block sessionFindCapabilityByUriVendor:
  let result = findCapabilityByUri(goldenSession, "https://example.com/apis/foobar")
  doAssert result.isOk
  doAssert result.get().kind == ckUnknown

block sessionFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(goldenSession, "urn:nonexistent").isErr

block primaryAccountMail:
  let result = primaryAccount(goldenSession, ckMail)
  doAssert result.isOk
  doAssert result.get() == AccountId("A13824")

block primaryAccountUnknown:
  doAssert primaryAccount(goldenSession, ckUnknown).isErr

block primaryAccountBlob:
  doAssert primaryAccount(goldenSession, ckBlob).isErr

block findAccountKnown:
  let result = findAccount(goldenSession, AccountId("A13824"))
  doAssert result.isOk
  doAssert result.get().name == "john@example.com"

block findAccountUnknown:
  doAssert findAccount(goldenSession, AccountId("nonexistent")).isErr

# --- Invariant violation ---

block coreCapabilitiesInvariantViolation:
  doAssertRaises(AssertionDefect):
    let badSession = Session(
      capabilities: @[],
      accounts: initTable[AccountId, Account](),
      primaryAccounts: initTable[string, AccountId](),
      username: "",
      apiUrl: "https://example.com/api/",
      downloadUrl: parseUriTemplate("https://example.com/d").get(),
      uploadUrl: parseUriTemplate("https://example.com/u").get(),
      eventSourceUrl: parseUriTemplate("https://example.com/e").get(),
      state: parseJmapState("s1").get(),
    )
    discard coreCapabilities(badSession)

# --- Error content assertions ---

block parseSessionErrorContentMissingCkCore:
  let result = parseSession(
    capabilities = @[
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJNull()
      )
    ],
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result,
    "Session", "capabilities must include urn:ietf:params:jmap:core", ""

block parseSessionErrorContentEmptyApiUrl:
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrFields result, "Session", "apiUrl must not be empty", ""

block parseSessionErrorContentDownloadMissing:
  let badDl =
    parseUriTemplate("https://example.com/{accountId}/{name}?accept={type}").get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = badDl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrMsg result, "downloadUrl missing {blobId}"

block parseSessionErrorContentUploadMissing:
  let badUp = parseUriTemplate("https://example.com/upload/").get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = badUp,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  )
  assertErrMsg result, "uploadUrl missing {accountId}"

block parseSessionErrorContentEventSourceMissing:
  let badEs = parseUriTemplate(
      "https://example.com/events?closeafter={closeafter}&ping={ping}"
    )
    .get()
  let result = parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = badEs,
    state = goldenState,
  )
  assertErrMsg result, "eventSourceUrl missing {types}"

# --- Adversarial edge cases ---

block parseSessionDuplicateCkCore:
  let caps = @[makeCoreServerCap(), makeCoreServerCap()]
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = caps,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  doAssert result.isOk

block parseSessionNestedBraces:
  let dl = parseUriTemplate("https://e.com/{{accountId}}/{blobId}/{type}/{name}").get()
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = dl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  doAssert result.isOk

# --- Missing session validations ---

block parseSessionDownloadUrlMissingType:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}/{name}").get()
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = badDl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  assertErrFields result,
    "Session", "downloadUrl missing {type}", "https://e.com/{accountId}/{blobId}/{name}"

block parseSessionDownloadUrlMissingName:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}?accept={type}").get()
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = badDl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  assertErrFields result,
    "Session", "downloadUrl missing {name}",
    "https://e.com/{accountId}/{blobId}?accept={type}"

block parseSessionEventSourceMissingCloseafter:
  let badEs = parseUriTemplate("https://e.com/events?types={types}&ping={ping}").get()
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = badEs,
    state = args.state,
  )
  assertErrFields result,
    "Session", "eventSourceUrl missing {closeafter}",
    "https://e.com/events?types={types}&ping={ping}"

block parseSessionEmptyAccounts:
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = initTable[AccountId, Account](),
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  doAssert result.isOk

block parseSessionEmptyPrimaryAccounts:
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = initTable[string, AccountId](),
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  doAssert result.isOk

# --- Additional edge cases ---

block parseSessionWhitespaceOnlyApiUrl:
  ## Whitespace-only apiUrl passes the non-empty check. Documented as accepted
  ## because URL validation is a Layer 4 concern.
  let args = makeSessionArgs()
  let result = parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = "   ",
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  )
  doAssert result.isOk

block hasVariablePrefixOfLongerName:
  ## Template "{accountIdFull}" does NOT match variable "accountId" because
  ## hasVariable checks for the exact "{accountId}" substring.
  let tmpl = parseUriTemplate("https://e.com/{accountIdFull}").get()
  doAssert not hasVariable(tmpl, "accountId")

block hasVariableSuffixOfLongerName:
  ## Template "{fullAccountId}" does NOT contain "{accountId}" as substring.
  let tmpl = parseUriTemplate("https://e.com/{fullAccountId}").get()
  doAssert not hasVariable(tmpl, "accountId")

# --- Phase 4: Session template variable mutation resistance ---

block parseSessionExtraDownloadVariables:
  ## RFC 6570 allows extra variables beyond the required set.
  let args = makeSessionArgs()
  let extraUrl = parseUriTemplate(
      "https://example.com/{accountId}/{blobId}/{name}?accept={type}&extra={foo}"
    )
    .get()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    extraUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertOk res

block parseSessionUploadUrlNoVariables:
  ## uploadUrl with no variables at all is rejected — missing {accountId}.
  let args = makeSessionArgs()
  let badUpload = parseUriTemplate("https://example.com/upload/").get()
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, badUpload, args.eventSourceUrl, args.state,
  )
  assertErr res

block parseSessionDuplicateCkCoreAccepted:
  ## Multiple ckCore capabilities are accepted — first is used.
  var args = makeSessionArgs()
  args.capabilities.add makeCoreServerCap()
  let res = parseSessionFromArgs(args)
  assertOk res

block parseSessionEmptyAccountsValid:
  ## Empty accounts and primaryAccounts tables are valid.
  let args = makeMinimalSession()
  let res = parseSessionFromArgs(args)
  assertOk res
