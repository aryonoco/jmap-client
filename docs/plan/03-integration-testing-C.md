# Integration Testing Plan — Phase C

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **C0 — Helper extraction (preparatory)** | **Done** (2026-05-01) | Three new helpers landed in `tests/integration/live/mlive.nim`: `seedEmailsWithSubjects`, `seedThreadedEmails`, `resolveCollationAlgorithms`. Mirrors Phase B's preparatory commit `e11ca86`. Cumulative live tests: 11/11 (no test consumes the helpers yet). |
| **C1 — Filter, sort, snippet, thread chain** | **In progress** | Six live tests (Steps 13–18) establishing wire compatibility for `Filter[C]` / `FilterOperator` / `Comparator` / `EmailComparator` plus the H1 `ChainedHandles[A, B]` and `EmailQueryThreadChain` surfaces. Steps 13–16 done (2026-05-01); cumulative live tests 15/17. Step 16 surfaced one parser-layer divergence: `SearchSnippetGetResponse` lacked a typedesc-overload `fromJson` for dispatch's mixin resolution — fixed in `mail/methods` ahead of the test commit. |

Live-test pass rate (cumulative target across Phase A + B + C): **17 / 17**.
Wire-format divergences root-caused at the `fromJson`/`toJson` layer:
*to be catalogued as Phase C steps land.*

## Context

Phase A closed on 2026-05-01 with six live tests passing in 6.2 s against
Stalwart 0.15.5: `tsession_discovery`, `tcore_echo_live`,
`tmailbox_get_all_live`, `tidentity_get_live`,
`temail_query_get_chain_live`, `temail_set_keywords_live`. Phase B1 closed
the same day with five additional tests bringing the cumulative pass rate
to 11/11 in ~12 s: `tthread_get_live`, `tvacation_get_set_live`,
`tmailbox_set_crud_live`, `temail_changes_live`, `temail_query_changes_live`.

Both phases used `filter = Opt.none, sort = Opt.none` throughout. The
entire `Filter[C]` framework (`src/jmap_client/framework.nim:39-46`) and
the `FilterOperator` enum (`framework.nim:28-32`) — `foAnd`, `foOr`,
`foNot` — have unit and serde coverage but zero wire validation. The
`EmailFilterCondition` type (`src/jmap_client/mail/mail_filters.nim:62-103`)
with its 19 condition variants (`inMailbox`, `text`, `subject`,
`hasKeyword`, `before`, `after`, `from`, `to`, `cc`, `bcc`, `body`,
`header`, `hasAttachment`, plus thread-keyword and size variants) is
unexercised against any real server. The `Comparator` type
(`framework.nim:56-79`) and the case-object `EmailComparator`
(`src/jmap_client/mail/email.nim:56-99`) with its `eckPlain` and
`eckKeyword` arms have not been wire-tested either.

Two H1 type-lift surfaces likewise have no live coverage despite their
builders being shipped. `ChainedHandles[A, B]`
(`src/jmap_client/dispatch.nim:288-295`) and its `getBoth` extractor
(`dispatch.nim:302-313`) underpin the two-call chain pattern that
`addEmailQueryWithSnippets` (`mail/mail_methods.nim:248-270`) emits. The
purpose-built `EmailQueryThreadChain` four-handle record
(`mail/mail_builders.nim:367-375`) and its `getAll` extractor
(`mail_builders.nim:386-403`) carry the RFC 8621 §4.10 four-call inbox
display workflow. Both have unit-test coverage; neither has been
exercised end-to-end against Stalwart.

`SearchSnippet/get` (RFC 8621 §5; `src/jmap_client/mail/snippet.nim:14-19`)
has unit and serde tests but has never been exercised against a real
server. Its custom builder `addSearchSnippetGet`
(`mail/mail_methods.nim:194-214`) and the chain variant
`addEmailQueryWithSnippets` are both shipped without live validation.

