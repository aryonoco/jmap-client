# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for SearchSnippet (RFC 8621 §5).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_helpers
import ../serialisation/serde_primitives
import ../types
import ./snippet

func searchSnippetFromJson*(
    node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SearchSnippet, SerdeViolation] =
  ## Deserialises a SearchSnippet from server JSON.
  ## ``emailId`` is required; ``subject`` and ``preview`` are optional
  ## (absent/null yields ``Opt.none``).
  ?expectKind(node, JObject, path)
  let emailIdNode = ?fieldJString(node, "emailId", path)
  let emailId = ?Id.fromJson(emailIdNode, path / "emailId")
  let subject = block:
    let f = optJsonField(node, "subject", JString)
    if f.isSome:
      Opt.some(f.get().getStr(""))
    else:
      Opt.none(string)
  let preview = block:
    let f = optJsonField(node, "preview", JString)
    if f.isSome:
      Opt.some(f.get().getStr(""))
    else:
      Opt.none(string)
  ok(SearchSnippet(emailId: emailId, subject: subject, preview: preview))

func toJson*(ss: SearchSnippet): JsonNode =
  ## Serialise SearchSnippet to JSON. Emits all fields always (D5):
  ## ``Opt.none`` emits null.
  var node = newJObject()
  node["emailId"] = ss.emailId.toJson()
  node["subject"] = ss.subject.optStringToJsonOrNull()
  node["preview"] = ss.preview.optStringToJsonOrNull()
  return node
