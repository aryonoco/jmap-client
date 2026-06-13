# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Diagnostic ADTs — `SerdeViolation` (structured deserialisation
## error) and `JsonPath` (RFC 6901 pointer). Consumed by every
## `fromJson` site in L2 and projected to `TransportError.message` at
## the L3/L4 boundary via `toValidationError` (in `serde_diagnostics`).
##
## L2-private. Adding a `SerdeViolationKind` variant forces a compile
## error in `serde_diagnostics.toValidationError` — the single
## SerdeViolation → ValidationError translator.
##
## The 3 `{.ruleOff: "objects".}` pragmas on `JsonPathElement`,
## `JsonPath`, and `SerdeViolation` stay: these are inspection-shape
## types — public-field-by-design within L2 — and the sealed-distinct
## H1 lint correctly distinguishes them from data-carrying records.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../types

type JsonPathElementKind* = enum
  ## Discriminator for ``JsonPathElement`` — a path segment is either a
  ## named object key or a zero-based array index.
  jpeKey
  jpeIndex

type JsonPathElement* {.ruleOff: "objects".} = object
  ## One segment of a ``JsonPath``. Discriminated so indices and escaped
  ## keys remain distinguishable throughout composition.
  case kind*: JsonPathElementKind
  of jpeKey:
    key*: string
  of jpeIndex:
    idx*: int

type JsonPath* {.ruleOff: "objects".} = object
  ## Ordered, immutable path of object keys and array indices — rendered
  ## as an RFC 6901 JSON Pointer string by ``$``. Composed left-to-right
  ## via the ``/`` operator as a ``fromJson`` descends the wire tree.
  ## Inspection-shape: ``rawValue`` is L2-public so sibling diagnostic
  ## modules (``serde_diagnostics``) can construct the empty pointer.
  rawValue*: seq[JsonPathElement]

func `/`*(p: JsonPath, key: string): JsonPath =
  ## Extend the path with a named object key. Produces a fresh path;
  ## ``p`` is unchanged.
  return JsonPath(rawValue: p.rawValue & @[JsonPathElement(kind: jpeKey, key: key)])

func `/`*(p: JsonPath, idx: int): JsonPath =
  ## Extend the path with a zero-based array index. Produces a fresh
  ## path; ``p`` is unchanged.
  return JsonPath(rawValue: p.rawValue & @[JsonPathElement(kind: jpeIndex, idx: idx)])

func `$`*(p: JsonPath): string =
  ## Render as an RFC 6901 JSON Pointer string. The empty path renders
  ## as ``""`` (references the whole document); otherwise each segment
  ## contributes a leading ``/`` plus the escaped token or the index.
  result = ""
  for elem in p.rawValue:
    case elem.kind
    of jpeKey:
      # RFC 6901 §3 reference-token escaping inlined: ``~`` first so a
      # later ``/`` → ``~1`` cannot be re-escaped into ``~01``.
      var escaped = newStringOfCap(elem.key.len)
      for c in elem.key:
        if c == '~':
          escaped.add("~0")
        elif c == '/':
          escaped.add("~1")
        else:
          escaped.add(c)
      result.add("/" & escaped)
    of jpeIndex:
      result.add("/" & $elem.idx)

type SerdeViolationKind* = enum
  ## Enumerates the structural deserialisation-failure modes. Each variant
  ## corresponds to exactly one ``of`` arm in ``SerdeViolation``; adding a
  ## kind here forces a compile error in ``toValidationError``.
  svkWrongKind ## Node present but the wrong ``JsonNodeKind``.
  svkNilNode ## Node absent where one was required (top-level only).
  svkMissingField ## Required object field not present.
  svkEmptyRequired ## Wire-boundary non-empty invariant violated.
  svkArrayLength ## Array had the wrong number of elements.
  svkFieldParserFailed ## An inner smart constructor rejected the value.
  svkConflictingFields ## Two mutually-exclusive fields both present.
  svkEnumNotRecognised ## Token outside the enum's accepted set.
  svkDepthExceeded ## Recursive nesting exceeded the stack-safety cap.

type SerdeViolation* {.ruleOff: "objects".} = object
  ## Structured deserialisation error. The ``path`` locates the violation
  ## inside the wire tree (RFC 6901); the variant carries the detail.
  path*: JsonPath
  case kind*: SerdeViolationKind
  of svkWrongKind:
    expectedKind*: JsonNodeKind
    actualKind*: JsonNodeKind
  of svkNilNode:
    expectedKindForNil*: JsonNodeKind
  of svkMissingField:
    missingFieldName*: string
  of svkEmptyRequired:
    emptyFieldLabel*: string
  of svkArrayLength:
    expectedLen*: int
    actualLen*: int
  of svkFieldParserFailed:
    inner*: ValidationError
  of svkConflictingFields:
    conflictKeyA*: string
    conflictKeyB*: string
    conflictRule*: string
  of svkEnumNotRecognised:
    enumTypeLabel*: string
    rawValue*: string
  of svkDepthExceeded:
    maxDepth*: int
