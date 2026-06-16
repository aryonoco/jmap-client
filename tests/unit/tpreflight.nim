# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the S3 capability preflight sugar requireMail /
## requireSubmission / requireVacation (RFC 8620 §2 per-account capability +
## soft primaryAccounts fallback; RFC 8621 §1.3.1-3 distinct URNs).

{.push raises: [].}

import std/tables

import jmap_client/internal/protocol/preflight
import jmap_client/internal/types/session
import jmap_client/internal/types/identifiers

import ../massertions
import ../mtestblock
import ../mfixtures

proc sessionWith(
    accounts: seq[(string, Account)], primaries: seq[(string, string)]
): Session =
  ## Builds a Session from (accountId, Account) pairs and (capabilityUri,
  ## accountId) primaryAccounts pairs, on top of the minimal fixture session.
  var args = makeSessionArgs()
  var acctTable = initTable[AccountId, Account]()
  for (id, acc) in accounts:
    acctTable[makeAccountId(id)] = acc
  args.accounts = acctTable
  var primaryTable = initTable[string, AccountId]()
  for (uri, id) in primaries:
    primaryTable[uri] = makeAccountId(id)
  args.primaryAccounts = primaryTable
  parseSessionFromArgs(args)

testCase requireMailPrimaryPreferred:
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))],
    @[("urn:ietf:params:jmap:mail", "A1")],
  )
  assertOkEq requireMail(s), makeAccountId("A1")

testCase requireMailPrefersDesignatedPrimary:
  # Two mail-advertising accounts: only the designated primary disambiguates,
  # since Table iteration order over the fallback branch is nondeterministic.
  let s = sessionWith(
    @[
      ("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()])),
      ("A2", makeAccount(accountCapabilities = @[makeMailAccountEntry()])),
    ],
    @[("urn:ietf:params:jmap:mail", "A2")],
  )
  assertOkEq requireMail(s), makeAccountId("A2")

testCase requireMailSoftFallbackNoPrimary:
  # No primaryAccounts entry, but the account advertises the mail capability.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))], @[]
  )
  assertOkEq requireMail(s), makeAccountId("A1")

testCase requireVacationSoftFallback:
  # vacationresponse commonly has no primaryAccounts entry.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeVacationAccountEntry()]))], @[]
  )
  assertOkEq requireVacation(s), makeAccountId("A1")

testCase requireSubmissionDistinctFromMail:
  # An account with mail but NOT submission must fail requireSubmission.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeMailAccountEntry()]))], @[]
  )
  assertOkEq requireMail(s), makeAccountId("A1")
  let res = requireSubmission(s)
  assertErr res

testCase requireMailErrsWhenNoAccountSupports:
  let s = sessionWith(@[("A1", makeAccount(accountCapabilities = @[]))], @[])
  let res = requireMail(s)
  assertErr res

testCase requireMailBogusPrimaryFallsThrough:
  # Non-conformant primary: primaryAccounts designates A1 for mail, but A1's
  # accountCapabilities is empty. RFC 8620 §2 makes accountCapabilities the
  # authoritative check, so the pointer is not trusted — resolution falls
  # through to the real advertiser A2.
  let s = sessionWith(
    @[
      ("A1", makeAccount(accountCapabilities = @[])),
      ("A2", makeAccount(accountCapabilities = @[makeMailAccountEntry()])),
    ],
    @[("urn:ietf:params:jmap:mail", "A1")],
  )
  assertOkEq requireMail(s), makeAccountId("A2")

testCase requireMailBogusPrimaryNoOtherErrs:
  # The designated primary A1 advertises nothing and no other account advertises
  # mail: an honest capability-absent error, not a bogus ok on the dangling pointer.
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[]))],
    @[("urn:ietf:params:jmap:mail", "A1")],
  )
  assertErr requireMail(s)

testCase requireSubmissionOkPath:
  let s = sessionWith(
    @[("A1", makeAccount(accountCapabilities = @[makeSubmissionAccountEntry()]))], @[]
  )
  assertOkEq requireSubmission(s), makeAccountId("A1")
