# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Per-call limit metadata threaded through ``RequestBuilder`` so that
## L4 transport-layer limit enforcement (internal validation inside
## ``client.send``) can read typed counts from a typed source instead
## of walking ``Invocation.arguments`` JsonNode keys. Internal-only:
## never re-exported through the hub. ``src/jmap_client/protocol.nim``
## excludes the ``callLimits`` accessor; ``CallLimitMeta`` is reachable
## only via direct import of this module.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables

import results

import ../../types
import ../types/validation

type
  CallLimitMetaKind* = enum
    ## Discriminator for the per-call limit metadata variant. Each
    ## ``add*`` builder selects the appropriate kind from the typed
    ## inputs; internal validation inside ``client.send`` dispatches
    ## per-call enforcement from this discriminator.
    clmGet ## /get-class call subject to ``maxObjectsInGet``.
    clmSet ## /set-class call subject to ``maxObjectsInSet``.
    clmOther
      ## Query, changes, echo, parse, import, etc. — no per-call
      ## object-count limit applies.

  CallLimitMeta* {.ruleOff: "objects".} = object
    ## Per-call limit metadata accumulated parallel to invocations on
    ## ``RequestBuilder``. Carries typed counts derived from the
    ## builder's typed inputs so the L4 limit enforcement inside
    ## ``client.send`` never has to walk ``Invocation.arguments``
    ## JsonNode keys (P19).
    case kind*: CallLimitMetaKind
    of clmGet:
      idCount*: Opt[int]
        ## Number of direct ids; ``Opt.none(int)`` if the ids parameter
        ## is reference-resolved (count unknown until the server
        ## resolves the back-reference).
    of clmSet:
      objectCount*: Opt[int]
        ## Sum of direct create + update + destroy entries;
        ## ``Opt.none(int)`` if the destroy parameter is reference-
        ## resolved.
    of clmOther:
      discard

func lenOr0[T](opt: Opt[T]): int =
  ## Folds ``Opt[T]`` into the underlying length: ``None`` → 0,
  ## ``Some(x)`` → ``x.len``. ``mixin len`` resolves ``T.len`` at
  ## instantiation (``Table.len``, ``NonEmpty*Updates.len``, etc.).
  mixin len
  for x in opt:
    return x.len
  0

func getMeta*(ids: Opt[Referencable[seq[Id]]]): CallLimitMeta =
  ## Builds ``CallLimitMeta(kind: clmGet, ...)`` from a typed
  ## ``Opt[Referencable[seq[Id]]]``. ``Opt.none`` → idCount=Opt.some(0)
  ## (no ids supplied); ``rkDirect`` → idCount=Opt.some(seq.len);
  ## ``rkReference`` → idCount=Opt.none(int) (count unknown until the
  ## server resolves the back-reference).
  let r = ids.valueOr:
    return CallLimitMeta(kind: clmGet, idCount: Opt.some(0))
  case r.kind
  of rkDirect:
    CallLimitMeta(kind: clmGet, idCount: Opt.some(r.value.len))
  of rkReference:
    CallLimitMeta(kind: clmGet, idCount: Opt.none(int))

func setMeta*[C, U](
    create: Opt[Table[CreationId, C]],
    update: Opt[U],
    destroy: Opt[Referencable[seq[Id]]],
): CallLimitMeta =
  ## Builds ``CallLimitMeta(kind: clmSet, ...)`` from the typed
  ## create/update/destroy triple. Sums direct counts; switches to
  ## ``Opt.none(int)`` when the destroy rail carries a ``rkReference``.
  ## ``mixin len`` resolves ``U.len`` at instantiation (see
  ## ``NonEmptyMailboxUpdates``, ``NonEmptyEmailUpdates``,
  ## ``NonEmptyEmailSubmissionUpdates`` — each defines ``len``).
  mixin len
  let directCreateUpdate = lenOr0(create) + lenOr0(update)
  let r = destroy.valueOr:
    return CallLimitMeta(kind: clmSet, objectCount: Opt.some(directCreateUpdate))
  case r.kind
  of rkDirect:
    CallLimitMeta(kind: clmSet, objectCount: Opt.some(directCreateUpdate + r.value.len))
  of rkReference:
    CallLimitMeta(kind: clmSet, objectCount: Opt.none(int))

{.pop.}
