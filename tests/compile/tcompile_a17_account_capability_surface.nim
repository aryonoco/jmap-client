# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A17 audit: locks the public hub surface for the typed account-
## capability vocabulary. Every type and accessor that an application
## developer must reach through ``import jmap_client`` is asserted
## declared.

import jmap_client

static:
  # ---- Types ----
  doAssert declared(AccountCapabilityEntry)
  doAssert declared(MailAccountCapabilities)
  doAssert declared(SubmissionAccountCapabilities)
  doAssert declared(AccountPolicy)
  doAssert declared(apOwned)
  doAssert declared(apOwnedReadOnly)
  doAssert declared(apShared)
  doAssert declared(apSharedReadOnly)

  # ---- Account convenience accessors ----
  doAssert compiles(default(Account).mailCapability())
  doAssert compiles(default(Account).submissionCapability())
  doAssert compiles(default(Account).supportsVacationResponse())

  # ---- AccountCapabilityEntry projections ----
  doAssert compiles(asMailAccountCapabilities(default(AccountCapabilityEntry)))
  doAssert compiles(asSubmissionAccountCapabilities(default(AccountCapabilityEntry)))
  doAssert compiles(asRawData(default(AccountCapabilityEntry)))

  # ---- ServerCapability projections ----
  doAssert compiles(asRawData(default(ServerCapability)))
  doAssert compiles(asCoreCapabilities(default(ServerCapability)))

  # ---- S2 read model: capability records expose direct public fields ----
  # The pass-through accessors and the private ``raw*`` fields are gone; each
  # numeric limit is a validated ``UnsignedInt`` distinct, so direct
  # construction cannot forge an illegal value (RFC 8620 §2). Reads land on
  # the field, not an accessor call.
  doAssert compiles(default(CoreCapabilities).maxSizeUpload)
  doAssert compiles(default(ServerCapability).uri)
  doAssert compiles(default(AccountCapabilityEntry).uri)
  doAssert compiles(default(MailAccountCapabilities).maxMailboxesPerEmail)
  doAssert compiles(default(SubmissionAccountCapabilities).maxDelayedSend)
  doAssert compiles(default(Account).name)
  doAssert compiles(default(Account).policy)
  doAssert compiles(default(Account).accountCapabilities)

  # Direct public-field construction now compiles — the former sealed
  # Pattern-A seal was removed under S2 read-model uniformity.
  doAssert compiles(CoreCapabilities(maxSizeUpload: default(UnsignedInt)))
  doAssert compiles(
    ServerCapability(uri: "x", kind: ckCore, core: default(CoreCapabilities))
  )
  doAssert compiles(
    AccountCapabilityEntry(
      uri: "x", kind: ckMail, mail: default(MailAccountCapabilities)
    )
  )
  doAssert compiles(
    Account(name: default(DisplayName), policy: apOwned, accountCapabilities: @[])
  )
