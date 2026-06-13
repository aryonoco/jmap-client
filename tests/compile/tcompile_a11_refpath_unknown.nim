# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A11 RefPath compile audit. Proves rpUnknown and parseRefPath
## are reachable via ``import jmap_client``, and that the typed
## view of a vendor wire path surfaces as rpUnknown with rawPath
## preserved.

import jmap_client
# ``ResultReference`` and its constructors are hub-internal after A30b; this
# audit fabricates one to prove the typed ``RefPath`` view of a vendor wire
# path, so it reaches the envelope leaf directly (the H10-sanctioned in-tree
# access path).
import jmap_client/internal/types/envelope

static:
  doAssert declared(rpUnknown)
  doAssert compiles(parseRefPath("/ids"))
  doAssert parseRefPath("/ids") == rpIds
  doAssert parseRefPath("/created") == rpCreated
  doAssert parseRefPath("/list/*/threadId") == rpListThreadId
  doAssert parseRefPath("/vendor/extension") == rpUnknown
  let rr = parseResultReference(
      resultOf = parseMethodCallId("c0").get(),
      name = "Mailbox/get",
      path = "/vendor/extension",
    )
    .get()
  doAssert rr.path == rpUnknown
  doAssert rr.rawPath == "/vendor/extension"
