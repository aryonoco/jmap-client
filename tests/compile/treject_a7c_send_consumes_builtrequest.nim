discard """
  action: "reject"
  errormsg: "requires a copy because it's not the last read of"
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A7c reject — ``send`` consumes ``BuiltRequest``. ``BuiltRequest``
## is uncopyable (``=copy`` + ``=dup`` marked ``{.error.}``), so the
## second ``c.send(req)`` is a compile error: the first call would
## need to copy ``req`` (because the second is the actual last read),
## but the copy hook forbids it.

import jmap_client
import jmap_client/internal/types/identifiers
import jmap_client/internal/protocol/builder

var c = initJmapClient(sessionUrl = "https://example.com/jmap", bearerToken = "t").get()
let req = initRequestBuilder(initBuilderId(0'u64, 0'u64)).freeze()
discard c.send(req)
discard c.send(req)
