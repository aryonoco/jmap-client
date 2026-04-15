# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for EmailUpdate and EmailUpdateSet (RFC 8621 §4.6 update
## semantics). Flattens the typed update algebra to an RFC 8620 §5.3
## ``PatchObject``-shaped ``JsonNode``, with RFC 6901 JSON Pointer escaping
## on keyword reference tokens. Sender-side only — creation types admit no
## ``fromJson`` per the Postel-strict construction rule.

{.push raises: [], noSideEffect.}

import std/json
import std/strutils

import ../primitives
import ./email_update
import ./keyword
import ./serde_keyword
import ./serde_mailbox

func jsonPointerEscape(s: string): string =
  ## RFC 6901 §3 reference-token escaping. ``~`` MUST be escaped first:
  ## escaping ``/`` first would produce ``~1`` that a second pass would
  ## re-escape into ``~01``, corrupting keywords containing ``/``.
  s.replace("~", "~0").replace("/", "~1")

func toJson*(u: EmailUpdate): (string, JsonNode) =
  ## Emit the ``(wire-key, wire-value)`` pair for a single update. The
  ## aggregator installs the key directly into a ``JObject``; returning a
  ## tuple avoids parsing the key back out of a nested ``JsonNode``.
  ## ``Id`` reference tokens skip escaping — RFC 8620 §1.2 restricts the
  ## charset to ``[A-Za-z0-9_-]``, so neither ``~`` nor ``/`` can appear.
  case u.kind
  of euAddKeyword:
    ("keywords/" & jsonPointerEscape($u.keyword), newJBool(true))
  of euRemoveKeyword:
    ("keywords/" & jsonPointerEscape($u.keyword), newJNull())
  of euSetKeywords:
    ("keywords", u.keywords.toJson())
  of euAddToMailbox:
    ("mailboxIds/" & $u.mailboxId, newJBool(true))
  of euRemoveFromMailbox:
    ("mailboxIds/" & $u.mailboxId, newJNull())
  of euSetMailboxIds:
    ("mailboxIds", u.mailboxes.toJson())

func toJson*(us: EmailUpdateSet): JsonNode =
  ## Flatten the validated update-set to an RFC 8620 §5.3 wire patch.
  ## ``initEmailUpdateSet`` has already rejected duplicate target paths
  ## and every other conflict class, so blind aggregation here cannot
  ## shadow a prior entry.
  var node = newJObject()
  for u in seq[EmailUpdate](us):
    let (key, value) = u.toJson()
    node[key] = value
  return node
