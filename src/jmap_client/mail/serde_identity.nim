# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Identity entity (RFC 8621 section 6).

{.push raises: [], noSideEffect.}

import std/json

import ../serde
import ../types
import ./addresses
import ./identity
import ./serde_addresses

# =============================================================================
# Helpers
# =============================================================================

func parseDefaultingString(
    node: JsonNode, key: string
): Result[string, ValidationError] =
  ## Parse a string field that defaults to "" on absent or null.
  ## Rejects non-string values.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok("")
  ?checkJsonKind(field, JString, "Identity", key & " must be string")
  return ok(field.getStr(""))

func parseOptEmailAddresses(
    node: JsonNode, key: string
): Result[Opt[seq[EmailAddress]], ValidationError] =
  ## Parse an optional array of email addresses. Absent or null yields Opt.none;
  ## JArray yields Opt.some with parsed elements; other types rejected.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[EmailAddress]))
  ?checkJsonKind(field, JArray, "Identity", key & " must be array or null")
  var addrs: seq[EmailAddress] = @[]
  for elem in field.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem)
    addrs.add(ea)
  return ok(Opt.some(addrs))

# =============================================================================
# Identity
# =============================================================================

func toJson*(ident: Identity): JsonNode =
  ## Serialise Identity to JSON. All fields emitted; replyTo/bcc as array or null.
  var node = newJObject()
  node["id"] = ident.id.toJson()
  node["name"] = %ident.name
  node["email"] = %ident.email
  for addrs in ident.replyTo:
    var arr = newJArray()
    for ea in addrs:
      arr.add(ea.toJson())
    node["replyTo"] = arr
  if ident.replyTo.isNone:
    node["replyTo"] = newJNull()
  for addrs in ident.bcc:
    var arr = newJArray()
    for ea in addrs:
      arr.add(ea.toJson())
    node["bcc"] = arr
  if ident.bcc.isNone:
    node["bcc"] = newJNull()
  node["textSignature"] = %ident.textSignature
  node["htmlSignature"] = %ident.htmlSignature
  node["mayDelete"] = %ident.mayDelete
  return node

func fromJson*(
    T: typedesc[Identity], node: JsonNode
): Result[Identity, ValidationError] =
  ## Deserialise JSON object to Identity. Rejects absent or wrong-type required
  ## fields. Absent name/textSignature/htmlSignature default to "".
  ## Absent or null replyTo/bcc default to Opt.none.
  ?checkJsonKind(node, JObject, "Identity")
  let id = ?Id.fromJson(node{"id"})
  ?checkJsonKind(node{"email"}, JString, "Identity", "missing or invalid email")
  let email = node{"email"}.getStr("")
  if email.len == 0:
    return err(parseError("Identity", "email must not be empty"))
  let name = ?parseDefaultingString(node, "name")
  let replyTo = ?parseOptEmailAddresses(node, "replyTo")
  let bcc = ?parseOptEmailAddresses(node, "bcc")
  let textSignature = ?parseDefaultingString(node, "textSignature")
  let htmlSignature = ?parseDefaultingString(node, "htmlSignature")
  ?checkJsonKind(node{"mayDelete"}, JBool, "Identity", "missing or invalid mayDelete")
  let mayDelete = node{"mayDelete"}.getBool(false)
  return ok(
    Identity(
      id: id,
      name: name,
      email: email,
      replyTo: replyTo,
      bcc: bcc,
      textSignature: textSignature,
      htmlSignature: htmlSignature,
      mayDelete: mayDelete,
    )
  )

# =============================================================================
# IdentityCreate
# =============================================================================

func toJson*(ic: IdentityCreate): JsonNode =
  ## Serialise IdentityCreate to JSON. Emits all 6 fields (no id or mayDelete).
  var node = newJObject()
  node["email"] = %ic.email
  node["name"] = %ic.name
  for addrs in ic.replyTo:
    var arr = newJArray()
    for ea in addrs:
      arr.add(ea.toJson())
    node["replyTo"] = arr
  if ic.replyTo.isNone:
    node["replyTo"] = newJNull()
  for addrs in ic.bcc:
    var arr = newJArray()
    for ea in addrs:
      arr.add(ea.toJson())
    node["bcc"] = arr
  if ic.bcc.isNone:
    node["bcc"] = newJNull()
  node["textSignature"] = %ic.textSignature
  node["htmlSignature"] = %ic.htmlSignature
  return node
