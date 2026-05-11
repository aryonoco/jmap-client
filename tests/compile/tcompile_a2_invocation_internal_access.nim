# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the internal-module access path for
## `Invocation.arguments` (A2). The dispatcher, serde, and builder
## modules must continue to reach the JsonNode accessor via direct
## import of the L1 envelope module. Compiling this file proves the
## accessor remains exported from envelope.nim; drift here means an
## internal consumer would lose access. See
## ``docs/design/14-Nim-API-Principles.md`` P5.

import std/json

import jmap_client/internal/types/envelope
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/methods_enum

static:
  let inv = initInvocation(mnCoreEcho, %*{}, MethodCallId("c0"))

  # =========================================================================
  # POSITIVE — internal modules retain accessor access via UFCS and
  # qualified call.
  # =========================================================================

  doAssert compiles(arguments(inv))
  doAssert compiles(inv.arguments)

  # =========================================================================
  # NEGATIVE — the field itself stays module-private even from inside
  # an internal-import callsite. Construction goes through
  # ``initInvocation`` / ``parseInvocation``; the accessor is read-only.
  # =========================================================================

  doAssert not compiles(
    block:
      var i = inv
      i.arguments = newJObject()
  )
