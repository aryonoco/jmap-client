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

import jmap_client

static:
  # =========================================================================
  # POSITIVE — must be reachable through `import jmap_client`
  # =========================================================================

  # entity.nim — registration templates
  doAssert declared(registerJmapEntity)
  doAssert declared(registerQueryableEntity)
  doAssert declared(registerSettableEntity)

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
  doAssert declared(ChainedHandles)
  doAssert declared(ChainedResults)
  # dispatch.nim — extraction
  doAssert declared(callId)
  doAssert declared(get)
  doAssert declared(getBoth)
  # dispatch.nim — references
  doAssert declared(reference)
  doAssert declared(idsRef)
  doAssert declared(listIdsRef)
  doAssert declared(addedIdsRef)
  doAssert declared(createdRef)
  doAssert declared(updatedRef)
  # dispatch.nim — registration
  doAssert declared(registerCompoundMethod)
  doAssert declared(registerChainableMethod)

  # builder.nim — type + constructor
  doAssert declared(RequestBuilder)
  doAssert declared(initRequestBuilder)
  # builder.nim — accessors
  doAssert declared(methodCallCount)
  doAssert declared(isEmpty)
  doAssert declared(capabilities)
  # builder.nim — build
  doAssert declared(build)
  # builder.nim — add* family
  doAssert declared(addEcho)
  doAssert declared(addGet)
  doAssert declared(addChanges)
  doAssert declared(addSet)
  doAssert declared(addCopy)
  doAssert declared(addQuery)
  doAssert declared(addQueryChanges)
  # builder.nim — argument helpers
  doAssert declared(directIds)
  doAssert declared(initCreates)

  # =========================================================================
  # NEGATIVE — must NOT be reachable through `import jmap_client`
  # =========================================================================

  # methods.nim — `*`-stripped (truly module-private)
  doAssert not declared(optState)
  doAssert not declared(optUnsignedInt)
  doAssert not declared(mergeCreateResults)
  # dispatch.nim — `*`-stripped (truly module-private)
  doAssert not declared(serdeToMethodError)

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
