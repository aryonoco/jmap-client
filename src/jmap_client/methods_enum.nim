# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Typed JMAP method names, entity categories, and result-reference paths.
## Backing strings round-trip 1:1 with the wire format
## (``$mnMailboxGet == "Mailbox/get"``) so serialisation is identity-
## functional. Per-verb resolvers (``getMethodName``, ``setMethodName`` …)
## dispatch on the entity typedesc at compile time, making invalid
## combinations (e.g. ``setMethodName[Thread]``) refuse to compile rather
## than fail at the server.

{.push raises: [], noSideEffect.}

type MethodName* = enum
  ## Every JMAP method the library emits on the wire, plus a catch-all
  ## ``mnUnknown`` for receive-side forward compatibility (Postel's law).
  ## The catch-all has no backing string — ``$mnUnknown`` falls back to
  ## the symbol name; it is never emitted because only server replies
  ## populate it, and the verbatim wire string is preserved on the
  ## Invocation's ``rawName`` field for lossless round-trip.
  mnUnknown
  mnCoreEcho = "Core/echo"
  mnThreadGet = "Thread/get"
  mnThreadChanges = "Thread/changes"
  mnIdentityGet = "Identity/get"
  mnIdentityChanges = "Identity/changes"
  mnIdentitySet = "Identity/set"
  mnMailboxGet = "Mailbox/get"
  mnMailboxChanges = "Mailbox/changes"
  mnMailboxSet = "Mailbox/set"
  mnMailboxQuery = "Mailbox/query"
  mnMailboxQueryChanges = "Mailbox/queryChanges"
  mnEmailGet = "Email/get"
  mnEmailChanges = "Email/changes"
  mnEmailSet = "Email/set"
  mnEmailQuery = "Email/query"
  mnEmailQueryChanges = "Email/queryChanges"
  mnEmailCopy = "Email/copy"
  mnEmailParse = "Email/parse"
  mnEmailImport = "Email/import"
  mnVacationResponseGet = "VacationResponse/get"
  mnVacationResponseSet = "VacationResponse/set"
  mnSearchSnippetGet = "SearchSnippet/get"

type MethodEntity* = enum
  ## Entity category tag returned by ``methodEntity[T]``. Used by
  ## ``registerJmapEntity`` as the compile-time existence check —
  ## a type without a ``methodEntity`` overload fails the register
  ## step before ever reaching the builder. ``meTest`` is a sentinel
  ## for test-only fixture entities; production dispatch never
  ## observes it because real builders are statically typed to
  ## concrete entity types.
  meCore
  meThread
  meIdentity
  meMailbox
  meEmail
  meVacationResponse
  meSearchSnippet
  meTest

type RefPath* = enum
  ## JMAP result-reference paths (RFC 8620 §3.7) — the JSON Pointer
  ## fragments a chained method call reads out of a prior invocation's
  ## response.
  rpIds = "/ids"
  rpListIds = "/list/*/id"
  rpAddedIds = "/added/*/id"
  rpCreated = "/created"
  rpUpdated = "/updated"
  rpUpdatedProperties = "/updatedProperties"

func parseMethodName*(raw: string): MethodName =
  ## Total — returns ``mnUnknown`` for any wire string that doesn't
  ## match a known backing literal. Used on the receive path
  ## (serde_envelope fromJson) to tag known methods without rejecting
  ## forward-compatible server extensions.
  for m in MethodName:
    if m != mnUnknown and $m == raw:
      return m
  mnUnknown
