# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli identity list` — Identity/get; print each identity's id,
## display name and address (one is needed later to pick a From for
## sending). Identity exposes direct public fields.

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Identity/get failed: " & error.message
    return 1
  for ident in resp.list:
    echo $ident.id, "  ", ident.name, "  <", ident.email, ">"
  return 0
