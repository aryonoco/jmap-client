# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## The single public entry point and compile target for the API oracle
## (``scripts/api_oracle.nim``). Living in-repo means the project's own
## ``config.nims`` is found and applied when the oracle compiles it, so the
## enumerated surface is computed under the exact flags a consumer's build sees.

import jmap_client

export jmap_client
