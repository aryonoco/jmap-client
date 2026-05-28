# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for CoreCapabilities round-trip identity.

import std/random

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propCoreCapabilitiesRoundTrip:
  checkProperty "CoreCapabilities round-trip preserves all fields":
    let caps = rng.genCoreCapabilities()
    let rt = CoreCapabilities.fromJson(caps.toJson())
    doAssert rt.isOk, "fromJson failed"
    doAssert rt.get() == caps, "round-trip mismatch"
