# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A11 RequestContext internal-access compile audit. Proves the
## sibling-internal reach still works after relocation from
## ``internal/types/errors.nim`` to
## ``internal/transport/classify.nim`` (locks the relocation
## invariant from the inside).

import jmap_client/internal/transport/classify

static:
  doAssert declared(RequestContext)
  doAssert declared(rcSession)
  doAssert declared(rcApi)
  doAssert $rcSession == "session"
  doAssert $rcApi == "api"
