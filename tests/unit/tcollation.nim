# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``CollationAlgorithm`` — the sealed RFC 4790 collation
## identifier ADT. Covers round-trip identity, IANA classification, vendor
## extension capture, ``==``/``hash`` consistency, and the
## ``CollationViolation`` → ``ValidationError`` translation boundary.

import std/hashes
import std/sets
import std/strutils

import jmap_client/internal/types/collation
import jmap_client/internal/types/validation
import ../mtestblock

# --- round-trip identity for the four IANA-registered constants ---

testCase roundTripAsciiCasemap:
  let r = parseCollationAlgorithm($CollationAsciiCasemap).get()
  doAssert r == CollationAsciiCasemap
  doAssert r.kind == caAsciiCasemap
  doAssert $r == "i;ascii-casemap"

testCase roundTripOctet:
  let r = parseCollationAlgorithm($CollationOctet).get()
  doAssert r == CollationOctet
  doAssert r.kind == caOctet
  doAssert $r == "i;octet"

testCase roundTripAsciiNumeric:
  let r = parseCollationAlgorithm($CollationAsciiNumeric).get()
  doAssert r == CollationAsciiNumeric
  doAssert r.kind == caAsciiNumeric
  doAssert $r == "i;ascii-numeric"

testCase roundTripUnicodeCasemap:
  let r = parseCollationAlgorithm($CollationUnicodeCasemap).get()
  doAssert r == CollationUnicodeCasemap
  doAssert r.kind == caUnicodeCasemap
  doAssert $r == "i;unicode-casemap"

# --- classification: RFC backing strings resolve to the named constants ---

testCase classificationKnownIdentifiers:
  ## Parsing an IANA-registered identifier returns the corresponding named
  ## constant — NOT a ``caOther`` carrying the same wire text.
  doAssert parseCollationAlgorithm("i;ascii-casemap").get().kind == caAsciiCasemap
  doAssert parseCollationAlgorithm("i;octet").get().kind == caOctet
  doAssert parseCollationAlgorithm("i;ascii-numeric").get().kind == caAsciiNumeric
  doAssert parseCollationAlgorithm("i;unicode-casemap").get().kind == caUnicodeCasemap

# --- vendor extensions: caOther carries the raw identifier losslessly ---

testCase vendorExtensionCaOther:
  let v = parseCollationAlgorithm("x-vendor-foo").get()
  doAssert v.kind == caOther
  doAssert v.identifier == "x-vendor-foo"
  doAssert $v == "x-vendor-foo"

testCase vendorExtensionRoundTripIdentity:
  ## Round-trip through ``$`` and back preserves the vendor identifier.
  const raw = "x-acme-proprietary-casemap"
  let parsed = parseCollationAlgorithm(raw).get()
  doAssert $parsed == raw
  doAssert parseCollationAlgorithm($parsed).get() == parsed

# --- equality and hash consistency ---

testCase equalityKnownVsOther:
  ## A known kind never equals a ``caOther`` even when wire strings match.
  ## Since ``parseCollationAlgorithm`` classifies known kinds via
  ## ``parseEnum``, the only way to obtain ``caOther`` is with a string that
  ## fails the enum match — so this test uses two different wire values.
  let known = parseCollationAlgorithm("i;octet").get()
  let vendor = parseCollationAlgorithm("x-vendor").get()
  doAssert known != vendor

testCase equalityDistinctVendorsDiffer:
  let a = parseCollationAlgorithm("x-vendor-a").get()
  let b = parseCollationAlgorithm("x-vendor-b").get()
  doAssert a != b
  doAssert hash(a) != hash(b)

testCase equalityDuplicateVendorsMatch:
  let a = parseCollationAlgorithm("x-vendor-a").get()
  let b = parseCollationAlgorithm("x-vendor-a").get()
  doAssert a == b
  doAssert hash(a) == hash(b)

testCase hashSetMembershipKnown:
  let s = toHashSet(
    [CollationAsciiCasemap, CollationOctet, parseCollationAlgorithm("x-foo").get()]
  )
  doAssert s.contains(CollationAsciiCasemap)
  doAssert s.contains(CollationOctet)
  doAssert s.contains(parseCollationAlgorithm("x-foo").get())
  doAssert not s.contains(CollationAsciiNumeric)
  doAssert not s.contains(parseCollationAlgorithm("x-other").get())

testCase hashEqualityImpliesHashEquality:
  ## Invariant: ``a == b`` implies ``hash(a) == hash(b)`` for every pair of
  ## ``CollationAlgorithm`` values.
  let pairs = @[
    (CollationAsciiCasemap, parseCollationAlgorithm("i;ascii-casemap").get()),
    (CollationOctet, parseCollationAlgorithm("i;octet").get()),
    (CollationAsciiNumeric, parseCollationAlgorithm("i;ascii-numeric").get()),
    (CollationUnicodeCasemap, parseCollationAlgorithm("i;unicode-casemap").get()),
    (
      parseCollationAlgorithm("x-vendor-z").get(),
      parseCollationAlgorithm("x-vendor-z").get(),
    ),
  ]
  for (a, b) in pairs:
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- validation violations: empty and non-printable inputs ---

testCase rejectEmptyIdentifier:
  let r = parseCollationAlgorithm("")
  doAssert r.isErr
  doAssert r.error.typeName == "CollationAlgorithm"
  doAssert "must not be empty" in r.error.message

testCase rejectNonPrintableControlChar:
  ## A byte below 0x20 (here 0x1F, unit separator) is non-printable and is
  ## rejected at construction. The error message names the offending hex
  ## code so operators can diagnose malformed server payloads.
  const bad = "i;ok\x1Ftail"
  let r = parseCollationAlgorithm(bad)
  doAssert r.isErr
  doAssert r.error.typeName == "CollationAlgorithm"
  doAssert "0x1F" in r.error.message
  doAssert r.error.value == bad

testCase rejectDelByte:
  let r = parseCollationAlgorithm("x;del\x7Fchar")
  doAssert r.isErr
  doAssert "0x7F" in r.error.message

testCase acceptBoundaryPrintable:
  ## Space (0x20) is the lowest printable byte; tilde (0x7E) the highest.
  ## Both must survive detection.
  doAssert parseCollationAlgorithm(" ").isOk
  doAssert parseCollationAlgorithm("~").isOk
  doAssert parseCollationAlgorithm(" abc~").isOk
