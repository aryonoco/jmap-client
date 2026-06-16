# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions for EmailSubmission (RFC 8621 §7). Mirrors
## the F1 pattern in ``mail_builders.nim``: per-verb builders thin-wrap
## the generic ``addGet`` / ``addChanges`` / ``addQuery`` /
## ``addQueryChanges``, and the single total ``addEmailSubmissionSet``
## projects a pre-validated ``EmailSubmissionSetSpec`` onto the RFC 8621
## §7.5 wire shape — the RFC 8620 §5.3 onSuccess-to-create cross-reference
## was proven at spec construction, so the builder is total.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types
import ../types/validation
import ../serialisation/serde_diagnostics
import ../serialisation/serde_errors
import ../serialisation/serde_field_echo
import ../serialisation/serde_framework
import ../serialisation/serde_helpers
import ../serialisation/serde_primitives
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ../protocol/call_meta
import ./email_submission
import ./email
import ./mail_entities
import ./serde_email_submission

# =============================================================================
# addEmailSubmissionGet — EmailSubmission/get (RFC 8621 §7.1)
# =============================================================================

func addEmailSubmissionGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[GetResponse[AnyEmailSubmission]]) =
  ## Full-record EmailSubmission/get (RFC 8621 §7.1). Returns the existential
  ## wrapper ``AnyEmailSubmission`` — phantom-indexed branches resolve at the
  ## serde boundary (Design §4.2). For a typed property projection, use
  ## ``addPartialEmailSubmissionGet`` (A3.6).
  addGet[AnyEmailSubmission](b, accountId, ids)

func addPartialEmailSubmissionGet*(
    b: sink RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: NonEmptySeq[EmailSubmissionGetProperty],
): (RequestBuilder, ResponseHandle[GetResponse[PartialEmailSubmission]]) =
  ## Sparse EmailSubmission/get returning typed ``PartialEmailSubmission``
  ## (RFC 8621 §7.1 + A3.6).
  addGetSelected[PartialEmailSubmission, EmailSubmissionGetProperty](
    b, accountId, ids, properties
  )

# =============================================================================
# addEmailSubmissionChanges — EmailSubmission/changes (RFC 8621 §7.2)
# =============================================================================

func addEmailSubmissionChanges*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse[AnyEmailSubmission]]) =
  ## EmailSubmission/changes (RFC 8621 §7.2).
  addChanges[AnyEmailSubmission](b, accountId, sinceState, maxChanges)

# =============================================================================
# addEmailSubmissionQuery — EmailSubmission/query (RFC 8621 §7.3)
# =============================================================================

func addEmailSubmissionQuery*(
    b: sink RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryResponse[AnyEmailSubmission]]) =
  ## EmailSubmission/query (RFC 8621 §7.3). No extension args.
  addQuery[
    AnyEmailSubmission, EmailSubmissionFilterCondition, EmailSubmissionComparator
  ](b, accountId, filter, sort, queryParams)

# =============================================================================
# addEmailSubmissionQueryChanges — EmailSubmission/queryChanges (RFC 8621 §7.4)
# =============================================================================

func addEmailSubmissionQueryChanges*(
    b: sink RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): (RequestBuilder, ResponseHandle[QueryChangesResponse[AnyEmailSubmission]]) =
  ## EmailSubmission/queryChanges (RFC 8621 §7.4).
  addQueryChanges[
    AnyEmailSubmission, EmailSubmissionFilterCondition, EmailSubmissionComparator
  ](b, accountId, sinceQueryState, filter, sort, maxChanges, upToId, calculateTotal)

# =============================================================================
# addEmailSubmissionSet — EmailSubmission/set (RFC 8621 §7.5) + implicit
# Email/set (RFC 8621 §7.5 ¶3, RFC 8620 §5.4)
# =============================================================================

func addEmailSubmissionSet*(
    b: sink RequestBuilder, accountId: AccountId, spec: EmailSubmissionSetSpec
): (RequestBuilder, EmailSubmissionHandles) =
  ## EmailSubmission/set (RFC 8621 §7.5). The implicit Email/set the server runs
  ## after the submission (§7.5 ¶3) is surfaced through ``handles.implicit`` —
  ## an outcome when the spec's onSuccess* drove a change, ``Opt.none`` at
  ## extraction otherwise. Total: the spec proved the RFC 8620 §5.3
  ## cross-reference at construction.
  let req = SetRequest[
    AnyEmailSubmission, EmailSubmissionBlueprint, NonEmptyEmailSubmissionUpdates
  ](
    accountId: accountId,
    ifInState: spec.ifInState,
    create: spec.create,
    update: spec.update,
    destroy: spec.destroy,
  )
  var args = req.toJson()
  for v in spec.onSuccessUpdateEmail:
    args["onSuccessUpdateEmail"] = v.toJson()
  for v in spec.onSuccessDestroyEmail:
    args["onSuccessDestroyEmail"] = v.toJson()
  let (b1, callId) = addInvocation(
    b,
    mnEmailSubmissionSet,
    args,
    capabilityUri(AnyEmailSubmission),
    setMeta(spec.create, spec.update, spec.destroy),
  )
  let brand = b1.builderId
  # RFC 8621 §7.5 ¶3: the server runs the implicit Email/set only when the
  # request carried an onSuccess* extension. The implicit handle is present
  # iff one was requested, so a simple submission yields a ``none`` implicit
  # and ``getBoth`` stays total over its absence (RFC 8620 §5.4).
  let implicitRequested =
    spec.onSuccessUpdateEmail.isSome or spec.onSuccessDestroyEmail.isSome
  let implicit =
    if implicitRequested:
      Opt.some(
        initNameBoundHandle[SetResponse[EmailCreatedItem, PartialEmail]](
          callId, mnEmailSet, brand
        )
      )
    else:
      Opt.none(NameBoundHandle[SetResponse[EmailCreatedItem, PartialEmail]])
  let handles = EmailSubmissionHandles(
    primary: initResponseHandle[EmailSubmissionSetResponse](callId, brand),
    implicit: implicit,
  )
  (b1, handles)
