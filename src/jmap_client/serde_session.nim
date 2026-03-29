# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## Serialisation for JMAP Session resource types: CoreCapabilities,
## ServerCapability, AccountCapabilityEntry, Account, and Session
## (RFC 8620 section 2).

import std/json
import std/sets
import std/tables

import results

import ./serde
import ./types

# =============================================================================
# CoreCapabilities
# =============================================================================

func toJson*(caps: CoreCapabilities): JsonNode =
  ## Serialise CoreCapabilities to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:
    result = %*{
      "maxSizeUpload": int64(caps.maxSizeUpload),
      "maxConcurrentUpload": int64(caps.maxConcurrentUpload),
      "maxSizeRequest": int64(caps.maxSizeRequest),
      "maxConcurrentRequests": int64(caps.maxConcurrentRequests),
      "maxCallsInRequest": int64(caps.maxCallsInRequest),
      "maxObjectsInGet": int64(caps.maxObjectsInGet),
      "maxObjectsInSet": int64(caps.maxObjectsInSet),
    }
    var algArr = newJArray()
    for alg in caps.collationAlgorithms:
      algArr.add(%alg)
    result["collationAlgorithms"] = algArr

func fromJson*(
    T: typedesc[CoreCapabilities], node: JsonNode
): Result[CoreCapabilities, ValidationError] =
  ## Deserialise urn:ietf:params:jmap:core capability data.
  checkJsonKind(node, JObject, $T)
  let maxSizeUpload = ?UnsignedInt.fromJson(node{"maxSizeUpload"})
  let maxConcurrentUpload = ?UnsignedInt.fromJson(node{"maxConcurrentUpload"})
  let maxSizeRequest = ?UnsignedInt.fromJson(node{"maxSizeRequest"})
  # Decision D2.6: accept both singular and plural forms (RFC §2.1 typo)
  let maxConcurrentRequests = block:
    let plural = node{"maxConcurrentRequests"}
    let singular = node{"maxConcurrentRequest"}
    if plural.isNil and singular.isNil:
      return err(parseError($T, "missing maxConcurrentRequests"))
    let chosen = if plural.isNil: singular else: plural
    ?UnsignedInt.fromJson(chosen)
  let maxCallsInRequest = ?UnsignedInt.fromJson(node{"maxCallsInRequest"})
  let maxObjectsInGet = ?UnsignedInt.fromJson(node{"maxObjectsInGet"})
  let maxObjectsInSet = ?UnsignedInt.fromJson(node{"maxObjectsInSet"})
  let collationAlgorithms = block:
    let arr = node{"collationAlgorithms"}
    checkJsonKind(arr, JArray, $T, "missing or invalid collationAlgorithms")
    var algs: seq[string]
    for elem in arr.getElems(@[]):
      checkJsonKind(elem, JString, $T, "collationAlgorithms element must be string")
      algs.add(elem.getStr(""))
    toHashSet(algs)
  ok(
    CoreCapabilities(
      maxSizeUpload: maxSizeUpload,
      maxConcurrentUpload: maxConcurrentUpload,
      maxSizeRequest: maxSizeRequest,
      maxConcurrentRequests: maxConcurrentRequests,
      maxCallsInRequest: maxCallsInRequest,
      maxObjectsInGet: maxObjectsInGet,
      maxObjectsInSet: maxObjectsInSet,
      collationAlgorithms: collationAlgorithms,
    )
  )

# =============================================================================
# ServerCapability
# =============================================================================

func toJson*(cap: ServerCapability): JsonNode =
  ## Serialise capability data (not the URI key — handled by Session.toJson).
  case cap.kind
  of ckCore:
    cap.core.toJson()
  else:
    if cap.rawData.isNil:
      newJObject()
    else:
      cap.rawData

