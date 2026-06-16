# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Per-entity pipeline combinators for the common JMAP multi-method
## patterns (RFC 8620 §3.7 back-reference chains).
##
## Part of the always-on hub: ``import jmap_client`` reaches these
## combinators directly alongside the typed per-entity builder surface.
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

import ../types
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ../protocol/jmap_error
import ./email
import ./mailbox
import ./mailbox_changes_response
import ./identity
import ./thread
import ./email_submission
import ./mail_filters
import ./mail_builders
import ./identity_builders
import ./submission_builders

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
  ## Paired extraction results from a query-then-get pipeline. Each field is a
  ## ``MethodOutcome`` — a server method error rides the field as data, not the
  ## rail (RFC 8620 §3.6.2), so one method erroring does not discard the other.
  query*: MethodOutcome[QueryResponse[T]]
  get*: MethodOutcome[GetResponse[T]]

type ChangesGetResults*[T] = object
  ## Paired extraction results from a changes-then-get pipeline. Each field is a
  ## ``MethodOutcome`` (see ``QueryGetResults``).
  changes*: MethodOutcome[ChangesResponse[T]]
  get*: MethodOutcome[GetResponse[T]]

type MailboxChangesGetResults* = object
  ## Paired extraction target for ``getBoth(MailboxChangesGetHandles)``. Each
  ## field is a ``MethodOutcome`` (see ``QueryGetResults``).
  changes*: MethodOutcome[MailboxChangesResponse]
  get*: MethodOutcome[GetResponse[Mailbox]]

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
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, QueryGetHandles[Email]) =
  ## Email/query + full-record Email/get (RFC 8621 §4.4 + §4.2). The get's
  ## ``ids`` back-references the query's ``/ids`` path. For a typed property
  ## projection, compose ``addEmailQuery`` + ``addPartialEmailGet`` with
  ## ``ids = Opt.some(reference[seq[Id]](qh, mnEmailQuery, rpIds))`` directly.
  let (b1, qh) = addEmailQuery(b, accountId, filter, sort, queryParams, collapseThreads)
  let idsR = reference[seq[Id]](qh, mnEmailQuery, rpIds)
  let (b2, gh) = addEmailGet(
    b1, accountId, ids = Opt.some(idsR), bodyFetchOptions = bodyFetchOptions
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
): (RequestBuilder, QueryGetHandles[Mailbox]) =
  ## Mailbox/query + full-record Mailbox/get (RFC 8621 §2.3 + §2.1). The
  ## get's ``ids`` back-references the query's ``/ids`` path. For a typed
  ## property projection, compose ``addMailboxQuery`` + ``addPartialMailboxGet``
  ## directly.
  let (b1, qh) =
    addMailboxQuery(b, accountId, filter, sort, queryParams, sortAsTree, filterAsTree)
  let idsR = reference[seq[Id]](qh, mnMailboxQuery, rpIds)
  let (b2, gh) = addMailboxGet(b1, accountId, ids = Opt.some(idsR))
  (b2, QueryGetHandles[Mailbox](query: qh, get: gh))

func addEmailSubmissionQueryThenGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, QueryGetHandles[AnyEmailSubmission]) =
  ## EmailSubmission/query + full-record EmailSubmission/get (RFC 8621 §7.3 +
  ## §7.1). The get's ``ids`` back-references the query's ``/ids`` path. For a
  ## typed property projection, compose ``addEmailSubmissionQuery`` +
  ## ``addPartialEmailSubmissionGet`` directly.
  let (b1, qh) = addEmailSubmissionQuery(b, accountId, filter, sort, queryParams)
  let idsR = reference[seq[Id]](qh, mnEmailSubmissionQuery, rpIds)
  let (b2, gh) = addEmailSubmissionGet(b1, accountId, ids = Opt.some(idsR))
  (b2, QueryGetHandles[AnyEmailSubmission](query: qh, get: gh))

# =============================================================================
# Changes-to-get combinators
# =============================================================================

func addEmailChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    bodyFetchOptions: EmailBodyFetchOptions = default(EmailBodyFetchOptions),
): (RequestBuilder, ChangesGetHandles[Email]) =
  ## Email/changes + full-record Email/get (RFC 8621 §4.3 + §4.2). The get's
  ## ``ids`` back-references the changes response's ``/created`` path — only
  ## newly created records are fetched. For a typed property projection,
  ## compose ``addEmailChanges`` + ``addPartialEmailGet`` with
  ## ``ids = Opt.some(reference[seq[Id]](ch, mnEmailChanges, rpCreated))``
  ## directly.
  let (b1, ch) = addEmailChanges(b, accountId, sinceState, maxChanges)
  let idsR = reference[seq[Id]](ch, mnEmailChanges, rpCreated)
  let (b2, gh) = addEmailGet(
    b1, accountId, ids = Opt.some(idsR), bodyFetchOptions = bodyFetchOptions
  )
  (b2, ChangesGetHandles[Email](changes: ch, get: gh))

func addIdentityChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ChangesGetHandles[Identity]) =
  ## Identity/changes + full-record Identity/get (RFC 8621 §6.2 + §6.1). The
  ## get's ``ids`` back-references the changes response's ``/created`` path.
  ## For a typed property projection, compose ``addIdentityChanges`` +
  ## ``addPartialIdentityGet`` directly.
  let (b1, ch) = addIdentityChanges(b, accountId, sinceState, maxChanges)
  let idsR = reference[seq[Id]](ch, mnIdentityChanges, rpCreated)
  let (b2, gh) = addIdentityGet(b1, accountId, ids = Opt.some(idsR))
  (b2, ChangesGetHandles[Identity](changes: ch, get: gh))

func addThreadChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ChangesGetHandles[thread.Thread]) =
  ## Thread/changes + full-record Thread/get (RFC 8621 §3.2 + §3.1). The
  ## get's ``ids`` back-references the changes response's ``/created`` path.
  ## For a typed property projection, compose ``addThreadChanges`` +
  ## ``addPartialThreadGet`` directly.
  let (b1, ch) = addThreadChanges(b, accountId, sinceState, maxChanges)
  let idsR = reference[seq[Id]](ch, mnThreadChanges, rpCreated)
  let (b2, gh) = addThreadGet(b1, accountId, ids = Opt.some(idsR))
  (b2, ChangesGetHandles[thread.Thread](changes: ch, get: gh))

func addEmailSubmissionChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ChangesGetHandles[AnyEmailSubmission]) =
  ## EmailSubmission/changes + full-record EmailSubmission/get (RFC 8621 §7.2
  ## + §7.1). The get's ``ids`` back-references the changes response's
  ## ``/created`` path. For a typed property projection, compose
  ## ``addEmailSubmissionChanges`` + ``addPartialEmailSubmissionGet`` directly.
  let (b1, ch) = addEmailSubmissionChanges(b, accountId, sinceState, maxChanges)
  let idsR = reference[seq[Id]](ch, mnEmailSubmissionChanges, rpCreated)
  let (b2, gh) = addEmailSubmissionGet(b1, accountId, ids = Opt.some(idsR))
  (b2, ChangesGetHandles[AnyEmailSubmission](changes: ch, get: gh))

func addMailboxChangesToGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, MailboxChangesGetHandles) =
  ## Mailbox/changes + full-record Mailbox/get (RFC 8621 §2.2 + §2.1). The
  ## get's ``ids`` back-references the changes response's ``/created`` path.
  ## Returns the bespoke ``MailboxChangesGetHandles`` because Mailbox/changes
  ## yields the extended ``MailboxChangesResponse``, which
  ## ``ChangesGetHandles[Mailbox]`` cannot type. For a typed property
  ## projection, compose ``addMailboxChanges`` + ``addPartialMailboxGet``
  ## directly.
  let (b1, ch) = addMailboxChanges(b, accountId, sinceState, maxChanges)
  let idsR = reference[seq[Id]](ch, mnMailboxChanges, rpCreated)
  let (b2, gh) = addMailboxGet(b1, accountId, ids = Opt.some(idsR))
  (b2, MailboxChangesGetHandles(changes: ch, get: gh))

# =============================================================================
# getBoth — paired response extraction
# =============================================================================

func getBoth*[T](
    dr: DispatchedResponse, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], JmapError] =
  ## Extracts both query and get responses. Composes with the ``?`` operator:
  ## ``let results = ?dr.getBoth(handles)``. The rail carries only dispatch
  ## faults (misuse / protocol); a server method error rides each field as a
  ## ``MethodOutcome``. Resolution uses each handle's stored parser closure.
  let qr = ?dr.get(handles.query)
  let gr = ?dr.get(handles.get)
  ok(QueryGetResults[T](query: qr, get: gr))

func getBoth*[T](
    dr: DispatchedResponse, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], JmapError] =
  ## Extracts both changes and get responses (method errors as data per field;
  ## the rail carries only dispatch faults). Resolution uses each handle's
  ## stored parser closure.
  let cr = ?dr.get(handles.changes)
  let gr = ?dr.get(handles.get)
  ok(ChangesGetResults[T](changes: cr, get: gr))

func getBoth*(
    dr: DispatchedResponse, handles: MailboxChangesGetHandles
): Result[MailboxChangesGetResults, JmapError] =
  ## Extracts both the Mailbox/changes and Mailbox/get responses (method errors
  ## as data per field; the rail carries only dispatch faults).
  let cr = ?dr.get(handles.changes)
  let gr = ?dr.get(handles.get)
  ok(MailboxChangesGetResults(changes: cr, get: gr))