Phase C closes that gap before any work begins on the remaining surfaces:
Phase D (Email body content + header forms + Email/parse), Phase E
(EmailSubmission end-to-end), Phase F (multi-account ACL + Email/copy
cross-account + adversarial wire formats), and Phase G (oversize, RFC 2047
encoded words, fractional dates, empty-vs-null edge cases). Push, blob,
and Layer 5 C ABI remain out of scope for the entire integration-testing
campaign — they are not yet implemented in the library.

## Strategy

Continue Phase A and B's bottom-up discipline. Each step adds **exactly
one new dimension** the prior steps have not touched. When Step N fails,
Steps 1..N-1 have been proven, so the bug is isolated.

Phase C's dimensions, in build order:

1. The simplest filter shape — a single `EmailFilterCondition` leaf via
   `Filter[C]`'s `fkCondition` arm.
2. The recursive operator-tree shape — `FilterOperator` branches (AND, OR,
   NOT) over multiple leaves via the `fkOperator` arm.
3. The sort dimension — `Comparator` ascending and descending, plus an
   advertised `collation` round-trip.
4. The first SearchSnippet/get test — standalone form via
   `addSearchSnippetGet` with literal email ids. Proves the SearchSnippet
   parser and capability wiring before chain plumbing is exercised.
5. The first H1 chain test — `addEmailQueryWithSnippets` exercising
   `ChainedHandles[A, B]` via `getBoth`. If Step 16 passes and Step 17
   fails, the bug is in chain back-reference encoding or
   `ChainedHandles` extraction — not the SearchSnippet parser.
6. The four-call thread chain — `addEmailQueryWithThreads` and
   `EmailQueryThreadChain` via `getAll`. The most ambitious step in
   Phase C and the natural capstone, mirroring Phase A Step 7 (chained
   query+set with state-mismatch sad path) and Phase B Step 12
   (queryChanges) being the visible-difficulty climb of their phases.

Step 18 is visibly harder than Step 13 by construction. That asymmetry is
intentional: the climb stays inside Phase C rather than spilling into
Phase D.

Phase C grows to **six steps** (Phase A and B were five each). The
additional step splits SearchSnippet/get into standalone-then-chained
forms. Without the split, a single SearchSnippet step would conflate
parser correctness with chain plumbing — a Step 16 failure could land in
either layer. The split preserves the "Step N depends only on Steps
1..N-1's proofs" invariant.

Phase C deliberately does NOT include any inline sad-path tests for
`metUnsupportedFilter` / `metUnsupportedSort`. The sealed
`EmailFilterCondition` type and the case-object `EmailComparator` make
malformed filters and sorts unrepresentable at the type level — testing
the server's rejection requires raw-JSON injection bypassing the typed
builders, which is fundamentally adversarial and a natural fit for Phase F.

## Phase C0 — Helper extraction (preparatory commit)

Add three exported helpers to `tests/integration/live/mlive.nim`. Mirrors
Phase B's preparatory commit `e11ca86` precedent: helpers extracted in
their own commit before any test consumes them, so a step-level failure
can never be confused with a helper bug.

### `seedEmailsWithSubjects`

```nim
proc seedEmailsWithSubjects*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subjects: openArray[string],
): Result[seq[Id], string]
```

Seeds N minimal text/plain emails differentiated only by subject. Wraps
`seedSimpleEmail` per id; returns the server-assigned ids in the same
order as `subjects`. Used by Steps 13/14/15/16/17.

Implementation: iterate `subjects`, call `seedSimpleEmail` with each, and
short-circuit on the first error per the railway pattern. The
`creationLabel` argument can be derived from the index (`"seed-N"`) since
the test bodies do not consume it.

### `seedThreadedEmails`

```nim
proc seedThreadedEmails*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subjects: openArray[string],
    rootMessageId: string,
): Result[seq[Id], string]
```

