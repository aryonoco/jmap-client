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
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../../types
import ../../serialisation
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ../protocol/call_meta
import ./email_submission
import ./email
import ./mail_entities
import ./serde_email_submission
import ./serde_email

export serde_email_submission
export serde_email

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
  ](b, accountId, filter, sort, queryParams)

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
  ](b, accountId, sinceQueryState, filter, sort, maxChanges, upToId, calculateTotal)

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
  ## those, use ``addEmailSubmissionAndEmailSet``. Thin wrapper over
  ## ``addSet[AnyEmailSubmission, EmailSubmissionBlueprint,
  ## NonEmptyEmailSubmissionUpdates, EmailSubmissionSetResponse]``.
  addSet[
    AnyEmailSubmission, EmailSubmissionBlueprint, NonEmptyEmailSubmissionUpdates,
    EmailSubmissionSetResponse,
  ](b, accountId, ifInState, create, update, destroy)

# =============================================================================
# addEmailSubmissionAndEmailSet — compound EmailSubmission/set + implicit
# Email/set (RFC 8621 §7.5 ¶3, Design §9.1)
# =============================================================================

func addEmailSubmissionAndEmailSet*(
    b: RequestBuilder,
    accountId: AccountId,
    create: Opt[Table[CreationId, EmailSubmissionBlueprint]] =
      Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    update: Opt[NonEmptyEmailSubmissionUpdates] =
      Opt.none(NonEmptyEmailSubmissionUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    onSuccessUpdateEmail: Opt[NonEmptyOnSuccessUpdateEmail] =
      Opt.none(NonEmptyOnSuccessUpdateEmail),
    onSuccessDestroyEmail: Opt[NonEmptyOnSuccessDestroyEmail] =
      Opt.none(NonEmptyOnSuccessDestroyEmail),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, EmailSubmissionHandles) =
  ## Compound EmailSubmission/set with implicit Email/set on success
  ## (RFC 8621 §7.5 ¶3, Design §9.1). Single wire invocation; the server
  ## emits the implicit Email/set response sharing the parent call ID
  ## (RFC 8620 §5.4). ``handles.implicit`` carries the ``mnEmailSet``
  ## filter so ``getBoth`` can disambiguate without a call-site argument.
  ## The two compound extras (``onSuccessUpdateEmail`` and
  ## ``onSuccessDestroyEmail``) arrive as ``NonEmpty*`` wrappers — empty
  ## and duplicate-key shapes are unrepresentable at the type level, so
  ## ``Opt.none`` is the sole "no extras" encoding.
  let req = SetRequest[
    AnyEmailSubmission, EmailSubmissionBlueprint, NonEmptyEmailSubmissionUpdates
  ](
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    update: update,
    destroy: destroy,
  )
  var args = req.toJson()
  for v in onSuccessUpdateEmail:
    args["onSuccessUpdateEmail"] = v.toJson()
  for v in onSuccessDestroyEmail:
    args["onSuccessDestroyEmail"] = v.toJson()
  let (b1, callId) = addInvocation(
    b,
    mnEmailSubmissionSet,
    args,
    capabilityUri(AnyEmailSubmission),
    setMeta(create, update, destroy),
  )
  let handles = EmailSubmissionHandles(
    primary: ResponseHandle[EmailSubmissionSetResponse](callId),
    implicit: NameBoundHandle[SetResponse[EmailCreatedItem, PartialEmail]](
      callId: callId, methodName: mnEmailSet
    ),
  )
  (b1, handles)
