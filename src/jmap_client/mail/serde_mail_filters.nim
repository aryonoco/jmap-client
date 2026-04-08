# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for MailboxFilterCondition (RFC 8621 §2.3).
## toJson only — filter conditions flow client-to-server only (Decision B11).

{.push raises: [].}

import std/json

import ../serde
import ../types
import ./mailbox
import ./mail_filters
import ./serde_mailbox

func emitThreeState[T](node: JsonNode, key: string, opt: Opt[Opt[T]]) =
  ## Three-state filter dispatch: outer Opt = presence, inner Opt = null vs value.
  ## Opt.none omits the key, Opt.some(Opt.none) emits null, Opt.some(Opt.some(v)) emits value.
  for outer in opt:
    if outer.isNone:
      node[key] = newJNull()
    else:
      for inner in outer:
        node[key] = inner.toJson()

func toJson*(fc: MailboxFilterCondition): JsonNode =
  ## Serialise MailboxFilterCondition to JSON. Fields set to ``Opt.none`` are
  ## omitted entirely. Three-state ``Opt[Opt[T]]`` fields use three-way
  ## dispatch via ``emitThreeState``.
  var node = newJObject()
  node.emitThreeState("parentId", fc.parentId)

  for v in fc.name:
    node["name"] = %v

  node.emitThreeState("role", fc.role)

  for v in fc.hasAnyRole:
    node["hasAnyRole"] = %v

  for v in fc.isSubscribed:
    node["isSubscribed"] = %v

  return node
