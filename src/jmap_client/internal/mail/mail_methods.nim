# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions and response types for methods that need
## special handling beyond the generic ``addGet``/``addSet``/etc. builders.
## Covers VacationResponse (RFC 8621 §7), Email/parse (§4.9), and
## SearchSnippet/get (§5.1).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../../types
import ../../serialisation
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ./vacation
import ./snippet
import ./email
import ./mail_filters
import ./mail_builders
import ./serde_email
import ./serde_snippet
import ./serde_vacation

# Re-export the serde modules whose ``fromJson`` overloads are required at
# the dispatch call-site (``get(handle)``): the generic ``SetResponse[T]``
# resolves ``T.fromJson`` via ``mixin`` at the outer instantiation site, so
# the caller must have these in scope.
export serde_vacation
export serde_email
export serde_snippet

const VacationResponseCapUri = "urn:ietf:params:jmap:vacationresponse"
const MailCapUri = "urn:ietf:params:jmap:mail"

# =============================================================================
# VacationResponse/get
# =============================================================================

func addVacationResponseGet*(
    b: RequestBuilder,
    accountId: AccountId,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[VacationResponse]]) =
  ## Adds a VacationResponse/get invocation (RFC 8621 section 7). Always
  ## fetches the singleton — no ``ids`` parameter. Optionally restricts
  ## returned properties.
  let req = GetRequest[VacationResponse](
    accountId: accountId, ids: Opt.none(Referencable[seq[Id]]), properties: properties
  )
  let args = req.toJson()
  let (newBuilder, callId) =
    b.addInvocation(mnVacationResponseGet, args, VacationResponseCapUri)
  return (newBuilder, ResponseHandle[GetResponse[VacationResponse]](callId))

# =============================================================================
# VacationResponse/set
# =============================================================================

func addVacationResponseSet*(
    b: RequestBuilder,
    accountId: AccountId,
    update: VacationResponseUpdateSet,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[SetResponse[VacationResponse]]) =
  ## Adds a VacationResponse/set invocation (RFC 8621 section 7). Typed
  ## ``VacationResponseUpdateSet`` per Design §4.1 (Part F migration).
  ## Singleton id remains hardcoded from ``VacationResponseSingletonId``.
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  for state in ifInState:
    args["ifInState"] = state.toJson()
  var updateMap = newJObject()
  updateMap[VacationResponseSingletonId] = update.toJson()
  args["update"] = updateMap
  let (newBuilder, callId) =
    b.addInvocation(mnVacationResponseSet, args, VacationResponseCapUri)
  return (newBuilder, ResponseHandle[SetResponse[VacationResponse]](callId))

# =============================================================================
# EmailParseResponse (RFC 8621 §4.9)
# =============================================================================

{.push ruleOff: "objects".}

type
  EmailParseResponse* = object
    ## Response to Email/parse (RFC 8621 §4.9). Maps blob IDs to parsed
    ## email representations. ``notParseable`` uses Nim spelling; the wire
    ## key is ``"notParsable"`` (RFC spelling).
    accountId*: AccountId
    parsed*: Table[BlobId, ParsedEmail]
    notParseable*: seq[BlobId]
    notFound*: seq[BlobId]

  SearchSnippetGetResponse* = object
    ## Response to SearchSnippet/get (RFC 8621 §5.1). Returns search
    ## context snippets for a set of email IDs against a filter.
    accountId*: AccountId
    list*: seq[SearchSnippet]
    notFound*: seq[Id]

{.pop.}

# =============================================================================
# EmailParseResponse fromJson
# =============================================================================

func emailParseResponseFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailParseResponse, SerdeViolation] =
  ## Deserialise server JSON to ``EmailParseResponse``.
  ## Wire key ``"notParsable"`` maps to Nim field ``notParseable``.
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId = ?AccountId.fromJson(accountIdNode, path / "accountId")
  let parsed = ?parseKeyedTable[BlobId, ParsedEmail](
    node{"parsed"}, parseBlobId, parsedEmailFromJson, path / "parsed"
  )
  let notParseable = ?collapseNullToEmptySeq(node, "notParsable", parseBlobId, path)
  let notFound = ?collapseNullToEmptySeq(node, "notFound", parseBlobId, path)
  ok(
    EmailParseResponse(
      accountId: accountId,
      parsed: parsed,
      notParseable: notParseable,
      notFound: notFound,
    )
  )

