# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Id, UnsignedInt, JmapInt, Date, and UTCDate.

import std/hashes
import std/random
import std/sequtils

import pkg/results

import jmap_client/primitives
import jmap_client/validation
import ./mproperty

# --- Totality: never crashes ---

block propParseIdTotality:
  checkProperty "parseId never crashes":
    let s = genArbitraryString(rng)
    discard parseId(s)

block propParseIdFromServerTotality:
  checkProperty "parseIdFromServer never crashes":
    let s = genArbitraryString(rng)
    discard parseIdFromServer(s)

block propParseUnsignedIntTotality:
  checkProperty "parseUnsignedInt never crashes":
    let n = rng.rand(int64)
    discard parseUnsignedInt(n)

block propParseJmapIntTotality:
  checkProperty "parseJmapInt never crashes":
    let n = rng.rand(int64)
    discard parseJmapInt(n)

block propParseDateTotality:
  checkProperty "parseDate never crashes":
    let s = genArbitraryString(rng)
    discard parseDate(s)

block propParseUtcDateTotality:
  checkProperty "parseUtcDate never crashes":
    let s = genArbitraryString(rng)
    discard parseUtcDate(s)

# --- Round-trip and invariants ---

block propIdDollarRoundTrip:
  checkProperty "$(parseId(s).get()) == s":
    let s = genValidIdStrict(rng)
    doAssert $(parseId(s).get()) == s

block propIdStrictImpliesLenient:
  checkProperty "parseId ok implies parseIdFromServer ok":
    let s = genValidIdStrict(rng)
    doAssert parseId(s).isOk
    doAssert parseIdFromServer(s).isOk

block propIdLengthBounds:
  checkProperty "valid Id has len in 1..255":
    let s = genValidIdStrict(rng)
    let id = parseId(s).get()
    doAssert id.len >= 1 and id.len <= 255

block propIdCharsetInvariant:
  checkProperty "valid strict Id chars are in Base64UrlChars":
    let s = genValidIdStrict(rng)
    doAssert s.allIt(it in Base64UrlChars)

block propUnsignedIntRange:
  checkProperty "valid UnsignedInt in [0, MaxUnsignedInt]":
    let n = genValidUnsignedInt(rng)
    let u = parseUnsignedInt(n).get()
    doAssert int64(u) >= 0
    doAssert int64(u) <= MaxUnsignedInt

block propJmapIntRange:
  checkProperty "valid JmapInt in [MinJmapInt, MaxJmapInt]":
    let n = genValidJmapInt(rng)
    let j = parseJmapInt(n).get()
    doAssert int64(j) >= MinJmapInt
    doAssert int64(j) <= MaxJmapInt

block propJmapIntNegationInvolution:
  checkProperty "-(-x) == x":
    let n = genValidJmapInt(rng)
    let x = parseJmapInt(n).get()
    doAssert -(-x) == x

block propJmapIntNegationZero:
  let z = parseJmapInt(0).get()
  doAssert -z == z

# --- Equality/hash ---

block propIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propUnsignedIntOrderConsistency:
  checkProperty "(a < b) matches int64 order":
    let na = genValidUnsignedInt(rng)
    let nb = genValidUnsignedInt(rng)
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (na < nb)

block propIdFromServerDollarRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s":
    let s = genValidIdStrict(rng)
    doAssert $(parseIdFromServer(s).get()) == s

block propErrorPreservesValue:
  checkProperty "error.value == input for failing parseId":
    let s = genArbitraryString(rng)
    let r = parseId(s)
    if r.isErr:
      doAssert r.error.value == s

# --- Date/UTCDate properties ---

block propDateRoundTrip:
  checkProperty "$(parseDate(s).get()) == s":
    let s = genValidDate(rng)
    doAssert $(parseDate(s).get()) == s

block propUtcDateRoundTrip:
  checkProperty "$(parseUtcDate(s).get()) == s":
    let s = genValidUtcDate(rng)
    doAssert $(parseUtcDate(s).get()) == s

