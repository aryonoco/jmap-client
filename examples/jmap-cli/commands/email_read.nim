# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email read <emailId>` — full Email/get with decoded text body,
## then print headers and the joined text body. `addEmailGet` always
## returns a full `Email` (no `properties` arg — that is the separate
## `addPartialEmailGet`).
##
## The body readers carry the whole body path: `textBodies(cap)` builds the fetch
## options (no `EmailBodyFetchOptions` literal, no `bvsText` scope discovery,
## no `Opt` wrap on the cap); `decodedTextBody` joins the text/plain leaves;
## and `bodyValue`, reached through the `leafTextParts` iterator, surfaces the
## per-part truncation signal. The command no longer hand-rolls the
## textBody-walk + bodyValues-by-partId join, so the `std/tables` import that
## join required is gone.

import jmap_client
import ./cli_session

proc readEmail(emailIdArg: string): JmapResult[int] =
  # The id originates server-side (copied from `email query`), so use the
  # lenient receive-side parser; one `.lift` folds it onto the rail.
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let ctx = ?connect()
  # getEmails folds newBuilder -> addEmailGet -> freeze -> send -> get and
  # collapses the single Email/get outcome onto the rail; it still carries the
  # Email-specific body-fetch options. The explicit id wraps as
  # Opt.some(direct(@[id])) (NOT Opt.some(directIds(...)) — that double-Opts);
  # textBodies(cap) sets the bvsText scope and the 64 KiB truncation cap in one
  # call (the cap is still minted through parseUnsignedInt — no integer literal
  # helper — but the scope and the Opt wrap are gone).
  let resp = ?ctx.client.getEmails(
    ctx.mailAccount,
    ids = Opt.some(direct(@[emailId])),
    bodyFetchOptions = textBodies(parseUnsignedInt(65536).get()),
  )
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
  # decodedTextBody joins every text/plain leaf into one string; `none` only
  # when no text/plain was fetched. No partId join, no std/tables.
  echo e.decodedTextBody().valueOr("(no text body fetched)")
  # The happy path above ignores truncation; the rich primitive carries it.
  # leafTextParts yields the display leaves; bodyValue reads each part's value
  # (Opt — absent when unfetched) and its isTruncated flag — which the
  # textBodies cap may have tripped.
  for part in e.leafTextParts:
    for bv in e.bodyValue(part.partId):
      if bv.isTruncated:
        stderr.writeLine "note: text part " & $part.partId & " truncated at 64 KiB"
  ok(0)

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email read <emailId>"
    return 2
  readEmail(args[0]).valueOr:
    stderr.writeLine error.message
    return 1
