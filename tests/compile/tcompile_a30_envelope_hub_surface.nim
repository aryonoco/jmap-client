# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the envelope wire-type demotion (A30b). After A30b
## the entire RFC 8620 §3.2-3.4/3.7 envelope surface — ``Invocation``,
## ``Request``, ``Response``, ``ResultReference`` and their accessors /
## constructors — is hub-internal. ``import jmap_client`` exposes only the
## ``Referencable[T]`` direct-or-reference carrier, its ``direct``
## constructor, and the typed back-reference primitive ``reference``
## (``dispatch.nim``). Apps build requests via ``RequestBuilder`` and read
## typed responses via the dispatcher; they never obtain or construct a raw
## wire instance (P5/P8/P15/P16/P19). The companion
## ``tcompile_a30_envelope_internal_access.nim`` proves the demoted symbols
## remain reachable to in-tree consumers that import the envelope leaf.

import jmap_client

static:
  # =========================================================================
  # POSITIVE — the app-facing reference surface stays reachable.
  # =========================================================================

  doAssert declared(Referencable)
  doAssert declared(direct)
  doAssert declared(reference)
  doAssert declared(directIds)

  # =========================================================================
  # NEGATIVE — the wire types themselves are hub-internal.
  # =========================================================================

  doAssert not declared(Invocation)
  doAssert not declared(Request)
  doAssert not declared(Response)
  doAssert not declared(ResultReference)
  doAssert not declared(ReferencableKind)

  # =========================================================================
  # NEGATIVE — their constructors are hub-internal (no raw construction).
  # =========================================================================

  doAssert not declared(initInvocation)
  doAssert not declared(parseInvocation)
  doAssert not declared(initRequest)
  doAssert not declared(parseRequest)
  doAssert not declared(initResponse)
  doAssert not declared(initResultReference)
  doAssert not declared(parseResultReference)
  doAssert not declared(referenceTo)

  # The raw JsonNode accessor and the typedesc-keyed parse adapter that feeds
  # the generic ``Table[K, V].fromJson`` are hub-private (P5/P19).
  doAssert not declared(arguments)
  doAssert not declared(parseFromString)

  # =========================================================================
  # NEGATIVE — the redundant ``*ByRef`` get-builders are deleted (P7).
  # =========================================================================

  doAssert not declared(addEmailGetByRef)
  doAssert not declared(addPartialEmailGetByRef)
  doAssert not declared(addThreadGetByRef)
  doAssert not declared(addPartialThreadGetByRef)

  # =========================================================================
  # NEGATIVE — ``Referencable`` is sealed: its discriminator and both arm
  # fields are module-private. Only ``direct`` / ``reference`` construct it.
  # =========================================================================

  doAssert not compiles(Referencable[int](rawKind: rkDirect, rawValue: 1))

# Runtime anchor — `declared()` / `compiles()` probes do not count as "use"
# for Nim's UnusedImport check. Pin `jmap_client`.
discard sizeof(Referencable[int])
