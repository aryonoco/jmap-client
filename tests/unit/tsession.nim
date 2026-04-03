# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for JMAP Session resource types.

import std/json
import std/options
import std/sets
import std/tables

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session

import ../massertions
import ../mfixtures

# =============================================================================
# Shared fixture values
# =============================================================================

let zero = parseUnsignedInt(0)

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

let acctId1 = parseAccountId("A13824")
let acctId2 = parseAccountId("A97813")

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

let goldenUploadUrl = parseUriTemplate("https://jmap.example.com/upload/{accountId}/")

let goldenEventSourceUrl = parseUriTemplate(
  "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}"
)

let goldenState = parseJmapState("75128aab4b1b")

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

# =============================================================================
# A. UriTemplate tests
# =============================================================================

block parseUriTemplateEmpty:
  assertErrFields parseUriTemplate(""), "UriTemplate", "must not be empty", ""

block parseUriTemplateValid:
  let tmpl = parseUriTemplate("https://example.com/{accountId}")
  doAssert $tmpl == "https://example.com/{accountId}"

block uriTemplateBorrowedOps:
  let a = parseUriTemplate("https://example.com/{id}")
  let b = parseUriTemplate("https://example.com/{id}")
  let c = parseUriTemplate("https://other.com/")
  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "https://example.com/{id}"
  doAssert hash(a) == hash(b)
  doAssert a.len == 24

block hasVariablePresent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}")
  doAssert tmpl.hasVariable("accountId")

block hasVariableAbsent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}")
  doAssert not tmpl.hasVariable("nonexistent")

block hasVariablePartialMatch:
  let tmpl = parseUriTemplate("https://example.com/{accountId}")
  doAssert not tmpl.hasVariable("account")

# =============================================================================
# B. Account helper tests
# =============================================================================

block accountFindCapabilityByKind:
  let result = findCapability(testAccount, ckMail)
  doAssert result.isSome
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

block accountFindCapabilityNotFound:
  doAssert findCapability(testAccount, ckBlob).isNone

block accountFindCapabilityFirstCkUnknown:
  let result = findCapability(testAccount, ckUnknown)
  doAssert result.isSome
  doAssert result.get().rawUri == "https://vendor1.example/ext"

block accountFindCapabilityByUri:
  let result = findCapabilityByUri(testAccount, "urn:ietf:params:jmap:mail")
  doAssert result.isSome
  doAssert result.get().kind == ckMail

block accountFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(testAccount, "urn:nonexistent").isNone

block accountHasCapability:
  doAssert hasCapability(testAccount, ckMail)
  doAssert not hasCapability(testAccount, ckBlob)

# =============================================================================
# C. parseSession validation
# =============================================================================

block parseSessionMissingCkCore:
  assertErrFields parseSession(
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
  ), "Session", "capabilities must include urn:ietf:params:jmap:core", ""

block parseSessionEmptyApiUrl:
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  ), "Session", "apiUrl must not be empty", ""

block parseSessionDownloadUrlMissingBlobId:
  let badDownload =
    parseUriTemplate("https://example.com/{accountId}/{name}?accept={type}")
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = badDownload,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  ),
    "Session",
    "downloadUrl missing {blobId}",
    "https://example.com/{accountId}/{name}?accept={type}"

block parseSessionDownloadUrlMissingAccountId:
  let badDownload =
    parseUriTemplate("https://example.com/{blobId}/{name}?accept={type}")
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = badDownload,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  ),
    "Session",
    "downloadUrl missing {accountId}",
    "https://example.com/{blobId}/{name}?accept={type}"

block parseSessionUploadUrlMissingAccountId:
  let badUpload = parseUriTemplate("https://example.com/upload/")
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = badUpload,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  ), "Session", "uploadUrl missing {accountId}", "https://example.com/upload/"

block parseSessionEventSourceUrlMissingTypes:
  let badEvent =
    parseUriTemplate("https://example.com/events?closeafter={closeafter}&ping={ping}")
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = badEvent,
    state = goldenState,
  ),
    "Session",
    "eventSourceUrl missing {types}",
    "https://example.com/events?closeafter={closeafter}&ping={ping}"

block parseSessionEventSourceUrlMissingPing:
  let badEvent =
    parseUriTemplate("https://example.com/events?types={types}&closeafter={closeafter}")
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "",
    apiUrl = "https://jmap.example.com/api/",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = badEvent,
    state = goldenState,
  ),
    "Session",
    "eventSourceUrl missing {ping}",
    "https://example.com/events?types={types}&closeafter={closeafter}"

