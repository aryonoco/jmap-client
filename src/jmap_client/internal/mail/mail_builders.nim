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
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../../types
import ../../serialisation
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ./mailbox
import ./mailbox_changes_response
import ./thread
import ./email
import ./email_blueprint
import ./email_update
import ./mail_filters
import ./mail_entities
import ./serde_mailbox
import ./serde_thread
import ./serde_email
import ./serde_email_blueprint
import ./serde_email_update
import ./serde_mail_filters

# Re-export the serde modules whose ``fromJson`` overloads are required at
# the dispatch call-site (``get(handle)``): the generic ``SetResponse[T,
# U]`` and ``CopyResponse[T]`` resolve ``T.fromJson`` / ``U.fromJson`` via
# ``mixin`` at the outer instantiation site, so the caller must have these
# in scope.
export serde_mailbox
export serde_thread
export serde_email
export mailbox_changes_response

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
    b, accountId, sinceQueryState, filter, sort, maxChanges, upToId, calculateTotal
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
): (RequestBuilder, ResponseHandle[SetResponse[MailboxCreatedItem, PartialMailbox]]) =
  ## Mailbox/set (RFC 8621 §2.5). Thin wrapper over
  ## ``addSet[Mailbox, MailboxCreate, NonEmptyMailboxUpdates,
  ## SetResponse[MailboxCreatedItem, PartialMailbox]]`` with the
  ## Mailbox-specific ``onDestroyRemoveEmails`` extension emitted via
  ## ``extras``. ``create`` and ``update`` arrive typed; the generic
  ## ``SetRequest[T, C, U].toJson`` serialises both through the ``mixin
  ## toJson`` cascade. The ``createResults`` payload is
  ## ``MailboxCreatedItem`` rather than the full ``Mailbox`` because
  ## RFC 8620 §5.3's ``created[cid]`` carries only the server-set
  ## subset (id + counts + myRights), and Stalwart further trims to
  ## ``{"id": "..."}``. ``updateResults`` carries ``PartialMailbox`` per
  ## A4 D2 — RFC 8620 §5.3 admits the four outer states (absent /
  ## confirmed-without-echo / echoed-partial / rejected).
  addSet[
    Mailbox,
    MailboxCreate,
    NonEmptyMailboxUpdates,
    SetResponse[MailboxCreatedItem, PartialMailbox],
  ](
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
  ## (RFC 8621 §4.2, Decision D9). ``bodyFetchOptions.toExtras()`` supplies
  ## the RFC-specific keys; ``default(EmailBodyFetchOptions)`` yields an
  ## empty seq (no extra keys). Thin wrapper over ``addGet[Email]``'s
  ## ``extras`` parameter.
  addGet[Email](b, accountId, ids, properties, extras = bodyFetchOptions.toExtras())

# =============================================================================
# addEmailGetByRef — Email/get by back-reference (RFC 8620 §3.7 / H1 §4.3)
# =============================================================================

func addEmailGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[Email]]) =
  ## Sibling of ``addEmailGet`` for RFC 8620 §3.7 back-reference chains —
  ## ``ids`` is sourced from a previous invocation's response rather than
  ## supplied as literal IDs. Delegates to ``addEmailGet`` with a
  ## ``referenceTo[seq[Id]]``-wrapped ``Referencable``; the generic
  ## ``addGet[T]`` routes ``rkReference`` variants to the ``#ids`` wire
  ## key.
  addEmailGet(
    b,
    accountId,
    ids = Opt.some(referenceTo[seq[Id]](idsRef)),
    properties = properties,
    bodyFetchOptions = bodyFetchOptions,
  )

# =============================================================================
# addPartialEmailGet — sparse Email/get returning typed ``PartialEmail``
# (A3.6 D7)
# =============================================================================

func addPartialEmailGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[PartialEmail]]) =
  ## Sparse Email/get returning a typed ``PartialEmail`` (RFC 8621 §4.2
  ## + A3.6 D7). Mirrors ``addEmailGet`` shape; the partial parser
  ## tolerates any subset of properties the server returns, so an
  ## explicit ``properties`` projection no longer surfaces
  ## ``MethodError(metServerFail)`` on the typed entry point.
  addGet[PartialEmail](
    b, accountId, ids, properties, extras = bodyFetchOptions.toExtras()
  )

# =============================================================================
# addPartialEmailGetByRef — sparse Email/get via RFC 8620 §3.7 back-reference
# (A3.6 D7)
# =============================================================================

func addPartialEmailGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ResponseHandle[GetResponse[PartialEmail]]) =
  ## Sibling of ``addPartialEmailGet`` for RFC 8620 §3.7 back-reference
  ## chains (A3.6 D7). ``ids`` is sourced from a previous invocation's
  ## response rather than supplied as literal IDs.
  addPartialEmailGet(
    b,
    accountId,
    ids = Opt.some(referenceTo[seq[Id]](idsRef)),
    properties = properties,
    bodyFetchOptions = bodyFetchOptions,
  )

