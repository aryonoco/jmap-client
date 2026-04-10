# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared email address sub-types for RFC 8621 (JMAP Mail).
## EmailAddress (RFC 8621 section 4.1.2.3) and EmailAddressGroup
## (RFC 8621 section 4.1.2.4) are used by Identity, Email, and
## EmailSubmission entities.

{.push raises: [], noSideEffect.}

import ../validation

type EmailAddress* {.ruleOff: "objects".} = object
  ## An email address with optional display name (RFC 8621 section 4.1.2.3).
  name*: Opt[string] ## Display name, or none if absent.
  email*: string ## RFC 5322 addr-spec (non-empty, not format-validated).

type EmailAddressGroup* {.ruleOff: "objects".} = object
  ## A named or unnamed group of email addresses (RFC 8621 section 4.1.2.4).
  name*: Opt[string] ## Group name, or none if not a named group.
  addresses*: seq[EmailAddress] ## Members of the group (may be empty).

func parseEmailAddress*(
    email: string, name: Opt[string] = Opt.none(string)
): Result[EmailAddress, ValidationError] =
  ## Smart constructor: validates non-empty email, constructs EmailAddress.
  ## Name defaults to none. No addr-spec format validation — JMAP servers
  ## deliver clean JSON with pre-parsed addresses.
  if email.len == 0:
    return err(validationError("EmailAddress", "email must not be empty", ""))
  let ea = EmailAddress(name: name, email: email)
  doAssert ea.email.len > 0
  return ok(ea)
