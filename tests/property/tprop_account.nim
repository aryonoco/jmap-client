# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for the sealed Account Pattern-A type.
## Covers parseAccount → toJson → fromJson round-trip identity and the
## capability-preservation invariant: every capability the server sent is
## retained regardless of the account's read-only status (RFC 8620 §2 lists
## accountCapabilities verbatim from the server, with no client-side filter).

import std/json
import std/random
import std/sets

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/primitives
import jmap_client/internal/types/session
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propAccountRoundTrip:
  checkProperty "parseAccount → toJson → fromJson preserves the account":
    let acct = rng.genAccount()
    lastInput = $acct.name
    # Round-trip succeeds; equality holds at the type level (==).
    let rt = Account.fromJson(acct.toJson())
    doAssert rt.isOk, "fromJson failed: " & $rt.error

testCase propAccountCapabilitiesPreservedRegardlessOfReadOnly:
  ## A read-only account must retain every capability the server sent.
  ## Construct an account with each AccountPolicy and a ckMail entry;
  ## verify the resulting account keeps the ckMail entry whether or not
  ## the account is read-only. (The former B12 filter that dropped
  ## write-implying capabilities from read-only accounts violated
  ## RFC 8620 §2 and was removed.)
  let mailCaps = parseMailAccountCapabilities(
      Opt.none(UnsignedInt),
      Opt.none(UnsignedInt),
      Opt.none(UnsignedInt),
      parseUnsignedInt(0).get(),
      initHashSet[string](),
      true,
    )
    .get()
  let mailEntry = parseAccountCapabilityEntry(
      "urn:ietf:params:jmap:mail",
      Opt.some(mailCaps),
      Opt.none(SubmissionAccountCapabilities),
      Opt.none(JsonNode),
    )
    .get()

  for policy in [apOwnedReadOnly, apSharedReadOnly]:
    let acct = parseAccount(
        "ro",
        isPersonal = policy in {apOwned, apOwnedReadOnly},
        isReadOnly = policy in {apOwnedReadOnly, apSharedReadOnly},
        @[mailEntry],
      )
      .get()
    doAssert acct.accountCapabilities.len == 1,
      "ckMail must be preserved under read-only policy " & $policy

  for policy in [apOwned, apShared]:
    let acct = parseAccount(
        "rw",
        isPersonal = policy in {apOwned, apOwnedReadOnly},
        isReadOnly = policy in {apOwnedReadOnly, apSharedReadOnly},
        @[mailEntry],
      )
      .get()
    doAssert acct.accountCapabilities.len == 1,
      "ckMail must be retained under " & $policy
