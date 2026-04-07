# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Thread entity (RFC 8621 section 3).

{.push raises: [].}

import std/json

import ../serde
import ../types
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
    T: typedesc[thread.Thread], node: JsonNode
): Result[thread.Thread, ValidationError] =
  ## Deserialise JSON object to Thread. Rejects absent, null, or wrong-type
  ## fields. Delegates to parseThread which enforces non-empty emailIds.
  ?checkJsonKind(node, JObject, "Thread")
  let id = ?Id.fromJson(node{"id"})
  let emailIdsNode = node{"emailIds"}
  ?checkJsonKind(emailIdsNode, JArray, "Thread", "missing or invalid emailIds")
  var emailIds: seq[Id] = @[]
  for elem in emailIdsNode.getElems(@[]):
    let eid = ?Id.fromJson(elem)
    emailIds.add(eid)
  return parseThread(id, emailIds)
