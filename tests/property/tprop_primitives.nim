# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Id, UnsignedInt, JmapInt, Date, and UTCDate.

import std/random
import std/sequtils

import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation
import ../mproperty

# --- Totality: never crashes ---

block propParseIdTotality:
  checkProperty "parseId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseId(s)

block propParseIdFromServerTotality:
  checkProperty "parseIdFromServer never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseIdFromServer(s)

block propParseIdMaliciousTotality:
  checkProperty "parseId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseId(s)

block propParseIdFromServerMaliciousTotality:
  checkProperty "parseIdFromServer never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseIdFromServer(s)

block propParseIdInvalidStrictRejected:
  checkProperty "genInvalidIdStrict always rejected by parseId":
    let s = genInvalidIdStrict(rng, trial)
    lastInput = s
    doAssert parseId(s).isErr

block propParseIdBoundaryLength:
  checkPropertyN "genBoundaryIdStrict accepted by parseId", QuickTrials:
    let s = genBoundaryIdStrict(rng, trial)
    lastInput = s
    discard parseId(s).get()

block propParseUnsignedIntTotality:
  checkProperty "parseUnsignedInt never crashes":
    let n = rng.rand(int64)
    lastInput = $n
    discard parseUnsignedInt(n)

block propParseJmapIntTotality:
  checkProperty "parseJmapInt never crashes":
    let n = rng.rand(int64)
    lastInput = $n
    discard parseJmapInt(n)

block propParseDateTotality:
  checkProperty "parseDate never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseDate(s)

block propParseUtcDateTotality:
  checkProperty "parseUtcDate never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseUtcDate(s)

block propCalendarInvalidDateAccepted:
  checkProperty "calendar-invalid dates accepted by parseDate":
    let s = genCalendarInvalidDate(rng)
    lastInput = s
    discard parseDate(s).get()

# --- Round-trip and invariants ---

block propIdDollarRoundTrip:
  checkProperty "$(parseId(s).get()) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseId(s).get()) == s

block propIdStrictImpliesLenient:
  checkProperty "parseId ok implies parseIdFromServer ok":
    let s = genValidIdStrict(rng)
    lastInput = s
    discard parseId(s).get()
    discard parseIdFromServer(s).get()

block propIdLengthBounds:
  checkProperty "valid Id has len in 1..255":
    let s = genValidIdStrict(rng)
    lastInput = s
    let id = parseId(s).get()
    doAssert id.len >= 1 and id.len <= 255

block propIdCharsetInvariant:
  checkProperty "valid strict Id chars are in Base64UrlChars":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert s.allIt(it in Base64UrlChars)

block propUnsignedIntRange:
  checkProperty "valid UnsignedInt in [0, MaxUnsignedInt]":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    let u = parseUnsignedInt(n).get()
    doAssert int64(u) >= 0
    doAssert int64(u) <= MaxUnsignedInt

block propJmapIntRange:
  checkProperty "valid JmapInt in [MinJmapInt, MaxJmapInt]":
    let n = genValidJmapInt(rng)
    lastInput = $n
    let j = parseJmapInt(n).get()
    doAssert int64(j) >= MinJmapInt
    doAssert int64(j) <= MaxJmapInt

block propJmapIntNegationInvolution:
  checkProperty "-(-x) == x":
    let n = genValidJmapInt(rng)
    lastInput = $n
    let x = parseJmapInt(n).get()
    doAssert -(-x) == x

block propJmapIntNegationZero:
  let z = parseJmapInt(0).get()
  doAssert -z == z

# --- Equality/hash ---

block propIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propUnsignedIntOrderConsistency:
  checkProperty "(a < b) matches int64 order":
    let na = genValidUnsignedInt(rng)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (na < nb)

block propIdFromServerDollarRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseIdFromServer(s).get()) == s

block propErrorPreservesValue:
  checkProperty "error.value == input for failing parseId":
    let s = genArbitraryString(rng)
    lastInput = s
    let r = parseId(s)
    if r.isErr:
      doAssert r.error.value == s

# --- Date/UTCDate properties ---

block propDateRoundTrip:
  checkProperty "$(parseDate(s).get()) == s":
    let s = genValidDate(rng)
    lastInput = s
    doAssert $(parseDate(s).get()) == s

block propUtcDateRoundTrip:
  checkProperty "$(parseUtcDate(s).get()) == s":
    let s = genValidUtcDate(rng)
    lastInput = s
    doAssert $(parseUtcDate(s).get()) == s

block propDateMinLength:
  checkProperty "valid Date has len >= 20":
    let s = genValidDate(rng)
    lastInput = s
    let d = parseDate(s).get()
    doAssert d.len >= 20

block propDateTSeparator:
  checkProperty "valid Date has 'T' at position 10":
    let s = genValidDate(rng)
    lastInput = s
    doAssert s[10] == 'T'

block propUtcDateEndsWithZ:
  checkProperty "valid UTCDate ends with 'Z'":
    let s = genValidUtcDate(rng)
    lastInput = s
    doAssert s[^1] == 'Z'

