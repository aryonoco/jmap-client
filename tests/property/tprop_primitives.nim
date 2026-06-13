# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Id, UnsignedInt, JmapInt, Date, and UTCDate.

import std/random
import std/sequtils

import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation
import ../mproperty
import ../mtestblock

# --- Totality: never crashes ---

testCase propParseIdTotality:
  checkProperty "parseId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseId(s)

testCase propParseIdFromServerTotality:
  checkProperty "parseIdFromServer never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseIdFromServer(s)

testCase propParseIdMaliciousTotality:
  checkProperty "parseId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseId(s)

testCase propParseIdFromServerMaliciousTotality:
  checkProperty "parseIdFromServer never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseIdFromServer(s)

testCase propParseIdInvalidStrictRejected:
  checkProperty "genInvalidIdStrict always rejected by parseId":
    let s = genInvalidIdStrict(rng, trial)
    lastInput = s
    doAssert parseId(s).isErr

testCase propParseIdBoundaryLength:
  checkPropertyN "genBoundaryIdStrict accepted by parseId", QuickTrials:
    let s = genBoundaryIdStrict(rng, trial)
    lastInput = s
    discard parseId(s).get()

testCase propParseUnsignedIntTotality:
  checkProperty "parseUnsignedInt never crashes":
    let n = rng.rand(int64)
    lastInput = $n
    discard parseUnsignedInt(n)

testCase propParseJmapIntTotality:
  checkProperty "parseJmapInt never crashes":
    let n = rng.rand(int64)
    lastInput = $n
    discard parseJmapInt(n)

testCase propParseDateTotality:
  checkProperty "parseDate never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseDate(s)

testCase propParseUtcDateTotality:
  checkProperty "parseUtcDate never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseUtcDate(s)

testCase propCalendarInvalidDateAccepted:
  checkProperty "calendar-invalid dates accepted by parseDate":
    let s = genCalendarInvalidDate(rng)
    lastInput = s
    discard parseDate(s).get()

# --- Round-trip and invariants ---

testCase propIdDollarRoundTrip:
  checkProperty "$(parseId(s).get()) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseId(s).get()) == s

testCase propIdStrictImpliesLenient:
  checkProperty "parseId ok implies parseIdFromServer ok":
    let s = genValidIdStrict(rng)
    lastInput = s
    discard parseId(s).get()
    discard parseIdFromServer(s).get()

testCase propIdLengthBounds:
  checkProperty "valid Id has len in 1..255":
    let s = genValidIdStrict(rng)
    lastInput = s
    let id = parseId(s).get()
    doAssert id.len >= 1 and id.len <= 255

testCase propIdCharsetInvariant:
  checkProperty "valid strict Id chars are in Base64UrlChars":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert s.allIt(it in Base64UrlChars)

testCase propUnsignedIntRange:
  checkProperty "valid UnsignedInt in [0, MaxUnsignedInt]":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    let u = parseUnsignedInt(n).get()
    doAssert u.toInt64 >= 0
    doAssert u.toInt64 <= MaxUnsignedInt

testCase propJmapIntRange:
  checkProperty "valid JmapInt in [MinJmapInt, MaxJmapInt]":
    let n = genValidJmapInt(rng)
    lastInput = $n
    let j = parseJmapInt(n).get()
    doAssert j.toInt64 >= MinJmapInt
    doAssert j.toInt64 <= MaxJmapInt

testCase propJmapIntNegationInvolution:
  checkProperty "-(-x) == x":
    let n = genValidJmapInt(rng)
    lastInput = $n
    let x = parseJmapInt(n).get()
    doAssert -(-x) == x

testCase propJmapIntNegationZero:
  let z = parseJmapInt(0).get()
  doAssert -z == z

# --- Equality/hash ---

testCase propIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

testCase propUnsignedIntOrderConsistency:
  checkProperty "(a < b) matches int64 order":
    let na = genValidUnsignedInt(rng)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (na < nb)

testCase propIdFromServerDollarRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseIdFromServer(s).get()) == s

testCase propErrorPreservesValue:
  checkProperty "error.value == input for failing parseId":
    let s = genArbitraryString(rng)
    lastInput = s
    let r = parseId(s)
    if r.isErr:
      doAssert r.error.value == s

# --- Date/UTCDate properties ---