The first email gets `messageId = @[rootMessageId]`; each subsequent email
gets `inReplyTo = @[rootMessageId]` and `references = @[rootMessageId]`.
Consumes `EmailBlueprint`'s settable `messageId`/`inReplyTo`/`references`
fields (`src/jmap_client/mail/email_blueprint.nim:680-684`). Used by
Step 18.

Implementation: build N `EmailBlueprint` values in a loop, threading the
root-vs-reply discriminator through `parseEmailBlueprint`. Same
short-circuit-on-error railway pattern as `seedEmailsWithSubjects`.

### `resolveCollationAlgorithms`

```nim
func resolveCollationAlgorithms*(
    session: Session,
): HashSet[CollationAlgorithm]
```

Reads `session.coreCapabilities.collationAlgorithms`. Pure helper (no IO);
takes the already-fetched session. Used by Step 15.

Implementation: a one-line accessor. Exists as a named helper for symmetry
with the seed helpers and to keep test bodies free of capability-traversal
boilerplate.

### Commit shape

One commit. SPDX header preserved. New helpers added in source order
(seed helpers before the pure capability accessor). No existing helper
modified. The commit must pass `just test` (testament joinable suite —
helpers are unused, so no test exercises them yet).

## Phase C1 — Six live tests

All tests live under `tests/integration/live/` and follow the established
idiom verbatim (Phase A established it, Phase B reinforced it):

- SPDX header + copyright block on lines 1–2
- `##` docstring (lines 4–~25) explaining purpose, Stalwart prerequisite,
  `testament_skip.txt` listing, and the `loadLiveTestConfig().isOk` guard
  semantics
- Imports in fixed order: `std/...` first, then `results`, then
  `jmap_client`, `jmap_client/client`, then `./mconfig` and `./mlive`
- Single top-level `block <camelCaseName>:` wrapping the test body
- `let cfgRes = loadLiveTestConfig(); if cfgRes.isOk:` guard so the file
  joins testament's megatest cleanly when Stalwart is down
- `var client = initJmapClient(...).expect("initJmapClient")`
- `client.close()` immediately before the block exit — explicit, no
  `defer`
- `doAssert <invariant>, "<narrative explaining the invariant>"`
- All new files added to `tests/testament_skip.txt` so `just test` stays
  deterministic; run via `just test-integration`

Write them in order. Each step builds on what the previous step proved.

### Step 13: `temail_query_filter_simple_live.nim` — Email/query with one EmailFilterCondition

Scope: first wire test of any `EmailFilterCondition`. Validates
`Filter[EmailFilterCondition]` leaf serialisation (bare condition object
per `framework.nim:39-46` discriminator `fkCondition`), sparse `toJson`
emit (`mail/serde_mail_filters.nim:108-133`), and Stalwart's evaluator
agreement on a single condition.

Body — one block, four sequential `client.send` segments:

1. Resolve inbox via `resolveInboxId`.
2. `seedEmailsWithSubjects(client, mailAccountId, inbox, @["phase-c-13
   match", "phase-c-13 miss alpha", "phase-c-13 miss bravo"])`. Capture
   the three ids.
3. Build `Email/query` with
   `filter = Opt.some(filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-c-13 match"))))`. Use `subject` rather than `text` —
   Stalwart's `text` matches across multiple fields; `subject` isolates
   the dimension cleanly.
4. Send. Assert `queryResp.ids.len == 1` and the returned id equals the
   seeded "phase-c-13 match" id.

What this proves:

- `urn:ietf:params:jmap:mail` capability auto-injection for filtered
  Email/query
- `Filter[EmailFilterCondition]` leaf wire shape (bare condition object)
- `EmailFilterCondition.toJson` sparse emit (only `subject` set, all
  other fields absent per the Decision B16 client-to-server discipline)
- Stalwart's filter evaluator returns the seeded match exactly

Anticipated wire-format divergences:

- Stalwart's `subject` filter may be substring or full-token. The seeded
  subjects are `phase-c-13 <token>`-prefixed so a substring match on the
  full subject string returns exactly one. If Stalwart tokenises and
  matches `match` against the inbox-wide corpus, additional results may
  surface. Document the observed behaviour in the Predictable Divergences
  catalogue.

### Step 14: `temail_query_filter_tree_live.nim` — Email/query with FilterOperator AND/OR/NOT

Scope: recursive `Filter[C]` with `FilterOperator` branches. Validates
the `fkOperator` arm wire shape (`{"operator": "AND"|"OR"|"NOT",
"conditions": [...]}` per `serde_framework.nim`), all three operators,
and Stalwart's evaluator agreement on classical AND/OR/NOT semantics.

Body — three sub-tests in one block, all sharing the same seeded corpus:

1. Resolve inbox.
2. `seedEmailsWithSubjects(client, mailAccountId, inbox, @["phase-c-14
   alpha-1", "phase-c-14 alpha-2", "phase-c-14 bravo-1", "phase-c-14
   bravo-2", "phase-c-14 charlie-1"])`.
3. **AND test:** filter =
   `filterOperator(foAnd, @[filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-c-14 alpha"))), filterCondition(EmailFilterCondition(
   subject: Opt.some("1")))])`. Expected: 1 email (`alpha-1`). Assert.
4. **OR test:** filter =
   `filterOperator(foOr, @[filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-c-14 alpha"))), filterCondition(EmailFilterCondition(
   subject: Opt.some("phase-c-14 bravo")))])`. Expected: 4 emails
   (alpha-1, alpha-2, bravo-1, bravo-2). Assert.
5. **NOT test:** filter =
   `filterOperator(foAnd, @[filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-c-14"))), filterOperator(foNot, @[filterCondition(
   EmailFilterCondition(subject: Opt.some("alpha")))])])`. Expected: 3
   emails (bravo-1, bravo-2, charlie-1). Assert. The wrapper-AND scopes
   the negation to phase-c-14 emails, avoiding negation against
   Stalwart's entire mailbox.

What this proves:

- Filter[C] recursive structure round-trips through serialisation
- All three FilterOperator variants ("AND" / "OR" / "NOT") accepted by
  Stalwart's evaluator
- Stalwart agrees with classical Boolean semantics
- `serde_framework.nim`'s operator-arm `toJson` produces wire-compatible
  JSON

Anticipated wire-format divergences:

- NOT semantics: RFC 8620 §5.5 specifies NOT applies to the conjunction
  of its conditions. With one condition this is unambiguous and matches
  classical negation. The wrapper-AND in sub-test 5 avoids relying on
  Stalwart's interpretation of full-mailbox negation.
- Operator string casing: `FilterOperator` emits `"AND"` / `"OR"` /
  `"NOT"` (uppercase per the enum string-backing at
  `framework.nim:28-32`). Stalwart accepts these per RFC 8620 §5.5; if a
  divergence appears, the fix lives in `serde_framework.nim` only after
  confirming the RFC's normative casing.

### Step 15: `temail_query_sort_live.nim` — Email/query with EmailComparator (ascending + descending + advertised collation)

Scope: `Comparator` (`framework.nim:56-79`) and `EmailComparator`
(`mail/email.nim:56-99`) wire serde. Validates the `isAscending` flag in
both directions, the `eckPlain` arm with `pspSubject`, and an explicit
`collation` round-trip when Stalwart advertises one.

Body — one block, four-to-five sequential `client.send` segments:

1. Fetch session, resolve inbox.
2. Capture `colls = resolveCollationAlgorithms(session)`.
3. `seedEmailsWithSubjects(client, mailAccountId, inbox, @["phase-c-15
   zulu", "phase-c-15 alpha", "phase-c-15 mike"])` — three subjects in
   non-alphabetical insertion order.
