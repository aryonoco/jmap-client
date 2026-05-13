# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## JMAP client library entry point. Re-exports the five public hubs:
## ``types`` (L1 domain vocabulary), ``serialisation`` (L2 wire format),
## ``protocol`` (L3 builders + dispatch — the headline API), ``client``
## (L4 transport), and ``mail`` (RFC 8621 hub). Modules under
## ``jmap_client/internal/`` are implementation details and not part of
## the public API contract — see H10 internal-boundary lint.
##
## ``jmap_client/convenience`` is publicly importable but opt-in: it is
## NOT re-exported here. Consumers who want pipeline combinators must
## ``import jmap_client/convenience`` explicitly (P6 quarantine).

import jmap_client/types
import jmap_client/serialisation
import jmap_client/protocol
import jmap_client/transport
import jmap_client/client
import jmap_client/mail

export types
export serialisation
export protocol
export transport
export client
export mail