func fromJson*(
    T: typedesc[EmailParseResponse], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailParseResponse, SerdeViolation] =
  ## Typedesc-overload wrapper so dispatch's ``mixin fromJson`` resolves
  ## ``EmailParseResponse.fromJson`` at the ``resp.get(handle)`` site
  ## (RFC 8621 §4.9). Mirrors the ``SearchSnippetGetResponse.fromJson``
  ## wrapper below — the named function ``emailParseResponseFromJson``
  ## continues to be the implementation; this wrapper exposes it through
  ## the ``T.fromJson(node)`` mixin-discovery path.
  discard $T # consumed for nimalyzer params rule
  emailParseResponseFromJson(node, path)

# =============================================================================
# SearchSnippetGetResponse fromJson
# =============================================================================

func searchSnippetGetResponseFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SearchSnippetGetResponse, SerdeViolation] =
  ## Deserialise server JSON to ``SearchSnippetGetResponse``.
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId = ?AccountId.fromJson(accountIdNode, path / "accountId")
  let listNode = node{"list"}
  let list =
    if listNode.isNil or listNode.kind != JArray:
      newSeq[SearchSnippet]()
    else:
      var snippets: seq[SearchSnippet] = @[]
      for i, elem in listNode.getElems(@[]):
        snippets.add(?searchSnippetFromJson(elem, path / "list" / i))
      snippets
  let notFound = ?collapseNullToEmptySeq(node, "notFound", parseIdFromServer, path)
  ok(SearchSnippetGetResponse(accountId: accountId, list: list, notFound: notFound))

func fromJson*(
    T: typedesc[SearchSnippetGetResponse],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[SearchSnippetGetResponse, SerdeViolation] =
  ## Typedesc-overload wrapper so dispatch's ``mixin fromJson`` resolves
  ## ``SearchSnippetGetResponse.fromJson`` at the ``resp.get(handle)``
  ## site (RFC 8621 §5.1). Mirrors the typedesc-overload pattern used by
  ## ``Mailbox.fromJson`` / ``MailboxCreatedItem.fromJson`` / etc. — the
  ## named function ``searchSnippetGetResponseFromJson`` continues to be
  ## the implementation; this wrapper only exposes it through the
  ## ``T.fromJson(node)`` mixin-discovery path.
  discard $T # consumed for nimalyzer params rule
  searchSnippetGetResponseFromJson(node, path)

# =============================================================================
# addEmailParse — Email/parse (RFC 8621 §4.9)
# =============================================================================

func addEmailParse*(
    b: RequestBuilder,
    accountId: AccountId,
    blobIds: seq[BlobId],
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[EmailParseResponse]) =
  ## Adds an Email/parse invocation. ``blobIds`` is a plain seq (no result
  ## references — Email/parse doesn't support them).
  ## ``bodyFetchOptions.toExtras()`` supplies the RFC 8621 §4.9 body-fetch
  ## keys, merged into the args after the standard frame (insertion order
  ## preserved).
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  var arr = newJArray()
  for id in blobIds:
    arr.add(id.toJson())
  args["blobIds"] = arr
  for props in properties:
    var propsArr = newJArray()
    for p in props:
      propsArr.add(%p)
    args["properties"] = propsArr
  for (k, v) in bodyFetchOptions.toExtras():
    args[k] = v
  let (newBuilder, callId) = b.addInvocation(mnEmailParse, args, MailCapUri)
  (newBuilder, ResponseHandle[EmailParseResponse](callId))

# =============================================================================
# addSearchSnippetGet — SearchSnippet/get (RFC 8621 §5.1)
# =============================================================================

func addSearchSnippetGet*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    firstEmailId: Id,
    restEmailIds: seq[Id] = @[],
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse]) =
  ## Adds a SearchSnippet/get invocation (RFC 8621 §5.1). ``filter`` is
  ## required (search snippets are meaningless without a query context).
  ## Cons-cell pattern (``firstEmailId`` + ``restEmailIds``) enforces at
  ## least one email ID at compile time (Decision D12).
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  args["filter"] = serializeFilter(filter).toJsonNode()
  var emailIds = newJArray()
  emailIds.add(firstEmailId.toJson())
  for id in restEmailIds:
    emailIds.add(id.toJson())
  args["emailIds"] = emailIds
  let (newBuilder, callId) = b.addInvocation(mnSearchSnippetGet, args, MailCapUri)
  (newBuilder, ResponseHandle[SearchSnippetGetResponse](callId))

