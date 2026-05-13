# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all RFC 8621 (JMAP Mail) modules. Import this single
## module to access mail types, serialisation, entity registration, and
## method builders.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./mail/types
import ./mail/serialisation
import ./mail/mail_entities
import ./mail/mail_methods
import ./mail/mail_builders
import ./mail/identity_builders
import ./mail/submission_builders

export types
export serialisation
export mail_entities
export mail_methods
export mail_builders
export identity_builders
export submission_builders
