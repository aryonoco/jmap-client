# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli identity list` — Identity/get; print each identity's id,
## display name and address (one is needed later to pick a From for
## sending). Identity exposes direct public fields.

import jmap_client
import ./cli_session

proc listIdentities(): JmapResult[int] =
  let ctx = ?connect()
  let (b, handle) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(handle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Identity/get: " & outcome.error.message
    ok(1)
  of mokValue:
    for ident in outcome.value.list:
      echo $ident.id, "  ", ident.name, "  <", ident.email, ">"
    ok(0)

proc run*(args: seq[string]): int =
  listIdentities().valueOr:
    stderr.writeLine error.message
    return 1