block propDateMinLength:
  checkProperty "valid Date has len >= 20":
    let s = genValidDate(rng)
    let d = parseDate(s).get()
    doAssert d.len >= 20

block propDateTSeparator:
  checkProperty "valid Date has 'T' at position 10":
    let s = genValidDate(rng)
    doAssert s[10] == 'T'

block propUtcDateEndsWithZ:
  checkProperty "valid UTCDate ends with 'Z'":
    let s = genValidUtcDate(rng)
    doAssert s[^1] == 'Z'

block propUtcDateImpliesDate:
  checkProperty "parseUtcDate(s).isOk implies parseDate(s).isOk":
    let s = genValidUtcDate(rng)
    doAssert parseUtcDate(s).isOk
    doAssert parseDate(s).isOk

# --- Cross-type subset properties ---

block propUnsignedIntSubsetOfJmapInt:
  checkProperty "valid n >= 0: parseUnsignedInt(n).isOk implies parseJmapInt(n).isOk":
    let n = genValidUnsignedInt(rng)
    doAssert parseUnsignedInt(n).isOk
    doAssert parseJmapInt(n).isOk

block propJmapIntNegationPreservesValidity:
  checkProperty "parseJmapInt(-n).isOk when parseJmapInt(n).isOk":
    let n = genValidJmapInt(rng)
    doAssert parseJmapInt(n).isOk
    doAssert parseJmapInt(-n).isOk

# --- Idempotence ---

block propIdDoubleParseIdempotent:
  checkProperty "parseId($(parseId(s).get())).isOk for valid strict s":
    let s = genValidIdStrict(rng)
    let first = parseId(s).get()
    doAssert parseId($first).isOk

# --- Missing round-trips ---

block propUnsignedIntInt64RoundTrip:
  checkProperty "int64(parseUnsignedInt(n).get()) == n":
    let n = genValidUnsignedInt(rng)
    doAssert int64(parseUnsignedInt(n).get()) == n

block propJmapIntInt64RoundTrip:
  checkProperty "int64(parseJmapInt(n).get()) == n":
    let n = genValidJmapInt(rng)
    doAssert int64(parseJmapInt(n).get()) == n

# --- Lenient Id properties ---

block propIdLenientRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s for lenient string":
    let s = genValidLenientString(rng, 1, 255)
    doAssert $(parseIdFromServer(s).get()) == s

block propIdLenientLengthInvariant:
  checkProperty "valid lenient Id has len 1..255":
    let s = genValidLenientString(rng, 1, 255)
    let id = parseIdFromServer(s).get()
    doAssert id.len >= 1 and id.len <= 255

# --- Equivalence relation properties ---

block propIdReflexivity:
  checkProperty "propIdReflexivity":
    let s = genValidIdStrict(rng, trial)
    let a = parseId(s).get()
    doAssert a == a

block propIdSymmetry:
  checkProperty "propIdSymmetry":
    let s = genValidIdStrict(rng, trial)
    let a = parseId(s).get()
    let b = parseId(s).get()
    if a == b:
      doAssert b == a

block propUnsignedIntReflexivity:
  checkProperty "propUnsignedIntReflexivity":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    doAssert a == a

block propJmapIntReflexivity:
  checkProperty "propJmapIntReflexivity":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    doAssert a == a

block propDateReflexivity:
  checkProperty "propDateReflexivity":
    let s = genValidDate(rng)
    let a = parseDate(s).get()
    doAssert a == a

block propUtcDateReflexivity:
  checkProperty "propUtcDateReflexivity":
    let s = genValidUtcDate(rng)
    let a = parseUtcDate(s).get()
    doAssert a == a

# --- Total order properties ---

block propUnsignedIntTrichotomy:
  checkProperty "propUnsignedIntTrichotomy":
    let a = parseUnsignedInt(genValidUnsignedInt(rng, trial)).get()
    let b = parseUnsignedInt(genValidUnsignedInt(rng)).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