block propUtcDateImpliesDate:
  checkProperty "parseUtcDate(s).get() implies parseDate(s).get()":
    let s = genValidUtcDate(rng)
    lastInput = s
    discard parseUtcDate(s).get()
    discard parseDate(s).get()

# --- Cross-type subset properties ---

block propUnsignedIntSubsetOfJmapInt:
  checkProperty "valid n >= 0: parseUnsignedInt(n).get() implies parseJmapInt(n).get()":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    discard parseUnsignedInt(n).get()
    discard parseJmapInt(n).get()

block propJmapIntNegationPreservesValidity:
  checkProperty "parseJmapInt(-n).get() when parseJmapInt(n).get()":
    let n = genValidJmapInt(rng)
    lastInput = $n
    discard parseJmapInt(n).get()
    discard parseJmapInt(-n).get()

# --- Idempotence ---

block propIdDoubleParseIdempotent:
  checkProperty "parseId($(parseId(s).get())) for valid strict s":
    let s = genValidIdStrict(rng)
    lastInput = s
    let first = parseId(s).get()
    discard parseId($first).get()

# --- Missing round-trips ---

block propUnsignedIntInt64RoundTrip:
  checkProperty "int64(parseUnsignedInt(n).get()) == n":
    let n = genValidUnsignedInt(rng)
    lastInput = $n
    doAssert int64(parseUnsignedInt(n).get()) == n

block propJmapIntInt64RoundTrip:
  checkProperty "int64(parseJmapInt(n).get()) == n":
    let n = genValidJmapInt(rng)
    lastInput = $n
    doAssert int64(parseJmapInt(n).get()) == n

# --- Lenient Id properties ---

block propIdLenientRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s for lenient string":
    let s = genValidLenientString(rng, 1, 255)
    lastInput = s
    doAssert $(parseIdFromServer(s).get()) == s

block propIdLenientLengthInvariant:
  checkProperty "valid lenient Id has len 1..255":
    let s = genValidLenientString(rng, 1, 255)
    lastInput = s
    let id = parseIdFromServer(s).get()
    doAssert id.len >= 1 and id.len <= 255

# --- Total order properties ---

block propUnsignedIntTrichotomy:
  checkProperty "propUnsignedIntTrichotomy":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

block propJmapIntTrichotomy:
  checkProperty "propJmapIntTrichotomy":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    let count = ord(a < b) + ord(a == b) + ord(b < a)
    doAssert count == 1

block propUnsignedIntTransitivityLt:
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

block propJmapIntTransitivityLt:
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

block propUnsignedIntAntisymmetryLeq:
  checkProperty "propUnsignedIntAntisymmetryLeq":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a <= b and b <= a:
      doAssert a == b

block propJmapIntConnex:
  checkProperty "propJmapIntConnex":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    doAssert a <= b or b <= a

block propUnsignedIntLtLeqConsistency:
  checkProperty "propUnsignedIntLtLeqConsistency":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (a <= b and not (a == b))

# --- Hash consistency for additional types ---