block parseSessionValid:
  let s = parseSession(
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
  doAssert s.username == "john@example.com"
  doAssert s.apiUrl == "https://jmap.example.com/api/"
  doAssert s.state == goldenState
  doAssert s.capabilities.len == 5
  doAssert s.accounts.len == 2

# =============================================================================
# D. Session accessor helpers
# =============================================================================

block coreCapabilitiesAccess:
  let core = coreCapabilities(goldenSession)
  doAssert core.maxSizeUpload == zero

block sessionFindCapabilityByKind:
  let result = findCapability(goldenSession, ckMail)
  doAssert result.isSome
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

block sessionFindCapabilityByKindNotFound:
  doAssert findCapability(goldenSession, ckBlob).isNone

block sessionFindCapabilityFirstCkUnknown:
  let result = findCapability(goldenSession, ckUnknown)
  doAssert result.isSome
  doAssert result.get().rawUri == "https://example.com/apis/foobar"

block sessionFindCapabilityByUriVendor:
  let result = findCapabilityByUri(goldenSession, "https://example.com/apis/foobar")
  doAssert result.isSome
  doAssert result.get().kind == ckUnknown

block sessionFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(goldenSession, "urn:nonexistent").isNone

block primaryAccountMail:
  let result = primaryAccount(goldenSession, ckMail)
  doAssert result.isSome
  doAssert result.get() == AccountId("A13824")

block primaryAccountUnknown:
  doAssert primaryAccount(goldenSession, ckUnknown).isNone

block primaryAccountBlob:
  doAssert primaryAccount(goldenSession, ckBlob).isNone

block findAccountKnown:
  let result = findAccount(goldenSession, AccountId("A13824"))
  doAssert result.isSome
  doAssert result.get().name == "john@example.com"

block findAccountUnknown:
  doAssert findAccount(goldenSession, AccountId("nonexistent")).isNone

# =============================================================================
# E. Invariant violation — tested in tsession_invariant.nim (panics:on)
# =============================================================================

# =============================================================================
# G. Adversarial edge cases
# =============================================================================

block parseSessionDuplicateCkCore:
  let caps = @[makeCoreServerCap(), makeCoreServerCap()]
  let args = makeSessionArgs()
  assertOk parseSession(
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

block parseSessionNestedBraces:
  let dl = parseUriTemplate("https://e.com/{{accountId}}/{blobId}/{type}/{name}")
  let args = makeSessionArgs()
  assertOk parseSession(
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

# =============================================================================
# H. Missing session URL variable validations
# =============================================================================

block parseSessionDownloadUrlMissingType:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}/{name}")
  let args = makeSessionArgs()
  assertErrFields parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = badDl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  ),
    "Session", "downloadUrl missing {type}", "https://e.com/{accountId}/{blobId}/{name}"

block parseSessionDownloadUrlMissingName:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}?accept={type}")
  let args = makeSessionArgs()
  assertErrFields parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = badDl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = args.eventSourceUrl,
    state = args.state,
  ),
    "Session",
    "downloadUrl missing {name}",
    "https://e.com/{accountId}/{blobId}?accept={type}"

block parseSessionEventSourceMissingCloseafter:
  let badEs = parseUriTemplate("https://e.com/events?types={types}&ping={ping}")
  let args = makeSessionArgs()
  assertErrFields parseSession(
    capabilities = args.capabilities,
    accounts = args.accounts,
    primaryAccounts = args.primaryAccounts,
    username = args.username,
    apiUrl = args.apiUrl,
    downloadUrl = args.downloadUrl,
    uploadUrl = args.uploadUrl,
    eventSourceUrl = badEs,
    state = args.state,
  ),
    "Session",
    "eventSourceUrl missing {closeafter}",
    "https://e.com/events?types={types}&ping={ping}"

