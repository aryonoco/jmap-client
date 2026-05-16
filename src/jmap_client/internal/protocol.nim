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
import ./serialisation/serde_envelope_emit

export entity
export methods except
  SerializedSort, SerializedFilter, toJsonNode, serializeOptSort, serializeOptFilter,
  serializeFilter, assembleQueryArgs, assembleQueryChangesArgs
export dispatch except
  initResponseHandle, initNameBoundHandle, initDispatchedResponse, response, builderId
export builder except
  addInvocation, callLimits, addGet, addChanges, addSet, addCopy, addQuery,
  addQueryChanges, initRequestBuilder, request, builderId, builtRequestFromParts
# `Invocation` / `Request` / `Response` / `ResultReference` toJson are
# user-facing — application developers use `inv.toJson` for diagnostic
# inspection (A2) and `req.toJson` / `resp.toJson` for batch logging.
# The parse half (`*.fromJson`, `referencableKey`, `fromJsonField`)
# stays hub-private per P19 ("the reverse direction is not").
export serde_envelope_emit
