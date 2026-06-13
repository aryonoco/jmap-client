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
  doAssert declared(WriteImplyingAccountCapabilities)

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

  # ---- Sealed Pattern-A: external raw construction must be rejected ----
  doAssert not compiles(CoreCapabilities(rawMaxSizeUpload: default(UnsignedInt)))
  doAssert not compiles(
    ServerCapability(rawUri: "x", kind: ckCore, rawCore: default(CoreCapabilities))
  )
  doAssert not compiles(
    AccountCapabilityEntry(
      rawUri: "x", kind: ckMail, rawMail: default(MailAccountCapabilities)
    )
  )
  doAssert not compiles(
    Account(rawName: "x", rawPolicy: apOwned, rawAccountCapabilities: @[])
  )
  doAssert not compiles(
    MailAccountCapabilities(rawMaxMailboxesPerEmail: Opt.none(UnsignedInt))
  )
  doAssert not compiles(
    SubmissionAccountCapabilities(rawMaxDelayedSend: default(UnsignedInt))
  )
