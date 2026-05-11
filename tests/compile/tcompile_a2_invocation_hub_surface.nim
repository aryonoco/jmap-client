# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the application-developer-facing seal on
## `Invocation.arguments` (A2). Compiling this file proves that
## ``import jmap_client`` does not expose the raw JsonNode accessor,
## the field cannot be read or written via UFCS, and no
## JsonNode-shaped setter is reachable. A compile failure here is
## the canonical signal that the seal has drifted. See
## ``docs/design/14-Nim-API-Principles.md`` P5, P8, P15, P19.

import std/json

import jmap_client

static:
  let inv = initInvocation(mnCoreEcho, %*{}, MethodCallId("c0"))

  # =========================================================================
  # POSITIVE — the typed public accessors must remain reachable.
  # =========================================================================

  doAssert compiles(name(inv))
  doAssert compiles(inv.name)
  doAssert compiles(methodCallId(inv))
  doAssert compiles(inv.toJson)

  # =========================================================================
  # NEGATIVE — the raw JsonNode accessor must NOT be declared at the
  # hub. Application developers consume typed values through the
  # dispatcher; diagnostic inspection is via ``inv.toJson``.
  # =========================================================================

  doAssert not declared(arguments)
  doAssert not compiles(inv.arguments)

  # =========================================================================
  # NEGATIVE — the field itself is module-private; direct write
  # rejected even when the symbol is in scope.
  # =========================================================================

  doAssert not compiles(
    block:
      var i = inv
      i.arguments = newJObject()
  )

  # =========================================================================
  # NEGATIVE — no JsonNode-shaped setter exists. P19 forbids it.
  # =========================================================================

  doAssert not declared(withArguments)
