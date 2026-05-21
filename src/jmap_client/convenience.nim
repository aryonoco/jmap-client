# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Opt-in per-entity pipeline combinators for the common JMAP
## multi-method patterns (RFC 8620 §3.7 back-reference chains).
##
## This module is publicly importable as ``jmap_client/convenience`` but
## is NOT re-exported by the root ``jmap_client`` module — consumers who
## want pipeline combinators ``import jmap_client/convenience``
## explicitly. The physical separation keeps the typed per-entity
## builder surface the sole always-on API while these combinators stay
## opt-in (P6 quarantine; lessons from analysing OpenSSL/libgit2).
##
## **The combinators.** ``add<Entity>QueryThenGet`` emits
## ``<Entity>/query`` + ``<Entity>/get``; ``add<Entity>ChangesToGet``
## emits ``<Entity>/changes`` + ``<Entity>/get``. Each wires the second
## invocation's ``ids`` argument to the first's response with the public
## ``reference`` primitive — the ``/ids`` path for the query chains, the
## ``/created`` path for the changes chains. ``getBoth`` extracts both
## responses from the returned handle pair, short-circuiting on the
## first error.
##
## **Naming convention.** Combinators use the ``add*`` prefix because
## they thread the ``RequestBuilder`` state (the builder naming
## convention). Paired extraction uses ``getBoth`` (always exactly two
## handles).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import jmap_client

# =============================================================================
# Paired handle bundles
# =============================================================================

type QueryGetHandles*[T] = object
  ## Paired phantom-typed handles from a query-then-get pipeline.
  ## Both handles retain full compile-time type safety.
  query*: ResponseHandle[QueryResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

type ChangesGetHandles*[T] = object
  ## Paired phantom-typed handles from a changes-then-get pipeline.
  changes*: ResponseHandle[ChangesResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

type MailboxChangesGetHandles* = object
  ## Paired handles from ``addMailboxChangesToGet``. Bespoke because
  ## Mailbox/changes returns the extended ``MailboxChangesResponse``
  ## (carrying ``updatedProperties``), which the generic
  ## ``ChangesGetHandles[Mailbox]`` cannot express.
  changes*: ResponseHandle[MailboxChangesResponse]
  get*: ResponseHandle[GetResponse[Mailbox]]

# =============================================================================
# Paired extraction targets
# =============================================================================

type QueryGetResults*[T] = object
  ## Paired extraction results from a query-then-get pipeline.
  query*: QueryResponse[T]
  get*: GetResponse[T]

type ChangesGetResults*[T] = object
  ## Paired extraction results from a changes-then-get pipeline.
  changes*: ChangesResponse[T]
  get*: GetResponse[T]

type MailboxChangesGetResults* = object
  ## Paired extraction target for ``getBoth(MailboxChangesGetHandles)``.
  changes*: MailboxChangesResponse
  get*: GetResponse[Mailbox]

# =============================================================================
# Query-then-get combinators
# =============================================================================

func addEmailQueryThenGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailFilterCondition]] = Opt.none(Filter[EmailFilterCondition]),
    sort: Opt[seq[EmailComparator]] = Opt.none(seq[EmailComparator]),
    queryParams: QueryParams = QueryParams(),
    collapseThreads: bool = false,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, QueryGetHandles[Email]) =
  ## Email/query + Email/get (RFC 8621 §4.4 + §4.2). The get's ``ids``
  ## back-references the query's ``/ids`` path.
  let (b1, qh) = addEmailQuery(b, accountId, filter, sort, queryParams, collapseThreads)
  let idsR = referenceTo[seq[Id]](reference(qh, mnEmailQuery, rpIds))
  let (b2, gh) = addEmailGet(
    b1,
    accountId,
    ids = Opt.some(idsR),
    properties = properties,
    bodyFetchOptions = bodyFetchOptions,
  )
  (b2, QueryGetHandles[Email](query: qh, get: gh))

func addMailboxQueryThenGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[MailboxFilterCondition]] =
      Opt.none(Filter[MailboxFilterCondition]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
    sortAsTree: bool = false,
    filterAsTree: bool = false,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, QueryGetHandles[Mailbox]) =
  ## Mailbox/query + Mailbox/get (RFC 8621 §2.3 + §2.1). The get's
  ## ``ids`` back-references the query's ``/ids`` path.
  let (b1, qh) =
    addMailboxQuery(b, accountId, filter, sort, queryParams, sortAsTree, filterAsTree)
  let idsR = referenceTo[seq[Id]](reference(qh, mnMailboxQuery, rpIds))
  let (b2, gh) =
    addMailboxGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, QueryGetHandles[Mailbox](query: qh, get: gh))

func addEmailSubmissionQueryThenGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, QueryGetHandles[AnyEmailSubmission]) =
  ## EmailSubmission/query + EmailSubmission/get (RFC 8621 §7.3 + §7.1).
  ## The get's ``ids`` back-references the query's ``/ids`` path.
  let (b1, qh) = addEmailSubmissionQuery(b, accountId, filter, sort, queryParams)
  let idsR = referenceTo[seq[Id]](reference(qh, mnEmailSubmissionQuery, rpIds))
  let (b2, gh) =
    addEmailSubmissionGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, QueryGetHandles[AnyEmailSubmission](query: qh, get: gh))