block propJmapIntTrichotomy:
  checkProperty "propJmapIntTrichotomy":
    let a = parseJmapInt(genValidJmapInt(rng, trial)).get()
    let b = parseJmapInt(genValidJmapInt(rng)).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

block propUnsignedIntTransitivityLt:
  checkProperty "propUnsignedIntTransitivityLt":
    let va = genValidUnsignedInt(rng, trial)
    let vb = genValidUnsignedInt(rng)
    let vc = genValidUnsignedInt(rng)
    let a = parseUnsignedInt(va).get()
    let b = parseUnsignedInt(vb).get()
    let c = parseUnsignedInt(vc).get()
    if a < b and b < c:
      doAssert a < c

block propJmapIntTransitivityLt:
  checkProperty "propJmapIntTransitivityLt":
    let va = genValidJmapInt(rng, trial)
    let vb = genValidJmapInt(rng)
    let vc = genValidJmapInt(rng)
    let a = parseJmapInt(va).get()
    let b = parseJmapInt(vb).get()
    let c = parseJmapInt(vc).get()
    if a < b and b < c:
      doAssert a < c

block propUnsignedIntAntisymmetryLeq:
  checkProperty "propUnsignedIntAntisymmetryLeq":
    let a = parseUnsignedInt(genValidUnsignedInt(rng, trial)).get()
    let b = parseUnsignedInt(genValidUnsignedInt(rng)).get()
    if a <= b and b <= a:
      doAssert a == b

block propJmapIntConnex:
  checkProperty "propJmapIntConnex":
    let a = parseJmapInt(genValidJmapInt(rng, trial)).get()
    let b = parseJmapInt(genValidJmapInt(rng)).get()
    doAssert a <= b or b <= a

block propUnsignedIntLtLeqConsistency:
  checkProperty "propUnsignedIntLtLeqConsistency":
    let a = parseUnsignedInt(genValidUnsignedInt(rng, trial)).get()
    let b = parseUnsignedInt(genValidUnsignedInt(rng)).get()
    doAssert (a < b) == (a <= b and not (a == b))

# --- Hash consistency for additional types ---

block propUnsignedIntEqImpliesHashEq:
  checkProperty "propUnsignedIntEqImpliesHashEq":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propJmapIntEqImpliesHashEq:
  checkProperty "propJmapIntEqImpliesHashEq":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propDateEqImpliesHashEq:
  checkProperty "propDateEqImpliesHashEq":
    let s = genValidDate(rng)
    let a = parseDate(s).get()
    let b = parseDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propUtcDateEqImpliesHashEq:
  checkProperty "propUtcDateEqImpliesHashEq":
    let s = genValidUtcDate(rng)
    let a = parseUtcDate(s).get()
    let b = parseUtcDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

block propIdDoubleRoundTripEquality:
  checkProperty "propIdDoubleRoundTripEquality":
    let s = genValidIdStrict(rng, trial)
    let first = parseId(s).get()
    let second = parseId($first).get()
    doAssert first == second

block propUnsignedIntDoubleRoundTrip:
  checkProperty "propUnsignedIntDoubleRoundTrip":
    let n = genValidUnsignedInt(rng, trial)
    let first = parseUnsignedInt(n).get()
    let reparsed = parseUnsignedInt(int64(first)).get()
    doAssert first == reparsed

block propJmapIntDoubleRoundTrip:
  checkProperty "propJmapIntDoubleRoundTrip":
    let n = genValidJmapInt(rng, trial)
    let first = parseJmapInt(n).get()
    let reparsed = parseJmapInt(int64(first)).get()
    doAssert first == reparsed

block propDateDoubleRoundTripEquality:
  checkProperty "propDateDoubleRoundTripEquality":
    let s = genValidDate(rng)
    let first = parseDate(s).get()
    let second = parseDate($first).get()
    doAssert first == second