# =============================================================================
# addThreadGetByRef — Thread/get by back-reference (RFC 8620 §3.7 / H1 §4.3)
# =============================================================================

func addThreadGetByRef*(
    b: RequestBuilder,
    accountId: AccountId,
    idsRef: ResultReference,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[thread.Thread]]) =
  ## Sibling of generic ``addGet[thread.Thread]`` for RFC 8620 §3.7
  ## back-reference chains. ``Thread`` is immutable and read-only — no
  ## body-fetch analogue, so only ``properties`` is forwarded. Delegates
  ## to ``addGet[T]`` through the ``Referencable`` wrapper, which routes
  ## ``rkReference`` to the ``#ids`` wire key.
  addGet[thread.Thread](
    b, accountId, ids = Opt.some(referenceTo[seq[Id]](idsRef)), properties = properties
  )

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
): (RequestBuilder, ResponseHandle[SetResponse[EmailCreatedItem, PartialEmail]]) =
  ## Email/set (RFC 8621 §4.6). Thin wrapper over
  ## ``addSet[Email, EmailBlueprint, NonEmptyEmailUpdates,
  ## SetResponse[EmailCreatedItem, PartialEmail]]`` with no entity-
  ## specific extras. The ``SetResponse[EmailCreatedItem, PartialEmail]``
  ## handle carries typed ``createResults`` via ``mixin``-resolved
  ## ``EmailCreatedItem.fromJson`` and typed ``updateResults`` via
  ## ``PartialEmail.fromJson`` (A4 D2).
  addSet[
    Email,
    EmailBlueprint,
    NonEmptyEmailUpdates,
    SetResponse[EmailCreatedItem, PartialEmail],
  ](b, accountId, ifInState, create, update, destroy)

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
  ## Simple Email/copy invocation (non-compound; no implicit destroy). Thin
  ## wrapper over ``addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]]``.
  ## ``destroyMode`` defaults to ``keepOriginals()``, so
  ## ``onSuccessDestroyOriginal`` is omitted from the wire per RFC 8620 §5.4.
  addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]](
    b, fromAccountId, accountId, create, ifFromInState, ifInState
  )

# =============================================================================
# EmailCopyHandles / EmailCopyResults — compound dispatch (RFC 8620 §5.4)
# =============================================================================

type EmailCopyHandles* = CompoundHandles[
  CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem, PartialEmail]
]
  ## Domain-named specialisation of ``CompoundHandles[A, B]`` for
  ## ``addEmailCopyAndDestroy`` (Email/copy + implicit Email/set destroy
  ## per RFC 8620 §5.4). Fields ``primary`` / ``implicit`` inherit from
  ## the generic at ``dispatch.nim``. The implicit handle's
  ## ``SetResponse`` carries typed ``PartialEmail`` echoes for any
  ## successfully-destroyed source records (A4 D2).

type EmailCopyResults* = CompoundResults[
  CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem, PartialEmail]
]
  ## Paired extraction target for ``getBoth(EmailCopyHandles)`` — the
  ## generic overload in ``dispatch.nim`` handles the dispatch.

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
  ## Compound Email/copy with ``onSuccessDestroyOriginal: true``. Routes
  ## the primary Email/copy through ``addCopy[Email, ...]`` with the
  ## destroy-mode supplied via ``destroyAfterSuccess(destroyFromIfInState)``;
  ## the ``CopyRequest.toJson`` emits ``onSuccessDestroyOriginal: true`` and
  ## the optional ``destroyFromIfInState`` guard. The returned handle is
  ## paired with a ``NameBoundHandle`` filtered by ``mnEmailSet`` for the
  ## implicit-destroy response (RFC 8620 §5.4, Design §5.3).
  let (b1, copyHandle) = addCopy[Email, EmailCopyItem, CopyResponse[EmailCreatedItem]](
    b,
    fromAccountId,
    accountId,
    create,
    ifFromInState,
    ifInState,
    destroyMode = destroyAfterSuccess(destroyFromIfInState),
  )
  let handles = EmailCopyHandles(
    primary: copyHandle,
    implicit: NameBoundHandle[SetResponse[EmailCreatedItem, PartialEmail]](
      callId: MethodCallId(copyHandle), methodName: mnEmailSet
    ),
  )
  (b1, handles)

# =============================================================================
# EmailQueryThreadChain + addEmailQueryWithThreads (H1 §4)
# RFC 8621 §4.10 first-login workflow: 4-invocation back-reference chain
# =============================================================================

