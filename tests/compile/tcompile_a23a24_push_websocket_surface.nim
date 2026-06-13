# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only positive surface gate for the RFC 8620 §7 Push and RFC 8887
## WebSocket type stubs (A23/A24). These are surfaced to application
## developers through ``import jmap_client`` (re-exported from the root hub,
## no separate public module path per A10c). This audit pins that surface so
## a future hub-export drift that dropped them would fail at compile time;
## previously A23/A24 had presence coverage only via the wider hub audits.
## See ``docs/design/14-Nim-API-Principles.md`` P5.

import jmap_client

static:
  doAssert declared(PushChannel)
  doAssert declared(WebSocketChannel)

# Runtime anchor — `declared()` probes do not count as "use" for Nim's
# UnusedImport check.
discard sizeof(PushChannel)
discard sizeof(WebSocketChannel)
