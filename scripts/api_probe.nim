# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Union of the two public entry points, the single compile target for the
## API oracle (``scripts/api_oracle.nim``). Living in-repo means the project's
## own ``config.nims`` is found and applied when the oracle compiles it, so the
## enumerated surface is computed under the exact flags a consumer's build sees.

import jmap_client
import jmap_client/convenience

export jmap_client
export convenience
