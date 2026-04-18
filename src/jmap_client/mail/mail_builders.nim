# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions and response types for Mailbox (RFC 8621 §2).
## ``addGet[Mailbox]`` uses the generic builder (no custom overload needed).
## Custom builders handle methods with extra parameters or custom response
## types: ``addMailboxChanges`` (extended response), ``addMailboxQuery``
## (sortAsTree, filterAsTree), ``addMailboxQueryChanges`` (explicit
## parameter surface), ``addMailboxSet`` (onDestroyRemoveEmails, typed
## MailboxCreate).

{.push raises: [], noSideEffect.}

import std/json
import std/tables

import ../types
import ../serialisation
import ../methods
import ../dispatch
import ../builder
import ./mailbox
import ./email
import ./email_blueprint
import ./email_update
import ./mail_filters
import ./mail_entities
import ./serde_mailbox
import ./serde_email
import ./serde_email_blueprint
import ./serde_email_update
import ./serde_mail_filters

# Re-export the serde modules whose ``fromJson`` overloads are required at
# the dispatch call-site (``get(handle)``): the generic ``SetResponse[T]``
# and ``CopyResponse[T]`` resolve ``T.fromJson`` via ``mixin`` at the outer
# instantiation site, so the caller must have these in scope.
export serde_mailbox
export serde_email

const MailCapUri = "urn:ietf:params:jmap:mail"

# =============================================================================
# MailboxChangesResponse (Decision B9 — composition pattern)
# =============================================================================

{.push ruleOff: "objects".}

type MailboxChangesResponse* = object
  ## Extended Foo/changes response for Mailbox (RFC 8621 §2.2). Composes
  ## the standard ``ChangesResponse[Mailbox]`` with the Mailbox-specific
  ## ``updatedProperties`` extension field.
  base*: ChangesResponse[Mailbox]
  updatedProperties*: Opt[seq[string]]

{.pop.}

# =============================================================================
# UFCS forwarding accessors
# =============================================================================

template forwardChangesFields(T: typedesc) =
  ## Generates UFCS forwarding funcs for the 7 ChangesResponse base fields,
  ## so callers write ``resp.accountId`` instead of ``resp.base.accountId``.
  func accountId*(r: T): AccountId =
    ## Forwarded from ``base.accountId``.
    r.base.accountId

  func oldState*(r: T): JmapState =
    ## Forwarded from ``base.oldState``.
    r.base.oldState

  func newState*(r: T): JmapState =
    ## Forwarded from ``base.newState``.
    r.base.newState

  func hasMoreChanges*(r: T): bool =
    ## Forwarded from ``base.hasMoreChanges``.
    r.base.hasMoreChanges

  func created*(r: T): seq[Id] =
    ## Forwarded from ``base.created``.
    r.base.created

  func updated*(r: T): seq[Id] =
    ## Forwarded from ``base.updated``.
    r.base.updated

  func destroyed*(r: T): seq[Id] =
    ## Forwarded from ``base.destroyed``.
    r.base.destroyed

forwardChangesFields(MailboxChangesResponse)

# =============================================================================
# MailboxChangesResponse fromJson
# =============================================================================

