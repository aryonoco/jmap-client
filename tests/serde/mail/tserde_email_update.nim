# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailUpdate and EmailUpdateSet (F2 §8.3 update-algebra row,
## §8.8 RFC 6901 JSON-Pointer escape boundary). Pins the wire contract shape
## of ``toJson(EmailUpdate)`` (tuple per variant) and ``toJson(EmailUpdateSet)``
## (patch-object flatten) alongside the 15 escape-edge cases that the
## ``jsonPointerEscape`` helper has to survive.

{.push raises: [].}

import std/json

import jmap_client/mail/keyword
import jmap_client/mail/serde_email_update
import jmap_client/mail/serde_keyword
import jmap_client/mail/serde_mailbox
import jmap_client/primitives
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. toJson(EmailUpdate) per-variant tuple =============

block addKeywordEmitsTuple:
  let (key, value) = makeAddKeyword(kwSeen).toJson()
  assertEq key, "keywords/$seen"
  assertEq value, newJBool(true)

block removeKeywordEmitsTuple:
  let (key, value) = makeRemoveKeyword(kwSeen).toJson()
  assertEq key, "keywords/$seen"
  assertEq value, newJNull()

block setKeywordsEmitsTuple:
  let ks = initKeywordSet(@[kwSeen, kwFlagged])
  let (key, value) = makeSetKeywords(ks).toJson()
  assertEq key, "keywords"
  assertEq value, ks.toJson()

block addToMailboxEmitsTuple:
  let id = makeId("mbx1")
  let (key, value) = makeAddToMailbox(id).toJson()
  assertEq key, "mailboxIds/" & $id
  assertEq value, newJBool(true)

block removeFromMailboxEmitsTuple:
  let id = makeId("mbx1")
  let (key, value) = makeRemoveFromMailbox(id).toJson()
  assertEq key, "mailboxIds/" & $id
  assertEq value, newJNull()

block setMailboxIdsEmitsTuple:
  let ids = makeNonEmptyMailboxIdSet(@[makeId("mbx1"), makeId("mbx2")])
  let (key, value) = makeSetMailboxIds(ids).toJson()
  assertEq key, "mailboxIds"
  assertEq value, ids.toJson()

# ============= B. toJson(EmailUpdateSet) flatten =============

block emailUpdateSetFlattensTuple:
  let ids = makeNonEmptyMailboxIdSet(@[makeId("mbx1")])
  let us = makeEmailUpdateSet(@[makeAddKeyword(kwSeen), makeSetMailboxIds(ids)])
  let node = us.toJson()
  doAssert node.kind == JObject
  assertLen node, 2
  assertJsonFieldEq node, "keywords/$seen", newJBool(true)
  assertJsonFieldEq node, "mailboxIds", ids.toJson()

# ============= C. moveToMailbox wire semantics (F21 pin) =============

block moveToMailboxWireIsSetMailboxIds:
  let id = makeId("mbx9")
  let (key, value) = makeMoveToMailbox(id).toJson()
  assertEq key, "mailboxIds"
  doAssert value.kind == JObject
  doAssert value{$id} != nil, "expected $id key in mailboxIds object"
  assertEq value{$id}, newJBool(true)

block moveToMailboxNotAddToMailbox:
  let id = makeId("mbx9")
  let (key, _) = makeMoveToMailbox(id).toJson()
  doAssert key != "mailboxIds/" & $id,
    "moveToMailbox must NOT serialise as the sub-path add-to-mailbox form"

# ============= D. RFC 6901 JSON-Pointer escape boundary (§8.8 — 15 blocks) =============
#
# Every block drives through ``makeAddKeyword(parseKeyword(raw).get()).toJson()``
# so the private ``jsonPointerEscape`` helper is only exercised via the public
# wire contract. The ``escUtf8Keyword`` block uses ``parseKeywordFromServer``
# because ``parseKeyword`` restricts the charset to ASCII 0x21-0x7E.

block escNoMetachars:
  let kw = parseKeyword("$seen").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/$seen"
  assertEq value, newJBool(true)

block escTildeOnly:
  let kw = parseKeyword("a~b").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/a~0b"
  assertEq value, newJBool(true)

block escSlashOnly:
  let kw = parseKeyword("a/b").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/a~1b"
  assertEq value, newJBool(true)

block escTildeAndSlash:
  let kw = parseKeyword("a~/b").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/a~0~1b"
  assertEq value, newJBool(true)

block escAllMeta:
  let kw = parseKeyword("~/~/").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~0~1~0~1"
  assertEq value, newJBool(true)

block escOrderMatters:
  ## Pins the RFC 6901 §3 escape order: ``~ → ~0`` MUST run BEFORE
  ## ``/ → ~1``. Swapping the order would yield ``~01`` (a corrupted
  ## token), not ``~0~1``. See jsonPointerEscape in serde.nim.
  let kw = parseKeyword("~/").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~0~1"
  doAssert key != "keywords/~01",
    "escape order regression: / was escaped before ~, corrupting the token"
  assertEq value, newJBool(true)

block escSingleTilde:
  let kw = parseKeyword("~").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~0"
  assertEq value, newJBool(true)

block escSingleSlash:
  let kw = parseKeyword("/").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~1"
  assertEq value, newJBool(true)

block escEmbeddedTildeZero:
  ## Literal ``~0`` in the input must round-trip as ``~00`` — the escape
  ## is byte-oriented, not RFC-6901-aware; the escaper does not treat
  ## an existing ``~0`` as already-escaped.
  let kw = parseKeyword("a~0b").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/a~00b"
  assertEq value, newJBool(true)

block escEmbeddedTildeOne:
  let kw = parseKeyword("a~1b").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/a~01b"
  assertEq value, newJBool(true)

block escDoubleTilde:
  let kw = parseKeyword("~~").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~0~0"
  assertEq value, newJBool(true)

block escDoubleSlash:
  let kw = parseKeyword("//").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~1~1"
  assertEq value, newJBool(true)

block escTrailingTilde:
  let kw = parseKeyword("abc~").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/abc~0"
  assertEq value, newJBool(true)

block escLeadingTilde:
  let kw = parseKeyword("~abc").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/~0abc"
  assertEq value, newJBool(true)

block escUtf8Keyword:
  ## Byte-oriented escape: multi-byte UTF-8 runes pass through unchanged
  ## because their bytes do not overlap with ``~`` (0x7E) or ``/`` (0x2F).
  ## ``parseKeyword`` strict rejects non-ASCII; drive via
  ## ``parseKeywordFromServer`` so the test fixture survives the
  ## server-originated charset.
  let kw = parseKeywordFromServer("$日本語").get()
  let (key, value) = makeAddKeyword(kw).toJson()
  assertEq key, "keywords/$日本語"
  assertEq value, newJBool(true)
