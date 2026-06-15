# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email read <emailId>` — full Email/get with decoded text body,
## then print headers and the joined text body. `addEmailGet` always
## returns a full `Email` (no `properties` arg — that is the separate
## `addPartialEmailGet`).
##
## `import std/tables` is required: the hub re-exports `results` but NOT
## std/tables, and `Email.bodyValues` is a `Table[PartId, EmailBodyValue]`
## whose `withValue` accessor lives there.

import jmap_client
import std/tables
import ./cli_session

func textBodyFetchOptions(): EmailBodyFetchOptions =
  ## Fetch decoded body values for the text bodies, capped at 64 KiB. The
  ## literal cap must round-trip through the smart constructor + Opt.some.
  EmailBodyFetchOptions(
    fetchBodyValues: bvsText, maxBodyValueBytes: Opt.some(parseUnsignedInt(65536).get())
  )

func decodeTextBody(email: Email): string =
  ## Join the decoded value of each non-multipart text body part. textBody
  ## parts reference values by partId; the values live in the separate
  ## bodyValues table (RFC 8621 §4.1.4). The consumer does not enable
  ## strictCaseObjects (a src/-only per-file pragma), so a plain `if` over
  ## the bool discriminator reads `part.partId` on the leaf arm fine.
  result = ""
  for part in email.textBody:
    if not part.isMultipart: # leaf part — partId/blobId live on this arm
      email.bodyValues.withValue(part.partId, bv):
        result.add bv.value

proc readEmail(emailIdArg: string): JmapResult[int] =
  # The id originates server-side (copied from `email query`), so use the
  # lenient receive-side parser; one `.lift` folds it onto the rail.
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let ctx = ?connect()
  let (b, handle) = ctx.client.newBuilder().addEmailGet(
      ctx.mailAccount,
      ids = Opt.some(direct(@[emailId])), # NOT Opt.some(directIds(...)) — double Opt
      bodyFetchOptions = textBodyFetchOptions(),
    )
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(handle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Email/get: " & outcome.error.message
    ok(1)
  of mokValue:
    let resp = outcome.value
    if resp.list.len == 0:
      stderr.writeLine "email not found"
      return ok(1)
    let e = resp.list[0] # full Email
    echo "Subject: ", e.subject.valueOr("(no subject)") # Opt[string]
    for addrs in e.fromAddr: # Opt[seq[EmailAddress]]
      if addrs.len > 0:
        echo "From: ", addrs[0].email
    echo "Preview: ", e.preview # plain string on the full Email
    echo "----"
    echo decodeTextBody(e)
    ok(0)

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email read <emailId>"
    return 2
  readEmail(args[0]).valueOr:
    stderr.writeLine error.message
    return 1
