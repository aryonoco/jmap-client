# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Identity entity for RFC 8621 (JMAP Mail) section 6. An Identity stores
## information about an email address or domain a user may send as. Identity
## is a read model with plain public fields; IdentityCreate is the creation
## model with a smart constructor enforcing non-empty email.

{.push raises: [], noSideEffect.}

import ../validation
import ../primitives
import ./addresses

type Identity* {.ruleOff: "objects".} = object
  ## An Identity represents information about an email address or domain
  ## the user may send from (RFC 8621 section 6).
  id*: Id ## Server-assigned identifier.
  name*: string ## Display name for this identity, default "".
  email*: string ## Email address, immutable after creation.
  replyTo*: Opt[seq[EmailAddress]] ## Default Reply-To addresses, or none.
  bcc*: Opt[seq[EmailAddress]] ## Default Bcc addresses, or none.
  textSignature*: string ## Plain text signature, default "".
  htmlSignature*: string ## HTML signature, default "".
  mayDelete*: bool ## Whether the client may delete this identity.

type IdentityCreate* {.ruleOff: "objects".} = object
  ## Creation model for Identity — excludes server-set fields (id, mayDelete).
  email*: string ## Required, must be non-empty.
  name*: string ## Display name, default "".
  replyTo*: Opt[seq[EmailAddress]] ## Default Reply-To addresses, or none.
  bcc*: Opt[seq[EmailAddress]] ## Default Bcc addresses, or none.
  textSignature*: string ## Plain text signature, default "".
  htmlSignature*: string ## HTML signature, default "".

func parseIdentityCreate*(
    email: string,
    name: string = "",
    replyTo: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    bcc: Opt[seq[EmailAddress]] = Opt.none(seq[EmailAddress]),
    textSignature: string = "",
    htmlSignature: string = "",
): Result[IdentityCreate, ValidationError] =
  ## Smart constructor: validates non-empty email, constructs IdentityCreate.
  ## All parameters except email have RFC-matching defaults for ergonomic use.
  if email.len == 0:
    return err(validationError("IdentityCreate", "email must not be empty", ""))
  let ic = IdentityCreate(
    email: email,
    name: name,
    replyTo: replyTo,
    bcc: bcc,
    textSignature: textSignature,
    htmlSignature: htmlSignature,
  )
  doAssert ic.email.len > 0
  return ok(ic)
