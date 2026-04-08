# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## MailboxFilterCondition for RFC 8621 (JMAP Mail) §2.3 Mailbox/query.
## Encodes filter predicates that flow client-to-server. Uses Opt[Opt[T]]
## for three-state filter semantics: absent (don't filter), null (filter for
## no value), or value (filter for specific value).

{.push raises: [].}

import ../validation
import ../primitives
import ./mailbox

type MailboxFilterCondition* {.ruleOff: "objects".} = object
  ## Filter condition for Mailbox/query (RFC 8621 §2.3). No smart constructor —
  ## all field combinations are valid (Decision B16). toJson only — the server
  ## never sends this back (Decision B11).
  ##
  ## Three-state fields use ``Opt[Opt[T]]``:
  ## - ``Opt.none(Opt[T])`` — don't filter on this field (omit from JSON)
  ## - ``Opt.some(Opt.none(T))`` — filter for null/absent (emit null)
  ## - ``Opt.some(Opt.some(v))`` — filter for specific value (emit value)
  parentId*: Opt[Opt[Id]] ## Filter by parent mailbox.
  name*: Opt[string] ## Filter by name substring.
  role*: Opt[Opt[MailboxRole]] ## Filter by role.
  hasAnyRole*: Opt[bool] ## Filter by whether any role is set.
  isSubscribed*: Opt[bool] ## Filter by subscription status.