block propUtcDateDoubleRoundTripEquality:
  checkProperty "propUtcDateDoubleRoundTripEquality":
    let s = genValidUtcDate(rng)
    let first = parseUtcDate(s).get()
    let second = parseUtcDate($first).get()
    doAssert first == second

# --- Injectivity ---

block propUnsignedIntInjectivity:
  checkProperty "propUnsignedIntInjectivity":
    let a = genValidUnsignedInt(rng, trial)
    let b = genValidUnsignedInt(rng)
    let ua = parseUnsignedInt(a).get()
    let ub = parseUnsignedInt(b).get()
    if ua == ub:
      doAssert a == b

block propJmapIntInjectivity:
  checkProperty "propJmapIntInjectivity":
    let a = genValidJmapInt(rng, trial)
    let b = genValidJmapInt(rng)
    let ja = parseJmapInt(a).get()
    let jb = parseJmapInt(b).get()
    if ja == jb:
      doAssert a == b

# --- Strict subset proofs ---

block propIdFromServerStrictSuperset:
  var witnessCount = 0
  checkPropertyN "propIdFromServerStrictSuperset", QuickTrials:
    ## There exist strings accepted by parseIdFromServer but rejected by parseId.
    let s = genValidLenientString(rng, 1, 255)
    let lenient = parseIdFromServer(s)
    let strict = parseId(s)
    if lenient.isOk and strict.isErr:
      witnessCount += 1
  doAssert witnessCount > 0, "no witness found for IdFromServer strict superset"

block propDateStrictSupersetOfUtcDate:
  var witnessCount = 0
  checkPropertyN "propDateStrictSupersetOfUtcDate", QuickTrials:
    ## There exist dates accepted by parseDate but rejected by parseUtcDate.
    let s = genValidDate(rng)
    let date = parseDate(s)
    let utcDate = parseUtcDate(s)
    if date.isOk and utcDate.isErr:
      witnessCount += 1
  doAssert witnessCount > 0, "no witness found for Date strict superset of UtcDate"

block propJmapIntStrictSupersetOfUnsignedInt:
  var witnessCount = 0
  checkPropertyN "propJmapIntStrictSupersetOfUnsignedInt", QuickTrials:
    ## There exist values accepted by parseJmapInt but rejected by parseUnsignedInt.
    let n = genValidJmapInt(rng, trial)
    let jmap = parseJmapInt(n)
    let unsigned = parseUnsignedInt(n)
    if jmap.isOk and unsigned.isErr:
      witnessCount += 1
  doAssert witnessCount > 0,
    "no witness found for JmapInt strict superset of UnsignedInt"

block propDateMetamorphicCaseSensitivity:
  ## Metamorphic: if parseDate succeeds, replacing T with t at position 10
  ## must cause rejection.
  checkProperty "date metamorphic T->t":
    let s = rng.genValidDate()
    let result = parseDate(s)
    if result.isOk:
      var mutated = s
      mutated[10] = 't'
      doAssert parseDate(mutated).isErr

block propStrictSubsetMetamorphic:
  ## Metamorphic: if parseId(s) succeeds, parseIdFromServer(s) must also succeed.
  ## Strict is a subset of lenient.
  checkProperty "strict Id subset of lenient":
    let s = rng.genValidIdStrict(trial)
    let strictResult = parseId(s)
    if strictResult.isOk:
      doAssert parseIdFromServer(s).isOk

# --- Equality symmetry ---

block propIdSymmetryExplicit:
  checkProperty "propIdSymmetryExplicit":
    let s = genValidIdStrict(rng, trial)
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert a == b
    doAssert b == a

block propDateSymmetry:
  checkProperty "propDateSymmetry":
    let s = genValidDate(rng)
    let a = parseDate(s).get()
    let b = parseDate(s).get()
    doAssert a == b
    doAssert b == a