block propUnsignedIntEqImpliesHashEq:
  checkProperty "propUnsignedIntEqImpliesHashEq":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propJmapIntEqImpliesHashEq:
  checkProperty "propJmapIntEqImpliesHashEq":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propDateEqImpliesHashEq:
  checkProperty "propDateEqImpliesHashEq":
    let s = genValidDate(rng)
    lastInput = s
    let a = parseDate(s).get()
    let b = parseDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propUtcDateEqImpliesHashEq:
  checkProperty "propUtcDateEqImpliesHashEq":
    let s = genValidUtcDate(rng)
    lastInput = s
    let a = parseUtcDate(s).get()
    let b = parseUtcDate(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

block propIdDoubleRoundTripEquality:
  checkProperty "propIdDoubleRoundTripEquality":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let first = parseId(s).get()
    let second = parseId($first).get()
    doAssert first == second

block propUnsignedIntDoubleRoundTrip:
  checkProperty "propUnsignedIntDoubleRoundTrip":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let first = parseUnsignedInt(n).get()
    let reparsed = parseUnsignedInt(int64(first)).get()
    doAssert first == reparsed

block propJmapIntDoubleRoundTrip:
  checkProperty "propJmapIntDoubleRoundTrip":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let first = parseJmapInt(n).get()
    let reparsed = parseJmapInt(int64(first)).get()
    doAssert first == reparsed

block propDateDoubleRoundTripEquality:
  checkProperty "propDateDoubleRoundTripEquality":
    let s = genValidDate(rng)
    lastInput = s
    let first = parseDate(s).get()
    let second = parseDate($first).get()
    doAssert first == second

block propUtcDateDoubleRoundTripEquality:
  checkProperty "propUtcDateDoubleRoundTripEquality":
    let s = genValidUtcDate(rng)
    lastInput = s
    let first = parseUtcDate(s).get()
    let second = parseUtcDate($first).get()
    doAssert first == second

# --- Injectivity ---

block propUnsignedIntInjectivity:
  checkProperty "propUnsignedIntInjectivity":
    let a = genValidUnsignedInt(rng, trial)
    let b = genValidUnsignedInt(rng)
    lastInput = $a & ", " & $b
    let ua = parseUnsignedInt(a).get()
    let ub = parseUnsignedInt(b).get()
    if ua == ub:
      doAssert a == b

block propJmapIntInjectivity:
  checkProperty "propJmapIntInjectivity":
    let a = genValidJmapInt(rng, trial)
    let b = genValidJmapInt(rng)
    lastInput = $a & ", " & $b
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
    lastInput = s
    let lenientOk = parseIdFromServer(s).isOk
    let strictOk = parseId(s).isOk
    if lenientOk and not strictOk:
      witnessCount += 1
  doAssert witnessCount > 0, "no witness found for IdFromServer strict superset"

block propDateStrictSupersetOfUtcDate:
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

block propJmapIntStrictSupersetOfUnsignedInt:
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

block propDateMetamorphicCaseSensitivity:
  ## Metamorphic: if parseDate succeeds, replacing T with t at position 10
  ## must cause rejection.
  checkProperty "date metamorphic T->t":
    let s = rng.genValidDate()
    lastInput = s
    discard parseDate(s)
    var mutated = s
    mutated[10] = 't'
    doAssert parseDate(mutated).isErr
block propStrictSubsetMetamorphic:
  ## Metamorphic: if parseId(s).get() succeeds, parseIdFromServer(s).get() must also succeed.
  ## Strict is a subset of lenient.
  checkProperty "strict Id subset of lenient":
    let s = rng.genValidIdStrict(trial)
    lastInput = s
    discard parseId(s)
    discard parseIdFromServer(s)
# --- Invalid input rejection properties ---

block propInvalidDateAlwaysRejected:
  checkPropertyN "genInvalidDate always rejected by parseDate", QuickTrials:
    let s = genInvalidDate(rng, trial)
    lastInput = s
    doAssert parseDate(s).isErr

block propInvalidUtcDateAlwaysRejected:
  checkPropertyN "genInvalidUtcDate always rejected by parseUtcDate", QuickTrials:
    let s = genInvalidUtcDate(rng, trial)
    lastInput = s
    doAssert parseUtcDate(s).isErr

# --- Equivalence substitution and ordering ---

block propIdSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y).
  checkProperty "propIdSubstitution":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propUnsignedIntSubstitution:
  ## Leibniz's law: x == y implies $(x) == $(y) and hash(x) == hash(y).
  checkProperty "propUnsignedIntSubstitution":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    let b = parseUnsignedInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propJmapIntSubstitution:
  checkProperty "propJmapIntSubstitution":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    let b = parseJmapInt(n).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)

block propUnsignedIntIrreflexivity:
  ## Strict ordering: not (x < x).
  checkProperty "propUnsignedIntIrreflexivity":
    let n = genValidUnsignedInt(rng, trial)
    lastInput = $n
    let a = parseUnsignedInt(n).get()
    doAssert not (a < a)

block propJmapIntIrreflexivity:
  checkProperty "propJmapIntIrreflexivity":
    let n = genValidJmapInt(rng, trial)
    lastInput = $n
    let a = parseJmapInt(n).get()
    doAssert not (a < a)

block propUnsignedIntAsymmetry:
  ## x < y implies not (y < x).
  checkProperty "propUnsignedIntAsymmetry":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert not (b < a)

block propJmapIntAsymmetry:
  checkProperty "propJmapIntAsymmetry":
    let na = genValidJmapInt(rng, trial)
    let nb = genValidJmapInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseJmapInt(na).get()
    let b = parseJmapInt(nb).get()
    if a < b:
      doAssert not (b < a)

block propUnsignedIntLtImpliesLeq:
  ## x < y implies x <= y.
  checkProperty "propUnsignedIntLtImpliesLeq":
    let na = genValidUnsignedInt(rng, trial)
    let nb = genValidUnsignedInt(rng, trial)
    lastInput = $na & ", " & $nb
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    if a < b:
      doAssert a <= b

block propParseIdIdempotence:
  ## Parsing the same string twice yields identical results.
  checkProperty "propParseIdIdempotence":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    let first = parseId(s).get()
    let second = parseId(s).get()
    doAssert first == second

block propParseDateIdempotence:
  checkProperty "propParseDateIdempotence":
    let s = genValidDate(rng)
    lastInput = s
    let first = parseDate(s).get()
    let second = parseDate(s).get()
    doAssert first == second

# --- Cross-type consistency ---

block propStrictIdImpliesLenientId:
  ## parseId(s).get() success implies parseIdFromServer(s).get() success: strict is a subset of lenient.
  checkProperty "strict Id acceptance implies lenient Id acceptance":
    let s = genValidIdStrict(rng, trial)
    lastInput = s
    discard parseId(s).get()
    discard parseIdFromServer(s).get()

block propDateMetamorphicZToLowerZ:
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
