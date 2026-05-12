# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Blueprint header types
## (Part E §6.1.4 scenarios 28a-32c, §6.1.5 scenarios 33-37b,
## §6.1.5a scenarios 37c-37h).

{.push raises: [].}

import jmap_client/internal/mail/headers
import jmap_client/internal/mail/addresses
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. BlueprintEmailHeaderName (§6.1.4 scenarios 28a–32c) =============

testCase blueprintEmailHeaderNameCaseVariants: # §6.1.4 scenario 28a
  let upper = parseBlueprintEmailHeaderName("X-Custom").get()
  let lower = parseBlueprintEmailHeaderName("x-custom").get()
  let shout = parseBlueprintEmailHeaderName("X-CUSTOM").get()
  # All three normalise to the lowercase form.
  assertEq string(upper), "x-custom"
  assertEq string(lower), "x-custom"
  assertEq string(shout), "x-custom"
  # Pairwise equality via borrowed `==` from defineStringDistinctOps.
  assertEq upper, lower
  assertEq lower, shout
  # Hash consistency.
  assertEq hash(upper), hash(lower)
  assertEq hash(lower), hash(shout)

testCase blueprintEmailHeaderNameContentTypeRejected: # §6.1.4 scenario 29
  assertErr parseBlueprintEmailHeaderName("Content-Type")

testCase blueprintEmailHeaderNameForbiddenPrefixTable: # §6.1.4 scenario 29a
  assertErr parseBlueprintEmailHeaderName("Content-Disposition")
  assertErr parseBlueprintEmailHeaderName("CONTENT-TYPE")
  assertErr parseBlueprintEmailHeaderName("content-type")

testCase blueprintEmailHeaderNameColonRejected: # §6.1.4 scenario 30
  assertErr parseBlueprintEmailHeaderName("header:X-Custom:asText")
  assertErr parseBlueprintEmailHeaderName("X:Custom")

testCase blueprintEmailHeaderNameCharacterRejectionTable: # §6.1.4 scenario 31
  assertErr parseBlueprintEmailHeaderName("")
  assertErr parseBlueprintEmailHeaderName("X-Has Space")
  assertErr parseBlueprintEmailHeaderName("X-Has\tTab")
  assertErr parseBlueprintEmailHeaderName("X-Del\x7F")
  assertErr parseBlueprintEmailHeaderName("X-\x00NUL")
  assertErr parseBlueprintEmailHeaderName("X-UTF8-\xC3\xA9")

testCase blueprintEmailHeaderNamePrefixBoundary: # §6.1.4 scenario 32
  assertOk parseBlueprintEmailHeaderName("Content") # no hyphen — allowed
  assertOk parseBlueprintEmailHeaderName("contents")
    # no hyphen after "content" — allowed
  assertErr parseBlueprintEmailHeaderName("content-") # minimum forbidden value

testCase blueprintEmailHeaderNamePrintableAsciiBoundary: # §6.1.4 scenario 32a
  # The 256 possible bytes partition into 93 accepted (printable ASCII
  # minus the colon) and 163 rejected (the 162 non-printable bytes plus
  # colon, which fails the separate no-colon rule). The design doc at
  # §6.1.4 scenario 32a captures the same split after the pre-execution
  # correction.
  var acceptedPos0 = 0
  var rejectedPos0 = 0
  var acceptedPosMid = 0
  var rejectedPosMid = 0
  for b in 0 .. 255:
    let ch = char(b)
    let atStart = $ch & "-xxxxxxxx"
    if parseBlueprintEmailHeaderName(atStart).isOk:
      inc acceptedPos0
    else:
      inc rejectedPos0
    let inside = "x-xxxx" & $ch & "xxx"
    if parseBlueprintEmailHeaderName(inside).isOk:
      inc acceptedPosMid
    else:
      inc rejectedPosMid
  assertEq acceptedPos0, 93
  assertEq rejectedPos0, 163
  assertEq acceptedPosMid, 93
  assertEq rejectedPosMid, 163

testCase blueprintEmailHeaderNameStrictOnlyCommitment: # §6.1.4 scenario 32c
  # Accidentally adding a lenient server-side sibling would open a second
  # construction path through the creation aggregate and violate the
  # unidirectional creation-vocabulary rule (R1-3).
  assertNotCompiles parseBlueprintEmailHeaderNameFromServer("X-Custom")
  assertNotCompiles parseBlueprintBodyHeaderNameFromServer("X-Custom")

# ============= B. BlueprintBodyHeaderName (§6.1.5 scenarios 33–37b) =============

testCase blueprintBodyHeaderNameAllowedTable: # §6.1.5 scenario 33
  assertOk parseBlueprintBodyHeaderName("Content-Type")
  assertOk parseBlueprintBodyHeaderName("Content-Disposition")
  assertOk parseBlueprintBodyHeaderName("Content-Language")
  assertOk parseBlueprintBodyHeaderName("X-Custom")

