# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Entity registration for Thread, Identity, and Mailbox (RFC 8621
## sections 2, 3, 6). VacationResponse is deliberately NOT registered
## (Decision A7) — it uses custom builder functions in ``mail_methods``
## instead.

{.push raises: [].}

import std/json

import ../entity
import ./thread
import ./identity
import ./mailbox
import ./mail_filters
import ./serde_mail_filters

# ---------------------------------------------------------------------------
# Thread (RFC 8621 section 3) — supports /get, /changes
# ---------------------------------------------------------------------------

func methodNamespace*(T: typedesc[thread.Thread]): string =
  ## JMAP method prefix for Thread (e.g. "Thread/get").
  discard $T # consumed for nimalyzer params rule
  "Thread"

func capabilityUri*(T: typedesc[thread.Thread]): string =
  ## Capability URI for Thread methods.
  discard $T # consumed for nimalyzer params rule
  "urn:ietf:params:jmap:mail"

registerJmapEntity(thread.Thread)

# ---------------------------------------------------------------------------
# Identity (RFC 8621 section 6) — supports /get, /changes, /set
# ---------------------------------------------------------------------------

func methodNamespace*(T: typedesc[Identity]): string =
  ## JMAP method prefix for Identity (e.g. "Identity/get").
  discard $T # consumed for nimalyzer params rule
  "Identity"

func capabilityUri*(T: typedesc[Identity]): string =
  ## Capability URI for Identity methods.
  discard $T # consumed for nimalyzer params rule
  "urn:ietf:params:jmap:submission"

registerJmapEntity(Identity)

# ---------------------------------------------------------------------------
# Mailbox (RFC 8621 section 2) — supports /get, /changes, /set, /query,
# /queryChanges
# ---------------------------------------------------------------------------

func methodNamespace*(T: typedesc[Mailbox]): string =
  ## JMAP method prefix for Mailbox (e.g. "Mailbox/get").
  discard $T # consumed for nimalyzer params rule
  "Mailbox"

func capabilityUri*(T: typedesc[Mailbox]): string =
  ## Capability URI for Mailbox methods.
  discard $T # consumed for nimalyzer params rule
  "urn:ietf:params:jmap:mail"

template filterType*(T: typedesc[Mailbox]): typedesc =
  ## Associated filter condition type for Mailbox/query.
  discard $T # consumed for nimalyzer params rule
  MailboxFilterCondition

func filterConditionToJson*(c: MailboxFilterCondition): JsonNode =
  ## Serialise MailboxFilterCondition to JSON. Resolved via ``mixin`` in the
  ## single-type-parameter ``addQuery[Mailbox]`` template.
  c.toJson()

registerJmapEntity(Mailbox)
registerQueryableEntity(Mailbox)
