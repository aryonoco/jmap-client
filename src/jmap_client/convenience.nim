# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Pipeline combinators for common JMAP multi-method patterns.
##
## This module is **NOT** re-exported by ``protocol.nim``. Users who want
## pipeline combinators must explicitly ``import jmap_client/convenience``.
## This physical separation (recommended by the OpenSSL/libgit2 analysis)
## keeps the core API surface in ``builder.nim`` and ``dispatch.nim`` frozen
## while providing opt-in ergonomics.
##
## **Naming convention.** Pipeline combinators use the ``add*`` prefix because
## they mutate the ``RequestBuilder`` (following the builder naming convention).
## Paired extraction uses ``getBoth`` (always exactly two handles).
##
## **Implicit decisions.** Each combinator documents the choices it makes
## internally (reference paths, same-account assumption, etc.). For full
## control, use the individual ``addQuery``/``addGet``/``addChanges`` functions
## from the core API.

{.push raises: [].}

import ./types
import ./methods
import ./dispatch
import ./builder

# =============================================================================
# QueryGetHandles — paired handles from addQueryThenGet
# =============================================================================

type QueryGetHandles*[T] = object
  ## Paired phantom-typed handles from a query-then-get pipeline.
  ## Both handles retain full compile-time type safety.
  query*: ResponseHandle[QueryResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

# =============================================================================
# addQueryThenGet — the most common JMAP pipeline
# =============================================================================

template addQueryThenGet*[T](
    b: var RequestBuilder, accountId: AccountId
): QueryGetHandles[T] =
  ## Adds Foo/query + Foo/get with automatic result reference wiring.
  ## The get's ``ids`` parameter references the query's ``/ids`` path.
  ## Resolves filter type and serialisation callback via template expansion.
  ##
  ## **Implicit decisions:**
  ## - Reference path is always ``/ids`` (RefPathIds)
  ## - Both calls use the same ``accountId`` (no cross-account)
  ## - No filter, sort, or properties constraints applied
  ## - Response method name derived from ``methodNamespace(T)``
  ##
  ## For queries with filters, use the core API directly:
  ## ``addQuery[T, C]`` + ``idsRef`` + ``addGet[T]``.
  block:
    let qh = addQuery[T](b, accountId)
    let gh = addGet[T](b, accountId, ids = Opt.some(qh.idsRef()))
    QueryGetHandles[T](query: qh, get: gh)

# =============================================================================
# ChangesGetHandles — paired handles from addChangesToGet
# =============================================================================

type ChangesGetHandles*[T] = object
  ## Paired phantom-typed handles from a changes-then-get pipeline.
  changes*: ResponseHandle[ChangesResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

# =============================================================================
# addChangesToGet — sync pattern
# =============================================================================

func addChangesToGet*[T](
    b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): ChangesGetHandles[T] =
  ## Adds Foo/changes + Foo/get with automatic result reference from
  ## ``/created``. The get fetches newly created records identified by
  ## the changes response.
  ##
  ## **Implicit decisions:**
  ## - Reference path is ``/created`` (RefPathCreated) — only newly created
  ##   IDs are fetched. For updated IDs, use the core API with ``updatedRef``.
  ## - Both calls use the same ``accountId``
  let ch = addChanges[T](b, accountId, sinceState, maxChanges)
  let gh =
    addGet[T](b, accountId, ids = Opt.some(ch.createdRef()), properties = properties)
  ChangesGetHandles[T](changes: ch, get: gh)

# =============================================================================
# getBoth — paired response extraction
# =============================================================================

type QueryGetResults*[T] = object
  ## Paired extraction results from a query-then-get pipeline.
  query*: QueryResponse[T]
  get*: GetResponse[T]

proc getBoth*[T](
    resp: Response, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], MethodError] =
  ## Extracts both query and get responses, failing on the first error.
  ## Composes naturally with the ``?`` operator:
  ## ``let results = resp.getBoth(handles).?``
  mixin fromJson
  let qr = ?resp.get(handles.query)
  let gr = ?resp.get(handles.get)
  ok(QueryGetResults[T](query: qr, get: gr))

type ChangesGetResults*[T] = object
  ## Paired extraction results from a changes-then-get pipeline.
  changes*: ChangesResponse[T]
  get*: GetResponse[T]

proc getBoth*[T](
    resp: Response, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], MethodError] =
  ## Extracts both changes and get responses, failing on the first error.
  mixin fromJson
  let cr = ?resp.get(handles.changes)
  let gr = ?resp.get(handles.get)
  ok(ChangesGetResults[T](changes: cr, get: gr))
