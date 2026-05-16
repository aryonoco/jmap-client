# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Diagnostic helpers for the L2 serde railway: empty-path constructor,
## RFC 6901 reference-token escaping, and the SerdeViolation →
## ValidationError translator that runs at the L3/L4 boundary.
##
## L2-private. Reach from in-tree callers via direct H10 import.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/strutils

import ../types
import ./serde

func emptyJsonPath*(): JsonPath =
  ## The empty RFC 6901 pointer — references the root of the document.
  return JsonPath(rawValue: @[])

func jsonPointerEscape*(s: string): string =
  ## RFC 6901 §3 reference-token escaping. ``~`` MUST be escaped first:
  ## escaping ``/`` first would produce ``~1`` that a second pass would
  ## re-escape into ``~01``, corrupting tokens containing ``/``.
  return s.replace("~", "~0").replace("/", "~1")

func toValidationError*(v: SerdeViolation, rootType: string): ValidationError =
  ## Translate a structured violation to the wire ``ValidationError``
  ## shape. The suffix ``" at <rfc-6901-pointer>"`` is appended when the
  ## path is non-empty. For ``svkFieldParserFailed`` the inner
  ## ``typeName`` and ``value`` are preserved verbatim; otherwise
  ## ``rootType`` is used.
  let pathStr = $v.path
  let suffix =
    if pathStr.len == 0:
      ""
    else:
      " at " & pathStr
  case v.kind
  of svkWrongKind:
    return validationError(
      rootType, "expected " & $v.expectedKind & ", got " & $v.actualKind & suffix, ""
    )
  of svkNilNode:
    return validationError(
      rootType, "expected " & $v.expectedKindForNil & ", got nil" & suffix, ""
    )
  of svkMissingField:
    return
      validationError(rootType, "missing field: " & v.missingFieldName & suffix, "")
  of svkEmptyRequired:
    return
      validationError(rootType, v.emptyFieldLabel & " must not be empty" & suffix, "")
  of svkArrayLength:
    return validationError(
      rootType,
      "expected " & $v.expectedLen & " elements, got " & $v.actualLen & suffix,
      "",
    )
  of svkFieldParserFailed:
    return validationError(v.inner.typeName, v.inner.message & suffix, v.inner.value)
  of svkConflictingFields:
    return validationError(
      rootType,
      "cannot specify both " & v.conflictKeyA & " and " & v.conflictKeyB & " (" &
        v.conflictRule & ")" & suffix,
      "",
    )
  of svkEnumNotRecognised:
    return validationError(
      rootType, "unknown " & v.enumTypeLabel & ": " & v.rawValue & suffix, v.rawValue
    )
  of svkDepthExceeded:
    return validationError(
      rootType, "maximum nesting depth (" & $v.maxDepth & ") exceeded" & suffix, ""
    )