func fromJson*(
    T: typedesc[ServerCapability], uri: string, data: JsonNode
): Result[ServerCapability, ValidationError] =
  ## Deserialise a capability from its URI and JSON data.
  ## Non-core capabilities use compile-time literal discriminators (exhaustive
  ## case) instead of uncheckedAssign, which corrupts ARC branch tracking
  ## on case objects with ref fields.
  let parsedKind = parseCapabilityKind(uri)
  case parsedKind
  of ckCore:
    checkJsonKind(data, JObject, $T, "core capability data must be JSON object")
    let core = ?CoreCapabilities.fromJson(data)
    ok(ServerCapability(kind: ckCore, rawUri: uri, core: core))
  of ckMail:
    ok(ServerCapability(kind: ckMail, rawUri: uri, rawData: data))
  of ckSubmission:
    ok(ServerCapability(kind: ckSubmission, rawUri: uri, rawData: data))
  of ckVacationResponse:
    ok(ServerCapability(kind: ckVacationResponse, rawUri: uri, rawData: data))
  of ckWebsocket:
    ok(ServerCapability(kind: ckWebsocket, rawUri: uri, rawData: data))
  of ckMdn:
    ok(ServerCapability(kind: ckMdn, rawUri: uri, rawData: data))
  of ckSmimeVerify:
    ok(ServerCapability(kind: ckSmimeVerify, rawUri: uri, rawData: data))
  of ckBlob:
    ok(ServerCapability(kind: ckBlob, rawUri: uri, rawData: data))
  of ckQuota:
    ok(ServerCapability(kind: ckQuota, rawUri: uri, rawData: data))
  of ckContacts:
    ok(ServerCapability(kind: ckContacts, rawUri: uri, rawData: data))
  of ckCalendars:
    ok(ServerCapability(kind: ckCalendars, rawUri: uri, rawData: data))
  of ckSieve:
    ok(ServerCapability(kind: ckSieve, rawUri: uri, rawData: data))
  of ckUnknown:
    ok(ServerCapability(kind: ckUnknown, rawUri: uri, rawData: data))

# =============================================================================
# AccountCapabilityEntry
# =============================================================================

func toJson*(entry: AccountCapabilityEntry): JsonNode =
  ## Serialise the capability data (URI key handled by Account.toJson).
  if entry.data.isNil:
    newJObject()
  else:
    entry.data

func fromJson*(
    T: typedesc[AccountCapabilityEntry], uri: string, data: JsonNode
): Result[AccountCapabilityEntry, ValidationError] =
  ## Deserialise an account capability entry from URI and JSON data.
  if uri.len == 0:
    return err(parseError($T, "capability URI must not be empty"))
  # Deep-copy to avoid ARC double-free on shared JsonNode refs.
  let ownedData = block:
    {.cast(noSideEffect).}:
      if data.isNil:
        newJObject()
      else:
        data.copy()
  ok(
    AccountCapabilityEntry(kind: parseCapabilityKind(uri), rawUri: uri, data: ownedData)
  )

# =============================================================================
# Account
# =============================================================================

func toJson*(acct: Account): JsonNode =
  ## Serialise Account to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:
    result = %*{
      "name": acct.name, "isPersonal": acct.isPersonal, "isReadOnly": acct.isReadOnly
    }
    var acctCaps = newJObject()
    for entry in acct.accountCapabilities:
      acctCaps[entry.rawUri] = entry.toJson()
    result["accountCapabilities"] = acctCaps

func fromJson*(T: typedesc[Account], node: JsonNode): Result[Account, ValidationError] =
  ## Deserialise JSON to Account (RFC 8620 §2).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"name"}, JString, $T, "missing or invalid name")
  let name = node{"name"}.getStr("")
  checkJsonKind(node{"isPersonal"}, JBool, $T, "missing or invalid isPersonal")
  let isPersonal = node{"isPersonal"}.getBool(false)
  checkJsonKind(node{"isReadOnly"}, JBool, $T, "missing or invalid isReadOnly")
  let isReadOnly = node{"isReadOnly"}.getBool(false)
  let acctCapsNode = node{"accountCapabilities"}
  checkJsonKind(acctCapsNode, JObject, $T, "missing or invalid accountCapabilities")
  var accountCapabilities: seq[AccountCapabilityEntry]
  for uri, data in acctCapsNode.pairs:
    let entry = ?AccountCapabilityEntry.fromJson(uri, data)
    accountCapabilities.add(entry)
  ok(
    Account(
      name: name,
      isPersonal: isPersonal,
      isReadOnly: isReadOnly,
      accountCapabilities: accountCapabilities,
    )
  )

