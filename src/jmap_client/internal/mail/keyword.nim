# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Keyword and KeywordSet types for RFC 8621 (JMAP Mail) section 4.1.1.
## Keywords are case-insensitive labels on Email objects (e.g. $seen, $flagged).
## KeywordSet is an immutable set of keywords used in Email and filter types.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sets
import std/strutils

import ../types/validation

const KeywordForbiddenChars* = {'(', ')', '{', ']', '%', '*', '"', '\\'}
  ## Characters forbidden in JMAP keywords (RFC 8621 §4.1.1, IMAP flag grammar).

type Keyword* {.ruleOff: "objects".} = object
  ## A case-insensitive keyword label: 1–255 bytes, printable ASCII
  ## excluding IMAP-forbidden characters. Always stored as lowercase.
  ## Sealed Pattern-A object — ``rawValue`` is module-private. Construct
  ## via ``parseKeyword`` (strict) or ``parseKeywordFromServer`` (lenient).
  rawValue: string

defineSealedStringOps(Keyword)

func parseKeyword*(raw: string): Result[Keyword, ValidationError] =
  ## Strict: printable ASCII (0x21–0x7E), no IMAP-forbidden chars, lowercase
  ## normalised. For client-constructed keywords.
  detectStrictPrintableToken(raw, KeywordForbiddenChars).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(rawValue: raw.toLowerAscii()))

func parseKeywordFromServer*(raw: string): Result[Keyword, ValidationError] =
  ## Lenient: 1–255 octets, no control characters, lowercase normalised.
  ## Tolerates IMAP-forbidden chars that strict rejects.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(rawValue: raw.toLowerAscii()))

const
  kwDraft* = parseKeyword("$draft").get() ## IANA $draft keyword.
  kwSeen* = parseKeyword("$seen").get() ## IANA $seen keyword.
  kwFlagged* = parseKeyword("$flagged").get() ## IANA $flagged keyword.
  kwAnswered* = parseKeyword("$answered").get() ## IANA $answered keyword.
  kwForwarded* = parseKeyword("$forwarded").get() ## IANA $forwarded keyword.
  kwPhishing* = parseKeyword("$phishing").get() ## IANA $phishing keyword.
  kwJunk* = parseKeyword("$junk").get() ## IANA $junk keyword.
  kwNotJunk* = parseKeyword("$notjunk").get() ## IANA $notjunk keyword.

type KeywordSet* {.ruleOff: "objects".} = object
  ## Immutable set of keywords. Sealed Pattern-A object — ``rawValue``
  ## is module-private. Read-only operations only — no mutation after
  ## construction (Decision B3).
  rawValue: HashSet[Keyword]

defineSealedHashSetOps(KeywordSet, Keyword)

func initKeywordSet*(keywords: openArray[Keyword]): KeywordSet =
  ## Constructs a KeywordSet from the given keywords. Empty set is
  ## valid (Decision B2). Duplicates are naturally deduplicated by the
  ## underlying HashSet.
  KeywordSet(rawValue: keywords.toHashSet)

func toHashSet*(ks: KeywordSet): HashSet[Keyword] {.inline.} =
  ## Value-projection accessor — returns a copy of the underlying set.
  ks.rawValue

iterator items*(ks: KeywordSet): Keyword =
  ## Yields each keyword in the set.
  for kw in ks.rawValue:
    yield kw
