# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Keyword and KeywordSet (RFC 8621 §4.1.1).
## Keywords serialise as JSON strings. KeywordSet serialises as a JSON object
## mapping keyword strings to ``true`` (RFC 8621 patch-object pattern).

{.push raises: [], noSideEffect.}

import std/json
import std/sets

import ../serde
import ../types
import ./keyword

defineDistinctStringToJson(Keyword)
defineDistinctStringFromJson(Keyword, parseKeywordFromServer)

func toJson*(ks: KeywordSet): JsonNode =
  ## Serialise KeywordSet as ``{"keyword": true, ...}``. Empty set yields ``{}``.
  var node = newJObject()
  for kw in ks:
    node[$kw] = newJBool(true)
  return node

func fromJson*(T: typedesc[KeywordSet], node: JsonNode): Result[T, ValidationError] =
  ## Deserialise ``{"keyword": true, ...}`` to KeywordSet. Rejects non-object,
  ## non-boolean values, and explicit ``false``.
  ?checkJsonKind(node, JObject, $T)
  var hs = initHashSet[Keyword](node.len)
  for key, val in node.pairs:
    if val.kind != JBool or not val.getBool(false):
      return err(validationError($T, "all keyword values must be true", key))
    let kw = ?parseKeywordFromServer(key)
    hs.incl(kw)
  return ok(KeywordSet(hs))
