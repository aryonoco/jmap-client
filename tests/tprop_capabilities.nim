# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for CapabilityKind parsing and URI round-trips.

import std/random

import pkg/results

import jmap_client/capabilities
import ./mproperty

block propCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes on arbitrary string":
    discard parseCapabilityKind(genArbitraryString(rng))

block propCapabilityKindKnownRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

block propCapabilityKindUnknownReturnsNone:
  doAssert capabilityUri(ckUnknown).isNone

block propCapabilityKindAllKnownHaveUri:
  for kind in CapabilityKind:
    if kind != ckUnknown:
      doAssert capabilityUri(kind).isSome
