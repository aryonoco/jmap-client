# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Keyword and KeywordSet (RFC 8621 §4.1.1).
## Keywords serialise as JSON strings. KeywordSet serialises as a JSON object
## mapping keyword strings to ``true`` (RFC 8621 patch-object pattern).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/sets

import ../serialisation/serde
import ../../types
import ./keyword

defineDistinctStringToJson(Keyword)
defineDistinctStringFromJson(Keyword, parseKeywordFromServer)

func toJson*(ks: KeywordSet): JsonNode =
  ## Serialise KeywordSet as ``{"keyword": true, ...}``. Empty set yields ``{}``.
  var node = newJObject()
  for kw in ks:
    node[$kw] = newJBool(true)
  return node

func fromJson*(
    T: typedesc[KeywordSet], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[T, SerdeViolation] =
  ## Deserialise ``{"keyword": true, ...}`` to KeywordSet. Rejects non-object,
  ## non-boolean values, and explicit ``false``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  var hs = initHashSet[Keyword](node.len)
  for key, val in node.pairs:
    if val.kind != JBool:
      return err(
        SerdeViolation(
          kind: svkWrongKind,
          path: path / key,
          expectedKind: JBool,
          actualKind: val.kind,
        )
      )
    if not val.getBool(false):
      return err(
        SerdeViolation(
          kind: svkEnumNotRecognised,
          path: path / key,
          enumTypeLabel: "keyword value",
          rawValue: "false",
        )
      )
    let kw = ?wrapInner(parseKeywordFromServer(key), path / key)
    hs.incl(kw)
  return ok(KeywordSet(hs))
