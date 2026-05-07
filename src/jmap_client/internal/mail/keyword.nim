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

type Keyword* = distinct string
  ## A case-insensitive keyword label: 1–255 bytes, printable ASCII excluding
  ## IMAP-forbidden characters. Always stored as lowercase.

defineStringDistinctOps(Keyword)

func parseKeyword*(raw: string): Result[Keyword, ValidationError] =
  ## Strict: printable ASCII (0x21–0x7E), no IMAP-forbidden chars, lowercase
  ## normalised. For client-constructed keywords.
  detectStrictPrintableToken(raw, KeywordForbiddenChars).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(raw.toLowerAscii()))

func parseKeywordFromServer*(raw: string): Result[Keyword, ValidationError] =
  ## Lenient: 1–255 octets, no control characters, lowercase normalised.
  ## Tolerates IMAP-forbidden chars that strict rejects.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "Keyword", raw))
  return ok(Keyword(raw.toLowerAscii()))

const
  kwDraft* = Keyword("$draft") ## IANA $draft keyword.
  kwSeen* = Keyword("$seen") ## IANA $seen keyword.
  kwFlagged* = Keyword("$flagged") ## IANA $flagged keyword.
  kwAnswered* = Keyword("$answered") ## IANA $answered keyword.
  kwForwarded* = Keyword("$forwarded") ## IANA $forwarded keyword.
  kwPhishing* = Keyword("$phishing") ## IANA $phishing keyword.
  kwJunk* = Keyword("$junk") ## IANA $junk keyword.
  kwNotJunk* = Keyword("$notjunk") ## IANA $notjunk keyword.

type KeywordSet* = distinct HashSet[Keyword]
  ## Immutable set of keywords. Read-only operations only — no mutation after
  ## construction (Decision B3).

defineHashSetDistinctOps(KeywordSet, Keyword)

func initKeywordSet*(keywords: openArray[Keyword]): KeywordSet =
  ## Constructs a KeywordSet from the given keywords. Empty set is valid
  ## (Decision B2). Duplicates are naturally deduplicated by the underlying
  ## HashSet.
  KeywordSet(keywords.toHashSet)

iterator items*(ks: KeywordSet): Keyword =
  ## Yields each keyword in the set. Unwraps the distinct type to iterate
  ## the underlying HashSet.
  for kw in HashSet[Keyword](ks):
    yield kw
