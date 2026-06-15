# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli search <text>` — full-text Email/query plus SearchSnippet/get
## via the compound back-reference builder `addEmailQueryWithSnippets`.
## This is the API's ergonomic shape for search at its best — one call wires
## the query result ids into the snippet get — yet (a recorded finding) all
## four symbols of this compound are absent from the frozen public-api
## snapshot, so a snapshot-guided consumer would hand-roll the manual
## addEmailQuery + reference + addSearchSnippetGetByRef path instead.

import jmap_client
import ./cli_session

proc searchEmails(text: string): JmapResult[int] =
  let ctx = ?connect()
  # No smart constructor on EmailFilterCondition: raw object literal, then wrap.
  let filter = filterCondition(EmailFilterCondition(text: Opt.some(text)))
  let (b, chain) =
    ctx.client.newBuilder().addEmailQueryWithSnippets(ctx.mailAccount, filter)
  let dr = ?ctx.client.send(b.freeze())
  # getBoth's rail carries only dispatch faults; each field is a MethodOutcome,
  # so a method error on either invocation is data handled per branch.
  let results = ?dr.getBoth(chain) # EmailQuerySnippetResults{query, snippets}
  case results.query.kind
  of mokMethodError:
    stderr.writeLine "Email/query: " & results.query.error.message
    ok(1)
  of mokValue:
    case results.snippets.kind
    of mokMethodError:
      stderr.writeLine "SearchSnippet/get: " & results.snippets.error.message
      ok(1)
    of mokValue:
      echo "matched ", $results.query.value.ids.len, " emails"
      for s in results.snippets.value.list:
        # SearchSnippet: emailId bare Id, subject/preview Opt.
        echo $s.emailId, "  ", s.subject.valueOr(""), "  ", s.preview.valueOr("")
      ok(0)

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli search <text>"
    return 2
  searchEmails(args[0]).valueOr:
    stderr.writeLine error.message
    return 1