testCase blueprintBodyHeaderNameCteExactNameRejected: # §6.1.5 scenario 35
  assertErr parseBlueprintBodyHeaderName("Content-Transfer-Encoding")
  assertErr parseBlueprintBodyHeaderName("CONTENT-TRANSFER-ENCODING")
  assertErr parseBlueprintBodyHeaderName("content-transfer-encoding")
  assertErr parseBlueprintBodyHeaderName("Content-transfer-Encoding")

testCase blueprintBodyHeaderNameCteSuffixBoundary: # §6.1.5 scenario 35c
  # "Content-Transfer-Encoding-X" is not an exact-name match — allowed.
  assertOk parseBlueprintBodyHeaderName("Content-Transfer-Encoding-X")

testCase blueprintBodyHeaderNameUtf8HomoglyphRejected: # §6.1.5 scenario 35d
  # UTF-8 bytes visually approximating "Content-Type"; the printable-ASCII
  # check fires before the exact-name check.
  assertErr parseBlueprintBodyHeaderName("\xC3\x83\xC2\xA7ontent-Type")

testCase blueprintBodyHeaderNameCharacterRejectionTable: # §6.1.5 scenario 36
  assertErr parseBlueprintBodyHeaderName("")
  assertErr parseBlueprintBodyHeaderName("X-Has Space")
  assertErr parseBlueprintBodyHeaderName("X-Has\tTab")
  assertErr parseBlueprintBodyHeaderName("header:X-Custom:asText")

testCase blueprintBodyHeaderNameCaseEquivalence: # §6.1.5 scenario 37b
  let upper = parseBlueprintBodyHeaderName("X-Custom").get()
  let lower = parseBlueprintBodyHeaderName("x-custom").get()
  assertEq upper, lower
  assertEq hash(upper), hash(lower)

# ============= C. BlueprintHeaderMultiValue (§6.1.5a scenarios 37c–37h) =============

testCase blueprintHeaderMultiValueRawSingle: # §6.1.5a scenario 37c
  let res = rawMulti(@["v1"])
  assertOk res
  let mv = res.get()
  assertEq mv.form, hfRaw
  assertLen mv.rawValues, 1

testCase blueprintHeaderMultiValueRawMulti: # §6.1.5a scenario 37d
  let res = rawMulti(@["v1", "v2"])
  assertOk res
  assertLen res.get().rawValues, 2

testCase blueprintHeaderMultiValueEmptyRejected: # §6.1.5a scenario 37e
  # Delegates to parseNonEmptySeq — empty input rejected.
  assertErr rawMulti(@[])

testCase blueprintHeaderMultiValuePerFormHelpers: # §6.1.5a scenario 37f
  # textMulti
  let tm = textMulti(@["t"])
  assertOk tm
  assertEq tm.get().form, hfText
  assertLen tm.get().textValues, 1
  # addressesMulti
  let addr1 = EmailAddress(name: Opt.none(string), email: "a@example.com")
  let am = addressesMulti(@[@[addr1]])
  assertOk am
  assertEq am.get().form, hfAddresses
  assertLen am.get().addressLists, 1
  # groupedAddressesMulti
  let grp1 = EmailAddressGroup(name: Opt.none(string), addresses: @[addr1])
  let gm = groupedAddressesMulti(@[@[grp1]])
  assertOk gm
  assertEq gm.get().form, hfGroupedAddresses
  assertLen gm.get().groupLists, 1
  # messageIdsMulti
  let mm = messageIdsMulti(@[@["<id@example.com>"]])
  assertOk mm
  assertEq mm.get().form, hfMessageIds
  assertLen mm.get().messageIdLists, 1
  # dateMulti
  let d = parseDate("2026-04-13T12:00:00Z").get()
  let dm = dateMulti(@[d])
  assertOk dm
  assertEq dm.get().form, hfDate
  assertLen dm.get().dateValues, 1
  # urlsMulti
  let um = urlsMulti(@[@["https://example.com"]])
  assertOk um
  assertEq um.get().form, hfUrls
  assertLen um.get().urlLists, 1

testCase blueprintHeaderMultiValueRawSingleConvenience: # §6.1.5a scenario 37g
  # rawSingle returns BlueprintHeaderMultiValue directly, no Result.
  let mv = rawSingle("value")
  assertEq mv.form, hfRaw
  assertLen mv.rawValues, 1

testCase blueprintHeaderMultiValueDirectCaseObjectEquality: # §6.1.5a scenario 37h
  let ne = parseNonEmptySeq(@["v"]).get()
  let direct = BlueprintHeaderMultiValue(form: hfRaw, rawValues: ne)
  let viaHelper = rawMulti(@["v"]).get()
  # Compare the discriminator and the active branch's field directly. The
  # generic case-object `==` generated by Nim uses the parallel ``fields``
  # iterator, which does not traverse case-object branches — so an `==`
  # call on ``BlueprintHeaderMultiValue`` fails to compile until a
  # dedicated equality helper is introduced in Step 14 (L-6 family).
  assertEq direct.form, viaHelper.form
  assertEq direct.rawValues, viaHelper.rawValues
