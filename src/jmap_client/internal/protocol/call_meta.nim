# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Per-call limit metadata threaded through ``RequestBuilder`` so that
## L4 transport-layer limit enforcement (``client.validateLimits``) can
## read typed counts from a typed source instead of walking
## ``Invocation.arguments`` JsonNode keys. Internal-only: never
## re-exported through the hub. ``src/jmap_client/protocol.nim``
## excludes the ``callLimits`` accessor; ``CallLimitMeta`` is
## reachable only via direct import of this module.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import results

import ../types/validation

type
  CallLimitMetaKind* = enum
    ## Discriminator for the per-call limit metadata variant. Each
    ## ``add*`` builder selects the appropriate kind from the typed
    ## inputs; ``client.validateLimits`` dispatches per-call enforcement
    ## from this discriminator.
    clmGet ## /get-class call subject to ``maxObjectsInGet``.
    clmSet ## /set-class call subject to ``maxObjectsInSet``.
    clmOther
      ## Query, changes, echo, parse, import, etc. — no per-call
      ## object-count limit applies.

  CallLimitMeta* {.ruleOff: "objects".} = object
    ## Per-call limit metadata accumulated parallel to invocations on
    ## ``RequestBuilder``. Carries typed counts derived from the
    ## builder's typed inputs so the L4 ``validateLimits`` enforcement
    ## never has to walk ``Invocation.arguments`` JsonNode keys (P19).
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

{.pop.}
