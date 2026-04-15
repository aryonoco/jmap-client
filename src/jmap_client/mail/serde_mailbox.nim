# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for Mailbox entity and supporting types (RFC 8621 §2).
## MailboxCreate is toJson-only — creation models flow client-to-server only.

{.push raises: [], noSideEffect.}

import std/json
import std/sets

import ../serde
import ../types
import ./mailbox

# =============================================================================
# MailboxRole
# =============================================================================

defineDistinctStringToJson(MailboxRole)
defineDistinctStringFromJson(MailboxRole, parseMailboxRole)

# =============================================================================
# Helpers
# =============================================================================

func parseBoolField(
    node: JsonNode, key, typeName: string
): Result[bool, ValidationError] =
  ## Extracts a required boolean field, returning ValidationError if absent or non-bool.
  ?checkJsonKind(node{key}, JBool, typeName, "missing or invalid " & key)
  return ok(node{key}.getBool(false))

func parseOptId(node: JsonNode, key: string): Result[Opt[Id], ValidationError] =
  ## Extracts an optional Id field: nil/JNull yields Opt.none, otherwise parses via Id.fromJson.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(Id))
  return ok(Opt.some(?Id.fromJson(field)))

func parseOptMailboxRole(
    node: JsonNode, key: string
): Result[Opt[MailboxRole], ValidationError] =
  ## Extracts an optional MailboxRole field: nil/JNull yields Opt.none, otherwise parses via MailboxRole.fromJson.
  let field = node{key}
  if field.isNil or field.kind == JNull:
    return ok(Opt.none(MailboxRole))
  return ok(Opt.some(?MailboxRole.fromJson(field)))

# =============================================================================
# MailboxIdSet
# =============================================================================

func toJson*(ms: MailboxIdSet): JsonNode =
  ## Serialise MailboxIdSet as ``{"id": true, ...}``. Empty set yields ``{}``.
  var node = newJObject()
  for id in ms:
    node[$id] = newJBool(true)
  return node

func fromJson*(T: typedesc[MailboxIdSet], node: JsonNode): Result[T, ValidationError] =
  ## Deserialise ``{"id": true, ...}`` to MailboxIdSet. Rejects non-object,
  ## non-boolean values, and explicit ``false``.
  ?checkJsonKind(node, JObject, $T)
  var hs = initHashSet[Id](node.len)
  for key, val in node.pairs:
    if val.kind != JBool or not val.getBool(false):
      return err(validationError($T, "all mailbox id values must be true", key))
    let id = ?parseIdFromServer(key)
    hs.incl(id)
  return ok(MailboxIdSet(hs))

# =============================================================================
# NonEmptyMailboxIdSet (Part E §4.2)
# =============================================================================
# Creation-context distinct HashSet: toJson-only per R1-3. The non-empty
# invariant is guaranteed by ``parseNonEmptyMailboxIdSet`` at construction;
# the serialiser simply projects the backing set onto the ``{id: true, ...}``
# wire shape — identical to ``MailboxIdSet`` but retyped at the signature.

func toJson*(ms: NonEmptyMailboxIdSet): JsonNode =
  ## Serialise NonEmptyMailboxIdSet as ``{"id": true, ...}``. Wire shape
  ## matches ``MailboxIdSet``; the non-empty invariant is enforced at
  ## construction, not here.
  var node = newJObject()
  for id in ms:
    node[$id] = newJBool(true)
  return node

# =============================================================================
# MailboxRights
# =============================================================================

func toJson*(mr: MailboxRights): JsonNode =
  ## Serialise MailboxRights to JSON with all 9 boolean fields.
  var node = newJObject()
  node["mayReadItems"] = %mr.mayReadItems
  node["mayAddItems"] = %mr.mayAddItems
  node["mayRemoveItems"] = %mr.mayRemoveItems
  node["maySetSeen"] = %mr.maySetSeen
  node["maySetKeywords"] = %mr.maySetKeywords
  node["mayCreateChild"] = %mr.mayCreateChild
  node["mayRename"] = %mr.mayRename
  node["mayDelete"] = %mr.mayDelete
  node["maySubmit"] = %mr.maySubmit
  return node

func fromJson*(
    T: typedesc[MailboxRights], node: JsonNode
): Result[MailboxRights, ValidationError] =
  ## Deserialise JSON object to MailboxRights. All 9 boolean fields are required.
  ?checkJsonKind(node, JObject, $T)
  let mayReadItems = ?parseBoolField(node, "mayReadItems", "MailboxRights")
  let mayAddItems = ?parseBoolField(node, "mayAddItems", "MailboxRights")
  let mayRemoveItems = ?parseBoolField(node, "mayRemoveItems", "MailboxRights")
  let maySetSeen = ?parseBoolField(node, "maySetSeen", "MailboxRights")
  let maySetKeywords = ?parseBoolField(node, "maySetKeywords", "MailboxRights")
  let mayCreateChild = ?parseBoolField(node, "mayCreateChild", "MailboxRights")
  let mayRename = ?parseBoolField(node, "mayRename", "MailboxRights")
  let mayDelete = ?parseBoolField(node, "mayDelete", "MailboxRights")
  let maySubmit = ?parseBoolField(node, "maySubmit", "MailboxRights")
  return ok(
    MailboxRights(
      mayReadItems: mayReadItems,
      mayAddItems: mayAddItems,
      mayRemoveItems: mayRemoveItems,
      maySetSeen: maySetSeen,
      maySetKeywords: maySetKeywords,
      mayCreateChild: mayCreateChild,
      mayRename: mayRename,
      mayDelete: mayDelete,
      maySubmit: maySubmit,
    )
  )

