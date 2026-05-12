# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for JMAP Session resource types.

import std/json
import std/sets
import std/strutils
import std/tables

import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session
import jmap_client/internal/types/validation

import ../massertions
import ../mfixtures
import ../mtestblock

# =============================================================================
# Shared fixture values
# =============================================================================

let zero = parseUnsignedInt(0).get()

let testCoreCaps = CoreCapabilities(
  maxSizeUpload: zero,
  maxConcurrentUpload: zero,
  maxSizeRequest: zero,
  maxConcurrentRequests: zero,
  maxCallsInRequest: zero,
  maxObjectsInGet: zero,
  maxObjectsInSet: zero,
  collationAlgorithms: initHashSet[CollationAlgorithm](),
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

# =============================================================================
# A. UriTemplate tests
# =============================================================================

testCase parseUriTemplateEmpty:
  assertErrFields parseUriTemplate(""), "UriTemplate", "must not be empty", ""

testCase parseUriTemplateValid:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert $tmpl == "https://example.com/{accountId}"

testCase uriTemplateBorrowedOps:
  ## Now a case object; ``len`` was a borrow-only hangover from the
  ## previous ``distinct string`` representation and is dropped. Source
  ## length is recovered via ``$`` when needed.
  let a = parseUriTemplate("https://example.com/{id}").get()
  let b = parseUriTemplate("https://example.com/{id}").get()
  let c = parseUriTemplate("https://other.com/").get()
  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "https://example.com/{id}"
  doAssert hash(a) == hash(b)
  doAssert ($a).len == 24

testCase hasVariablePresent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert tmpl.hasVariable("accountId")

testCase hasVariableAbsent:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert not tmpl.hasVariable("nonexistent")

testCase hasVariablePartialMatch:
  let tmpl = parseUriTemplate("https://example.com/{accountId}").get()
  doAssert not tmpl.hasVariable("account")

# =============================================================================
# B. Account helper tests
# =============================================================================

testCase accountFindCapabilityByKind:
  let result = findCapability(testAccount, ckMail)
  doAssert result.isSome
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

testCase accountFindCapabilityNotFound:
  doAssert findCapability(testAccount, ckBlob).isNone

testCase accountFindCapabilityFirstCkUnknown:
  let result = findCapability(testAccount, ckUnknown)
  doAssert result.isSome
  doAssert result.get().rawUri == "https://vendor1.example/ext"

testCase accountFindCapabilityByUri:
  let result = findCapabilityByUri(testAccount, "urn:ietf:params:jmap:mail")
  doAssert result.isSome
  doAssert result.get().kind == ckMail

testCase accountFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(testAccount, "urn:nonexistent").isNone

testCase accountHasCapability:
  doAssert hasCapability(testAccount, ckMail)
  doAssert not hasCapability(testAccount, ckBlob)

# =============================================================================
# C. parseSession validation
# =============================================================================

testCase parseSessionMissingCkCore:
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

testCase parseSessionEmptyApiUrl:
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

testCase parseSessionApiUrlNewline:
  ## apiUrl with newline characters rejected (prevents doAssert crash in
  ## std/httpclient when used by Layer 4 IO procs).
  assertErrFields parseSession(
    capabilities = goldenCaps,
    accounts = goldenAccounts,
    primaryAccounts = goldenPrimaryAccounts,
    username = "john@example.com",
    apiUrl = "https://jmap.example.com/api/\r\nEvil: header",
    downloadUrl = goldenDownloadUrl,
    uploadUrl = goldenUploadUrl,
    eventSourceUrl = goldenEventSourceUrl,
    state = goldenState,
  ),
    "Session",
    "apiUrl must not contain newline characters",
    "https://jmap.example.com/api/\r\nEvil: header"

testCase parseSessionDownloadUrlMissingBlobId:
  let badDownload =
    parseUriTemplate("https://example.com/{accountId}/{name}?accept={type}").get()
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

testCase parseSessionDownloadUrlMissingAccountId:
  let badDownload =
    parseUriTemplate("https://example.com/{blobId}/{name}?accept={type}").get()
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

testCase parseSessionUploadUrlMissingAccountId:
  let badUpload = parseUriTemplate("https://example.com/upload/").get()
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

testCase parseSessionEventSourceUrlMissingTypes:
  let badEvent = parseUriTemplate(
      "https://example.com/events?closeafter={closeafter}&ping={ping}"
    )
    .get()
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

testCase parseSessionEventSourceUrlMissingPing:
  let badEvent = parseUriTemplate(
      "https://example.com/events?types={types}&closeafter={closeafter}"
    )
    .get()
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

testCase parseSessionValid:
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
    .get()
  doAssert s.username == "john@example.com"
  doAssert s.apiUrl == "https://jmap.example.com/api/"
  doAssert s.state == goldenState
  doAssert s.capabilities.len == 5
  doAssert s.accounts.len == 2

# =============================================================================
# D. Session accessor helpers
# =============================================================================

testCase coreCapabilitiesAccess:
  let core = coreCapabilities(goldenSession)
  doAssert core.maxSizeUpload == zero

testCase sessionFindCapabilityByKind:
  let result = findCapability(goldenSession, ckMail)
  doAssert result.isSome
  doAssert result.get().rawUri == "urn:ietf:params:jmap:mail"

testCase sessionFindCapabilityByKindNotFound:
  doAssert findCapability(goldenSession, ckBlob).isNone

testCase sessionFindCapabilityFirstCkUnknown:
  let result = findCapability(goldenSession, ckUnknown)
  doAssert result.isSome
  doAssert result.get().rawUri == "https://example.com/apis/foobar"

testCase sessionFindCapabilityByUriVendor:
  let result = findCapabilityByUri(goldenSession, "https://example.com/apis/foobar")
  doAssert result.isSome
  doAssert result.get().kind == ckUnknown

testCase sessionFindCapabilityByUriNotFound:
  doAssert findCapabilityByUri(goldenSession, "urn:nonexistent").isNone

testCase primaryAccountMail:
  let result = primaryAccount(goldenSession, ckMail)
  doAssert result.isSome
  doAssert result.get() == AccountId("A13824")

testCase primaryAccountUnknown:
  doAssert primaryAccount(goldenSession, ckUnknown).isNone

testCase primaryAccountBlob:
  doAssert primaryAccount(goldenSession, ckBlob).isNone

testCase findAccountKnown:
  let result = findAccount(goldenSession, AccountId("A13824"))
  doAssert result.isSome
  doAssert result.get().name == "john@example.com"

testCase findAccountUnknown:
  doAssert findAccount(goldenSession, AccountId("nonexistent")).isNone

# =============================================================================
# E. Invariant violation — tested in tsession_invariant.nim (panics:on)
# =============================================================================

# =============================================================================
# G. Adversarial edge cases
# =============================================================================

testCase parseSessionDuplicateCkCore:
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

testCase parseSessionNestedBracesRejectedAtParse:
  ## Nested ``{{accountId}}`` is rejected at ``parseUriTemplate`` rather
  ## than being round-tripped via substring search. Session construction
  ## never sees a malformed template; the error surfaces at the serde
  ## boundary or the explicit constructor call.
  let res = parseUriTemplate("https://e.com/{{accountId}}/{blobId}/{type}/{name}")
  doAssert res.isErr
  doAssert res.error.typeName == "UriTemplate"
  doAssert "invalid variable character" in res.error.message

# =============================================================================
# H. Missing session URL variable validations
# =============================================================================

testCase parseSessionDownloadUrlMissingType:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}/{name}").get()
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

