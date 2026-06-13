discard """
  action: "reject"
  errormsg: "requires a copy because it's not the last read of"
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A7d reject — ``freeze`` consumes the ``RequestBuilder``. ``RequestBuilder``
## is uncopyable (``=copy`` + ``=dup`` marked ``{.error.}``), so freezing the
## same builder twice is a compile error: the first ``freeze`` would need to
## copy the builder (the second is the actual last read), but the copy hook
## forbids it. A retry replays ``freeze`` from a freshly constructed builder.

import jmap_client
import jmap_client/internal/types/identifiers
import jmap_client/internal/protocol/builder

proc misuse() =
  ## Freezes the same builder twice — the second ``freeze`` is the read the
  ## uncopyable contract must reject, since the first already consumed it.
  let b = initRequestBuilder(initBuilderId(0'u64, 0'u64))
  discard b.freeze()
  discard b.freeze()

misuse()