# =============================================================================
# Mailbox
# =============================================================================

func toJson*(mbx: Mailbox): JsonNode =
  ## Serialise Mailbox to JSON. All fields emitted; parentId/role as value or null.
  var node = newJObject()
  node["id"] = mbx.id.toJson()
  node["name"] = %mbx.name
  for pid in mbx.parentId:
    node["parentId"] = pid.toJson()
  if mbx.parentId.isNone:
    node["parentId"] = newJNull()
  for r in mbx.role:
    node["role"] = r.toJson()
  if mbx.role.isNone:
    node["role"] = newJNull()
  node["sortOrder"] = mbx.sortOrder.toJson()
  node["totalEmails"] = mbx.totalEmails.toJson()
  node["unreadEmails"] = mbx.unreadEmails.toJson()
  node["totalThreads"] = mbx.totalThreads.toJson()
  node["unreadThreads"] = mbx.unreadThreads.toJson()
  node["myRights"] = mbx.myRights.toJson()
  node["isSubscribed"] = %mbx.isSubscribed
  return node

func fromJson*(T: typedesc[Mailbox], node: JsonNode): Result[Mailbox, ValidationError] =
  ## Deserialise JSON object to Mailbox. Validates all required fields.
  ## Rejects absent, null, or empty name. Absent or null parentId/role
  ## yield Opt.none.
  ?checkJsonKind(node, JObject, $T)
  let id = ?Id.fromJson(node{"id"})
  ?checkJsonKind(node{"name"}, JString, $T, "missing or invalid name")
  let name = node{"name"}.getStr("")
  if name.len == 0:
    return err(parseError($T, "name must not be empty"))
  let parentId = ?parseOptId(node, "parentId")
  let role = ?parseOptMailboxRole(node, "role")
  let sortOrder = ?UnsignedInt.fromJson(node{"sortOrder"})
  let totalEmails = ?UnsignedInt.fromJson(node{"totalEmails"})
  let unreadEmails = ?UnsignedInt.fromJson(node{"unreadEmails"})
  let totalThreads = ?UnsignedInt.fromJson(node{"totalThreads"})
  let unreadThreads = ?UnsignedInt.fromJson(node{"unreadThreads"})
  let myRights = ?MailboxRights.fromJson(node{"myRights"})
  let isSubscribed = ?parseBoolField(node, "isSubscribed", "Mailbox")
  return ok(
    Mailbox(
      id: id,
      name: name,
      parentId: parentId,
      role: role,
      sortOrder: sortOrder,
      totalEmails: totalEmails,
      unreadEmails: unreadEmails,
      totalThreads: totalThreads,
      unreadThreads: unreadThreads,
      myRights: myRights,
      isSubscribed: isSubscribed,
    )
  )

# =============================================================================
# MailboxCreate
# =============================================================================

func toJson*(mc: MailboxCreate): JsonNode =
  ## Serialise MailboxCreate to JSON. Emits all 5 fields (no server-set fields).
  ## parentId/role emit as value or null.
  var node = newJObject()
  node["name"] = %mc.name
  for pid in mc.parentId:
    node["parentId"] = pid.toJson()
  if mc.parentId.isNone:
    node["parentId"] = newJNull()
  for r in mc.role:
    node["role"] = r.toJson()
  if mc.role.isNone:
    node["role"] = newJNull()
  node["sortOrder"] = mc.sortOrder.toJson()
  node["isSubscribed"] = %mc.isSubscribed
  return node

# =============================================================================
# MailboxUpdate
# =============================================================================

func toJson*(u: MailboxUpdate): (string, JsonNode) =
  ## Emit the ``(wire-key, wire-value)`` pair for a single Mailbox update.
  ## RFC 8621 §2 settable Mailbox properties are whole-value replace — each
  ## variant maps to exactly one top-level property, no sub-path flattening.
  case u.kind
  of muSetName:
    ("name", %u.name)
  of muSetParentId:
    ("parentId", u.parentId.optToJsonOrNull())
  of muSetRole:
    ("role", u.role.optToJsonOrNull())
  of muSetSortOrder:
    ("sortOrder", u.sortOrder.toJson())
  of muSetIsSubscribed:
    ("isSubscribed", %u.isSubscribed)

func toJson*(us: MailboxUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initMailboxUpdateSet`` has already rejected duplicate target
  ## properties, so blind aggregation cannot shadow a prior entry.
  var node = newJObject()
  for u in seq[MailboxUpdate](us):
    let (key, value) = u.toJson()
    node[key] = value
  return node