func fromJson*(
    R: typedesc[MailboxChangesResponse],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[MailboxChangesResponse, SerdeViolation] =
  ## Deserialise JSON to MailboxChangesResponse. Reuses
  ## ``ChangesResponse[Mailbox].fromJson`` for the 7 standard fields, then
  ## extracts the Mailbox-specific ``updatedProperties`` extension.
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let base = ?ChangesResponse[Mailbox].fromJson(node, path)
  let upNode = node{"updatedProperties"}
  let updatedProperties =
    if upNode.isNil or upNode.kind == JNull:
      Opt.none(seq[string])
    elif upNode.kind == JArray:
      var props: seq[string] = @[]
      for i, elem in upNode.getElems(@[]):
        if elem.kind != JString:
          return err(
            SerdeViolation(
              kind: svkWrongKind,
              path: path / "updatedProperties" / i,
              expectedKind: JString,
              actualKind: elem.kind,
            )
          )
        props.add(elem.getStr(""))
      Opt.some(props)
    else:
      return err(
        SerdeViolation(
          kind: svkWrongKind,
          path: path / "updatedProperties",
          expectedKind: JArray,
          actualKind: upNode.kind,
        )
      )
  return ok(MailboxChangesResponse(base: base, updatedProperties: updatedProperties))

# =============================================================================
# addMailboxChanges — Mailbox/changes (RFC 8621 §2.2)
# =============================================================================

func addMailboxChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[MailboxChangesResponse]) =
  ## Adds a Mailbox/changes invocation. Returns a handle typed to the
  ## extended ``MailboxChangesResponse`` (which includes ``updatedProperties``).
  let req = ChangesRequest[Mailbox](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges
  )
  let args = req.toJson()
  let (newBuilder, callId) = b.addInvocation(mnMailboxChanges, args, MailCapUri)
  (newBuilder, ResponseHandle[MailboxChangesResponse](callId))

# =============================================================================
# addMailboxQuery — Mailbox/query (RFC 8621 §2.3)
# =============================================================================

func addMailboxQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Mailbox]]) =
  ## Mailbox/query (RFC 8621 §2.3). Mailbox uses the protocol-level
  ## ``Comparator``; the RFC defines no typed Mailbox comparator. Tree
  ## extension args (Decision B13) are emitted unconditionally.
  addQuery[Mailbox, MailboxFilterCondition, Comparator](
    b,
    accountId,
    toJson,
    filter,
    sort,
    queryParams,
    extras = @[("sortAsTree", %sortAsTree), ("filterAsTree", %filterAsTree)],
  )

# =============================================================================
# addMailboxQueryChanges — Mailbox/queryChanges (RFC 8621 §2.4)
# =============================================================================

func addMailboxQueryChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[Mailbox]]) =
  ## Mailbox/queryChanges (RFC 8621 §2.4). No extension args.
  addQueryChanges[Mailbox, MailboxFilterCondition, Comparator](
    b, accountId, sinceQueryState, toJson, filter, sort, maxChanges, upToId,
    calculateTotal,
  )

# =============================================================================
# addMailboxSet — Mailbox/set (RFC 8621 §2.5)
# =============================================================================

func addMailboxSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, MailboxCreate]] =
      Opt.none(Table[CreationId, MailboxCreate]),
    update: Opt[Table[Id, MailboxUpdateSet]] = Opt.none(Table[Id, MailboxUpdateSet]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): (RequestBuilder, ResponseHandle[SetResponse[Mailbox]]) =
  ## Adds a Mailbox/set invocation with typed ``MailboxCreate`` and
  ## ``MailboxUpdateSet`` per Design §4.1 (Part F migration). The typed
  ## update algebra is the only public update path.
  ## ``onDestroyRemoveEmails`` RFC 8621 §2.5 extension always emitted.
  let jsonCreate = block:
    var res = Opt.none(Table[CreationId, JsonNode])
    for createMap in create:
      var tbl = initTable[CreationId, JsonNode](createMap.len)
      for k, v in createMap:
        tbl[k] = v.toJson()
      res = Opt.some(tbl)
    res
  # SetRequest serialises the common fields; the typed update map is
  # appended to `args["update"]` below, bypassing any wire-patch wrapper.
  let req = SetRequest[Mailbox](
    accountId: accountId, ifInState: ifInState, create: jsonCreate, destroy: destroy
  )
  var args = req.toJson()
  for updateMap in update:
    var updateObj = newJObject()
    for id, updateSet in updateMap:
      updateObj[string(id)] = updateSet.toJson()
    args["update"] = updateObj
  args["onDestroyRemoveEmails"] = %onDestroyRemoveEmails
  let (newBuilder, callId) = b.addInvocation(mnMailboxSet, args, MailCapUri)
  (newBuilder, ResponseHandle[SetResponse[Mailbox]](callId))