testCase parseSessionDownloadUrlMissingName:
  let badDl = parseUriTemplate("https://e.com/{accountId}/{blobId}?accept={type}").get()
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

testCase parseSessionEventSourceMissingCloseafter:
  let badEs = parseUriTemplate("https://e.com/events?types={types}&ping={ping}").get()
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

testCase parseSessionEmptyAccounts:
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

testCase parseSessionEmptyPrimaryAccounts:
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

testCase parseSessionWhitespaceOnlyApiUrl:
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

testCase hasVariablePrefixOfLongerName:
  ## Template "{accountIdFull}" does NOT match variable "accountId" because
  ## hasVariable checks for the exact "{accountId}" substring.
  let tmpl = parseUriTemplate("https://e.com/{accountIdFull}").get()
  doAssert not hasVariable(tmpl, "accountId")

testCase hasVariableSuffixOfLongerName:
  ## Template "{fullAccountId}" does NOT contain "{accountId}" as substring.
  let tmpl = parseUriTemplate("https://e.com/{fullAccountId}").get()
  doAssert not hasVariable(tmpl, "accountId")

# =============================================================================
# J. Session template variable mutation resistance
# =============================================================================

testCase parseSessionExtraDownloadVariables:
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

testCase parseSessionEmptyAccountsValid:
  ## Empty accounts and primaryAccounts tables are valid.
  let args = makeMinimalSession()
  let res = parseSessionFromArgs(args)
  assertOk res

