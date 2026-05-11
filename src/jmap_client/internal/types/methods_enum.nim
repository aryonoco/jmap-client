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
{.experimental: "strictCaseObjects".}

import std/hashes

import ./validation

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
  mnEmailSubmissionGet = "EmailSubmission/get"
  mnEmailSubmissionChanges = "EmailSubmission/changes"
  mnEmailSubmissionSet = "EmailSubmission/set"
  mnEmailSubmissionQuery = "EmailSubmission/query"
  mnEmailSubmissionQueryChanges = "EmailSubmission/queryChanges"
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
  meEmailSubmission
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
  rpListThreadId = "/list/*/threadId"
  rpListEmailIds = "/list/*/emailIds"

func parseMethodName*(raw: string): MethodName =
  ## Total — returns ``mnUnknown`` for any wire string that doesn't
  ## match a known backing literal. Used on the receive path
  ## (serde_envelope fromJson) to tag known methods without rejecting
  ## forward-compatible server extensions.
  for m in MethodName:
    if m != mnUnknown and $m == raw:
      return m
  mnUnknown

type MethodNameLiteral* = distinct string
  ## Validated wire-format method name carrier for
  ## ``addCapabilityInvocation`` — distinct from the typed ``MethodName``
  ## enum because vendor methods cannot be enumerated. Parses any
  ## 1..255-octet, control-free, slash-containing string; rendered
  ## verbatim on the wire via ``parseInvocation``. Raw constructor
  ## ``MethodNameLiteral(s)`` is module-private (P15); external consumers
  ## go through ``parseMethodNameLiteral``.

defineStringDistinctOps(MethodNameLiteral)

func parseMethodNameLiteral*(raw: string): Result[MethodNameLiteral, ValidationError] =
  ## Validates the wire shape RFC 8620 §3.2 requires: 1..255 octets, no
  ## control characters, contains at least one ``/`` separator. The
  ## library cannot enumerate vendor ``Entity/verb`` pairs, so the
  ## structural check is the only construction-time gate.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "MethodNameLiteral", raw))
  if '/' notin raw:
    return err(
      validationError(
        "MethodNameLiteral", "must contain '/' (RFC 8620 §3.2 Entity/verb)", raw
      )
    )
  ok(MethodNameLiteral(raw))
