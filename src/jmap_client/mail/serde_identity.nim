# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Identity entity (RFC 8621 section 6).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

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
    node: JsonNode, key: string, path: JsonPath
): Result[string, SerdeViolation] =
  ## Parse a string field that defaults to "" on absent or null.
  ## Rejects non-string values.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok("")
  ?expectKind(field, JString, path / key)
  return ok(field.getStr(""))

func parseOptEmailAddresses(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[seq[EmailAddress]], SerdeViolation] =
  ## Parse an optional array of email addresses. Absent or null yields Opt.none;
  ## JArray yields Opt.some with parsed elements; other types rejected.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(seq[EmailAddress]))
  ?expectKind(field, JArray, path / key)
  var addrs: seq[EmailAddress] = @[]
  for i, elem in field.getElems(@[]):
    let ea = ?EmailAddress.fromJson(elem, path / key / i)
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
    T: typedesc[Identity], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Identity, SerdeViolation] =
  ## Deserialise JSON object to Identity. Rejects absent or wrong-type required
  ## fields. Absent name/textSignature/htmlSignature default to "".
  ## Absent or null replyTo/bcc default to Opt.none.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  # RFC 8621 §6.1 ``Identity.email`` is a ``String`` — no MUST-non-empty
  # constraint. Cyrus 3.12.2 emits an empty ``email`` for server-default
  # identities (config-derived, no explicit address); Stalwart and James
  # populate it with the user's primary address. Postel-receive: accept
  # any string the server sends. Client-construction validation lives in
  # ``parseIdentityCreate`` (smart constructor), not here.
  let emailNode = ?fieldJString(node, "email", path)
  let email = emailNode.getStr("")
  let name = ?parseDefaultingString(node, "name", path)
  let replyTo = ?parseOptEmailAddresses(node, "replyTo", path)
  let bcc = ?parseOptEmailAddresses(node, "bcc", path)
  let textSignature = ?parseDefaultingString(node, "textSignature", path)
  let htmlSignature = ?parseDefaultingString(node, "htmlSignature", path)
  let mayDeleteNode = ?fieldJBool(node, "mayDelete", path)
  let mayDelete = mayDeleteNode.getBool(false)
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

# =============================================================================
# IdentityCreatedItem — Identity/set ``created[cid]`` payload (RFC 8620 §5.3)
# =============================================================================

func toJson*(item: IdentityCreatedItem): JsonNode =
  ## Serialise IdentityCreatedItem to JSON. Emits ``id`` always; ``mayDelete``
  ## only when present (round-trips Stalwart's elision symmetrically).
  var node = newJObject()
  node["id"] = item.id.toJson()
  for v in item.mayDelete:
    node["mayDelete"] = %v
  return node

func fromJson*(
    T: typedesc[IdentityCreatedItem], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[IdentityCreatedItem, SerdeViolation] =
  ## Deserialise the partial Identity payload sent in Identity/set
  ## ``created[cid]``. ``id`` is required (RFC 8620 §5.3); ``mayDelete`` is
  ## ``Opt`` because Stalwart 0.15.5 omits it (strict-RFC minor divergence,
  ## accommodated here per Postel's law). Other Identity fields are not
  ## expected in this payload — the client already sent them in ``create``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let mayDeleteField = node{"mayDelete"}
  var mayDelete = Opt.none(bool)
  if not mayDeleteField.isNil and mayDeleteField.kind != JNull:
    ?expectKind(mayDeleteField, JBool, path / "mayDelete")
    mayDelete = Opt.some(mayDeleteField.getBool(false))
  return ok(IdentityCreatedItem(id: id, mayDelete: mayDelete))
