# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the internal-module access path for the demoted
## envelope wire types (A30b). The serde, dispatch, builder, and client
## modules must continue to reach ``Invocation`` / ``Request`` / ``Response``
## / ``ResultReference`` and the sealed ``Referencable`` accessors via direct
## import of the L1 envelope leaf. Compiling this file proves the demotion is
## a hub re-export filter, not a deletion — drift here means an internal
## consumer would lose access. Mirror of
## ``tcompile_a2_invocation_internal_access.nim``. See
## ``docs/design/14-Nim-API-Principles.md`` P5.

import std/json

import jmap_client/internal/types/envelope
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

static:
  # =========================================================================
  # POSITIVE — the wire types and their constructors remain reachable to
  # in-tree consumers that import the leaf directly.
  # =========================================================================

  let inv = initInvocation(mnCoreEcho, %*{}, parseMethodCallId("c0").get())
  doAssert compiles(inv.arguments)
  doAssert compiles(parseInvocation("Core/echo", %*{}, parseMethodCallId("c1").get()))

  let rr = initResultReference(
    resultOf = parseMethodCallId("c0").get(), name = mnEmailQuery, path = rpIds
  )
  doAssert compiles(rr.resultOf)
  doAssert compiles(rr.name)

  # The sealed ``Referencable`` read accessors are reachable internally.
  let r = referenceTo[seq[Id]](rr)
  doAssert compiles(r.kind)
  doAssert compiles(r.asDirect)
  doAssert compiles(r.asReference)
  doAssert compiles(direct(@[parseIdFromServer("x").get()]))

  # =========================================================================
  # NEGATIVE — the seal holds even from a leaf-import callsite: the arm
  # fields stay module-private. Construction goes through ``direct`` /
  # ``referenceTo``; reads go through ``asDirect`` / ``asReference``.
  # =========================================================================

  doAssert not compiles(Referencable[seq[Id]](rawKind: rkReference, rawReference: rr))
