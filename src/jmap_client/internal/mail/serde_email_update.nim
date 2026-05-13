# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for EmailUpdate and EmailUpdateSet (RFC 8621 §4.6 update
## semantics). Flattens the typed update algebra to an RFC 8620 §5.3 wire
## patch ``JsonNode`` (JSON-Pointer-keyed object), with RFC 6901 JSON
## Pointer escaping on keyword reference tokens. Sender-side only —
## creation types admit no ``fromJson`` per the Postel-strict construction
## rule.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types/primitives
import ../serialisation/serde
import ./email_update
import ./keyword
import ./serde_keyword
import ./serde_mailbox

func toJson*(u: EmailUpdate): (string, JsonNode) =
  ## Emit the ``(wire-key, wire-value)`` pair for a single update. The
  ## aggregator installs the key directly into a ``JObject``; returning a
  ## tuple avoids parsing the key back out of a nested ``JsonNode``.
  ## ``Id`` reference tokens skip escaping — RFC 8620 §1.2 restricts the
  ## charset to ``[A-Za-z0-9_-]``, so neither ``~`` nor ``/`` can appear.
  ##
  ## Combined of-arms mirror ``EmailUpdate``'s declaration
  ## (``euAddKeyword`` and ``euRemoveKeyword`` share ``keyword``;
  ## ``euAddToMailbox`` and ``euRemoveFromMailbox`` share ``mailboxId``).
  ## Strict rejects split-of-arms when the type combines them.
  case u.kind
  of euAddKeyword, euRemoveKeyword:
    let keyPart = "keywords/" & jsonPointerEscape($u.keyword)
    if u.kind == euAddKeyword:
      (keyPart, newJBool(true))
    else:
      (keyPart, newJNull())
  of euSetKeywords:
    ("keywords", u.keywords.toJson())
  of euAddToMailbox, euRemoveFromMailbox:
    let keyPart = "mailboxIds/" & $u.mailboxId
    if u.kind == euAddToMailbox:
      (keyPart, newJBool(true))
    else:
      (keyPart, newJNull())
  of euSetMailboxIds:
    ("mailboxIds", u.mailboxes.toJson())

func toJson*(us: EmailUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initEmailUpdateSet`` has already rejected duplicate target paths
  ## and every other conflict class, so blind aggregation here cannot
  ## shadow a prior entry.
  var node = newJObject()
  for u in us.toSeq:
    let (key, value) = u.toJson()
    node[key] = value
  return node

func toJson*(upd: NonEmptyEmailUpdates): JsonNode =
  ## Flatten the whole-container update algebra to the RFC 8620 §5.3
  ## wire ``update`` value — ``{emailId: patchObj, ...}``.
  ## ``parseNonEmptyEmailUpdates`` has already enforced non-empty input
  ## and distinct ids, so blind aggregation cannot shadow a prior entry.
  var node = newJObject()
  for id, patchSet in upd.toTable:
    node[$id] = patchSet.toJson()
  return node
