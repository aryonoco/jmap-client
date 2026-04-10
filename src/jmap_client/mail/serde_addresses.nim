# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for email address sub-types (RFC 8621 section 4.1.2.3-4).

{.push raises: [], noSideEffect.}

import std/json

import ../serde
import ../types
import ./addresses

# =============================================================================
# EmailAddress
# =============================================================================

func toJson*(ea: EmailAddress): JsonNode =
  ## Serialise EmailAddress to JSON. Name emitted as string or null.
  var node = newJObject()
  for name in ea.name:
    node["name"] = %name
  if ea.name.isNone:
    node["name"] = newJNull()
  node["email"] = %ea.email
  return node

func fromJson*(
    T: typedesc[EmailAddress], node: JsonNode
): Result[EmailAddress, ValidationError] =
  ## Deserialise JSON object to EmailAddress. Rejects absent or non-string email.
  ## Absent or null name maps to Opt.none.
  ?checkJsonKind(node, JObject, $T)
  let emailNode = node{"email"}
  ?checkJsonKind(emailNode, JString, $T, "missing or invalid email")
  let email = emailNode.getStr("")
  let name = block:
    let nameField = optJsonField(node, "name", JString)
    if nameField.isSome:
      Opt.some(nameField.get().getStr(""))
    else:
      Opt.none(string)
  return parseEmailAddress(email, name)

# =============================================================================
# EmailAddressGroup
# =============================================================================

func toJson*(group: EmailAddressGroup): JsonNode =
  ## Serialise EmailAddressGroup to JSON. Name emitted as string or null.
  var node = newJObject()
  for name in group.name:
    node["name"] = %name
  if group.name.isNone:
    node["name"] = newJNull()
  var arr = newJArray()
  for ea in group.addresses:
    arr.add(ea.toJson())
  node["addresses"] = arr
  return node

func fromJson*(
    T: typedesc[EmailAddressGroup], node: JsonNode
): Result[EmailAddressGroup, ValidationError] =
  ## Deserialise JSON object to EmailAddressGroup. Rejects absent or non-array
  ## addresses. Short-circuits on first invalid element.
  ?checkJsonKind(node, JObject, $T)
  let name = block:
    let nameField = optJsonField(node, "name", JString)
    if nameField.isSome:
      Opt.some(nameField.get().getStr(""))
    else:
      Opt.none(string)
  let addrsNode = node{"addresses"}
  ?checkJsonKind(addrsNode, JArray, $T, "missing or invalid addresses")
  var addrs: seq[EmailAddress] = @[]
  for elem in addrsNode.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem)
    addrs.add(ea)
  return ok(EmailAddressGroup(name: name, addresses: addrs))