const DefaultDisplayProperties*: seq[string] = @[
  "threadId", "mailboxIds", "keywords", "hasAttachment", "from", "subject",
  "receivedAt", "size", "preview",
]
  ## RFC 8621 §4.10 first-login example display properties. Override via
  ## the ``displayProperties`` argument of ``addEmailQueryWithThreads``;
  ## this const is the default for a minimally-configured first-login
  ## scenario. One named auditable default, visible at one site (H12).

type EmailQueryThreadChain* {.ruleOff: "objects".} = object
  ## Paired handles for the RFC 8621 §4.10 first-login workflow. Each
  ## handle binds a distinct ``MethodCallId``; the domain role of each
  ## step lives at the field level because there is no generic above
  ## this record to carry it (H10, H11).
  queryH*: ResponseHandle[QueryResponse[Email]]
  threadIdFetchH*: ResponseHandle[GetResponse[Email]]
  threadsH*: ResponseHandle[GetResponse[thread.Thread]]
  displayH*: ResponseHandle[GetResponse[Email]]

type EmailQueryThreadResults* {.ruleOff: "objects".} = object
  ## Paired extraction target of ``getAll(EmailQueryThreadChain)``. Plain
  ## domain names; the enclosing type name already conveys "responses"
  ## (H11).
  query*: QueryResponse[Email]
  threadIdFetch*: GetResponse[Email]
  threads*: GetResponse[thread.Thread]
  display*: GetResponse[Email]

func getAll*(
    resp: Response, handles: EmailQueryThreadChain
): Result[EmailQueryThreadResults, MethodError] =
  ## Extract all four responses from the first-login workflow. Monomorphic
  ## over ``EmailQueryThreadChain`` — not a parametric ``getAll[A, B, C, D]``
  ## — because the record it serves is not parametric either (H14).
  ## Co-located with the builder rather than placed in ``dispatch.nim``
  ## because there is no parametric shape to share with the dispatch layer.
  mixin fromJson
  let query = ?resp.get(handles.queryH)
  let threadIdFetch = ?resp.get(handles.threadIdFetchH)
  let threads = ?resp.get(handles.threadsH)
  let display = ?resp.get(handles.displayH)
  ok(
    EmailQueryThreadResults(
      query: query, threadIdFetch: threadIdFetch, threads: threads, display: display
    )
  )

func addEmailQueryWithThreads*(
    b: RequestBuilder,
    accountId: AccountId,
    filter: Filter[EmailFilterCondition],
    sort: seq[EmailComparator] = @[],
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = true,
    displayProperties: seq[string] = DefaultDisplayProperties,
    displayBodyFetchOptions: EmailBodyFetchOptions = EmailBodyFetchOptions(
      fetchBodyValues: bvsAll, maxBodyValueBytes: Opt.some(UnsignedInt(256))
    ),
): (RequestBuilder, EmailQueryThreadChain) =
  ## RFC 8621 §4.10 first-login workflow encoded in types. Emits the
  ## exact 4-invocation back-reference chain the RFC demonstrates
  ## byte-for-byte, with ``ResultReference`` paths sourced from ``RefPath``
  ## — no stringly-typed JSON Pointers at this site (H16).
  ##
  ## ``filter`` is mandatory (H6; RFC 8621 §4.10 ¶1 — first-login always
  ## filters to a user-visible mailbox scope). ``collapseThreads``
  ## defaults to ``true`` per RFC §4.10 example (H13).
  ## ``displayProperties`` defaults to the RFC-enumerated nine
  ## (``DefaultDisplayProperties``); override is a normal argument (H12).
  let sortOpt =
    if sort.len > 0:
      Opt.some(sort)
    else:
      Opt.none(seq[EmailComparator])

  let (b1, queryH) =
    addEmailQuery(b, accountId, Opt.some(filter), sortOpt, queryParams, collapseThreads)

  let (b2, threadIdFetchH) = addEmailGetByRef(
    b1,
    accountId,
    idsRef =
      initResultReference(resultOf = callId(queryH), name = mnEmailQuery, path = rpIds),
    properties = Opt.some(@["threadId"]),
  )

  let (b3, threadsH) = addThreadGetByRef(
    b2,
    accountId,
    idsRef = initResultReference(
      resultOf = callId(threadIdFetchH), name = mnEmailGet, path = rpListThreadId
    ),
  )

  let (b4, displayH) = addEmailGetByRef(
    b3,
    accountId,
    idsRef = initResultReference(
      resultOf = callId(threadsH), name = mnThreadGet, path = rpListEmailIds
    ),
    properties = Opt.some(displayProperties),
    bodyFetchOptions = displayBodyFetchOptions,
  )

  (
    b4,
    EmailQueryThreadChain(
      queryH: queryH,
      threadIdFetchH: threadIdFetchH,
      threadsH: threadsH,
      displayH: displayH,
    ),
  )
