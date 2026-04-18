# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions for EmailSubmission (RFC 8621 §7). Mirrors
## the F1 pattern in ``mail_builders.nim``: per-verb builders thin-wrap
## the generic ``addGet`` / ``addChanges`` / ``addQuery`` /
## ``addQueryChanges``, and ``addEmailSubmissionSet`` adapts the typed
## ``NonEmptyEmailSubmissionUpdates`` container to the RFC 8620 §5.3
## wire shape. ``getBoth`` lives here because ``mixin fromJson`` is
## a no-op inside a non-generic body — the enclosing module must have
## ``EmailSubmissionCreatedItem.fromJson`` and ``EmailCreatedItem.fromJson``
## in scope at definition time, which is why the two serde modules are
## re-exported below.

{.push raises: [], noSideEffect.}

import std/json
import std/tables

import ../types
import ../serialisation
import ../methods
import ../dispatch
import ../builder
import ./email_submission
import ./mail_entities
import ./serde_email_submission
import ./serde_email

export serde_email_submission
export serde_email

const SubmissionCapUri = "urn:ietf:params:jmap:submission"

# =============================================================================
# addEmailSubmissionGet — EmailSubmission/get (RFC 8621 §7.1)
# =============================================================================

func addEmailSubmissionGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[AnyEmailSubmission]]) =
  ## EmailSubmission/get (RFC 8621 §7.1). Returns the existential wrapper
  ## ``AnyEmailSubmission`` — phantom-indexed branches resolve at the serde
  ## boundary (Design §4.2).
  addGet[AnyEmailSubmission](b, accountId, ids, properties)

# =============================================================================
# addEmailSubmissionChanges — EmailSubmission/changes (RFC 8621 §7.2)
# =============================================================================

func addEmailSubmissionChanges*(
    b: RequestBuilder,
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
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[EmailSubmissionFilterCondition]] =
      Opt.none(Filter[EmailSubmissionFilterCondition]),
    sort: Opt[seq[EmailSubmissionComparator]] = Opt.none(seq[EmailSubmissionComparator]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryResponse[AnyEmailSubmission]]) =
  ## EmailSubmission/query (RFC 8621 §7.3). No extension args.
  addQuery[
    AnyEmailSubmission, EmailSubmissionFilterCondition, EmailSubmissionComparator
  ](b, accountId, toJson, filter, sort, queryParams)

# =============================================================================
# addEmailSubmissionQueryChanges — EmailSubmission/queryChanges (RFC 8621 §7.4)
# =============================================================================

func addEmailSubmissionQueryChanges*(
    b: RequestBuilder,
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
  ](
    b, accountId, sinceQueryState, toJson, filter, sort, maxChanges, upToId,
    calculateTotal,
  )

# =============================================================================
# addEmailSubmissionSet — EmailSubmission/set (RFC 8621 §7.5) — simple overload
# =============================================================================

func addEmailSubmissionSet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] =
      Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    update: Opt[NonEmptyEmailSubmissionUpdates] =
      Opt.none(NonEmptyEmailSubmissionUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[EmailSubmissionSetResponse]) =
  ## EmailSubmission/set (RFC 8621 §7.5). Simple overload — no
  ## ``onSuccessUpdateEmail`` / ``onSuccessDestroyEmail`` extensions; for
  ## those, use ``addEmailSubmissionAndEmailSet``.
  let jsonCreate = block:
    var res = Opt.none(Table[CreationId, JsonNode])
    for createMap in create:
      var tbl = initTable[CreationId, JsonNode](createMap.len)
      for k, v in createMap:
        tbl[k] = v.toJson()
      res = Opt.some(tbl)
    res
  let req = SetRequest[AnyEmailSubmission](
    accountId: accountId, ifInState: ifInState, create: jsonCreate, destroy: destroy
  )
  var args = req.toJson()
  for updateSet in update:
    args["update"] = updateSet.toJson()
  let (newBuilder, callId) =
    b.addInvocation(mnEmailSubmissionSet, args, SubmissionCapUri)
  (newBuilder, ResponseHandle[EmailSubmissionSetResponse](callId))

# =============================================================================
# getBoth — paired extraction for EmailSubmissionHandles
# =============================================================================

func getBoth*(
    resp: Response, handles: EmailSubmissionHandles
): Result[EmailSubmissionResults, MethodError] =
  ## Extract both the EmailSubmission/set response and the implicit
  ## Email/set triggered by ``onSuccessUpdateEmail`` /
  ## ``onSuccessDestroyEmail`` (RFC 8620 §5.4 sibling-invocation
  ## semantics). ``handles.submission`` resolves through the default
  ## ``get[T]`` overload; ``handles.emailSet`` resolves through the
  ## ``NameBoundHandle`` overload which applies the ``mnEmailSet``
  ## method-name filter.
  mixin fromJson
  let submission = ?resp.get(handles.submission)
  let emailSet = ?resp.get(handles.emailSet)
  return ok(EmailSubmissionResults(submission: submission, emailSet: emailSet))
