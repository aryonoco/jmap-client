# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for MailboxFilterCondition (RFC 8621 §2.3) and
## EmailHeaderFilter / EmailFilterCondition (RFC 8621 §4.4.1).
## toJson only — filter conditions flow client-to-server only (Decision B11).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde_primitives
import ../types
import ./keyword
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

# =============================================================================
# EmailHeaderFilter toJson
# =============================================================================

func toJson*(ehf: EmailHeaderFilter): JsonNode =
  ## Serialise EmailHeaderFilter as a 1-or-2 element JSON array.
  ## Name only: ``["Subject"]``. Name + value: ``["Subject", "test"]``.
  var arr = newJArray()
  arr.add(%ehf.name)
  for val in ehf.value:
    arr.add(%val)
  return arr

# =============================================================================
# EmailFilterCondition toJson
# =============================================================================

func emitDateSizeFilters(node: JsonNode, fc: EmailFilterCondition) =
  ## Emits the 4 date/size filter fields.
  for v in fc.before:
    node["before"] = v.toJson()
  for v in fc.after:
    node["after"] = v.toJson()
  for v in fc.minSize:
    node["minSize"] = v.toJson()
  for v in fc.maxSize:
    node["maxSize"] = v.toJson()

func emitKeywordFilters(node: JsonNode, fc: EmailFilterCondition) =
  ## Emits the 5 keyword filter fields (thread + per-email). Keyword values
  ## serialise via ``$`` operator (distinct string backing).
  for v in fc.allInThreadHaveKeyword:
    node["allInThreadHaveKeyword"] = %($v)
  for v in fc.someInThreadHaveKeyword:
    node["someInThreadHaveKeyword"] = %($v)
  for v in fc.noneInThreadHaveKeyword:
    node["noneInThreadHaveKeyword"] = %($v)
  for v in fc.hasKeyword:
    node["hasKeyword"] = %($v)
  for v in fc.notKeyword:
    node["notKeyword"] = %($v)

func emitTextSearchFilters(node: JsonNode, fc: EmailFilterCondition) =
  ## Emits the 7 text search fields. ``fromAddr`` emits as ``"from"`` key.
  for v in fc.text:
    node["text"] = %v
  for v in fc.fromAddr:
    node["from"] = %v
  for v in fc.to:
    node["to"] = %v
  for v in fc.cc:
    node["cc"] = %v
  for v in fc.bcc:
    node["bcc"] = %v
  for v in fc.subject:
    node["subject"] = %v
  for v in fc.body:
    node["body"] = %v

func toJson*(fc: EmailFilterCondition): JsonNode =
  ## Serialise EmailFilterCondition to JSON. ``Opt.none`` fields are omitted
  ## entirely (sparse client-to-server pattern). ``fromAddr`` emits as
  ## ``"from"`` key. Keyword fields serialise via ``$`` operator.
  var node = newJObject()

  # -- Mailbox membership --
  for v in fc.inMailbox:
    node["inMailbox"] = v.toJson()
  for v in fc.inMailboxOtherThan:
    var arr = newJArray()
    for id in v:
      arr.add(id.toJson())
    node["inMailboxOtherThan"] = arr

  node.emitDateSizeFilters(fc)
  node.emitKeywordFilters(fc)
  for v in fc.hasAttachment:
    node["hasAttachment"] = %v
  node.emitTextSearchFilters(fc)

  # -- Header filter --
  for v in fc.header:
    node["header"] = v.toJson()

  return node
