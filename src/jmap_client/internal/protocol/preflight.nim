# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Capability / primary-account preflight against a live ``Session``. Resolves
## and guards the account to use for a capability before dispatch, folding any
## failure onto the consumer error rail (``JmapError``, ``jeSession`` arm) when
## the session does not advertise the capability, or advertises it but has no
## primary account for it. Account resolution prefers the designated primary
## and otherwise accepts any advertising account, per RFC 8620 §2.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables

import results

import ../types/session
import ../types/capabilities
import ../types/identifiers
import ./jmap_error

func requirePrimaryAccount*(
    session: Session, kind: CapabilityKind
): Result[AccountId, JmapError] =
  ## ``ok(accountId)`` when ``session`` advertises ``kind`` and has a primary
  ## account for it; otherwise ``err`` on the one rail: ``sfCapabilityAbsent``
  ## when the capability is not advertised at all, ``sfPrimaryAccountAbsent``
  ## when it is advertised but carries no primary account. A connect-style flow
  ## can therefore thread the mail/submission capability check on a single
  ## ``?`` instead of unpacking an ``Opt`` by hand.
  if session.findCapability(kind).isNone:
    return err(jmapSession(sessionFault(sfCapabilityAbsent, kind)))
  let accountId = session.primaryAccount(kind).valueOr:
    return err(jmapSession(sessionFault(sfPrimaryAccountAbsent, kind)))
  ok(accountId)

func usableAccount(
    session: Session, kind: CapabilityKind
): Result[AccountId, JmapError] =
  ## RFC 8620 §2 account resolution for a capability: prefer the designated
  ## primary account, else any account whose ``accountCapabilities`` advertises
  ## the capability — ``primaryAccounts`` MAY legitimately have no entry for a
  ## supported capability (§2). Errs ``sfCapabilityAbsent`` only when no account
  ## supports the capability at all. When several accounts advertise the
  ## capability and none is the designated primary, an unspecified supporting
  ## account is returned — configure ``primaryAccounts`` to disambiguate.
  ## Module-private — the public ``require*`` sugar names each capability.
  for accountId in session.primaryAccount(kind):
    return ok(accountId)
  for accountId, account in session.accounts:
    if account.hasCapability(kind):
      return ok(accountId)
  err(jmapSession(sessionFault(sfCapabilityAbsent, kind)))

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