# =============================================================================
# addEmailGet — Email/get (RFC 8621 §4.2)
# =============================================================================

func addEmailGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[Email]]) =
  ## Adds an Email/get invocation with Email-specific body fetch options
  ## (RFC 8621 §4.2, Decision D9). ``bodyFetchOptions`` controls which body
  ## values to fetch and optional truncation. Default produces no extra keys.
  let req = GetRequest[Email](accountId: accountId, ids: ids, properties: properties)
  var args = req.toJson()
  bodyFetchOptions.emitInto(args)
  let (newBuilder, callId) = b.addInvocation(mnEmailGet, args, MailCapUri)
  (newBuilder, ResponseHandle[GetResponse[Email]](callId))

# =============================================================================
# addEmailQuery — Email/query (RFC 8621 §4.4)
# =============================================================================

func addEmailQuery*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
): (RequestBuilder, ResponseHandle[QueryResponse[Email]]) =
  ## Email/query (RFC 8621 §4.4). Typed ``EmailComparator`` flows through
  ## the generic. ``collapseThreads`` (Decision D11) is emitted unconditionally.
  addQuery[Email, EmailFilterCondition, EmailComparator](
    b,
    accountId,
    toJson,
    filter,
    sort,
    queryParams,
    extras = @[("collapseThreads", %collapseThreads)],
  )

# =============================================================================
# addEmailQueryChanges — Email/queryChanges (RFC 8621 §4.5)
# =============================================================================

func addEmailQueryChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    collapseThreads: bool = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[Email]]) =
  ## Email/queryChanges (RFC 8621 §4.5).
  addQueryChanges[Email, EmailFilterCondition, EmailComparator](
    b,
    accountId,
    sinceQueryState,
    toJson,
    filter,
    sort,
    maxChanges,
    upToId,
    calculateTotal,
    extras = @[("collapseThreads", %collapseThreads)],
  )

# =============================================================================
# addEmailSet — Email/set (RFC 8621 §4.6)
# =============================================================================

func addEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, EmailBlueprint]] =
      Opt.none(Table[CreationId, EmailBlueprint]),
    update: Opt[Table[Id, EmailUpdateSet]] = Opt.none(Table[Id, EmailUpdateSet]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[EmailCreatedItem]]) =
  ## Adds an Email/set invocation. Typed create (EmailBlueprint) and update
  ## (EmailUpdateSet) per Design §4.1. Returns a handle typed to the
  ## generic ``SetResponse[EmailCreatedItem]`` — ``createResults`` carries
  ## the typed per-entity payload, ``updateResults`` / ``destroyResults``
  ## follow the RFC 8620 §5.3 merged-Result-table shape.
  let jsonCreate = block:
    var res = Opt.none(Table[CreationId, JsonNode])
    for createMap in create:
      var tbl = initTable[CreationId, JsonNode](createMap.len)
      for k, v in createMap:
        tbl[k] = v.toJson()
      res = Opt.some(tbl)
    res
  # SetRequest serialises the common fields; the typed update map is
  # appended to `args["update"]` below.
  let req = SetRequest[Email](
    accountId: accountId, ifInState: ifInState, create: jsonCreate, destroy: destroy
  )
  var args = req.toJson()
  for updateMap in update:
    var updateObj = newJObject()
    for id, updateSet in updateMap:
      updateObj[string(id)] = updateSet.toJson()
    args["update"] = updateObj
  let (newBuilder, callId) = b.addInvocation(mnEmailSet, args, MailCapUri)
  (newBuilder, ResponseHandle[SetResponse[EmailCreatedItem]](callId))

# =============================================================================
# addEmailCopy — Email/copy (RFC 8621 §4.7)
# =============================================================================

