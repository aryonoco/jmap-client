# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP Session resource types: CoreCapabilities,
## ServerCapability, AccountCapabilityEntry, Account, and Session
## (RFC 8620 section 2).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/sets
import std/tables

import ./serde
import ./types

# =============================================================================
# CoreCapabilities
# =============================================================================

func toJson*(caps: CoreCapabilities): JsonNode =
  ## Serialise CoreCapabilities to JSON (RFC 8620 §2).
  var node = %*{
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
    algArr.add(%($alg))
  node["collationAlgorithms"] = algArr
  return node

func fromJson*(
    T: typedesc[CoreCapabilities], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[CoreCapabilities, SerdeViolation] =
  ## Deserialise urn:ietf:params:jmap:core capability data.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let maxSizeUpload =
    ?UnsignedInt.fromJson(node{"maxSizeUpload"}, path / "maxSizeUpload")
  let maxConcurrentUpload =
    ?UnsignedInt.fromJson(node{"maxConcurrentUpload"}, path / "maxConcurrentUpload")
  let maxSizeRequest =
    ?UnsignedInt.fromJson(node{"maxSizeRequest"}, path / "maxSizeRequest")
  # Decision D2.6: accept both singular and plural forms (RFC §2.1 typo)
  let plural = node{"maxConcurrentRequests"}
  let singular = node{"maxConcurrentRequest"}
  if plural.isNil and singular.isNil:
    return err(
      SerdeViolation(
        kind: svkMissingField, path: path, missingFieldName: "maxConcurrentRequests"
      )
    )
  let maxConcurrentRequests =
    if plural.isNil:
      ?UnsignedInt.fromJson(singular, path / "maxConcurrentRequest")
    else:
      ?UnsignedInt.fromJson(plural, path / "maxConcurrentRequests")
  let maxCallsInRequest =
    ?UnsignedInt.fromJson(node{"maxCallsInRequest"}, path / "maxCallsInRequest")
  let maxObjectsInGet =
    ?UnsignedInt.fromJson(node{"maxObjectsInGet"}, path / "maxObjectsInGet")
  let maxObjectsInSet =
    ?UnsignedInt.fromJson(node{"maxObjectsInSet"}, path / "maxObjectsInSet")
  let algArrNode = ?fieldJArray(node, "collationAlgorithms", path)
  var algs: seq[CollationAlgorithm] = @[]
  for i, elem in algArrNode.getElems(@[]):
    ?expectKind(elem, JString, path / "collationAlgorithms" / i)
    let alg = ?wrapInner(
      parseCollationAlgorithm(elem.getStr("")), path / "collationAlgorithms" / i
    )
    algs.add(alg)
  let collationAlgorithms = toHashSet(algs)
  return ok(
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
  ## Non-core capabilities deep-copy to prevent callers from mutating internal
  ## state through the returned ref (mirrors fromJson's ownData pattern).
  case cap.kind
  of ckCore:
    return cap.core.toJson()
  else:
    if cap.rawData.isNil:
      return newJObject()
    return cap.rawData.copy()

func ownData(data: JsonNode): JsonNode =
  ## Deep-copy a JsonNode to avoid ARC double-free on shared refs.
  ## Mirrors the pattern used by AccountCapabilityEntry.fromJson.
  if data.isNil:
    return newJObject()
  return data.copy()

template mkNonCoreCap(k: CapabilityKind): untyped =
  ## Constructs a non-core ServerCapability with deep-copied data. Uses a
  ## compile-time literal discriminator to satisfy ARC branch tracking on
  ## case objects with ref fields (rawData: JsonNode).
  return ok(ServerCapability(kind: k, rawUri: uri, rawData: ownData(data)))

func fromJson*(
    T: typedesc[ServerCapability],
    uri: string,
    data: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[ServerCapability, SerdeViolation] =
  ## Deserialise a capability from its URI and JSON data.
  ## Non-core capabilities deep-copy data to avoid ARC double-free on shared
  ## JsonNode refs, and use compile-time literal discriminators (exhaustive
  ## case) instead of uncheckedAssign, which corrupts ARC branch tracking
  ## on case objects with ref fields.
  discard $T # consumed for nimalyzer params rule
  let parsedKind = parseCapabilityKind(uri)
  case parsedKind
  of ckCore:
    ?expectKind(data, JObject, path)
    let core = ?CoreCapabilities.fromJson(data, path)
    return ok(ServerCapability(kind: ckCore, rawUri: uri, core: core))
  of ckMail:
    mkNonCoreCap(ckMail)
  of ckSubmission:
    mkNonCoreCap(ckSubmission)
  of ckVacationResponse:
    mkNonCoreCap(ckVacationResponse)
  of ckWebsocket:
    mkNonCoreCap(ckWebsocket)
  of ckMdn:
    mkNonCoreCap(ckMdn)
  of ckSmimeVerify:
    mkNonCoreCap(ckSmimeVerify)
  of ckBlob:
    mkNonCoreCap(ckBlob)
  of ckQuota:
    mkNonCoreCap(ckQuota)
  of ckContacts:
    mkNonCoreCap(ckContacts)
  of ckCalendars:
    mkNonCoreCap(ckCalendars)
  of ckSieve:
    mkNonCoreCap(ckSieve)
  of ckUnknown:
    mkNonCoreCap(ckUnknown)

# =============================================================================
# AccountCapabilityEntry
# =============================================================================

func toJson*(entry: AccountCapabilityEntry): JsonNode =
  ## Serialise the capability data (URI key handled by Account.toJson).
  ## Deep-copies to prevent callers from mutating internal state through
  ## the returned ref (mirrors fromJson's deep-copy pattern).
  if entry.data.isNil:
    return newJObject()
  return entry.data.copy()

func fromJson*(
    T: typedesc[AccountCapabilityEntry],
    uri: string,
    data: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[AccountCapabilityEntry, SerdeViolation] =
  ## Deserialise an account capability entry from URI and JSON data.
  discard $T # consumed for nimalyzer params rule
  if uri.len == 0:
    return err(
      SerdeViolation(
        kind: svkEmptyRequired, path: path, emptyFieldLabel: "capability URI"
      )
    )
  return ok(
    AccountCapabilityEntry(
      kind: parseCapabilityKind(uri), rawUri: uri, data: ownData(data)
    )
  )

# =============================================================================
# Account
# =============================================================================

func toJson*(acct: Account): JsonNode =
  ## Serialise Account to JSON (RFC 8620 §2).
  var node =
    %*{"name": acct.name, "isPersonal": acct.isPersonal, "isReadOnly": acct.isReadOnly}
  var acctCaps = newJObject()
  for _, entry in acct.accountCapabilities:
    acctCaps[entry.rawUri] = entry.toJson()
  node["accountCapabilities"] = acctCaps
  return node

func fromJson*(
    T: typedesc[Account], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Account, SerdeViolation] =
  ## Deserialise JSON to Account (RFC 8620 §2).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  let isPersonalNode = ?fieldJBool(node, "isPersonal", path)
  let isPersonal = isPersonalNode.getBool(false)
  let isReadOnlyNode = ?fieldJBool(node, "isReadOnly", path)
  let isReadOnly = isReadOnlyNode.getBool(false)
  let acctCapsNode = ?fieldJObject(node, "accountCapabilities", path)
  var accountCapabilities: seq[AccountCapabilityEntry] = @[]
  for uri, data in acctCapsNode.pairs:
    let entry =
      ?AccountCapabilityEntry.fromJson(uri, data, path / "accountCapabilities" / uri)
    accountCapabilities.add(entry)
  return ok(
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
  var node = %*{
    "username": s.username,
    "apiUrl": s.apiUrl,
    "downloadUrl": $s.downloadUrl,
    "uploadUrl": $s.uploadUrl,
    "eventSourceUrl": $s.eventSourceUrl,
    "state": string(s.state),
  }
  # capabilities: URI -> capability data
  var caps = newJObject()
  for _, cap in s.capabilities:
    caps[cap.rawUri] = cap.toJson()
  node["capabilities"] = caps
  # accounts: AccountId -> Account
  var accts = newJObject()
  for id, acct in s.accounts:
    accts[string(id)] = acct.toJson()
  node["accounts"] = accts
  # primaryAccounts: capability URI -> AccountId
  var primary = newJObject()
  for uri, id in s.primaryAccounts:
    primary[uri] = %string(id)
  node["primaryAccounts"] = primary
  return node

func fromJson*(
    T: typedesc[Session], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Session, SerdeViolation] =
  ## Deserialise JSON to Session (RFC 8620 §2). Calls parseSession for
  ## structural invariant validation.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)

  # 1. Parse capabilities
  let capsNode = ?fieldJObject(node, "capabilities", path)
  var capabilities: seq[ServerCapability] = @[]
  for uri, data in capsNode.pairs:
    let cap = ?ServerCapability.fromJson(uri, data, path / "capabilities" / uri)
    capabilities.add(cap)

  # 2. Parse accounts
  let acctsNode = ?fieldJObject(node, "accounts", path)
  var accounts = initTable[AccountId, Account]()
  for idStr, acctData in acctsNode.pairs:
    let accountId = ?wrapInner(parseAccountId(idStr), path / "accounts" / idStr)
    let account = ?Account.fromJson(acctData, path / "accounts" / idStr)
    accounts[accountId] = account

  # 3. Parse primaryAccounts (required per RFC §2)
  let primaryNode = ?fieldJObject(node, "primaryAccounts", path)
  var primaryAccounts = initTable[string, AccountId]()
  for uri, idNode in primaryNode.pairs:
    ?expectKind(idNode, JString, path / "primaryAccounts" / uri)
    let accountId =
      ?wrapInner(parseAccountId(idNode.getStr("")), path / "primaryAccounts" / uri)
    primaryAccounts[uri] = accountId

  # 4. Parse scalar fields
  let usernameNode = ?fieldJString(node, "username", path)
  let username = usernameNode.getStr("")
  let apiUrlNode = ?fieldJString(node, "apiUrl", path)
  let apiUrl = apiUrlNode.getStr("")

  # 5. Parse URI templates
  let downloadUrlNode = ?fieldJString(node, "downloadUrl", path)
  let downloadUrl =
    ?wrapInner(parseUriTemplate(downloadUrlNode.getStr("")), path / "downloadUrl")
  let uploadUrlNode = ?fieldJString(node, "uploadUrl", path)
  let uploadUrl =
    ?wrapInner(parseUriTemplate(uploadUrlNode.getStr("")), path / "uploadUrl")
  let eventSourceUrlNode = ?fieldJString(node, "eventSourceUrl", path)
  let eventSourceUrl =
    ?wrapInner(parseUriTemplate(eventSourceUrlNode.getStr("")), path / "eventSourceUrl")

  # 6. Parse state
  let stateNode = ?fieldJString(node, "state", path)
  let state = ?wrapInner(parseJmapState(stateNode.getStr("")), path / "state")

  # 7. Call parseSession for structural invariant validation
  return wrapInner(
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
    ),
    path,
  )