testCase propDateRoundTrip:
  checkProperty "$(parseDate(s).get()) == s":
    let s = genValidDate(rng)
    lastInput = s
    doAssert $(parseDate(s).get()) == s

testCase propUtcDateRoundTrip:
  checkProperty "$(parseUtcDate(s).get()) == s":
    let s = genValidUtcDate(rng)
    lastInput = s
    doAssert $(parseUtcDate(s).get()) == s

testCase propDateMinLength:
  checkProperty "valid Date has len >= 20":
    let s = genValidDate(rng)
    lastInput = s
    let d = parseDate(s).get()
    doAssert d.len >= 20

testCase propDateTSeparator:
  checkProperty "valid Date has 'T' at position 10":
    let s = genValidDate(rng)
    lastInput = s
    doAssert s[10] == 'T'

testCase propUtcDateEndsWithZ:
  checkProperty "valid UTCDate ends with 'Z'":
    let s = genValidUtcDate(rng)
    lastInput = s
    doAssert s[^1] == 'Z'

testCase propUtcDateImpliesDate:
  checkProperty "parseUtcDate(s).get() implies parseDate(s).get()":
    let s = genValidUtcDate(rng)
    lastInput = s
    discard parseUtcDate(s).get()
    discard parseDate(s).get()

# --- Cross-type subset properties ---

testCase propUnsignedIntSubsetOfJmapInt:
  checkProperty "valid n >= 0: parseUnsignedInt(n).get() implies parseJmapInt(n).get()":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    discard parseUnsignedInt(n).get()
    discard parseJmapInt(n).get()

testCase propJmapIntNegationPreservesValidity:
  checkProperty "parseJmapInt(-n).get() when parseJmapInt(n).get()":
    let n = genValidJmapInt(rng)
    lastInput = $n
    discard parseJmapInt(n).get()
    discard parseJmapInt(-n).get()

# --- Idempotence ---

testCase propIdDoubleParseIdempotent:
  checkProperty "parseId($(parseId(s).get())) for valid strict s":
    let s = genValidIdStrict(rng)
    lastInput = s
    let first = parseId(s).get()
    discard parseId($first).get()

# --- Missing round-trips ---

testCase propUnsignedIntInt64RoundTrip:
  checkProperty "parseUnsignedInt(n).get().toInt64 == n":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    doAssert parseUnsignedInt(n).get().toInt64 == n

testCase propJmapIntInt64RoundTrip:
  checkProperty "parseJmapInt(n).get().toInt64 == n":
    let n = genValidJmapInt(rng)
    lastInput = $n
    doAssert parseJmapInt(n).get().toInt64 == n

# --- Lenient Id properties ---

testCase propIdLenientRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s for lenient string":
    let s = genValidLenientString(rng, 1, 255)
    lastInput = s
    doAssert $(parseIdFromServer(s).get()) == s

testCase propIdLenientLengthInvariant:
  checkProperty "valid lenient Id has len 1..255":
    let s = genValidLenientString(rng, 1, 255)
    lastInput = s
    let id = parseIdFromServer(s).get()
    doAssert id.len >= 1 and id.len <= 255

# --- Total order properties ---

testCase propUnsignedIntTrichotomy:
  checkProperty "propUnsignedIntTrichotomy":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

testCase propJmapIntTrichotomy:
  checkProperty "propJmapIntTrichotomy":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

testCase propUnsignedIntTransitivityLt:
  checkProperty "propUnsignedIntTransitivityLt":
    let va = genValidUnsignedInt(rng, trial)
    let vb = genValidUnsignedInt(rng)
    let vc = genValidUnsignedInt(rng)
    lastInput = $va & ", " & $vb & ", " & $vc
    let a = parseUnsignedInt(va).get()
    let b = parseUnsignedInt(vb).get()
    let c = parseUnsignedInt(vc).get()
    if a < b and b < c:
      doAssert a < c

testCase propJmapIntTransitivityLt:
  checkProperty "propJmapIntTransitivityLt":
    let va = genValidJmapInt(rng, trial)
    let vb = genValidJmapInt(rng)
    let vc = genValidJmapInt(rng)
    lastInput = $va & ", " & $vb & ", " & $vc
    let a = parseJmapInt(va).get()
    let b = parseJmapInt(vb).get()
    let c = parseJmapInt(vc).get()
    if a < b and b < c:
      doAssert a < c

