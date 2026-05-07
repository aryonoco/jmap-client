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
  doAssert declared(addGet)
  doAssert declared(addSet)
  doAssert declared(addQuery)
  doAssert declared(addQueryChanges)
  doAssert declared(addChanges)
  doAssert declared(addCopy)
  doAssert declared(addEcho)

  # --- L4: client transport ---
  doAssert declared(JmapClient)

# Runtime anchor pins the import against UnusedImport warnings.
doAssert $mnCoreEcho == "Core/echo"
