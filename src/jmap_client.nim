# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## JMAP client library entry point — the canonical user import.
##
## ``import jmap_client`` is the headline API. It re-exports the
## full public surface: L1 domain vocabulary, L2 serialisation, L3
## protocol builders + dispatch, L4 transport + client, RFC 8621
## mail entities, and the ``PushChannel`` / ``WebSocketChannel``
## reservation types (RFC 8620 §7 / RFC 8887 — types named pre-1.0;
## implementations land additively per P20).
##
## ``jmap_client/convenience`` is publicly importable but opt-in:
## NOT re-exported here. Consumers who want pipeline combinators
## must ``import jmap_client/convenience`` explicitly.

import jmap_client/internal/types
import jmap_client/internal/serialisation
import jmap_client/internal/protocol
import jmap_client/internal/transport
import jmap_client/internal/client
import jmap_client/internal/mail
import jmap_client/internal/push
import jmap_client/internal/websocket

export types
export serialisation
export protocol
export transport
export client
export mail
export push
export websocket
