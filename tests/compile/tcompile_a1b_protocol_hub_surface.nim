# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the protocol hub's public surface (A1b).
## A compile failure here is the canonical signal that the hub's
## ``export`` list has drifted from the agreed contract — symbols
## have been added or removed without updating this file.
##
## The audit asserts BOTH presence (must be reachable through
## ``import jmap_client``) and absence (must NOT be reachable). This
## locks the public commitment to application developers — see
## ``docs/design/14-Nim-API-Principles.md`` P2, P5.

import std/json

import jmap_client

static:
  # =========================================================================
  # POSITIVE — must be reachable through `import jmap_client`
  # =========================================================================

  # entity.nim — registration templates
  doAssert declared(registerJmapEntity)
  doAssert declared(registerQueryableEntity)
  doAssert declared(registerSettableEntity)
  doAssert declared(registerExtractableEntity)

  # methods.nim — request types
  doAssert declared(GetRequest)
  doAssert declared(ChangesRequest)
  doAssert declared(SetRequest)
  doAssert declared(CopyRequest)
  # methods.nim — response types
  doAssert declared(GetResponse)
  doAssert declared(ChangesResponse)
  doAssert declared(SetResponse)
  doAssert declared(CopyResponse)
  doAssert declared(QueryResponse)
  doAssert declared(QueryChangesResponse)
  # methods.nim — copy disposition
  doAssert declared(CopyDestroyModeKind)
  doAssert declared(CopyDestroyMode)
  doAssert declared(keepOriginals)
  doAssert declared(destroyAfterSuccess)
  # methods.nim — serde
  doAssert declared(toJson)
  doAssert declared(fromJson)

  # dispatch.nim — handle types
  doAssert declared(ResponseHandle)
  doAssert declared(NameBoundHandle)
  doAssert declared(CompoundHandles)
  doAssert declared(CompoundResults)
  # dispatch.nim — extraction
  doAssert declared(callId)
  doAssert declared(get)
  doAssert declared(getBoth)
  # dispatch.nim — reference construction
  doAssert declared(reference)
  # dispatch.nim — registration
  doAssert declared(registerCompoundMethod)

  # builder.nim — type only (initRequestBuilder is hub-private under A6)
  doAssert declared(RequestBuilder)
  # builder.nim — accessors
  doAssert declared(methodCallCount)
  doAssert declared(isEmpty)
  doAssert declared(capabilities)
  # builder.nim — freeze + BuiltRequest (A6 lifecycle types)
  doAssert declared(freeze)
  doAssert declared(BuiltRequest)
  # builder.nim — public add* family (A5: per-entity wrappers + P19 escapes)
  doAssert declared(addEcho)
  doAssert declared(addCapabilityInvocation)
  # builder.nim — argument helpers
  doAssert declared(directIds)
  # dispatch.nim / identifiers.nim / errors.nim — A6 surface.
  # Note: the internal-only arm constructors (``jmapMisuse`` / ``jmapProtocol``
  # / the ``MethodOutcome`` producers) are filtered out of the hub by A12; the
  # negative assertions live further below. The single ``JmapError`` rail ADT
  # and the ``MethodOutcome`` data type remain publicly visible so callers can
  # ``case err.kind`` and pattern-match a method outcome.
  doAssert declared(BuilderId)
  doAssert declared(DispatchedResponse)
  doAssert declared(JmapError)
  doAssert declared(JmapErrorKind)
  doAssert declared(MethodOutcome)
  doAssert declared(MethodOutcomeKind)
  doAssert declared(fulfil)
  doAssert declared(SessionFault)
  doAssert declared(Misuse)
  doAssert declared(ProtocolFault)
  doAssert declared(MethodFault)
  # identifiers.nim — BuilderId accessors stay public
  doAssert declared(clientBrand)
  doAssert declared(serial)
  # dispatch.nim — DispatchedResponse hub-public accessors
  doAssert declared(sessionState)
  doAssert declared(createdIds)
  # client.nim — newBuilder is the single blessed entry point
  doAssert declared(newBuilder)

  # A16: wire-shape diagnostic on the sealed handle reaches the hub.
  # ``BuiltRequest`` itself is already asserted declared above. Use a
  # proc-literal so the by-value parameter binding does not trip
  # ``=copy {.error.}`` at the use site.
  doAssert compiles(
    (
      proc(br: BuiltRequest): JsonNode =
        br.toJson()
    )
  )

  # A30b: the Request / Response / Invocation / ResultReference wire types are
  # hub-internal (supersedes A28/A30's "sealed Pattern-A but hub-public read
  # accessors" stance). Apps build requests via ``RequestBuilder`` and read
  # typed responses via ``DispatchedResponse`` (whose ``sessionState`` /
  # ``createdIds`` accessors are asserted reachable above); they never touch a
  # raw envelope value.
  doAssert not declared(Request)
  doAssert not declared(Response)
  doAssert not declared(Invocation)
  doAssert not declared(ResultReference)

  # A31: per-handle debug callback reaches the hub.
  doAssert declared(WireDirection)
  doAssert declared(DebugCallback)
  doAssert declared(wdSend)
  doAssert declared(wdReceive)
  doAssert declared(setDebugCallback)

  # =========================================================================
  # NEGATIVE — must NOT be reachable through `import jmap_client`
  # =========================================================================

  # methods.nim — `*`-stripped (truly module-private)
  doAssert not declared(optState)
  doAssert not declared(optUnsignedInt)
  doAssert not declared(mergeCreateResults)
  # dispatch.nim — `*`-stripped (truly module-private)
  doAssert not declared(serdeToMethodError)

  # dispatch.nim — generic mixin reference helpers retired; the public
  # back-reference surface is `reference` plus the per-entity combinators
  # folded onto the hub (internal/mail/combinators)
  doAssert not declared(idsRef)
  doAssert not declared(listIdsRef)
  doAssert not declared(addedIdsRef)
  doAssert not declared(createdRef)
  doAssert not declared(updatedRef)

  # methods.nim — retain `*` for cross-internal use, hub-private
  doAssert not declared(serializeOptSort)
  doAssert not declared(serializeOptFilter)
  doAssert not declared(serializeFilter)
  doAssert not declared(assembleQueryArgs)
  doAssert not declared(assembleQueryChangesArgs)
  doAssert not declared(SerializedSort)
  doAssert not declared(SerializedFilter)
  doAssert not declared(toJsonNode)
  # builder.nim — retain `*` for cross-internal use, hub-private
  doAssert not declared(addInvocation)
  # builder.nim — A15: initCreates removed (no demote; full delete)
  doAssert not declared(initCreates)
  # builder.nim — A5: generic builders hub-private
  doAssert not declared(addGet)
  # builder.nim — A3.6: typed-projection generic builder hub-private
  # (exposed only via the per-entity `addPartial<E>Get` wrappers)
  doAssert not declared(addGetSelected)
  doAssert not declared(addChanges)
  doAssert not declared(addSet)
  doAssert not declared(addCopy)
  doAssert not declared(addQuery)
  doAssert not declared(addQueryChanges)
  # A6 — factories and raw-access accessors are hub-private
  doAssert not declared(initRequestBuilder)
  doAssert not declared(initResponseHandle)
  doAssert not declared(initNameBoundHandle)
  doAssert not declared(initDispatchedResponse)
  doAssert not declared(initBuilderId)
  doAssert not declared(build) # replaced by freeze
  # A12 — the internal-only JmapError arm constructors and the MethodOutcome
  # producers (minted by dispatch, not by consumers) are hub-private.
  doAssert not declared(jmapMisuse)
  doAssert not declared(jmapProtocol)
  doAssert not declared(jmapMethod)
  doAssert not declared(protocolMissingCall)
  doAssert not declared(protocolMalformedError)
  doAssert not declared(protocolDecode)
  doAssert not declared(methodValue)
  doAssert not declared(methodFailure)
  doAssert not declared(methodFault)
  # B9 — the generic Chained* paired-handle plumbing was deleted; RFC 8620 §3.7
  # chains are bespoke records co-located with their builders, so the hub
  # exposes exactly the two compound paired-handle context types (P9).
  doAssert not declared(ChainedHandles)
  doAssert not declared(ChainedResults)
  doAssert not declared(registerChainableMethod)

  # A30b: the envelope wire types are fully hub-internal (asserted absent
  # above), which subsumes the earlier A16/A30 negatives on their ``toJson``
  # and raw-field construction. Their smart constructors are likewise
  # hub-private — asserted by symbol name so a re-leak of the bare
  # constructor (without the type) would still be caught.
  doAssert not declared(initRequest)
  doAssert not declared(parseRequest)
  doAssert not declared(initResponse)

# Runtime anchor — `declared()` in the static block above does not
# count as "use" for Nim's UnusedImport check. Reference one
# public-surface symbol from each filtered hub (methods, dispatch,
# builder) at runtime to pin the import.
discard sizeof(GetRequest)
discard sizeof(DispatchedResponse)
discard sizeof(RequestBuilder)