4. **Ascending sort:** Email/query with
   `filter = filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-c-15")))` and
   `sort = Opt.some(@[plainComparator(pspSubject,
   isAscending = Opt.some(true), collation = Opt.none(CollationAlgorithm))])`.
   Capture result ids; for each id fetch the subject via Email/get;
   assert order is alpha → mike → zulu.
5. **Descending sort:** same query with `isAscending = Opt.some(false)`.
   Assert order is zulu → mike → alpha.
6. **Explicit collation (conditional):** if `colls.len > 0`, project the
   set into a `seq` (sorted lexicographically for determinism, since
   `HashSet` iteration order is unspecified) and pick element 0. Re-issue
   the ascending sort with `collation = Opt.some(<chosen>)`. Assert order
   unchanged. Log the chosen collation in the test's narrative `doAssert`
   message for traceability.

What this proves:

- `Comparator.toJson` with `isAscending` and `collation` fields
- `EmailComparator` `eckPlain` arm round-trips through Stalwart
- Stalwart correctly orders results in both directions on a plain string
  property
- An advertised collation round-trips successfully when echoed back in a
  Comparator

Anticipated wire-format divergences:

- Stalwart 0.15.5 may advertise zero collation algorithms. Sub-test 6 is
  conditional on `colls.len > 0`; if empty, the test logs this fact and
  skips the explicit-collation sub-test. The assertion is "the value
  advertised in `coreCapabilities` round-trips successfully when echoed
  in a Comparator," which holds vacuously for empty sets.
- `metUnsupportedSort` sad-path is NOT exercised here. The sealed
  `EmailComparator` type prevents constructing a Comparator with an
  unsupported property; testing the server's rejection requires raw-JSON
  injection. Deferred to Phase F.
- Stalwart may compare subjects using a Unicode case-insensitive default
  even when no `collation` is sent. The seeded subjects are lowercase
  only, so case sensitivity is not under test.

### Step 16: `tsearch_snippet_get_standalone_live.nim` — SearchSnippet/get with literal email ids

Scope: `SearchSnippet/get` with literal email ids. First wire test of
`addSearchSnippetGet` (`mail/mail_methods.nim:194-214`). Proves the
standalone form before the chained form (Step 17) — bottom-up isolation.

Body — one block, three sequential `client.send` segments:

1. Resolve inbox.
2. `seedEmailsWithSubjects(client, mailAccountId, inbox, @["phase-c-16
   token-α", "phase-c-16 token-β"])`. Capture both ids as `id1`, `id2`.
3. Build `addSearchSnippetGet(b, mailAccountId, filter =
   filterCondition(EmailFilterCondition(subject: Opt.some("phase-c-16"))),
   firstEmailId = id1, restEmailIds = @[id2])`.
4. Send. Assert `snippetResp.list.len == 2`.
5. For each snippet: assert `emailId in @[id1, id2]` and that at least
   one of `subject` / `preview` is `Opt.some` with non-empty contents.

What this proves:

- `addSearchSnippetGet` literal-id wire shape Stalwart accepts
- `SearchSnippet.fromJson` (`mail/snippet.nim:14-19`) accepts Stalwart's
  actual snippet shape
- `urn:ietf:params:jmap:mail` capability auto-injection for
  SearchSnippet/get
- Stalwart returns snippets for filter-matching emails when given a
  literal id list
- The non-ASCII tokens (`α`, `β`) round-trip through Stalwart's snippet
  highlighter without parser failure

Anticipated wire-format divergences:

- Stalwart may emit `null` or `""` for `subject` when no highlight is
  present, even when `preview` is non-empty (or vice versa). The lenient
  `Opt[string]` parse handles both; the test asserts at least one is
  non-empty, accepting null/empty for the other.
- The `<mark>` highlighting fragments may use HTML entities or raw
  Unicode for non-ASCII tokens. The test does NOT assert the exact
  highlight format — only non-emptiness on at least one of the two
  fields.

### Step 17: `temail_query_with_snippets_live.nim` — Email/query → SearchSnippet/get chained via ChainedHandles