# =============================================================================
# Session
# =============================================================================

func toJson*(s: Session): JsonNode =
  ## Serialise Session to JSON (RFC 8620 §2).
  {.cast(noSideEffect).}:
    result = %*{
      "username": s.username,
      "apiUrl": s.apiUrl,
      "downloadUrl": string(s.downloadUrl),
      "uploadUrl": string(s.uploadUrl),
      "eventSourceUrl": string(s.eventSourceUrl),
      "state": string(s.state),
    }
    # capabilities: URI -> capability data
    var caps = newJObject()
    for cap in s.capabilities:
      caps[cap.rawUri] = cap.toJson()
    result["capabilities"] = caps
    # accounts: AccountId -> Account
    var accts = newJObject()
    for id, acct in s.accounts:
      accts[string(id)] = acct.toJson()
    result["accounts"] = accts
    # primaryAccounts: capability URI -> AccountId
    var primary = newJObject()
    for uri, id in s.primaryAccounts:
      primary[uri] = %string(id)
    result["primaryAccounts"] = primary

func fromJson*(T: typedesc[Session], node: JsonNode): Result[Session, ValidationError] =
  ## Deserialise JSON to Session (RFC 8620 §2). Calls parseSession for
  ## structural invariant validation.
  checkJsonKind(node, JObject, $T)

  # 1. Parse capabilities
  let capsNode = node{"capabilities"}
  checkJsonKind(capsNode, JObject, $T, "missing or invalid capabilities")
  var capabilities: seq[ServerCapability]
  for uri, data in capsNode.pairs:
    let cap = ?ServerCapability.fromJson(uri, data)
    capabilities.add(cap)

  # 2. Parse accounts
  let acctsNode = node{"accounts"}
  checkJsonKind(acctsNode, JObject, $T, "missing or invalid accounts")
  var accounts = initTable[AccountId, Account]()
  for idStr, acctData in acctsNode.pairs:
    let accountId = ?parseAccountId(idStr)
    let account = ?Account.fromJson(acctData)
    accounts[accountId] = account

  # 3. Parse primaryAccounts (required per RFC §2)
  let primaryNode = node{"primaryAccounts"}
  checkJsonKind(primaryNode, JObject, $T, "missing or invalid primaryAccounts")
  var primaryAccounts = initTable[string, AccountId]()
  for uri, idNode in primaryNode.pairs:
    checkJsonKind(idNode, JString, $T, "primaryAccounts value must be string")
    let accountId = ?parseAccountId(idNode.getStr(""))
    primaryAccounts[uri] = accountId

  # 4. Parse scalar fields
  checkJsonKind(node{"username"}, JString, $T, "missing or invalid username")
  let username = node{"username"}.getStr("")
  checkJsonKind(node{"apiUrl"}, JString, $T, "missing or invalid apiUrl")
  let apiUrl = node{"apiUrl"}.getStr("")

  # 5. Parse URI templates
  checkJsonKind(node{"downloadUrl"}, JString, $T, "missing or invalid downloadUrl")
  let downloadUrl = ?parseUriTemplate(node{"downloadUrl"}.getStr(""))
  checkJsonKind(node{"uploadUrl"}, JString, $T, "missing or invalid uploadUrl")
  let uploadUrl = ?parseUriTemplate(node{"uploadUrl"}.getStr(""))
  checkJsonKind(
    node{"eventSourceUrl"}, JString, $T, "missing or invalid eventSourceUrl"
  )
  let eventSourceUrl = ?parseUriTemplate(node{"eventSourceUrl"}.getStr(""))

  # 6. Parse state
  checkJsonKind(node{"state"}, JString, $T, "missing or invalid state")
  let state = ?parseJmapState(node{"state"}.getStr(""))

  # 7. Call parseSession for structural invariant validation
  parseSession(
    capabilities = capabilities,
    accounts = accounts,
    primaryAccounts = primaryAccounts,
    username = username,
    apiUrl = apiUrl,
    downloadUrl = downloadUrl,
    uploadUrl = uploadUrl,
    eventSourceUrl = eventSourceUrl,
    state = state,
  )
