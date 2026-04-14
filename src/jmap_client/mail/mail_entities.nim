# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Entity registration for Thread, Identity, Mailbox, and Email (RFC 8621
## sections 2, 3, 4, 6). VacationResponse and SearchSnippet are deliberately
## NOT registered (Decision A7) — they use custom builder functions in
## ``mail_methods`` instead, keyed directly on the relevant ``MethodName``
## enum variants.
##
## **Per-verb resolvers.** Each entity exposes one ``methodEntity`` tag plus
## one ``<verb>MethodName`` overload per supported verb. Invalid combinations
## (e.g. ``setMethodName(typedesc[Thread])``) fail at the call site with an
## undeclared-identifier compile error instead of at the server.

{.push raises: [], noSideEffect.}

import std/json

import ../entity
import ../methods_enum
import ./thread
import ./identity
import ./mailbox
import ./email
import ./mail_filters
import ./serde_mail_filters

# ---------------------------------------------------------------------------
# Thread (RFC 8621 section 3) — supports /get, /changes
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[thread.Thread]): MethodEntity =
  ## Entity tag for Thread.
  discard $T # consumed for nimalyzer params rule
  meThread

func getMethodName*(T: typedesc[thread.Thread]): MethodName =
  ## Thread/get method name.
  discard $T
  mnThreadGet

func changesMethodName*(T: typedesc[thread.Thread]): MethodName =
  ## Thread/changes method name.
  discard $T
  mnThreadChanges

func capabilityUri*(T: typedesc[thread.Thread]): string =
  ## Capability URI for Thread methods.
  discard $T
  "urn:ietf:params:jmap:mail"

registerJmapEntity(thread.Thread)

# ---------------------------------------------------------------------------
# Identity (RFC 8621 section 6) — supports /get, /changes, /set
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Identity]): MethodEntity =
  ## Entity tag for Identity.
  discard $T
  meIdentity

func getMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/get method name.
  discard $T
  mnIdentityGet

func changesMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/changes method name.
  discard $T
  mnIdentityChanges

func setMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/set method name.
  discard $T
  mnIdentitySet

func capabilityUri*(T: typedesc[Identity]): string =
  ## Capability URI for Identity methods.
  discard $T
  "urn:ietf:params:jmap:submission"

registerJmapEntity(Identity)

# ---------------------------------------------------------------------------
# Mailbox (RFC 8621 section 2) — supports /get, /changes, /set, /query,
# /queryChanges
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Mailbox]): MethodEntity =
  ## Entity tag for Mailbox.
  discard $T
  meMailbox

func getMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/get method name.
  discard $T
  mnMailboxGet

func changesMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/changes method name.
  discard $T
  mnMailboxChanges

func setMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/set method name.
  discard $T
  mnMailboxSet

func queryMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/query method name.
  discard $T
  mnMailboxQuery

func queryChangesMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/queryChanges method name.
  discard $T
  mnMailboxQueryChanges

func capabilityUri*(T: typedesc[Mailbox]): string =
  ## Capability URI for Mailbox methods.
  discard $T
  "urn:ietf:params:jmap:mail"

template filterType*(T: typedesc[Mailbox]): typedesc =
  ## Associated filter condition type for Mailbox/query.
  discard $T
  MailboxFilterCondition

func filterConditionToJson*(c: MailboxFilterCondition): JsonNode =
  ## Serialise MailboxFilterCondition to JSON. Resolved via ``mixin`` in the
  ## single-type-parameter ``addQuery[Mailbox]`` template.
  c.toJson()

registerJmapEntity(Mailbox)
registerQueryableEntity(Mailbox)

# ---------------------------------------------------------------------------
# Email (RFC 8621 section 4) — supports /get, /changes, /set, /query,
# /queryChanges, /copy
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Email]): MethodEntity =
  ## Entity tag for Email.
  discard $T
  meEmail

func getMethodName*(T: typedesc[Email]): MethodName =
  ## Email/get method name.
  discard $T
  mnEmailGet

func changesMethodName*(T: typedesc[Email]): MethodName =
  ## Email/changes method name.
  discard $T
  mnEmailChanges

func setMethodName*(T: typedesc[Email]): MethodName =
  ## Email/set method name.
  discard $T
  mnEmailSet

func queryMethodName*(T: typedesc[Email]): MethodName =
  ## Email/query method name.
  discard $T
  mnEmailQuery

func queryChangesMethodName*(T: typedesc[Email]): MethodName =
  ## Email/queryChanges method name.
  discard $T
  mnEmailQueryChanges

func copyMethodName*(T: typedesc[Email]): MethodName =
  ## Email/copy method name.
  discard $T
  mnEmailCopy

func capabilityUri*(T: typedesc[Email]): string =
  ## Capability URI for Email methods.
  discard $T
  "urn:ietf:params:jmap:mail"

template filterType*(T: typedesc[Email]): typedesc =
  ## Associated filter condition type for Email/query.
  discard $T
  EmailFilterCondition

func filterConditionToJson*(c: EmailFilterCondition): JsonNode =
  ## Serialise EmailFilterCondition to JSON. Resolved via ``mixin`` in the
  ## single-type-parameter ``addQuery[Email]`` template.
  c.toJson()

registerJmapEntity(Email)
registerQueryableEntity(Email)
