# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A11 RefPath compile audit. Proves rpUnknown and parseRefPath
## are reachable via ``import jmap_client``, and that the typed
## view of a vendor wire path surfaces as rpUnknown with rawPath
## preserved.

import jmap_client

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
