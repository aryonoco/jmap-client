# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

## RFC 8887 WebSocket reservation. ``WebSocketChannel`` is a
## distinct type from ``PushChannel``: WebSocket is a different
## transport (a bidirectional connection upgraded from HTTPS),
## not a Push variant; conflating them is the libdbus-style
## retrofit failure mode. The TYPE is re-exported from
## ``jmap_client``; the *module path* is not public (P5).
##
## See ``docs/TODO/pre-1.0-api-alignment.md`` items A10 and A24.

{.push ruleOff: "objects".}

type WebSocketChannel* = ref object
  ## Reserved handle for RFC 8887 JMAP-over-WebSocket. Empty
  ## stub today; fields and methods are added additively when
  ## WebSocket is implemented. Sealed Pattern-A handle: future
  ## fields stay private.

{.pop.}