func addEmailCopy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[CopyResponse[EmailCreatedItem]]) =
  ## Simple Email/copy invocation (non-compound; no implicit destroy).
  ## ``onSuccessDestroyOriginal`` omitted (wire default false per RFC 8620
  ## §5.4). For the compound overload, use ``addEmailCopyAndDestroy``.
  var args = newJObject()
  args["fromAccountId"] = fromAccountId.toJson()
  for s in ifFromInState:
    args["ifFromInState"] = s.toJson()
  args["accountId"] = accountId.toJson()
  for s in ifInState:
    args["ifInState"] = s.toJson()
  var createObj = newJObject()
  for cid, item in create:
    createObj[string(cid)] = item.toJson()
  args["create"] = createObj
  let (newBuilder, callId) = b.addInvocation(mnEmailCopy, args, MailCapUri)
  (newBuilder, ResponseHandle[CopyResponse[EmailCreatedItem]](callId))

# =============================================================================
# EmailCopyHandles / EmailCopyResults — compound dispatch (RFC 8620 §5.4)
# =============================================================================

{.push ruleOff: "objects".}

type EmailCopyHandles* = object
  ## Paired handles from ``addEmailCopyAndDestroy``. The implicit Email/set
  ## destroy response shares its call-id with the parent Email/copy per
  ## RFC 8620 §5.4; destroy carries its own method-name (Email/set) via
  ## ``NameBoundHandle`` so ``getBoth`` dispatches correctly without a
  ## filter argument at the call site (Design §5.4).
  copy*: ResponseHandle[CopyResponse[EmailCreatedItem]]
  destroy*: NameBoundHandle[SetResponse[EmailCreatedItem]]

type EmailCopyResults* = object
  ## Paired extraction results from ``addEmailCopyAndDestroy``.
  copy*: CopyResponse[EmailCreatedItem]
  destroy*: SetResponse[EmailCreatedItem]

{.pop.}

# =============================================================================
# addEmailCopyAndDestroy — compound Email/copy with implicit Email/set destroy
# =============================================================================

func addEmailCopyAndDestroy*(
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, EmailCopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, EmailCopyHandles) =
  ## Compound Email/copy with ``onSuccessDestroyOriginal: true``. On
  ## successful copy the server performs an implicit Email/set call that
  ## destroys the originals in the from-account; that implicit response
  ## shares the parent call-id per RFC 8620 §5.4 (Design §5.3).
  ##
  ## Both handles are built from the same ``MethodCallId`` returned by
  ## ``addInvocation``; the destroy handle carries ``mnEmailSet`` so
  ## ``getBoth`` can disambiguate the two wire invocations.
  var args = newJObject()
  args["fromAccountId"] = fromAccountId.toJson()
  for s in ifFromInState:
    args["ifFromInState"] = s.toJson()
  args["accountId"] = accountId.toJson()
  for s in ifInState:
    args["ifInState"] = s.toJson()
  var createObj = newJObject()
  for cid, item in create:
    createObj[string(cid)] = item.toJson()
  args["create"] = createObj
  args["onSuccessDestroyOriginal"] = %true
  for s in destroyFromIfInState:
    args["destroyFromIfInState"] = s.toJson()
  let (newBuilder, cid) = b.addInvocation(mnEmailCopy, args, MailCapUri)
  let handles = EmailCopyHandles(
    copy: ResponseHandle[CopyResponse[EmailCreatedItem]](cid),
    destroy: NameBoundHandle[SetResponse[EmailCreatedItem]](
      callId: cid, methodName: mnEmailSet
    ),
  )
  (newBuilder, handles)

# =============================================================================
# getBoth — paired extraction for EmailCopyHandles
# =============================================================================

func getBoth*(
    resp: Response, handles: EmailCopyHandles
): Result[EmailCopyResults, MethodError] =
  ## Extract both copy and implicit-destroy responses. Dispatches via UFCS:
  ## ``handles.copy`` resolves through the default ``get[T]`` overload;
  ## ``handles.destroy`` resolves through the ``NameBoundHandle`` ``get[T]``
  ## overload, which applies the method-name filter from handle data.
  mixin fromJson
  let copy = ?resp.get(handles.copy)
  let destroy = ?resp.get(handles.destroy)
  return ok(EmailCopyResults(copy: copy, destroy: destroy))
