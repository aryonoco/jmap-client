# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

## RFC 8620 §7 Push reservation. The ``PushChannel`` type is
## named pre-1.0 so future Push integration lands additively as
## methods on ``PushChannel`` (P20, P23), never as methods on
## ``JmapClient`` (the libdbus retrofit failure that P23 exists
## to prevent). The TYPE is re-exported from ``jmap_client``;
## the *module path* is not public (P5 minimum surface). If a
## public path earns its keep later (e.g. ``jmap_client/push``),
## that is a minor bump per P20; naming the type now is the
## pre-1.0 commitment.
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` items A10 and A23.

{.push ruleOff: "objects".}

type PushChannel* = ref object
  ## Reserved handle for HTTP push notifications (RFC 8620 §7).
  ## Empty stub today; fields and methods are added additively
  ## when Push is implemented. Sealed Pattern-A handle: future
  ## fields stay private; the public API reaches them through
  ## methods.

{.pop.}
