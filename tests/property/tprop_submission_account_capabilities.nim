# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for SubmissionAccountCapabilities round-trip
## identity (RFC 8621 §1.3.2).

import std/random

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propSubmissionAccountCapabilitiesRoundTrip:
  checkProperty "SubmissionAccountCapabilities round-trip preserves all fields":
    let caps = rng.genSubmissionAccountCapabilities()
    let rt = SubmissionAccountCapabilities.fromJson(caps.toJson())
    doAssert rt.isOk, "fromJson failed"
    doAssert rt.get() == caps, "round-trip mismatch"
