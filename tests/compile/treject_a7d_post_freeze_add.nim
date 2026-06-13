discard """
  action: "reject"
  errormsg: "requires a copy because it's not the last read of"
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A7d reject — using a ``RequestBuilder`` after ``freeze`` is a compile error.
## ``freeze`` consumes the builder (``sink`` + uncopyable), so a subsequent
## ``add*`` on the same builder would need a copy — forbidden by the copy hook.
## The builder lifecycle is single-use: ``newBuilder`` → ``add*`` chain →
## ``freeze`` → ``send``, never branching off an already-frozen builder.

import std/json
import jmap_client
import jmap_client/internal/types/identifiers
import jmap_client/internal/protocol/builder

proc misuse() =
  ## Adds a method to a builder ``freeze`` has already consumed — the
  ## post-freeze ``addEcho`` is the read the uncopyable contract must reject.
  let b = initRequestBuilder(initBuilderId(0'u64, 0'u64))
  discard b.freeze()
  discard b.addEcho(%*{})

misuse()
