# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for the RFC 8621 (JMAP Mail) public surface: mail entity
## types, smart constructors, and the typed per-entity method builders.
## Aggregated into ``jmap_client`` for application developers; wire
## serialisation and entity-registration scaffolding stay hub-private.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./mail/types
import ./mail/mail_methods
import ./mail/mail_builders
import ./mail/identity_builders
import ./mail/submission_builders
import ./mail/combinators

export types except fromJson
export mail_methods
export mail_builders
export identity_builders
export submission_builders
export combinators
