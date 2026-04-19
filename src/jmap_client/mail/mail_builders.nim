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
import ./mailbox_changes_response
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
export mailbox_changes_response

const MailCapUri = "urn:ietf:params:jmap:mail"

# =============================================================================
# addMailboxChanges — Mailbox/changes (RFC 8621 §2.2)
# =============================================================================

func addMailboxChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[MailboxChangesResponse]) =
  ## Mailbox/changes (RFC 8621 §2.2). Thin alias over
  ## ``addChanges[Mailbox, MailboxChangesResponse]``; the extended response
  ## carries ``updatedProperties``.
  addChanges[Mailbox, MailboxChangesResponse](b, accountId, sinceState, maxChanges)

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
    update: Opt[NonEmptyMailboxUpdates] = Opt.none(NonEmptyMailboxUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onDestroyRemoveEmails: bool = false,
): (RequestBuilder, ResponseHandle[SetResponse[Mailbox]]) =
  ## Mailbox/set (RFC 8621 §2.5). Thin wrapper over
  ## ``addSet[Mailbox, MailboxCreate, NonEmptyMailboxUpdates, SetResponse[Mailbox]]``
  ## with the Mailbox-specific ``onDestroyRemoveEmails`` extension emitted
  ## via ``extras``. ``create`` and ``update`` arrive typed; the generic
  ## ``SetRequest[T, C, U].toJson`` serialises both through the ``mixin toJson``
  ## cascade.
  addSet[Mailbox, MailboxCreate, NonEmptyMailboxUpdates, SetResponse[Mailbox]](
    b,
    accountId,
    ifInState,
    create,
    update,
    destroy,
    extras = @[("onDestroyRemoveEmails", %onDestroyRemoveEmails)],
  )

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
    update: Opt[NonEmptyEmailUpdates] = Opt.none(NonEmptyEmailUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[EmailCreatedItem]]) =
  ## Email/set (RFC 8621 §4.6). Thin wrapper over
  ## ``addSet[Email, EmailBlueprint, NonEmptyEmailUpdates, SetResponse[EmailCreatedItem]]``
  ## with no entity-specific extras. The ``SetResponse[EmailCreatedItem]``
  ## handle carries typed ``createResults`` via ``mixin``-resolved
  ## ``EmailCreatedItem.fromJson`` at the dispatch site.
  addSet[Email, EmailBlueprint, NonEmptyEmailUpdates, SetResponse[EmailCreatedItem]](
    b, accountId, ifInState, create, update, destroy
  )

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
