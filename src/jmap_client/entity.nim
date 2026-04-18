# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time registration framework for JMAP entity types (RFC 8620 §5).
##
## JMAP uses a "Foo/get", "Foo/set" naming convention where each entity type
## declares its method family (the "Foo" prefix) and capability URI (for
## the ``Request.using`` array). This module provides two registration
## templates that verify entity types supply these required overloads at
## definition time, producing domain-specific compile errors instead of
## cryptic failures at distant generic call sites.
##
## **Required overloads** (§4.1). Every entity type must provide:
##
## - ``func methodEntity*(T: typedesc[Entity]): MethodEntity`` — returns the
##   typed entity tag (e.g. ``meMailbox``). Per-verb method-name resolvers
##   (``getMethodName(T)`` / ``setMethodName(T)`` / ...) live alongside this
##   overload; invalid verbs (e.g. ``setMethodName(typedesc[Thread])``)
##   fail at the call site with an undeclared-identifier compile error.
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
## ``builder.nim`` declare ``mixin`` for the per-verb resolvers and
## ``capabilityUri`` to force overload resolution at the **caller's scope**
## (instantiation time), not at ``builder.nim``'s scope (definition time).
## This allows entity modules to be added independently without modifying
## the import DAG.
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
## 2. ``func methodEntity*(T: typedesc[Entity]): MethodEntity``.
## 3. Per-verb method-name resolvers for every supported verb — e.g.
##    ``func getMethodName*(T: typedesc[Entity]): MethodName``.
## 4. ``func capabilityUri*(T: typedesc[Entity]): string``.
## 5. ``template filterType*(T: typedesc[Entity]): typedesc`` (if supports
##    ``/query``).
## 6. ``func toJson*(c: filterType(Entity)): JsonNode`` (if supports
##    ``/query``). Resolved via ``mixin`` at the builder's call site.
## 7. ``registerJmapEntity(Entity)`` at module scope.
## 8. ``registerQueryableEntity(Entity)`` at module scope (if supports
##    ``/query``).
## 9. ``toJson``/``fromJson`` for the entity type itself (entity-specific,
##    not Layer 3 Core).
##
## Items 1–8 are Layer 3 concerns. Item 9 is entity-specific.

{.push raises: [], noSideEffect.}

template registerJmapEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides the required framework
  ## overloads (``methodEntity`` and ``capabilityUri``). Call this
  ## once per entity type at module scope. Missing framework overloads
  ## produce domain-specific compile errors HERE, not cryptic
  ## "undeclared identifier" errors at distant add* call sites.
  ## Does not check conditional overloads (``filterType``) — use
  ## ``registerQueryableEntity`` for entity types that support /query
  ## (§4.6). Does not check per-verb method-name resolvers — those fail
  ## at their call site with an undeclared-identifier error that names
  ## the offending ``(entity, verb)`` pair, which is more precise than a
  ## generic registration check could be.
  ##
  ## Uses ``when not compiles()`` + ``{.error.}`` rather than bare
  ## ``discard`` calls to produce actionable error messages that name
  ## the entity type and the missing overload signature.
  static:
    when not compiles(methodEntity(T)):
      {.
        error:
          "registerJmapEntity: " & $T & " is missing `func methodEntity*(T: typedesc[" &
          $T & "]): MethodEntity`"
      .}
    when not compiles(capabilityUri(T)):
      {.
        error:
          "registerJmapEntity: " & $T & " is missing `func capabilityUri*(T: typedesc[" &
          $T & "]): string`"
      .}

template registerQueryableEntity*(T: typedesc) =
  ## Compile-time check: verifies T provides ``filterType`` and a
  ## ``toJson`` overload on its filter condition type, in addition to
  ## the base framework overloads. Call after ``registerJmapEntity`` for
  ## entity types that support /query and /queryChanges.
  ##
  ## The filter condition's ``toJson`` is resolved via ``mixin`` at the
  ## builder's instantiation site (``addQuery`` / ``addQueryChanges``).
  static:
    when not compiles(filterType(T)):
      {.
        error:
          "registerQueryableEntity: " & $T &
          " is missing `template filterType*(T: typedesc[" & $T & "]): typedesc`"
      .}
    when not compiles(toJson(default(filterType(T)))):
      {.
        error:
          "registerQueryableEntity: " & $T & " is missing `func toJson*(c: " &
          $filterType(T) & "): JsonNode`"
      .}
