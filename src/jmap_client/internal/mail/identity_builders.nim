# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Builder functions for Identity (RFC 8621 §6). Thin wrappers over the
## generic ``addGet`` / ``addChanges`` / ``addSet``;
## ``SetResponse[IdentityCreatedItem]`` carries typed ``createResults`` via
## ``mixin``-resolved ``IdentityCreatedItem.fromJson`` at the dispatch site
## (RFC 8620 §5.3 server-set subset, contrast ``Identity`` returned by
## ``Identity/get``). The L2 serde modules are re-exported so consumers who
## import ``identity_builders`` get the update-algebra ``toJson`` overloads
## in scope automatically.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables

import ../../types
import ../../serialisation
import ../protocol/methods
import ../protocol/dispatch
import ../protocol/builder
import ./identity
import ./mail_entities
import ./serde_identity
import ./serde_identity_update

export serde_identity
export serde_identity_update

# =============================================================================
# addIdentityGet — Identity/get (RFC 8621 §6.1)
# =============================================================================

func addIdentityGet*(
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[Identity]]) =
  ## Identity/get (RFC 8621 §6.1). Thin wrapper over ``addGet[Identity]``.
  addGet[Identity](b, accountId, ids, properties)

# =============================================================================
# addIdentityChanges — Identity/changes (RFC 8621 §6.2)
# =============================================================================

func addIdentityChanges*(
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse[Identity]]) =
  ## Identity/changes (RFC 8621 §6.2). Thin wrapper over
  ## ``addChanges[Identity]``.
  addChanges[Identity](b, accountId, sinceState, maxChanges)

# =============================================================================
# addIdentitySet — Identity/set (RFC 8621 §6.3)
# =============================================================================

func addIdentitySet*(
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, IdentityCreate]] =
      Opt.none(Table[CreationId, IdentityCreate]),
    update: Opt[NonEmptyIdentityUpdates] = Opt.none(NonEmptyIdentityUpdates),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[IdentityCreatedItem]]) =
  ## Identity/set (RFC 8621 §6.3). Thin wrapper over
  ## ``addSet[Identity, IdentityCreate, NonEmptyIdentityUpdates,
  ## SetResponse[IdentityCreatedItem]]`` with no entity-specific extras.
  ## ``createResults`` is keyed by ``CreationId`` and carries
  ## ``IdentityCreatedItem`` (``id`` plus the optional server-set
  ## ``mayDelete``), not full ``Identity`` records — the wire payload is
  ## the server-set subset per RFC 8620 §5.3. Destroying an Identity whose
  ## ``mayDelete`` is false surfaces as a per-id ``SetError`` inside
  ## ``destroyResults`` — no client-side pre-check.
  addSet[
    Identity, IdentityCreate, NonEmptyIdentityUpdates, SetResponse[IdentityCreatedItem]
  ](b, accountId, ifInState, create, update, destroy)
