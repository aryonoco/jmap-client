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

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli search <text>"
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  # No smart constructor on EmailFilterCondition: raw object literal, then wrap.
  let filter = filterCondition(EmailFilterCondition(text: Opt.some(args[0])))
  let (b, chain) =
    ctx.client.newBuilder().addEmailQueryWithSnippets(ctx.mailAccount, filter)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let results = dr.getBoth(chain).valueOr: # EmailQuerySnippetResults{query, snippets}
    stderr.writeLine "extraction failed: " & error.message
    return 1
  echo "matched ", $results.query.ids.len, " emails"
  for s in results.snippets.list: # SearchSnippet: emailId bare Id, subject/preview Opt
    echo $s.emailId, "  ", s.subject.valueOr(""), "  ", s.preview.valueOr("")
  return 0
