# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time registration framework for JMAP entity types (RFC 8620 §5).
##
## JMAP uses a "Foo/get", "Foo/set" naming convention where each entity type
## declares its method namespace (the "Foo" prefix) and capability URI (for
## the ``Request.using`` array). This module provides two registration
## templates that verify entity types supply these required overloads at
## definition time, producing domain-specific compile errors instead of
## cryptic failures at distant generic call sites.
##
## **Required overloads** (§4.1). Every entity type must provide:
##
## - ``func methodNamespace*(T: typedesc[Entity]): string`` — returns the
##   entity name for method construction ("Mailbox" → "Mailbox/get").
## - ``func capabilityUri*(T: typedesc[Entity]): string`` — returns the
##   capability URI for the ``using`` array (e.g. "urn:ietf:params:jmap:mail").
##
## **No concept constraint** (Decision D3.4). Generic ``add*`` functions leave
## ``T`` unconstrained. Concepts are rejected due to experimental status,
## known compiler bugs (byref #16897, block scope, implicit generic breakage),
## and generic type checking being unimplemented. Plain overloads with
## registration templates provide earlier error detection (definition time vs
## instantiation time) and domain-specific messages.
##
## **``mixin`` resolution** (§4.4). Generic ``add*`` functions in
## ``builder.nim`` declare ``mixin methodNamespace, capabilityUri`` to force
## overload resolution at the **caller's scope** (instantiation time), not at
## ``builder.nim``'s scope (definition time). This allows entity modules to be
## added independently without modifying the import DAG.
##
## **Associated type templates** (§4.5). Queryable entities additionally
## provide ``template filterType*(T: typedesc[Entity]): typedesc`` mapping the
## entity to its filter condition type. A ``template`` returning ``typedesc``
## works in generic object field type positions (e.g.
## ``Filter[filterType(T)]``). ``mixin filterType`` in ``addQuery`` /
## ``addQueryChanges`` ensures the caller's overload is found.
##
## **Entity module checklist.** Every entity module must provide:
##
## 1. Entity type definition (e.g. ``type Mailbox* = object``).
## 2. ``func methodNamespace*(T: typedesc[Entity]): string``.
## 3. ``func capabilityUri*(T: typedesc[Entity]): string``.
## 4. ``template filterType*(T: typedesc[Entity]): typedesc`` (if supports
##    ``/query``).
## 5. ``func filterConditionToJson*(c: filterType(Entity)): JsonNode``
##    (if supports ``/query``). Must use this exact name for mixin resolution.
## 6. ``registerJmapEntity(Entity)`` at module scope.
## 7. ``registerQueryableEntity(Entity)`` at module scope (if supports
##    ``/query``).
## 8. ``toJson``/``fromJson`` for the entity type itself (entity-specific,
##    not Layer 3 Core).
##
## Items 1–7 are Layer 3 concerns. Item 8 is entity-specific.

{.push raises: [], noSideEffect.}

template registerJmapEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides the required framework
  ## overloads (``methodNamespace`` and ``capabilityUri``). Call this
  ## once per entity type at module scope. Missing framework overloads
  ## produce domain-specific compile errors HERE, not cryptic
  ## "undeclared identifier" errors at distant add* call sites.
  ## Does not check conditional overloads (``filterType``) — use
  ## ``registerQueryableEntity`` for entity types that support /query
  ## (§4.6). Without it, missing ``filterType`` is caught at
  ## ``addQuery``/``addQueryChanges`` call sites via ``mixin``.
  ##
  ## Uses ``when not compiles()`` + ``{.error.}`` rather than bare
  ## ``discard`` calls to produce actionable error messages that name
  ## the entity type and the missing overload signature.
  static:
    when not compiles(methodNamespace(T)):
      {.
        error:
          "registerJmapEntity: " & $T & " is missing `func methodNamespace*(T: typedesc[" &
          $T & "]): string`"
      .}
    when not compiles(capabilityUri(T)):
      {.
        error:
          "registerJmapEntity: " & $T & " is missing `func capabilityUri*(T: typedesc[" &
          $T & "]): string`"
      .}

template registerQueryableEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides ``filterType`` and
  ## ``filterConditionToJson`` in addition to the base framework overloads.
  ## Call after ``registerJmapEntity`` for entity types that support /query
  ## and /queryChanges. Produces domain-specific errors if either is missing.
  ##
  ## ``filterConditionToJson`` is the standardised name for the filter
  ## serialisation callback. The single-type-parameter ``addQuery[T]``
  ## overload resolves it via ``mixin``, eliminating the need to pass the
  ## callback explicitly at every call site.
  static:
    when not compiles(filterType(T)):
      {.
        error:
          "registerQueryableEntity: " & $T &
          " is missing `template filterType*(T: typedesc[" & $T & "]): typedesc`"
      .}
    when not compiles(filterConditionToJson(default(filterType(T)))):
      {.
        error:
          "registerQueryableEntity: " & $T &
          " is missing `func filterConditionToJson*(c: " & $filterType(T) &
          "): JsonNode`"
      .}