Scope: Email/query → SearchSnippet/get chained via
`addEmailQueryWithSnippets` (`mail/mail_methods.nim:248-270`). First
exercise of the H1 `ChainedHandles[A, B]` generic
(`dispatch.nim:288-295`) and its `getBoth` extractor
(`dispatch.nim:302-313`). Validates back-reference plumbing across two
chained method calls.

Body — one block, two sequential `client.send` segments:

1. Resolve inbox.
2. `seedEmailsWithSubjects(client, mailAccountId, inbox, @["phase-c-17
   alpha unique", "phase-c-17 bravo distinct"])`.
3. Build `addEmailQueryWithSnippets(b, mailAccountId, filter =
   filterCondition(EmailFilterCondition(subject: Opt.some("phase-c-17"))))`.
4. Send. Extract via
   `let pair = resp.getBoth(chainHandles).expect("getBoth")`.
5. Assert `pair.first.ids.len == 2` (Email/query result).
6. Assert `pair.second.list.len == 2` (SearchSnippet/get result) and that
   each snippet's `emailId` appears in `pair.first.ids`.

What this proves:

- `ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]`
  extraction via `getBoth`
- Back-reference encoding in `addEmailQueryWithSnippets` (filter and
  emailIds both referenced from the prior Email/query call)
- Stalwart's JSON Pointer evaluator agrees with the chain's `/ids`
  reference path
- Two invocations in one Request and two responses in one Response, both
  parseable through the H1 chain handle

Anticipated wire-format divergences:

- If Step 16 passes but Step 17 fails, the bug is isolated to chain
  back-reference encoding in `addEmailQueryWithSnippets` or
  `ChainedHandles` extraction in `dispatch.nim` — not the SearchSnippet
  parser itself. This isolation is the explicit reason Steps 16 and 17
  exist as separate tests rather than a single chain-only test.

### Step 18: `temail_query_thread_chain_live.nim` — Email/query → Email/get(threadId) → Thread/get → Email/get(display) via EmailQueryThreadChain

Scope: RFC 8621 §4.10 four-call workflow via `addEmailQueryWithThreads`
(`mail/mail_builders.nim:405-470`) and the H1 purpose-built
`EmailQueryThreadChain` record (`mail/mail_builders.nim:367-375`, four
handles: `queryH`, `threadIdFetchH`, `threadsH`, `displayH`). Most
ambitious step in Phase C — proves the arity-4 type-lift end-to-end.

Body — one block with a re-fetch loop:

1. Resolve inbox.
2. `seedThreadedEmails(client, mailAccountId, inbox, @["phase-c-18 root",
   "phase-c-18 reply"], rootMessageId =
   "<phase-c-18-root@example.com>")`. Capture both ids. The helper sets
   `messageId = @[rootMessageId]` on the root and
   `inReplyTo = @[rootMessageId]`, `references = @[rootMessageId]` on the
   reply.
