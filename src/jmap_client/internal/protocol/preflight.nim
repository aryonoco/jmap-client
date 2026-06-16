# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Capability / primary-account preflight against a live ``Session``. Resolves
## and guards the account to use for a capability before dispatch, folding a
## failure onto the consumer error rail (``JmapError``, ``jeSession`` arm) when
## no account advertises the capability. Account resolution treats
## ``accountCapabilities`` as authoritative (RFC 8620 §2): it accepts the
## designated primary only when that account advertises the capability,
## otherwise the lowest-id advertising account.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables

import results

import ../types/session
import ../types/capabilities
import ../types/identifiers
import ./jmap_error

func lowestAdvertising(session: Session, kind: CapabilityKind): Opt[AccountId] =
  ## Among the accounts whose ``accountCapabilities`` advertises ``kind`` (RFC
  ## 8620 §2), the one with the lexicographically lowest ``$AccountId``.
  ## Choosing by id string makes the no-designated-primary fallback
  ## deterministic across runs — ``Table`` iteration order is not. ``Opt.none``
  ## when no account advertises the capability.
  var best = Opt.none(AccountId)
  for accountId, account in session.accounts:
    if account.hasCapability(kind):
      var isLower = true
      for current in best:
        isLower = $accountId < $current
      if isLower:
        best = Opt.some(accountId)
  best

func usableAccount(
    session: Session, kind: CapabilityKind
): Result[AccountId, JmapError] =
  ## RFC 8620 §2 account resolution for a capability. ``accountCapabilities`` is
  ## the authoritative check: the designated primary is accepted only when its
  ## own ``accountCapabilities`` advertises the capability — ``primaryAccounts``
  ## is merely a pointer into that authoritative list (§2 forbids advertising a
  ## capability the user cannot use), so a primary that is missing from
  ## ``accounts`` or does not advertise the capability is not trusted and
  ## resolution falls through. Failing the primary, the advertising account with
  ## the lowest ``$AccountId`` is returned — deterministic when several advertise
  ## and none is the designated primary (configure ``primaryAccounts`` to choose
  ## explicitly). Errs (a ``jeSession`` capability-absent fault) only when no
  ## account advertises the capability at all. ``primaryAccounts`` MAY
  ## legitimately have no entry for a supported capability (§2). Module-private
  ## — the public ``require*`` sugar names each capability.
  for accountId in session.primaryAccount(kind):
    for account in session.findAccount(accountId):
      if account.hasCapability(kind):
        return ok(accountId)
  for accountId in lowestAdvertising(session, kind):
    return ok(accountId)
  err(jmapSession(sessionFault(kind)))

func requireMail*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account to use for ``urn:ietf:params:jmap:mail`` operations
  ## (RFC 8621 §1.3.1), primary-preferred with a per-account fallback (RFC 8620
  ## §2). Folds onto the one rail so a connect flow threads on a single ``?``.
  usableAccount(session, ckMail)

func requireSubmission*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account for ``urn:ietf:params:jmap:submission`` (RFC 8621
  ## §1.3.2) — a separate capability from mail: a shared account may have mail
  ## but not submission, so this catches the gap before an EmailSubmission/set
  ## round-trip fails.
  usableAccount(session, ckSubmission)

func requireVacation*(session: Session): Result[AccountId, JmapError] =
  ## Resolves the account for ``urn:ietf:params:jmap:vacationresponse``
  ## (RFC 8621 §1.3.3). The soft fallback matters here: vacationresponse
  ## commonly has no ``primaryAccounts`` entry, so a strict primary lookup would
  ## spuriously fail on a genuinely usable account.
  usableAccount(session, ckVacationResponse)
