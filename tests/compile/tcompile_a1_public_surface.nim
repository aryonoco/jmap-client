# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only smoke test for the A1 closed-set public surface. Every
## core L1/L2/L3/L4 symbol that is part of the public contract must be
## reachable through a single ``import jmap_client``. A compile failure
## here is the canonical signal that A1's re-export cascade
## ``jmap_client.nim`` -> ``types``/``serialisation``/``protocol``/
## ``client``/``mail`` -> ``internal/<layer>/<leaf>`` is broken.

import jmap_client

static:
  # --- L1: identifiers + primitives + smart constructors ---
  doAssert declared(AccountId)
  doAssert declared(Id)
  doAssert declared(BlobId)
  doAssert declared(JmapState)
  doAssert declared(MethodCallId)
  doAssert declared(CreationId)
  doAssert declared(parseAccountId)
  doAssert declared(parseId)
  doAssert declared(parseUnsignedInt)

  # --- L1: capabilities + session ---
  doAssert declared(CapabilityKind)
  doAssert declared(CoreCapabilities)
  doAssert declared(Session)
  doAssert declared(Account)

  # --- L1: envelope + framework + errors ---
  doAssert declared(Invocation)
  doAssert declared(Request)
  doAssert declared(Response)
  doAssert declared(ResultReference)
  doAssert declared(Filter)
  doAssert declared(Comparator)
  doAssert declared(ClientError)
  doAssert declared(TransportError)
  doAssert declared(RequestError)
  doAssert declared(MethodError)
  doAssert declared(SetError)
  doAssert declared(JmapResult)

  # --- L2: serde toJson/fromJson reachable ---
  doAssert declared(toJson)
  doAssert declared(fromJson)

  # --- L3: builder + dispatch (headline API) ---
  doAssert declared(RequestBuilder)
  doAssert declared(ResponseHandle)
  doAssert declared(GetResponse)
  doAssert declared(SetResponse)
  doAssert declared(QueryResponse)
  doAssert declared(ChangesResponse)
  # P19 send-side JsonNode exceptions
  doAssert declared(addEcho)
  doAssert declared(addCapabilityInvocation)
  # Per-entity typed builders (A5)
  doAssert declared(addMailboxGet)
  doAssert declared(addMailboxSet)
  doAssert declared(addMailboxQuery)
  doAssert declared(addMailboxQueryChanges)
  doAssert declared(addMailboxChanges)
  doAssert declared(addEmailGet)
  doAssert declared(addEmailSet)
  doAssert declared(addEmailQuery)
  doAssert declared(addEmailQueryChanges)
  doAssert declared(addEmailChanges)
  doAssert declared(addEmailCopy)
  doAssert declared(addThreadGet)
  doAssert declared(addThreadChanges)
  doAssert declared(addIdentityGet)
  doAssert declared(addIdentityChanges)
  doAssert declared(addIdentitySet)
  # Generic builders are hub-private under A5 — filtered from
  # ``import jmap_client``.
  doAssert not declared(addGet)
  doAssert not declared(addSet)
  doAssert not declared(addQuery)
  doAssert not declared(addQueryChanges)
  doAssert not declared(addChanges)
  doAssert not declared(addCopy)

  # --- L4: client transport ---
  doAssert declared(JmapClient)
  # A6 lifecycle: ``newBuilder`` is the blessed entry point for application
  # developers; ``freeze`` returns the sealed ``BuiltRequest`` that ``send``
  # consumes; ``DispatchedResponse`` is the sealed artifact returned by
  # ``send``; ``GetError`` is the inner-railway error sum returned by
  # ``get`` / ``getBoth``.
  doAssert declared(newBuilder)
  doAssert declared(freeze)
  doAssert declared(BuiltRequest)
  doAssert declared(BuilderId)
  doAssert declared(DispatchedResponse)
  doAssert declared(GetError)
  doAssert declared(GetErrorKind)
  doAssert declared(gekMethod)
  doAssert declared(gekHandleMismatch)
  # Factories of the sealed types are hub-private (A6 P5/P8) — application
  # developers must use the lifecycle, not raw construction.
  doAssert not declared(initRequestBuilder)
  doAssert not declared(initResponseHandle)
  doAssert not declared(initNameBoundHandle)
  doAssert not declared(initDispatchedResponse)
  doAssert not declared(initBuilderId)
  doAssert not declared(build) # replaced by freeze

# Runtime anchor pins the import against UnusedImport warnings.
doAssert $mnCoreEcho == "Core/echo"