3. **Re-fetch loop** (Stalwart threading is asynchronous; mirrors
   Phase B Step 8's anticipated pattern). Up to 5 attempts, 200 ms apart:
   1. Build `addEmailQueryWithThreads(b, mailAccountId, filter =
      filterCondition(EmailFilterCondition(subject:
      Opt.some("phase-c-18"))))`.
   2. Send.
   3. Extract via
      `let all = resp.getAll(threadHandles).expect("getAll")`.
   4. If `all.displayH.list.len >= 2`: exit loop.
   5. Otherwise, sleep 200 ms (`os.sleep(200)`).
   6. After 5 attempts without success: `doAssert false, "Stalwart
      threading did not converge within 1 s — extend re-fetch budget or
      investigate Stalwart 0.15.5 threading pipeline"`.
4. After loop succeeds: assert every emailId in `all.displayH.list` is a
   member of the corresponding `Thread.emailIds` from
   `all.threadsH.list`.
5. Assert subjects in `all.displayH.list` include both
   `"phase-c-18 root"` and `"phase-c-18 reply"`.

What this proves:

- `EmailQueryThreadChain` four-handle record deserialisation across one
  Request / one Response round-trip
- `getAll` extractor (`mail_builders.nim:386-403`) projects all four
  responses into the four-handle result record
- Three sequential back-references resolve correctly:
  Email/query.ids → Email/get → list[*].threadId → Thread/get →
  list[*].emailIds → Email/get
- Stalwart's threading pipeline groups emails by RFC 5322
  In-Reply-To / References headers within the convergence window
- End-to-end inbox-display workflow returns coherent, parseable data

Anticipated wire-format divergences:

- **Threading asynchrony.** Stalwart may not have processed threading by
  query time. The re-fetch loop accommodates this. If 5 × 200 ms is
  insufficient, the fix is at the test layer (extend budget) NOT at the
  parser. Document as a known Stalwart 0.15.5 quirk in the catalogue
  below.
- **Subject-based threading fallback.** If Stalwart's threading falls
  back to subject heuristics when In-Reply-To references don't match a
  stored Message-ID, the assertion still passes (both seeded emails
  share the "phase-c-18" subject prefix). Document the observed
  threading mode in the test's narrative `doAssert` message.
- **Thread id is server-determined.** The test does NOT assert a
  specific `threadId` — only that both seeded emails appear in the same
  thread.

## Predictable wire-format divergences (Phase C catalogue)

Catalogue of what live testing typically reveals at each new surface
Phase C introduces. The strict/lenient boundary in serde is the right
place to fix each one.

1. **Subject vs text filter coverage.** Step 13/14: Stalwart's `text`
   filter spans multiple fields (subject + body + sender) per the
   default; tests isolate dimensions by using `subject` directly. If a
   future surface needs `text`, expect cross-field matches.
   **Observed at Step 13 (2026-05-01):** Stalwart 0.15.5 tokenises the
   `subject` filter input — a multi-word filter matches every subject
   sharing *any* token, not the literal substring. Tests must filter
   on a single discriminator token (`"aardvark"`) rather than a phrase
   that overlaps the corpus prefix (`"phase-c-13 match"`). Test-layer
   fix; no parser change.
2. **Empty collation set.** Step 15: Stalwart 0.15.5 may advertise zero
   collation algorithms. Explicit-collation sub-tests are conditional on
   `coreCapabilities.collationAlgorithms.len > 0`. If empty, the sub-test
   is skipped and the absence is logged; the parser is unaffected.
3. **Snippet null vs empty string.** Step 16/17: Stalwart may emit
   `null` or `""` for `subject` / `preview` when no highlight is present.
   The lenient `Opt[string]` parse handles both. Tests assert
   non-emptiness on at least one of the two fields, never both.
   **Observed at Step 16 (2026-05-01):** Stalwart 0.15.5 populates
   `subject` with `<mark>`-bracketed match text and `preview` with a
   highlighted body fragment when both surfaces match the filter; the
   parser handles this without further accommodation.

7. **Custom response types missing typedesc fromJson overload.**
   Step 16: `SearchSnippetGetResponse` had a named-function parser
   (`searchSnippetGetResponseFromJson`) but no typedesc-overload
   `fromJson(typedesc[T], node, path)` for dispatch's
   `mixin fromJson` to resolve. Fixed by adding a one-line wrapper
   next to the named function in `src/jmap_client/mail/mail_methods.nim`,
   mirroring the established `Mailbox.fromJson` / `MailboxCreatedItem.fromJson`
   pattern. No parser logic change. `EmailParseResponse` has the same
   gap and will be fixed when Phase D's first live Email/parse test
   surfaces it (strict scope discipline — no pre-emptive fixes).
4. **Threading asynchrony.** Step 18: Stalwart's threading pipeline is
   asynchronous; thread-membership assertions need re-fetch loops. The
   fix is always at the test layer (extend budget); never paper over by
   weakening the assertion.
5. **Subject-based threading fallback.** Step 18: when In-Reply-To
   references don't match a stored Message-ID, Stalwart may fall back to
   subject heuristics. Tests with a shared subject prefix succeed under
   either threading path; document the observed mode.
6. **FilterOperator string casing.** Step 14: `FilterOperator` emits
   `"AND"` / `"OR"` / `"NOT"` uppercase per the enum string-backing at
   `framework.nim:28-32`. Stalwart accepts these per RFC 8620 §5.5. If a
   divergence appears, confirm the RFC's normative casing before
   modifying `serde_framework.nim`.

## Success criteria

Phase C is complete when:

- [ ] Phase C0's `mlive.nim` helper-extraction commit lands and the three
  new helpers (`seedEmailsWithSubjects`, `seedThreadedEmails`,
  `resolveCollationAlgorithms`) are exported and consumed by at least one
  Phase C test
- [ ] All six new live test files exist under `tests/integration/live/`
  with the established idiom (license, docstring, single `block`,
  `loadLiveTestConfig().isOk` guard, `client.close()` before block exit,
  `doAssert` with narrative messages)
- [ ] All six new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six and Phase B five
- [ ] `just test-integration` exits 0 with seventeen live tests passing
  (six from Phase A, five from Phase B, six from Phase C)
- [ ] Every wire-format divergence Phase C surfaces has been root-caused
  at the `fromJson` / `toJson` layer or documented in this file's
  catalogue, NOT papered over in the test
- [ ] The seventeen tests run in under 60 s total wall-clock on the
  devcontainer (Phase A's six ran in 6.2 s; Phase B's eleven cumulative
  in ~12 s; Phase C's six additions plus the threading re-fetch loop
  keep comfortable headroom under a one-minute budget)
- [ ] No new Nimble dependencies, no new devcontainer packages — the
  2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro at
  `01-integration-testing-A.md:249-255`) holds throughout