block propUtcDateSymmetry:
  checkProperty "propUtcDateSymmetry":
    let s = genValidUtcDate(rng)
    let a = parseUtcDate(s).get()
    let b = parseUtcDate(s).get()
    doAssert a == b
    doAssert b == a

block propUnsignedIntSymmetry:
  checkProperty "propUnsignedIntSymmetry":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert a == b
    doAssert b == a

block propJmapIntSymmetry:
  checkProperty "propJmapIntSymmetry":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert a == b
    doAssert b == a

# --- Equality transitivity ---

block propIdTransitivity:
  checkProperty "propIdTransitivity":
    let s = genValidIdStrict(rng, trial)
    let a = parseId(s).get()
    let b = parseId(s).get()
    let c = parseId(s).get()
    doAssert a == b and b == c
    doAssert a == c

block propUnsignedIntTransitivity:
  checkProperty "propUnsignedIntTransitivity":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    let c = parseUnsignedInt(n).get()
    doAssert a == b and b == c
    doAssert a == c

block propJmapIntTransitivity:
  checkProperty "propJmapIntTransitivity":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    let c = parseJmapInt(n).get()
    doAssert a == b and b == c
    doAssert a == c

block propDateTransitivity:
  checkProperty "propDateTransitivity":
    let s = genValidDate(rng)
    let a = parseDate(s).get()
    let b = parseDate(s).get()
    let c = parseDate(s).get()
    doAssert a == b and b == c
    doAssert a == c

# --- Invalid input rejection properties ---

block propInvalidDateAlwaysRejected:
  checkPropertyN "genInvalidDate always rejected by parseDate", QuickTrials:
    let s = genInvalidDate(rng, trial)
    doAssert parseDate(s).isErr

block propInvalidUtcDateAlwaysRejected:
  checkPropertyN "genInvalidUtcDate always rejected by parseUtcDate", QuickTrials:
    let s = genInvalidUtcDate(rng, trial)
    doAssert parseUtcDate(s).isErr

# --- Equivalence substitution and ordering ---

block propIdSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y).
  checkProperty "propIdSubstitution":
    let s = genValidIdStrict(rng, trial)
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propUnsignedIntSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y) and hash(x) == hash(y).
  checkProperty "propUnsignedIntSubstitution":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propJmapIntSubstitution:
  checkProperty "propJmapIntSubstitution":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propUnsignedIntIrreflexivity:
  ## Strict ordering: not (x < x).
  checkProperty "propUnsignedIntIrreflexivity":
    let n = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(n).get()
    doAssert not (a < a)

block propJmapIntIrreflexivity:
  checkProperty "propJmapIntIrreflexivity":
    let n = genValidJmapInt(rng, trial)
    let a = parseJmapInt(n).get()
    doAssert not (a < a)

block propUnsignedIntAsymmetry:
  ## x < y implies not (y < x).
  checkProperty "propUnsignedIntAsymmetry":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert not (b < a)

block propJmapIntAsymmetry:
  checkProperty "propJmapIntAsymmetry":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng, trial)
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    if a < b:
      doAssert not (b < a)

block propUnsignedIntLtImpliesLeq:
  ## x < y implies x <= y.
  checkProperty "propUnsignedIntLtImpliesLeq":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert a <= b

block propParseIdIdempotence:
  ## Parsing the same string twice yields identical results.
  checkProperty "propParseIdIdempotence":
    let s = genValidIdStrict(rng, trial)
    let first = parseId(s)
    let second = parseId(s)
    doAssert first.isOk == second.isOk
    if first.isOk:
      doAssert first.get() == second.get()

block propParseDateIdempotence:
  checkProperty "propParseDateIdempotence":
    let s = genValidDate(rng)
    let first = parseDate(s)
    let second = parseDate(s)
    doAssert first.isOk == second.isOk
    if first.isOk:
      doAssert first.get() == second.get()
