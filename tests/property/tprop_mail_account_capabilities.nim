# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for MailAccountCapabilities round-trip identity
## and minValue invariant enforcement (RFC 8621 §1.3.1).

import std/json
import std/random
import std/sets

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propMailAccountCapabilitiesRoundTrip:
  checkProperty "MailAccountCapabilities round-trip preserves all fields":
    let caps = rng.genMailAccountCapabilities()
    let rt = MailAccountCapabilities.fromJson(caps.toJson())
    doAssert rt.isOk, "fromJson failed"
    doAssert rt.get() == caps, "round-trip mismatch"

testCase propMailAccountCapabilitiesMinValueInvariants:
  ## RFC 8621 §1.3.1: maxMailboxesPerEmail ≥ 1 when present;
  ## maxSizeMailboxName ≥ 100 when present. Verify the L1 smart
  ## constructor rejects boundary violations.
  let tooSmallMb = parseMailAccountCapabilities(
    Opt.some(parseUnsignedInt(0).get()),
    Opt.none(UnsignedInt),
    Opt.none(UnsignedInt),
    parseUnsignedInt(0).get(),
    initHashSet[string](),
    false,
  )
  doAssert tooSmallMb.isErr, "maxMailboxesPerEmail = 0 must be rejected"

  let tooSmallName = parseMailAccountCapabilities(
    Opt.none(UnsignedInt),
    Opt.none(UnsignedInt),
    Opt.some(parseUnsignedInt(99).get()),
    parseUnsignedInt(0).get(),
    initHashSet[string](),
    false,
  )
  doAssert tooSmallName.isErr, "maxSizeMailboxName = 99 must be rejected"

  let boundaryOk = parseMailAccountCapabilities(
    Opt.some(parseUnsignedInt(1).get()),
    Opt.none(UnsignedInt),
    Opt.some(parseUnsignedInt(100).get()),
    parseUnsignedInt(0).get(),
    initHashSet[string](),
    false,
  )
  doAssert boundaryOk.isOk, "boundary values (1, 100) must be accepted"
