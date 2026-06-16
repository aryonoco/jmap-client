# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli identity list` — Identity/get; print each identity's id,
## display name and address (one is needed later to pick a From for
## sending). Identity exposes direct public fields.

import jmap_client
import ./cli_session

proc listIdentities(): JmapResult[int] =
  let ctx = ?connect()
  # getIdentities folds the whole get lifecycle and collapses the single
  # Identity/get outcome onto the rail; the body reads the GetResponse's `.list`.
  let resp = ?ctx.client.getIdentities(ctx.mailAccount)
  for ident in resp.list:
    echo $ident.id, "  ", ident.name, "  <", ident.email, ">"
  ok(0)

proc run*(args: seq[string]): int =
  listIdentities().valueOr:
    stderr.writeLine error.message
    return 1
