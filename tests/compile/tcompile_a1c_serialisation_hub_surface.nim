# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A1c audit: locks the empty L2 serialisation surface of jmap_client.
##
## Under the P5-driven principled cut, the library projects
## SerdeViolation to TransportError(tekNetwork, message: string) at
## the L3/L4 boundary; the app developer never inspects an L2 type
## directly. Therefore every L2 serialisation symbol is hub-private.
##
## Compile failure is the canonical signal that the hub drifted from
## the agreed contract per P2 ("stability is bought with tests").

import std/[json, tables]

import jmap_client

static:
  # Drift guard: typed-entity ser/de still resolves at user scope.
  # The mixin chain must still find primitives at definition site —
  # this would break if the typed-entity fromJson chain lost a needed
  # internal import.
  doAssert compiles(GetResponse[Mailbox].fromJson(newJObject()))

  # ---- Absence: diagnostic types (serde.nim) ----
  when declared(SerdeViolation):
    {.error: "SerdeViolation reachable through hub".}
  when declared(SerdeViolationKind):
    {.error: "SerdeViolationKind reachable through hub".}
  when declared(JsonPath):
    {.error: "JsonPath reachable through hub".}
  when declared(JsonPathElement):
    {.error: "JsonPathElement reachable through hub".}
  when declared(JsonPathElementKind):
    {.error: "JsonPathElementKind reachable through hub".}
  when declared(svkWrongKind):
    {.error: "svkWrongKind reachable through hub".}
  when declared(svkNilNode):
    {.error: "svkNilNode reachable through hub".}
  when declared(svkMissingField):
    {.error: "svkMissingField reachable through hub".}
  when declared(svkEmptyRequired):
    {.error: "svkEmptyRequired reachable through hub".}
  when declared(svkArrayLength):
    {.error: "svkArrayLength reachable through hub".}
  when declared(svkFieldParserFailed):
    {.error: "svkFieldParserFailed reachable through hub".}
  when declared(svkConflictingFields):
    {.error: "svkConflictingFields reachable through hub".}
  when declared(svkEnumNotRecognised):
    {.error: "svkEnumNotRecognised reachable through hub".}
  when declared(svkDepthExceeded):
    {.error: "svkDepthExceeded reachable through hub".}
  when declared(jpeKey):
    {.error: "jpeKey reachable through hub".}
  when declared(jpeIndex):
    {.error: "jpeIndex reachable through hub".}

  # ---- Absence: serde_diagnostics ----
  # ``toValidationError`` is NOT probed here: the same name is a public L1
  # helper (``validation.nim`` for ``TokenViolation``, ``session.nim`` for
  # ``UriTemplateViolation`` etc.) and the L1 overload is legitimately
  # surfaced via ``import jmap_client``. The L2 ``toValidationError``
  # (``serde_diagnostics``) is a distinct overload over ``SerdeViolation``
  # — ``when declared`` cannot discriminate by signature.
  when declared(emptyJsonPath):
    {.error: "emptyJsonPath reachable through hub".}
  when declared(jsonPointerEscape):
    {.error: "jsonPointerEscape reachable through hub".}

  # ---- Absence: serde_helpers ----
  when declared(expectKind):
    {.error: "expectKind reachable through hub".}
  when declared(fieldOfKind):
    {.error: "fieldOfKind reachable through hub".}
  when declared(fieldJObject):
    {.error: "fieldJObject reachable through hub".}
  when declared(fieldJString):
    {.error: "fieldJString reachable through hub".}
  when declared(fieldJArray):
    {.error: "fieldJArray reachable through hub".}
  when declared(fieldJBool):
    {.error: "fieldJBool reachable through hub".}
  when declared(fieldJInt):
    {.error: "fieldJInt reachable through hub".}
  when declared(expectLen):
    {.error: "expectLen reachable through hub".}
  when declared(optField):
    {.error: "optField reachable through hub".}
  when declared(nonEmptyStr):
    {.error: "nonEmptyStr reachable through hub".}
  when declared(wrapInner):
    {.error: "wrapInner reachable through hub".}
  when declared(collectExtras):
    {.error: "collectExtras reachable through hub".}
  when declared(parseIdArray):
    {.error: "parseIdArray reachable through hub".}
  when declared(parseIdArrayField):
    {.error: "parseIdArrayField reachable through hub".}
  when declared(parseOptIdArray):
    {.error: "parseOptIdArray reachable through hub".}
  when declared(collapseNullToEmptySeq):
    {.error: "collapseNullToEmptySeq reachable through hub".}
  when declared(parseKeyedTable):
    {.error: "parseKeyedTable reachable through hub".}
  when declared(optJsonField):
    {.error: "optJsonField reachable through hub".}
  when declared(optToJsonOrNull):
    {.error: "optToJsonOrNull reachable through hub".}
  when declared(optStringToJsonOrNull):
    {.error: "optStringToJsonOrNull reachable through hub".}

  # ---- Absence: serde_primitives overloads ----
  when compiles(string.fromJson(newJString("x"))):
    {.error: "primitive string.fromJson reachable through hub".}
  when compiles(bool.fromJson(newJBool(true))):
    {.error: "primitive bool.fromJson reachable through hub".}
  when compiles(seq[Id].fromJson(newJArray())):
    {.error: "generic seq[T].fromJson reachable through hub".}
  when compiles(Table[Id, Id].fromJson(newJObject())):
    {.error: "generic Table[K,V].fromJson reachable through hub".}
  when compiles("x".toJson()):
    {.error: "primitive string.toJson reachable through hub".}
  when compiles(true.toJson()):
    {.error: "primitive bool.toJson reachable through hub".}
  when compiles((@[]: seq[Id]).toJson()):
    {.error: "generic seq[T].toJson reachable through hub".}
  when compiles(initTable[Id, Id]().toJson()):
    {.error: "generic Table[K,V].toJson reachable through hub".}

  # ---- Absence: defineDistinct* templates ----
  when declared(defineDistinctStringToJson):
    {.error: "defineDistinctStringToJson reachable through hub".}
  when declared(defineDistinctStringFromJson):
    {.error: "defineDistinctStringFromJson reachable through hub".}
  when declared(defineDistinctIntToJson):
    {.error: "defineDistinctIntToJson reachable through hub".}
  when declared(defineDistinctIntFromJson):
    {.error: "defineDistinctIntFromJson reachable through hub".}

  # ---- Absence: relocated per-type ser/de ----
  when compiles(MaxChanges.fromJson(%1)):
    {.error: "MaxChanges.fromJson reachable through hub".}
  when compiles(UriTemplate.fromJson(newJString("a"))):
    {.error: "UriTemplate.fromJson reachable through hub".}

  # ---- Absence: envelope fromJson (parse-side hub-private per P19) ----
  when compiles(Invocation.fromJson(newJArray())):
    {.error: "Invocation.fromJson reachable through hub".}
  when compiles(Request.fromJson(newJObject())):
    {.error: "Request.fromJson reachable through hub".}
  when compiles(Response.fromJson(newJObject())):
    {.error: "Response.fromJson reachable through hub".}
  when compiles(ResultReference.fromJson(newJObject())):
    {.error: "ResultReference.fromJson reachable through hub".}

  # ---- Absence: serde_envelope_parse helpers ----
  when declared(referencableKey):
    {.error: "referencableKey reachable through hub".}
  when declared(fromJsonField):
    {.error: "fromJsonField reachable through hub".}

  # ---- Absence: serde_field_echo ----
  when declared(parsePartialOptField):
    {.error: "parsePartialOptField reachable through hub".}
  when declared(parsePartialFieldEcho):
    {.error: "parsePartialFieldEcho reachable through hub".}
  when declared(emitPartialFieldEcho):
    {.error: "emitPartialFieldEcho reachable through hub".}

  # ---- Absence: serde_framework ----
  when declared(MaxFilterDepth):
    {.error: "MaxFilterDepth reachable through hub".}

# Runtime anchors — `when declared` / `when compiles` probes do not
# count as "use" for Nim's UnusedImport check. Reference two public-
# surface symbols at runtime to pin the import. Both remain hub-public
# via `internal/types` (Mailbox from `internal/mail/`, Session from
# `internal/types/`).
discard sizeof(Mailbox)
discard sizeof(Session)