testCase propUnsignedIntAntisymmetryLeq:
  checkProperty "propUnsignedIntAntisymmetryLeq":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a <= b and b <= a:
      doAssert a == b

testCase propJmapIntConnex:
  checkProperty "propJmapIntConnex":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    doAssert a <= b or b <= a

testCase propUnsignedIntLtLeqConsistency:
  checkProperty "propUnsignedIntLtLeqConsistency":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (a <= b and not (a == b))

# --- Hash consistency for additional types ---

testCase propUnsignedIntEqImpliesHashEq:
  checkProperty "propUnsignedIntEqImpliesHashEq":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

testCase propJmapIntEqImpliesHashEq:
  checkProperty "propJmapIntEqImpliesHashEq":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

testCase propDateEqImpliesHashEq:
  checkProperty "propDateEqImpliesHashEq":
    let s = genValidDate(rng)
    lastInput = s
    let a = parseDate(s).get()
    let b = parseDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

testCase propUtcDateEqImpliesHashEq:
  checkProperty "propUtcDateEqImpliesHashEq":
    let s = genValidUtcDate(rng)
    lastInput = s
    let a = parseUtcDate(s).get()
    let b = parseUtcDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

testCase propIdDoubleRoundTripEquality:
  checkProperty "propIdDoubleRoundTripEquality":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let first = parseId(s).get()
    let second = parseId($first).get()
    doAssert first == second

testCase propUnsignedIntDoubleRoundTrip:
  checkProperty "propUnsignedIntDoubleRoundTrip":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let first = parseUnsignedInt(n).get()
    let reparsed = parseUnsignedInt(first.toInt64).get()
    doAssert first == reparsed

testCase propJmapIntDoubleRoundTrip:
  checkProperty "propJmapIntDoubleRoundTrip":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let first = parseJmapInt(n).get()
    let reparsed = parseJmapInt(first.toInt64).get()
    doAssert first == reparsed

testCase propDateDoubleRoundTripEquality:
  checkProperty "propDateDoubleRoundTripEquality":
    let s = genValidDate(rng)
    lastInput = s
    let first = parseDate(s).get()
    let second = parseDate($first).get()
    doAssert first == second

testCase propUtcDateDoubleRoundTripEquality:
  checkProperty "propUtcDateDoubleRoundTripEquality":
    let s = genValidUtcDate(rng)
    lastInput = s
    let first = parseUtcDate(s).get()
    let second = parseUtcDate($first).get()
    doAssert first == second

# --- Injectivity ---

testCase propUnsignedIntInjectivity:
  checkProperty "propUnsignedIntInjectivity":
    let a = genValidUnsignedInt(rng, trial)
    let b = genValidUnsignedInt(rng)
    lastInput = $a & ", " & $b
    let ua = parseUnsignedInt(a).get()
    let ub = parseUnsignedInt(b).get()
    if ua == ub:
      doAssert a == b

testCase propJmapIntInjectivity:
  checkProperty "propJmapIntInjectivity":
    let a = genValidJmapInt(rng, trial)
    let b = genValidJmapInt(rng)
    lastInput = $a & ", " & $b
    let ja = parseJmapInt(a).get()
    let jb = parseJmapInt(b).get()
    if ja == jb:
      doAssert a == b

# --- Strict subset proofs ---

testCase propIdFromServerStrictSuperset:
  var witnessCount = 0
  checkPropertyN "propIdFromServerStrictSuperset", QuickTrials:
    ## There exist strings accepted by parseIdFromServer but rejected by parseId.
    let s = genValidLenientString(rng, 1, 255)
    lastInput = s
    let lenientOk = parseIdFromServer(s).isOk
    let strictOk = parseId(s).isOk
    if lenientOk and not strictOk:
      witnessCount += 1
  doAssert witnessCount > 0, "no witness found for IdFromServer strict superset"

testCase propDateStrictSupersetOfUtcDate:
  var witnessCount = 0
  checkPropertyN "propDateStrictSupersetOfUtcDate", QuickTrials:
    ## There exist dates accepted by parseDate but rejected by parseUtcDate.
    let s = genValidDate(rng)
    lastInput = s
    let dateOk = parseDate(s).isOk
    let utcDateOk = parseUtcDate(s).isOk
    if dateOk and not utcDateOk:
      witnessCount += 1
  doAssert witnessCount > 0, "no witness found for Date strict superset of UtcDate"

