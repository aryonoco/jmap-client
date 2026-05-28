# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Account convenience accessors: ``mailCapability``,
## ``submissionCapability``, ``supportsVacationResponse``, plus the
## derived ``isPersonal`` / ``isReadOnly`` projections of AccountPolicy.

import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/primitives
import jmap_client/internal/types/session
import jmap_client/internal/types/validation

import ../mfixtures
import ../mtestblock

# =============================================================================
# A. mailCapability
# =============================================================================

testCase mailCapabilityReturnsSomeWhenCkMailPresent:
  let acct = parseAccount(
      "rw",
      isPersonal = true,
      isReadOnly = false,
      @[makeMailAccountEntry(makeMailAccountCapabilities())],
    )
    .get()
  doAssert acct.mailCapability().isSome

testCase mailCapabilityReturnsNoneWhenAbsent:
  let acct = parseAccount("rw", isPersonal = true, isReadOnly = false, @[]).get()
  doAssert acct.mailCapability().isNone

# =============================================================================
# B. submissionCapability
# =============================================================================

testCase submissionCapabilityReturnsSomeWhenCkSubmissionPresent:
  let acct = parseAccount(
      "rw",
      isPersonal = true,
      isReadOnly = false,
      @[makeSubmissionAccountEntry(makeSubmissionAccountCapabilities())],
    )
    .get()
  doAssert acct.submissionCapability().isSome

testCase submissionCapabilityReturnsNoneWhenAbsent:
  let acct = parseAccount("rw", isPersonal = true, isReadOnly = false, @[]).get()
  doAssert acct.submissionCapability().isNone

# =============================================================================
# C. supportsVacationResponse
# =============================================================================

testCase supportsVacationResponseTrueWhenPresent:
  let acct = parseAccount(
      "rw", isPersonal = true, isReadOnly = false, @[makeVacationAccountEntry()]
    )
    .get()
  doAssert acct.supportsVacationResponse()

testCase supportsVacationResponseFalseWhenAbsent:
  let acct = parseAccount("rw", isPersonal = true, isReadOnly = false, @[]).get()
  doAssert not acct.supportsVacationResponse()

# =============================================================================
# D. AccountPolicy ↔ derived isPersonal / isReadOnly
# =============================================================================

testCase accountPolicyOwnedPersonalReadWrite:
  let acct = parseAccount("x", isPersonal = true, isReadOnly = false, @[]).get()
  doAssert acct.policy() == apOwned
  doAssert acct.isPersonal()
  doAssert not acct.isReadOnly()

testCase accountPolicyOwnedReadOnly:
  let acct = parseAccount("x", isPersonal = true, isReadOnly = true, @[]).get()
  doAssert acct.policy() == apOwnedReadOnly
  doAssert acct.isPersonal()
  doAssert acct.isReadOnly()

testCase accountPolicySharedReadWrite:
  let acct = parseAccount("x", isPersonal = false, isReadOnly = false, @[]).get()
  doAssert acct.policy() == apShared
  doAssert not acct.isPersonal()
  doAssert not acct.isReadOnly()

testCase accountPolicySharedReadOnly:
  let acct = parseAccount("x", isPersonal = false, isReadOnly = true, @[]).get()
  doAssert acct.policy() == apSharedReadOnly
  doAssert not acct.isPersonal()
  doAssert acct.isReadOnly()

# =============================================================================
# E. B12 silent-drop — observable through convenience accessors
# =============================================================================

testCase b12SilentDropMailCapabilityOnSharedReadOnly:
  ## Read-only account constructed with a ckMail entry: parseAccount
  ## silently drops the entry, so mailCapability returns none.
  let acct = parseAccount(
      "shared-ro",
      isPersonal = false,
      isReadOnly = true,
      @[makeMailAccountEntry(makeMailAccountCapabilities())],
    )
    .get()
  doAssert acct.mailCapability().isNone
  doAssert acct.accountCapabilities().len == 0