# =============================================================================
# addSearchSnippetGetByRef + addEmailQueryWithSnippets
# RFC 8620 §3.7 back-reference chain for RFC 8621 §4.10 + §5.1
# =============================================================================

func addSearchSnippetGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    emailIdsRef: ResultReference,
): (RequestBuilder, ResponseHandle[SearchSnippetGetResponse]) =
  ## Sibling of ``addSearchSnippetGet`` for RFC 8620 §3.7 back-reference
  ## chains — ``emailIds`` is sourced from a previous invocation's
  ## response rather than supplied as literal IDs. ``filter`` remains
  ## mandatory (H6; RFC 8621 §5.1 ¶2); see design §3.4 on why the
  ## cons-cell non-emptiness discipline of the literal-ids overload
  ## does NOT propagate into the back-reference case (H8).
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  args["filter"] = serializeFilter(filter).toJsonNode()
  args["#emailIds"] = emailIdsRef.toJson()
  let (newBuilder, callId) = b.addInvocation(mnSearchSnippetGet, args, MailCapUri)
  (newBuilder, ResponseHandle[SearchSnippetGetResponse](callId))

type EmailQuerySnippetChain* =
  ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]
  ## Domain-named specialisation of ``ChainedHandles[A, B]`` for
  ## ``addEmailQueryWithSnippets`` (Email/query + SearchSnippet/get
  ## via RFC 8620 §3.7 back-reference chain per RFC 8621 §4.10).
  ## Fields ``first`` / ``second`` inherit from the generic at
  ## ``dispatch.nim``.

func addEmailQueryWithSnippets*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, EmailQuerySnippetChain) =
  ## Compound Email/query + SearchSnippet/get (RFC 8621 §4.10 + §5.1).
  ## Emits two invocations with a RFC 8620 §3.7 back-reference from
  ## the snippet request's ``emailIds`` to the query's ``/ids``.
  ## ``filter`` is mandatory — snippets are meaningless without a
  ## query context (H6; RFC 8621 §5.1 ¶2). The filter is duplicated
  ## literally on the wire to both invocations rather than shared via
  ## a second back-reference (H7; simplicity over wire-clever).
  let (b1, queryHandle) =
    addEmailQuery(b, accountId, Opt.some(filter), sort, queryParams, collapseThreads)
  let emailIdsRef = initResultReference(
    resultOf = callId(queryHandle), name = mnEmailQuery, path = rpIds
  )
  let (b2, snippetHandle) =
    addSearchSnippetGetByRef(b1, accountId, filter, emailIdsRef = emailIdsRef)
  (b2, EmailQuerySnippetChain(first: queryHandle, second: snippetHandle))

# =============================================================================
# addEmailImport — Email/import (RFC 8621 §4.8)
# =============================================================================

func addEmailImport*(
    b: RequestBuilder,
    accountId: AccountId,
    emails: NonEmptyEmailImportMap,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[EmailImportResponse]) =
  ## Adds an Email/import invocation (RFC 8621 §4.8). ``emails`` is non-Opt
  ## — ``initNonEmptyEmailImportMap`` guarantees non-empty; an empty
  ## /import is semantically void (Design §6.2, F13).
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  args["emails"] = emails.toJson()
  for state in ifInState:
    args["ifInState"] = state.toJson()
  let (newBuilder, callId) = b.addInvocation(mnEmailImport, args, MailCapUri)
  (newBuilder, ResponseHandle[EmailImportResponse](callId))
