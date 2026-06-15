# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Public hub for the JMAP protocol layer (RFC 8620 §5–§6). This is
## the sole channel through which protocol-layer symbols flow to user
## code via ``import jmap_client``.
##
## **Audit mechanism (A1b).** Each ``export <module>`` re-exports the
## module's full ``*`` surface, with an ``except`` clause filtering
## out the helpers that retain ``*`` for cross-internal sibling
## access (``serializeOptFilter`` etc. in ``methods.nim``,
## ``addInvocation`` in ``builder.nim``). The paired compile-only
## audit at ``tests/compile/tcompile_a1b_protocol_hub_surface.nim``
## asserts presence and absence of every public-surface symbol,
## locking the user-facing commitment at compile time.
##
## See ``docs/design/14-Nim-API-Principles.md`` for the principles
## upheld by this hub: P5 (single public layer; internals are
## internal), P7 (watch the wrap rate), P15 (smart constructors
## return ``Result``; raw constructors private), P19 (schema-driven
## types; no stringly-typed escape hatches), P20 (additive variants
## over new module-level entry points), P2 (stability is bought with
## tests).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./protocol/entity
import ./protocol/methods
import ./protocol/dispatch
import ./protocol/builder
import ./protocol/jmap_error
import ./protocol/preflight

export jmap_error except
  jmapMisuse, jmapProtocol, misuse, protocolMissingCall, protocolMalformedError,
  protocolDecode, methodValue, methodFailure
export preflight
export entity
export methods except
  SerializedSort, SerializedFilter, toJsonNode, serializeOptSort, serializeOptFilter,
  serializeFilter, assembleQueryArgs, assembleQueryChangesArgs
export dispatch except
  initResponseHandle, initNameBoundHandle, initDispatchedResponse, response, builderId
export builder except
  addInvocation, callLimits, addGet, addGetSelected, addChanges, addSet, addCopy,
  addQuery, addQueryChanges, initRequestBuilder, request, builderId,
  builtRequestFromParts
# Envelope serde is hub-private after A16. The single public send-side
# wire diagnostic is ``BuiltRequest.toJson`` (re-exported via the
# ``export builder`` line above; ``toJson`` is not in that line's
# ``except`` filter). For bytes that actually crossed the wire,
# application code uses ``setDebugCallback`` on the ``JmapClient``
# (A31). See A16 in docs/TODO/pre-1.0-api-alignment.md and §1.7 of
# docs/design/04-layer-4-design.md.