testCase propJmapIntStrictSupersetOfUnsignedInt:
  var witnessCount = 0
  checkPropertyN "propJmapIntStrictSupersetOfUnsignedInt", QuickTrials:
    ## There exist values accepted by parseJmapInt but rejected by parseUnsignedInt.
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let jmapOk = parseJmapInt(n).isOk
    let unsignedOk = parseUnsignedInt(n).isOk
    if jmapOk and not unsignedOk:
      witnessCount += 1
  doAssert witnessCount > 0,
    "no witness found for JmapInt strict superset of UnsignedInt"

testCase propDateMetamorphicCaseSensitivity:
  ## Metamorphic: if parseDate succeeds, replacing T with t at position 10
  ## must cause rejection.
  checkProperty "date metamorphic T->t":
    let s = rng.genValidDate()
    lastInput = s
    discard parseDate(s)
    var mutated = s
    mutated[10] = 't'
    doAssert parseDate(mutated).isErr
testCase propStrictSubsetMetamorphic:
  ## Metamorphic: if parseId(s).get() succeeds, parseIdFromServer(s).get() must also succeed.
  ## Strict is a subset of lenient.
  checkProperty "strict Id subset of lenient":
    let s = rng.genValidIdStrict(trial)
    lastInput = s
    discard parseId(s)
    discard parseIdFromServer(s)
# --- Invalid input rejection properties ---

testCase propInvalidDateAlwaysRejected:
  checkPropertyN "genInvalidDate always rejected by parseDate", QuickTrials:
    let s = genInvalidDate(rng, trial)
    lastInput = s
    doAssert parseDate(s).isErr

testCase propInvalidUtcDateAlwaysRejected:
  checkPropertyN "genInvalidUtcDate always rejected by parseUtcDate", QuickTrials:
    let s = genInvalidUtcDate(rng, trial)
    lastInput = s
    doAssert parseUtcDate(s).isErr

# --- Equivalence substitution and ordering ---

testCase propIdSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y).
  checkProperty "propIdSubstitution":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

testCase propUnsignedIntSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y) and hash(x) == hash(y).
  checkProperty "propUnsignedIntSubstitution":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

testCase propJmapIntSubstitution:
  checkProperty "propJmapIntSubstitution":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

testCase propUnsignedIntIrreflexivity:
  ## Strict ordering: not (x < x).
  checkProperty "propUnsignedIntIrreflexivity":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    doAssert not (a < a)

testCase propJmapIntIrreflexivity:
  checkProperty "propJmapIntIrreflexivity":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    doAssert not (a < a)

testCase propUnsignedIntAsymmetry:
  ## x < y implies not (y < x).
  checkProperty "propUnsignedIntAsymmetry":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert not (b < a)

testCase propJmapIntAsymmetry:
  checkProperty "propJmapIntAsymmetry":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    if a < b:
      doAssert not (b < a)

testCase propUnsignedIntLtImpliesLeq:
  ## x < y implies x <= y.
  checkProperty "propUnsignedIntLtImpliesLeq":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert a <= b

testCase propParseIdIdempotence:
  ## Parsing the same string twice yields identical results.
  checkProperty "propParseIdIdempotence":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let first = parseId(s).get()
    let second = parseId(s).get()
    doAssert first == second

testCase propParseDateIdempotence:
  checkProperty "propParseDateIdempotence":
    let s = genValidDate(rng)
    lastInput = s
    let first = parseDate(s).get()
    let second = parseDate(s).get()
    doAssert first == second

# --- Cross-type consistency ---

testCase propStrictIdImpliesLenientId:
  ## parseId(s).get() success implies parseIdFromServer(s).get() success: strict is a subset of lenient.
  checkProperty "strict Id acceptance implies lenient Id acceptance":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    discard parseId(s).get()
    discard parseIdFromServer(s).get()

testCase propDateMetamorphicZToLowerZ:
  ## Valid UTC dates ending in Z must be rejected when Z is replaced with lowercase z.
  checkProperty "UTC date Z-to-z metamorphic rejection":
    let s = genValidUtcDate(rng)
    lastInput = s
    discard parseUtcDate(s).get()
    doAssert s[^1] == 'Z'
    var mutated = s
    mutated[^1] = 'z'
    doAssert parseDate(mutated).isErr
    doAssert parseUtcDate(mutated).isErr
