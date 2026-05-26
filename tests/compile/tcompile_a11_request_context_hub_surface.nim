# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A11 RequestContext hub-invisibility compile audit. Proves
## ``import jmap_client`` does NOT expose ``RequestContext``,
## ``rcSession``, or ``rcApi`` — internal-only classification
## per P5.

import jmap_client

static:
  # Engage the hub with a real call so the import is used; the
  # adjacent A11 closing (``rpUnknown``, ``parseRefPath``) doubles
  # as the public-surface witness.
  doAssert parseRefPath("/vendor/extension") == rpUnknown

  doAssert not declared(RequestContext)
  doAssert not declared(rcSession)
  doAssert not declared(rcApi)

when declared(RequestContext):
  {.error: "RequestContext re-leaked to the public surface; see A11.".}
when declared(rcSession):
  {.error: "rcSession re-leaked to the public surface; see A11.".}
when declared(rcApi):
  {.error: "rcApi re-leaked to the public surface; see A11.".}