block parseSessionEmptyAccounts:
  let args = makeSessionArgs()
  assertOk parseSession(
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

block parseSessionEmptyPrimaryAccounts:
  let args = makeSessionArgs()
  assertOk parseSession(
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

# =============================================================================
# I. Additional edge cases
# =============================================================================

block parseSessionWhitespaceOnlyApiUrl:
  ## Whitespace-only apiUrl passes the non-empty check. Documented as accepted
  ## because URL validation is a Layer 4 concern.
  let args = makeSessionArgs()
  assertOk parseSession(
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

block hasVariablePrefixOfLongerName:
  ## Template "{accountIdFull}" does NOT match variable "accountId" because
  ## hasVariable checks for the exact "{accountId}" substring.
  let tmpl = parseUriTemplate("https://e.com/{accountIdFull}")
  doAssert not hasVariable(tmpl, "accountId")

block hasVariableSuffixOfLongerName:
  ## Template "{fullAccountId}" does NOT contain "{accountId}" as substring.
  let tmpl = parseUriTemplate("https://e.com/{fullAccountId}")
  doAssert not hasVariable(tmpl, "accountId")

# =============================================================================
# J. Session template variable mutation resistance
# =============================================================================

block parseSessionExtraDownloadVariables:
  ## RFC 6570 allows extra variables beyond the required set.
  let args = makeSessionArgs()
  let extraUrl = parseUriTemplate(
    "https://example.com/{accountId}/{blobId}/{name}?accept={type}&extra={foo}"
  )
  let res = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    extraUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  assertOk res

block parseSessionEmptyAccountsValid:
  ## Empty accounts and primaryAccounts tables are valid.
  let args = makeMinimalSession()
  let res = parseSessionFromArgs(args)
  assertOk res

# =============================================================================
# K. Session accessor zero-coverage gaps
# =============================================================================

block findCapabilitySessionFoundContacts:
  ## findCapability(session, ckContacts) returns when present.
  let result = findCapability(goldenSession, ckContacts)
  assertSome result
  doAssert result.get().rawUri == "urn:ietf:params:jmap:contacts"

block findCapabilityByUriSessionFoundCore:
  ## findCapabilityByUri(session) returns the matching capability.
  let result = findCapabilityByUri(goldenSession, "urn:ietf:params:jmap:core")
  assertSome result
  doAssert result.get().kind == ckCore

block findCapabilityByUriSessionFoundVendor:
  ## findCapabilityByUri(session) disambiguates vendor extensions by URI.
  let result = findCapabilityByUri(goldenSession, "https://vendor2.example/ext")
  assertSome result
  doAssert result.get().kind == ckUnknown

block findCapabilityByUriSessionNotFound:
  ## findCapabilityByUri(session) returns none for absent URI.
  assertNone findCapabilityByUri(goldenSession, "urn:nonexistent:capability")

block primaryAccountContacts:
  ## primaryAccount returns the designated primary for ckContacts.
  let result = primaryAccount(goldenSession, ckContacts)
  assertSome result
  doAssert result.get() == AccountId("A13824")

block primaryAccountNotDesignated:
  ## primaryAccount returns none when no primary is designated for the kind.
  assertNone primaryAccount(goldenSession, ckCalendars)

block primaryAccountCkUnknownReturnsNone:
  ## primaryAccount returns none for ckUnknown (no canonical URI).
  assertNone primaryAccount(goldenSession, ckUnknown)

block findAccountFoundSecond:
  ## findAccount returns the correct account for the second AccountId.
  let result = findAccount(goldenSession, AccountId("A97813"))
  assertSome result
  doAssert result.get().name == "jane@example.com"
  doAssert result.get().isReadOnly == true

block findAccountNotFound:
  ## findAccount returns none for an unknown AccountId.
  assertNone findAccount(goldenSession, AccountId("ZZZZZZ"))

# =============================================================================
# L. Account accessor zero-coverage gaps
# =============================================================================

block accountFindCapabilityByUriFoundVendor:
  ## findCapabilityByUri(account) finds vendor extension by exact URI.
  let result = findCapabilityByUri(testAccount, "https://vendor2.example/ext")
  assertSome result
  doAssert result.get().kind == ckUnknown
  doAssert result.get().data == %*{"v": 2}

block accountFindCapabilityByUriNotFound:
  ## findCapabilityByUri(account) returns none for absent URI.
  assertNone findCapabilityByUri(testAccount, "urn:nonexistent:nothing")

block accountFindCapabilityByUriVendorExtension:
  ## findCapabilityByUri(account) disambiguates between multiple ckUnknown entries.
  let result1 = findCapabilityByUri(testAccount, "https://vendor1.example/ext")
  assertSome result1
  doAssert result1.get().data == %*{"v": 1}
  let result2 = findCapabilityByUri(testAccount, "https://vendor2.example/ext")
  assertSome result2
  doAssert result2.get().data == %*{"v": 2}

block accountHasCapabilityCkUnknown:
  ## hasCapability returns true for ckUnknown when vendor extensions exist.
  doAssert hasCapability(testAccount, ckUnknown)

# =============================================================================
# M. UriTemplate and hasVariable zero-coverage gaps
# =============================================================================

block parseUriTemplateSingleChar:
  ## parseUriTemplate accepts a single-character string.
  let tmpl = parseUriTemplate("x")
  assertOk tmpl
  doAssert $tmpl == "x"
