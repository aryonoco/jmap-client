# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Thread entity (RFC 8621 section 3).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../../types
import ./thread

# =============================================================================
# Thread
# =============================================================================

func toJson*(t: thread.Thread): JsonNode =
  ## Serialise Thread to JSON. Emits id and emailIds array.
  var node = newJObject()
  node["id"] = t.id.toJson()
  var arr = newJArray()
  for eid in t.emailIds:
    arr.add(eid.toJson())
  node["emailIds"] = arr
  return node

func fromJson*(
    T: typedesc[thread.Thread], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[thread.Thread, SerdeViolation] =
  ## Deserialise JSON object to Thread. Rejects absent, null, or wrong-type
  ## fields. Delegates to parseThread which enforces non-empty emailIds.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let emailIdsNode = ?fieldJArray(node, "emailIds", path)
  var emailIds: seq[Id] = @[]
  for i, elem in emailIdsNode.getElems(@[]):
    let eid = ?Id.fromJson(elem, path / "emailIds" / i)
    emailIds.add(eid)
  return wrapInner(parseThread(id, emailIds), path)