## Out of scope for Phase C

Explicitly deferred to later phases:

- **Email body and header form fetching** (Email/get with
  `bodyProperties`, `fetchTextBodyValues`, `fetchHTMLBodyValues`,
  `maxBodyValueBytes`, header-form properties like
  `header:Foo:asAddresses` / `asMessageIds` / `asDate` per RFC 8621
  §4.1.2) — Phase D
- **Email/parse** (RFC 8621 §4.9 attached `message/rfc822` parsing) —
  Phase D
- **Pagination** (`position`, `anchor`, `anchorOffset` on Email/query;
  `metAnchorNotFound` MethodError sad path) — Phase F or G
- **`metUnsupportedFilter` and `metUnsupportedSort` sad paths** against
  synthetic property names — Phase F (requires raw-JSON injection
  bypassing the typed builders, which the current sealed
  `EmailFilterCondition` and `EmailComparator` types correctly forbid)
- **EmailSubmission end-to-end** (alice → bob delivery, implicit chaining
  via `onSuccessUpdateEmail`, `DeliveryStatus` shape, `ParsedSmtpReply`
  round-trip with real RFC 3464 enhanced status codes) — Phase E
- **Multi-account ACL** (alice ↔ bob shared mailbox access, `Email/copy`
  between accounts, `forbidden` SetError variants on cross-account
  writes) — Phase F
- **Adversarial wire-format edge cases** (RFC 2047 encoded-word names in
  `EmailAddress.name`, fractional-second dates, empty-vs-null table
  entries, oversized request rejection at `maxSizeRequest`,
  control-character handling at byte boundaries) — Phase G
- **Push notifications, blob upload/download, Layer 5 C ABI** — not yet
  implemented in the library; not part of the integration-testing
  campaign at all until they exist
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in `tests/stress/`
  if/when it becomes a goal

Phase D will exercise Email body content, header forms, and Email/parse
against real MIME data once Phase C's filter/sort surface is proven.
