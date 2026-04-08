# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all RFC 8621 (JMAP Mail) modules. Import this single
## module to access mail types, serialisation, entity registration, and
## method builders.

{.push raises: [].}

import jmap_client/mail/types
import jmap_client/mail/serialisation
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_methods

export types
export serialisation
export mail_entities
export mail_methods
