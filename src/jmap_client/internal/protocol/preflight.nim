# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Capability / primary-account preflight against a live ``Session``. Resolves
## the primary account for a capability onto the one rail (``jeSession``) when
## the session does not advertise the capability, or advertises it but has no
## primary account for it. This is the S1 seed that exercises the ``jeSession``
## arm; S3 layers the ``requireMail`` / ``requireSubmission`` /
## ``requireVacation`` ergonomic sugar on top of it.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

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