# =============================================================================
# Changes-to-get combinators
# =============================================================================

func addEmailChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ChangesGetHandles[Email]) =
  ## Email/changes + Email/get (RFC 8621 §4.3 + §4.2). The get's ``ids``
  ## back-references the changes response's ``/created`` path — only
  ## newly created records are fetched.
  let (b1, ch) = addEmailChanges(b, accountId, sinceState, maxChanges)
  let idsR = referenceTo[seq[Id]](reference(ch, mnEmailChanges, rpCreated))
  let (b2, gh) = addEmailGet(
    b1,
    accountId,
    ids = Opt.some(idsR),
    properties = properties,
    bodyFetchOptions = bodyFetchOptions,
  )
  (b2, ChangesGetHandles[Email](changes: ch, get: gh))

func addIdentityChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ChangesGetHandles[Identity]) =
  ## Identity/changes + Identity/get (RFC 8621 §6.2 + §6.1). The get's
  ## ``ids`` back-references the changes response's ``/created`` path.
  let (b1, ch) = addIdentityChanges(b, accountId, sinceState, maxChanges)
  let idsR = referenceTo[seq[Id]](reference(ch, mnIdentityChanges, rpCreated))
  let (b2, gh) =
    addIdentityGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, ChangesGetHandles[Identity](changes: ch, get: gh))

func addThreadChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ChangesGetHandles[jmap_client.Thread]) =
  ## Thread/changes + Thread/get (RFC 8621 §3.2 + §3.1). The get's
  ## ``ids`` back-references the changes response's ``/created`` path.
  let (b1, ch) = addThreadChanges(b, accountId, sinceState, maxChanges)
  let idsR = referenceTo[seq[Id]](reference(ch, mnThreadChanges, rpCreated))
  let (b2, gh) =
    addThreadGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, ChangesGetHandles[jmap_client.Thread](changes: ch, get: gh))

func addEmailSubmissionChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ChangesGetHandles[AnyEmailSubmission]) =
  ## EmailSubmission/changes + EmailSubmission/get (RFC 8621 §7.2 +
  ## §7.1). The get's ``ids`` back-references the changes response's
  ## ``/created`` path.
  let (b1, ch) = addEmailSubmissionChanges(b, accountId, sinceState, maxChanges)
  let idsR = referenceTo[seq[Id]](reference(ch, mnEmailSubmissionChanges, rpCreated))
  let (b2, gh) =
    addEmailSubmissionGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, ChangesGetHandles[AnyEmailSubmission](changes: ch, get: gh))

func addMailboxChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, MailboxChangesGetHandles) =
  ## Mailbox/changes + Mailbox/get (RFC 8621 §2.2 + §2.1). The get's
  ## ``ids`` back-references the changes response's ``/created`` path.
  ## Returns the bespoke ``MailboxChangesGetHandles`` because
  ## Mailbox/changes yields the extended ``MailboxChangesResponse``,
  ## which ``ChangesGetHandles[Mailbox]`` cannot type.
  let (b1, ch) = addMailboxChanges(b, accountId, sinceState, maxChanges)
  let idsR = referenceTo[seq[Id]](reference(ch, mnMailboxChanges, rpCreated))
  let (b2, gh) =
    addMailboxGet(b1, accountId, ids = Opt.some(idsR), properties = properties)
  (b2, MailboxChangesGetHandles(changes: ch, get: gh))

# =============================================================================
# getBoth — paired response extraction
# =============================================================================

func getBoth*[T](
    dr: DispatchedResponse, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], GetError] =
  ## Extracts both query and get responses, failing on the first error.
  ## Composes naturally with the ``?`` operator:
  ## ``let results = ?dr.getBoth(handles)``. Resolution uses each
  ## handle's stored parser closure (no mixin at this site).
  let qr = ?dr.get(handles.query)
  let gr = ?dr.get(handles.get)
  ok(QueryGetResults[T](query: qr, get: gr))

func getBoth*[T](
    dr: DispatchedResponse, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], GetError] =
  ## Extracts both changes and get responses, failing on the first error.
  ## Resolution uses each handle's stored parser closure (no mixin at
  ## this site).
  let cr = ?dr.get(handles.changes)
  let gr = ?dr.get(handles.get)
  ok(ChangesGetResults[T](changes: cr, get: gr))

func getBoth*(
    dr: DispatchedResponse, handles: MailboxChangesGetHandles
): Result[MailboxChangesGetResults, GetError] =
  ## Extracts both the Mailbox/changes and Mailbox/get responses,
  ## failing on the first error.
  let cr = ?dr.get(handles.changes)
  let gr = ?dr.get(handles.get)
  ok(MailboxChangesGetResults(changes: cr, get: gr))