# =============================================================================
# K. Session accessor zero-coverage gaps
# =============================================================================

testCase findCapabilitySessionFoundContacts:
  ## findCapability(session, ckContacts) returns when present.
  let result = findCapability(goldenSession, ckContacts)
  assertSome result
  doAssert result.get().rawUri == "urn:ietf:params:jmap:contacts"

testCase findCapabilityByUriSessionFoundCore:
  ## findCapabilityByUri(session) returns the matching capability.
  let result = findCapabilityByUri(goldenSession, "urn:ietf:params:jmap:core")
  assertSome result
  doAssert result.get().kind == ckCore

testCase findCapabilityByUriSessionFoundVendor:
  ## findCapabilityByUri(session) disambiguates vendor extensions by URI.
  let result = findCapabilityByUri(goldenSession, "https://vendor2.example/ext")
  assertSome result
  doAssert result.get().kind == ckUnknown

testCase findCapabilityByUriSessionNotFound:
  ## findCapabilityByUri(session) returns none for absent URI.
  assertNone findCapabilityByUri(goldenSession, "urn:nonexistent:capability")

testCase primaryAccountContacts:
  ## primaryAccount returns the designated primary for ckContacts.
  let result = primaryAccount(goldenSession, ckContacts)
  assertSome result
  doAssert result.get() == AccountId("A13824")

testCase primaryAccountNotDesignated:
  ## primaryAccount returns none when no primary is designated for the kind.
  assertNone primaryAccount(goldenSession, ckCalendars)

testCase primaryAccountCkUnknownReturnsNone:
  ## primaryAccount returns none for ckUnknown (no canonical URI).
  assertNone primaryAccount(goldenSession, ckUnknown)

testCase findAccountFoundSecond:
  ## findAccount returns the correct account for the second AccountId.
  let result = findAccount(goldenSession, AccountId("A97813"))
  assertSome result
  doAssert result.get().name == "jane@example.com"
  doAssert result.get().isReadOnly == true

testCase findAccountNotFound:
  ## findAccount returns none for an unknown AccountId.
  assertNone findAccount(goldenSession, AccountId("ZZZZZZ"))

# =============================================================================
# L. Account accessor zero-coverage gaps
# =============================================================================

testCase accountFindCapabilityByUriFoundVendor:
  ## findCapabilityByUri(account) finds vendor extension by exact URI.
  let result = findCapabilityByUri(testAccount, "https://vendor2.example/ext")
  assertSome result
  doAssert result.get().kind == ckUnknown
  doAssert result.get().data == %*{"v": 2}

testCase accountFindCapabilityByUriNotFound2:
  ## findCapabilityByUri(account) returns none for absent URI.
  assertNone findCapabilityByUri(testAccount, "urn:nonexistent:nothing")

testCase accountFindCapabilityByUriVendorExtension:
  ## findCapabilityByUri(account) disambiguates between multiple ckUnknown entries.
  let result1 = findCapabilityByUri(testAccount, "https://vendor1.example/ext")
  assertSome result1
  doAssert result1.get().data == %*{"v": 1}
  let result2 = findCapabilityByUri(testAccount, "https://vendor2.example/ext")
  assertSome result2
  doAssert result2.get().data == %*{"v": 2}

testCase accountHasCapabilityCkUnknown:
  ## hasCapability returns true for ckUnknown when vendor extensions exist.
  doAssert hasCapability(testAccount, ckUnknown)

# =============================================================================
# M. UriTemplate and hasVariable zero-coverage gaps
# =============================================================================

testCase parseUriTemplateSingleChar:
  ## parseUriTemplate accepts a single-character string.
  let tmpl = parseUriTemplate("x").get()
  assertOk tmpl
  doAssert $tmpl == "x"
