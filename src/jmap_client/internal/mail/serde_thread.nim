# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Thread entity (RFC 8621 section 3).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../serialisation/serde_field_echo
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

# =============================================================================
# PartialThread (A3.6) — Thread has no /set per RFC 8621 §3, partial is
# sparse /get only. PartialThread mirrors Thread's private-fields-plus-
# accessors shape (D8) for structural symmetry.
# =============================================================================

func fromJson*(
    T: typedesc[PartialThread], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[PartialThread, SerdeViolation] =
  ## Deserialise a partial Thread echo (RFC 8621 §3). Lenient on missing
  ## fields. ``rawId`` and ``rawEmailIds`` are module-private — accessor
  ## funcs ``id`` and ``emailIds`` provide read access (D8).
  discard $T
  ?expectKind(node, JObject, path)
  let id = ?parsePartialOptField[Id](node, "id", path)
  let emailIds = ?parsePartialOptField[seq[Id]](node, "emailIds", path)
  return ok(initPartialThread(id, emailIds))

func toJson*(p: PartialThread): JsonNode =
  ## Emit a partial Thread echo — D3.7 unidirectional serde symmetry.
  ## ``Opt.none`` omits the key entirely.
  var node = newJObject()
  for v in p.id:
    node["id"] = v.toJson()
  for v in p.emailIds:
    node["emailIds"] = v.toJson()
  return node
