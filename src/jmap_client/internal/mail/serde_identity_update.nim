# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for IdentityUpdate, IdentityUpdateSet, and
## NonEmptyIdentityUpdates (RFC 8621 §6 /set update algebra). Flattens the
## typed ADT to an RFC 8620 §5.3 wire patch. Send-side only — creation
## types admit no ``fromJson`` per the Postel-strict construction rule.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types
import ./addresses
import ./identity
import ./serde_addresses

func emitOptEmailAddresses(opt: Opt[seq[EmailAddress]]): JsonNode =
  ## Match ``serde_identity``'s ``replyTo`` / ``bcc`` emission exactly —
  ## ``Opt.none`` projects to JSON null, ``Opt.some`` projects to a JSON
  ## array. RFC 8621 §6 treats null as the "clear the default list"
  ## signal on the patch path.
  for addrs in opt:
    var arr = newJArray()
    for ea in addrs:
      arr.add(ea.toJson())
    return arr
  return newJNull()

func toJson*(u: IdentityUpdate): (string, JsonNode) =
  ## Emit one ``(wireKey, wireValue)`` pair. RFC 8621 §6 property names
  ## match Identity field names verbatim — no JSON Pointer escaping
  ## because all keys are simple identifiers outside the RFC 6901 reserved
  ## charset.
  case u.kind
  of iuSetName:
    ("name", %u.name)
  of iuSetReplyTo:
    ("replyTo", emitOptEmailAddresses(u.replyTo))
  of iuSetBcc:
    ("bcc", emitOptEmailAddresses(u.bcc))
  of iuSetTextSignature:
    ("textSignature", %u.textSignature)
  of iuSetHtmlSignature:
    ("htmlSignature", %u.htmlSignature)

func toJson*(us: IdentityUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initIdentityUpdateSet`` has already rejected duplicate target
  ## properties, so blind aggregation here cannot shadow a prior entry.
  var node = newJObject()
  for u in us.toSeq:
    let (k, v) = u.toJson()
    node[k] = v
  return node

func toJson*(upd: NonEmptyIdentityUpdates): JsonNode =
  ## Flatten the whole-container update algebra to the RFC 8620 §5.3
  ## wire ``update`` value — ``{identityId: patchObj, ...}``.
  ## ``parseNonEmptyIdentityUpdates`` has already enforced non-empty
  ## input and distinct ids.
  var node = newJObject()
  for id, patchSet in upd.toTable:
    node[$id] = patchSet.toJson()
  return node
