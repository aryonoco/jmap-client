# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for email address sub-types (RFC 8621 section 4.1.2.3-4).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../../types
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
    T: typedesc[EmailAddress], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailAddress, SerdeViolation] =
  ## Deserialise JSON object to EmailAddress. Rejects absent or non-string email.
  ## Absent or null name maps to Opt.none.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let emailNode = ?fieldJString(node, "email", path)
  let email = emailNode.getStr("")
  let name = block:
    let nameField = optJsonField(node, "name", JString)
    if nameField.isSome:
      Opt.some(nameField.get().getStr(""))
    else:
      Opt.none(string)
  return wrapInner(parseEmailAddress(email, name), path)

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
    T: typedesc[EmailAddressGroup], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailAddressGroup, SerdeViolation] =
  ## Deserialise JSON object to EmailAddressGroup. Rejects absent or non-array
  ## addresses. Short-circuits on first invalid element.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let name = block:
    let nameField = optJsonField(node, "name", JString)
    if nameField.isSome:
      Opt.some(nameField.get().getStr(""))
    else:
      Opt.none(string)
  let addrsNode = ?fieldJArray(node, "addresses", path)
  var addrs: seq[EmailAddress] = @[]
  for i, elem in addrsNode.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem, path / "addresses" / i)
    addrs.add(ea)
  return ok(EmailAddressGroup(name: name, addresses: addrs))
