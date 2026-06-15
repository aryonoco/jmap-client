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
import ./serde_diagnostics
import ./serde_helpers
import ./serde_primitives
import ../types
import ../types/capabilities
import ../types/account_capability_schemas
import ../types/session as types_session

# =============================================================================
# CoreCapabilities
# =============================================================================

func toJson*(caps: CoreCapabilities): JsonNode =
  ## Serialise CoreCapabilities to JSON (RFC 8620 §2). Reads the public
  ## record fields directly.
  var node = %*{
    "maxSizeUpload": caps.maxSizeUpload.toInt64,
    "maxConcurrentUpload": caps.maxConcurrentUpload.toInt64,
    "maxSizeRequest": caps.maxSizeRequest.toInt64,
    "maxConcurrentRequests": caps.maxConcurrentRequests.toInt64,
    "maxCallsInRequest": caps.maxCallsInRequest.toInt64,
    "maxObjectsInGet": caps.maxObjectsInGet.toInt64,
    "maxObjectsInSet": caps.maxObjectsInSet.toInt64,
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
  return wrapInner(
    parseCoreCapabilities(
      maxSizeUpload, maxConcurrentUpload, maxSizeRequest, maxConcurrentRequests,
      maxCallsInRequest, maxObjectsInGet, maxObjectsInSet, collationAlgorithms,
    ),
    path,
  )

# =============================================================================
# ServerCapability
# =============================================================================

func ownData(data: JsonNode): JsonNode =
  ## Deep-copy a JsonNode to avoid ARC double-free on shared refs.
  ## Mirrors the pattern used by AccountCapabilityEntry.fromJson.
  if data.isNil:
    return newJObject()
  return data.copy()

func toJson*(cap: ServerCapability): JsonNode =
  ## Serialise capability data (not the URI key — handled by Session.toJson).
  ## ckCore renders typed; ckMail/ckSubmission/ckVacationResponse render
  ## as the empty object per RFC 8621 §1.3; ``rawXxxData``-bearing arms
  ## deep-copy the JsonNode to prevent callers from mutating internal
  ## state through the returned ref. The ``case .isOk of true: ...
  ## .unsafeValue`` pattern is strict-safe (the inner case proves the
  ## Opt's discriminator) and panic-free under ``--panics:on``.
  case cap.kind
  of ckCore:
    let coreOpt = cap.asCoreCapabilities()
    case coreOpt.isOk
    of true:
      coreOpt.unsafeValue.toJson()
    of false:
      newJObject()
  of ckMail, ckSubmission, ckVacationResponse:
    newJObject()
  of ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts, ckCalendars,
      ckSieve, ckUnknown:
    let dataOpt = cap.asRawData()
    case dataOpt.isOk
    of true:
      dataOpt.unsafeValue.copy()
    of false:
      newJObject()

func fromJson*(
    T: typedesc[ServerCapability],
    uri: string,
    data: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[ServerCapability, SerdeViolation] =
  ## Deserialise a capability from its URI and JSON data. Delegates to
  ## the L1 smart constructor via ``wrapInner``; ckCore parses the typed
  ## payload, all other arms carry the deep-copied JsonNode (discard
  ## arms drop it silently downstream).
  discard $T # consumed for nimalyzer params rule
  let parsedKind = parseCapabilityKind(uri)
  if parsedKind == ckCore:
    ?expectKind(data, JObject, path)
    let core = ?CoreCapabilities.fromJson(data, path)
    return
      wrapInner(parseServerCapability(uri, Opt.some(core), Opt.none(JsonNode)), path)
  return wrapInner(
    parseServerCapability(uri, Opt.none(CoreCapabilities), Opt.some(ownData(data))),
    path,
  )

# =============================================================================
# AccountCapabilityEntry
# =============================================================================

func toJson*(m: MailAccountCapabilities): JsonNode =
  ## Serialise MailAccountCapabilities to JSON (RFC 8621 §1.3.1
  ## declaration order). Optional fields are omitted when ``Opt.none``;
  ## emit order matches the RFC's section ordering.
  var node = newJObject()
  for v in m.maxMailboxesPerEmail:
    node["maxMailboxesPerEmail"] = %v.toInt64
  for v in m.maxMailboxDepth:
    node["maxMailboxDepth"] = %v.toInt64
  for v in m.maxSizeMailboxName:
    node["maxSizeMailboxName"] = %v.toInt64
  node["maxSizeAttachmentsPerEmail"] = %m.maxSizeAttachmentsPerEmail.toInt64
  var sortArr = newJArray()
  for opt in m.emailQuerySortOptions:
    sortArr.add(%opt)
  node["emailQuerySortOptions"] = sortArr
  node["mayCreateTopLevelMailbox"] = %m.mayCreateTopLevelMailbox
  return node

func fromJson*(
    T: typedesc[MailAccountCapabilities],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[MailAccountCapabilities, SerdeViolation] =
  ## Deserialise urn:ietf:params:jmap:mail account-scope capability data
  ## (RFC 8621 §1.3.1). Optional integer fields project null/absent to
  ## ``Opt.none``. The L1 smart constructor enforces minValue invariants.
  discard $T
  ?expectKind(node, JObject, path)

  func parseOpt(
      n: JsonNode, name: string, p: JsonPath
  ): Result[Opt[UnsignedInt], SerdeViolation] =
    ## Local helper: parses an optional UnsignedInt field, projecting
    ## absent/null to ``Opt.none``. Used only inside this overload.
    let fld = n{name}
    if fld.isNil or fld.kind == JNull:
      return ok(Opt.none(UnsignedInt))
    ?expectKind(fld, JInt, p / name)
    let v = ?UnsignedInt.fromJson(fld, p / name)
    ok(Opt.some(v))

  let maxMailboxesPerEmail = ?parseOpt(node, "maxMailboxesPerEmail", path)
  let maxMailboxDepth = ?parseOpt(node, "maxMailboxDepth", path)
  let maxSizeMailboxName = ?parseOpt(node, "maxSizeMailboxName", path)

  let msapeFld = ?fieldJInt(node, "maxSizeAttachmentsPerEmail", path)
  let maxSizeAttachmentsPerEmail =
    ?UnsignedInt.fromJson(msapeFld, path / "maxSizeAttachmentsPerEmail")

  let sortFld = node{"emailQuerySortOptions"}
  let emailQuerySortOptions =
    if sortFld.isNil or sortFld.kind == JNull:
      initHashSet[string]()
    else:
      ?expectKind(sortFld, JArray, path / "emailQuerySortOptions")
      var acc: seq[string] = @[]
      for i, elem in sortFld.getElems(@[]):
        ?expectKind(elem, JString, path / "emailQuerySortOptions" / i)
        acc.add(elem.getStr(""))
      toHashSet(acc)

  let mctlmFld = ?fieldJBool(node, "mayCreateTopLevelMailbox", path)
  let mayCreateTopLevelMailbox = mctlmFld.getBool(false)

  return wrapInner(
    parseMailAccountCapabilities(
      maxMailboxesPerEmail, maxMailboxDepth, maxSizeMailboxName,
      maxSizeAttachmentsPerEmail, emailQuerySortOptions, mayCreateTopLevelMailbox,
    ),
    path,
  )

func toJson*(s: SubmissionAccountCapabilities): JsonNode =
  ## Serialise SubmissionAccountCapabilities to JSON (RFC 8621 §1.3.2
  ## declaration order).
  var node = newJObject()
  node["maxDelayedSend"] = %s.maxDelayedSend.toInt64
  var ext = newJObject()
  for k, v in s.submissionExtensions.toOrderedTable():
    var arr = newJArray()
    for s in v:
      arr.add(%s)
    ext[$k] = arr
  node["submissionExtensions"] = ext
  return node

func fromJson*(
    T: typedesc[SubmissionAccountCapabilities],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[SubmissionAccountCapabilities, SerdeViolation] =
  ## Deserialise urn:ietf:params:jmap:submission account-scope capability
  ## data (RFC 8621 §1.3.2). Keys are validated ESMTP keywords; values
  ## are arrays of strings.
  discard $T
  ?expectKind(node, JObject, path)
  let mdsFld = ?fieldJInt(node, "maxDelayedSend", path)
  let maxDelayedSend = ?UnsignedInt.fromJson(mdsFld, path / "maxDelayedSend")
  let extNode = ?fieldJObject(node, "submissionExtensions", path)
  var extensions = initOrderedTable[RFC5321Keyword, seq[string]]()
  for key, val in extNode.pairs:
    let kw = ?wrapInner(parseRFC5321Keyword(key), path / "submissionExtensions" / key)
    ?expectKind(val, JArray, path / "submissionExtensions" / key)
    var args: seq[string] = @[]
    for i, elem in val.getElems(@[]):
      ?expectKind(elem, JString, path / "submissionExtensions" / key / i)
      args.add(elem.getStr(""))
    extensions[kw] = args
  return wrapInner(
    parseSubmissionAccountCapabilities(
      maxDelayedSend, initSubmissionExtensionMap(extensions)
    ),
    path,
  )

func toJson*(entry: AccountCapabilityEntry): JsonNode =
  ## Serialise the capability data (URI key handled by Account.toJson).
  ## ckMail/ckSubmission render typed; ckVacationResponse is the empty
  ## object (RFC 8621 §1.3.3 presence-only); ``rawXxxData`` arms deep-
  ## copy so callers can't mutate internal state. ``case .isOk of true:
  ## .unsafeValue`` is strict-safe and panic-free.
  case entry.kind
  of ckMail:
    let mailOpt = entry.asMailAccountCapabilities()
    case mailOpt.isOk
    of true:
      mailOpt.unsafeValue.toJson()
    of false:
      newJObject()
  of ckSubmission:
    let subOpt = entry.asSubmissionAccountCapabilities()
    case subOpt.isOk
    of true:
      subOpt.unsafeValue.toJson()
    of false:
      newJObject()
  of ckVacationResponse:
    newJObject()
  of ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts,
      ckCalendars, ckSieve, ckUnknown:
    let dataOpt = entry.asRawData()
    case dataOpt.isOk
    of true:
      dataOpt.unsafeValue.copy()
    of false:
      newJObject()

func fromJson*(
    T: typedesc[AccountCapabilityEntry],
    uri: string,
    data: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[AccountCapabilityEntry, SerdeViolation] =
  ## Deserialise an account capability entry from URI and JSON data.
  ## ckMail/ckSubmission delegate to typed sub-parsers; ckVacationResponse
  ## drops any payload (presence-only); all other arms deep-copy the
  ## JsonNode through the L1 smart constructor.
  discard $T # consumed for nimalyzer params rule
  if uri.len == 0:
    return err(
      SerdeViolation(
        kind: svkEmptyRequired, path: path, emptyFieldLabel: "capability URI"
      )
    )
  let parsedKind = parseCapabilityKind(uri)
  case parsedKind
  of ckMail:
    let m = ?MailAccountCapabilities.fromJson(data, path)
    return wrapInner(
      parseAccountCapabilityEntry(
        uri, Opt.some(m), Opt.none(SubmissionAccountCapabilities), Opt.none(JsonNode)
      ),
      path,
    )
  of ckSubmission:
    let s = ?SubmissionAccountCapabilities.fromJson(data, path)
    return wrapInner(
      parseAccountCapabilityEntry(
        uri, Opt.none(MailAccountCapabilities), Opt.some(s), Opt.none(JsonNode)
      ),
      path,
    )
  of ckVacationResponse:
    return wrapInner(
      parseAccountCapabilityEntry(
        uri,
        Opt.none(MailAccountCapabilities),
        Opt.none(SubmissionAccountCapabilities),
        Opt.none(JsonNode),
      ),
      path,
    )
  of ckCore, ckWebsocket, ckMdn, ckSmimeVerify, ckBlob, ckQuota, ckContacts,
      ckCalendars, ckSieve, ckUnknown:
    return wrapInner(
      parseAccountCapabilityEntry(
        uri,
        Opt.none(MailAccountCapabilities),
        Opt.none(SubmissionAccountCapabilities),
        Opt.some(ownData(data)),
      ),
      path,
    )

# =============================================================================
# Account
# =============================================================================

func toJson*(acct: Account): JsonNode =
  ## Serialise Account to JSON (RFC 8620 §2). ``isPersonal``/``isReadOnly``
  ## are derived from ``policy``; the wire shape is unchanged.
  var node = %*{
    "name": acct.name(),
    "isPersonal": acct.isPersonal(),
    "isReadOnly": acct.isReadOnly(),
  }
  var acctCaps = newJObject()
  for entry in acct.accountCapabilities():
    acctCaps[entry.uri()] = entry.toJson()
  node["accountCapabilities"] = acctCaps
  return node

func fromJson*(
    T: typedesc[Account], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Account, SerdeViolation] =
  ## Deserialise JSON to Account (RFC 8620 §2). Delegates to the L1
  ## smart constructor via ``wrapInner``; B12 silent-drop of write-
  ## implying capabilities is enforced inside ``parseAccount``.
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
  return
    wrapInner(parseAccount(name, isPersonal, isReadOnly, accountCapabilities), path)

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
    "state": $s.state,
  }
  # capabilities: URI -> capability data
  var caps = newJObject()
  for cap in s.capabilities():
    caps[cap.uri()] = cap.toJson()
  node["capabilities"] = caps
  # accounts: AccountId -> Account
  var accts = newJObject()
  for id, acct in s.accounts:
    accts[$id] = acct.toJson()
  node["accounts"] = accts
  # primaryAccounts: capability URI -> AccountId
  var primary = newJObject()
  for uri, id in s.primaryAccounts:
    primary[uri] = %($id)
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

# =============================================================================
# UriTemplate
# =============================================================================

func toJson*(x: UriTemplate): JsonNode =
  ## Serialise a parsed URI template to its lossless source string.
  return %($x)

func fromJson*(
    t: typedesc[UriTemplate], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[UriTemplate, SerdeViolation] =
  ## Deserialise a JSON string through ``parseUriTemplate``. Malformed
  ## templates (unmatched braces, empty ``{}``, invalid variable chars)
  ## surface as ``ValidationError`` wrapped by ``wrapInner``.
  discard $t # consumed for nimalyzer params rule
  ?expectKind(node, JString, path)
  return wrapInner(parseUriTemplate(node.getStr("")), path)
