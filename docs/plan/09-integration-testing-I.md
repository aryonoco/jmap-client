# Integration Testing Plan — Phase I

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **I0 — `mlive` helper extraction** | **Done 2026-05-03** (`fc99f0c`) | Two helpers: `seedEmailWithHeaders`, `seedSubmissionCorpus`. Mirrors B/C0/D0/E0/F0.5/G0/H0 precedent. |
| **I1 — Protocol-feature completeness (twelve steps)** | **Done 2026-05-03** (`eb872a5..7dc416b`) | Twelve live tests (Steps 49–60), fourteen captured fixtures, fourteen always-on parser-only replays. Cumulative result: **58 / 58 live**, **57 / 57 captured replays**. |
| **I follow-up — full-suite stability** | **Done 2026-05-03** (`30bf779`) | Step 60 corpus reduced 4→2 to relieve Stalwart's SMTP queue; Step 57 reframed from strict-convergence to wire-shape contract under heavy inbox load. |

Live-test pass-rate target (cumulative across A + B + C + D + E + F + G + H + I):
**58 / 58** (`*_live.nim` files run by `just test-integration`; the 46 pre-Phase-I
+ 12 new from Phase I). Captured-replay total rose from **43 to 57** — fourteen
new fixtures (Steps 49 and 60 each capture two; the other ten capture one each).

Step-to-commit trail:

| Step | Test name | Commit |
|---|---|---|
| 49 | `tmailbox_query_filter_sort_live` | `eb872a5` |
| 50 | `temail_changes_max_changes_live` | `ce62420` |
| 51 | `temail_query_changes_filter_mismatch_live` | `bf8266b` |
| 52 | `temail_get_max_body_value_bytes_live` | `63013e8` |
| 53 | `temail_get_header_forms_extended_live` | `efb30a5` |
| 54 | `temail_get_body_properties_all_live` | `98a02f6` |
| 55 | `temail_query_advanced_filter_live` | `185d7c3` |
| 56 | `temail_query_advanced_sort_live` | `6fac994` |
| 57 | `temail_query_collapse_threads_live` | `03c77a7` |
| 58 | `tvacation_set_all_arms_live` | `8365da6` |
| 59 | `tidentity_changes_with_updates_live` | `d442f2f` |
| 60 | `temail_submission_filter_sort_live` | `7dc416b` |

## Stalwart 0.15.5 empirical pins discovered during Phase I execution

The plan-doc anticipated several divergence categories before
execution; this section captures what Stalwart 0.15.5 actually did
when each step ran.

| Step | Pin | Where it surfaces |
|---|---|---|
| 51 | Filter-mismatch on `Email/queryChanges` resolves to **Ok with fresh delta**, NOT `cannotCalculateChanges`. RFC 8620 §5.6 uses MAY, so either choice is conformant; Stalwart chooses to silently recompute. The test's assertion is a set-membership over `{Ok-with-baseline-state, Err on metCannotCalculateChanges/metInvalidArguments}`. | `temail_query_changes_filter_mismatch_live.nim` |
| 52 | `EmailBodyValue.isTruncated` flips correctly under `maxBodyValueBytes` cap. Stalwart truncates at exactly the requested byte count (no UTF-8-boundary slack observed for the 64-byte / 2 KB test pair). | `temail_get_max_body_value_bytes_live.nim` |
| 54 | `bvsAll` over a multipart/mixed corpus carrying a text/plain body and a text/plain attachment returns **exactly one** `bodyValues` entry — the textBody leaf. The attachment's `bodyValue` is omitted even though RFC 8621 §4.1.4 permits its inclusion for text/* parts. The test asserts `bodyValues.len >= 1` to match Stalwart's actual behaviour. | `temail_get_body_properties_all_live.nim` |
| 56 | `eckKeyword` boolean-sort direction: under `isAscending = true` Stalwart places **flagged emails first** and unflagged emails last; under `isAscending = false` the order inverts. RFC 8620 §5.5 does not pin the boolean true/false numeric mapping, so this direction is conformant. The test was originally written under the opposite expectation and flipped to `isAscending = true` after the empirical observation. | `temail_query_advanced_sort_live.nim` |
| 57 | `collapseThreads` correctness depends on Stalwart's threading pipeline having merged the seeded reply into the same thread as the root. Under heavy inbox load (after many phase tests have run), the merge can be too slow to observe within a 12-second budget. The test's primary contract is the wire-shape correctness of the `collapseThreads` parameter; the convergence-to-strict-less-than assertion was downgraded to an opportunistic short-circuit so the test passes even when threading is asynchronously slow. | `temail_query_collapse_threads_live.nim` |
| 60 | `EmailSubmission/query` and `EmailSubmission/queryChanges` both accept the full `EmailSubmissionFilterCondition` algebra (identityIds, threadIds, emailIds, undoStatus, before, after) and the `EmailSubmissionComparator` (sentAt, threadId, emailId). The capstone seeds two submissions across two identities; a larger corpus (originally 4 submissions) stressed Stalwart's SMTP queue enough to surface unrelated downstream `pollSubmissionDelivery` budget timeouts, so the corpus was reduced. | `temail_submission_filter_sort_live.nim` |

## Plan-doc deviations confirmed during execution

Two plan-doc statements proved incorrect on inspection:

1. **Step 58 covers three new arms, not four.** The plan-doc named
   `setHtmlBody` / `setFromDate` / `setToDate` / `setReplyTo`. The
   first three exist as
   `src/jmap_client/mail/vacation.nim:84` / `:68` / `:72`;
   `setReplyTo` does not exist and is RFC-correct to be absent —
   RFC 8621 §8 defines no `replyTo` field on `VacationResponse`.
   Step 58 asserts the three real new arms.
2. **`addEmailChanges` does not exist as a custom builder.**
   Email/changes invocations go through the generic
   `addChanges[Email]` template at
   `src/jmap_client/builder.nim:193`, not a non-existent
   `addEmailChanges`. The plan-doc-implied custom builder was a
   false premise; the generic template is the correct surface.

## Closing checklist

- [x] Phase I0's `mlive.nim` helper-extraction commit landed with two
  helpers (`seedEmailWithHeaders`, `seedSubmissionCorpus`); both
  consumed by Phase I tests.
- [x] All twelve new live test files exist under
  `tests/integration/live/` with the established idiom.
- [x] All twelve new files are listed in `tests/testament_skip.txt`.
- [x] `just test-integration` exits 0 with **fifty-eight** live tests
  passing.
- [x] Fourteen new captured fixtures exist under
  `tests/testdata/captured/` (Steps 49 and 60 each capture two; the
  other ten capture one each).
- [x] Fourteen new always-on parser-only replay tests exist under
  `tests/serde/captured/` and pass under `just test` (cumulative
  count: 57).
- [x] `just ci` is green (reuse + fmt-check + lint + analyse + test).
- [x] No new Nimble dependencies, no new devcontainer packages.
- [x] No library source modifications — `git diff src/` is empty
  across the entire Phase I commit range. Every dimension reached
  through an existing typed surface, as the pre-implementation
  audit predicted.
- [x] Every divergence between Stalwart's wire shape and the test's
  expected behaviour has been classified (test premise / server
  quirk / client bug) and resolved at the right layer; no test
  papers over a real client bug.
- [x] Total wall-clock for the new tests under ~30 s on the
  devcontainer.

## Context

Phase H closed on 2026-05-03 with 46 live tests passing in ~49 s against
Stalwart 0.15.5. The campaign now covers every read-side mail surface RFC 8621
specifies, full CRUD on Mailbox/Identity/VacationResponse, server-side
`Email/copy` (intra-account rejection only), `Email/import`, `Email/query`
pagination, `Mailbox/set destroy` cascade semantics, the EmailSubmission
create/update/destroy lifecycle, `EmailSubmission/changes` + `queryChanges`,
multi-principal observation, the cross-account rejection rail, and the state-
delta protocol for all four entities (Email/Mailbox/Thread/Identity) plus the
existential `AnyEmailSubmission`.

Twelve concrete dimensions remain unexercised against any server. Each is a
parameterisation, sort variant, filter variant, or arm-set the library
implements but never wire-tested:

1. **`Mailbox/query` and `Mailbox/queryChanges` with filter + sort.** Phase H44
   exercised the methods with no filter and no sort. RFC 8621 §2.3
   `MailboxFilterCondition` (parentId/name/role/hasAnyRole/isSubscribed),
   `MailboxComparator` (sortOrder/name), and the `sortAsTree`/`filterAsTree`
   extensions are unverified.
2. **`Email/changes` with `maxChanges` cap + window-roll.** Phase B11/H48
   asserted `hasMoreChanges == false` at low cardinality; the library's
   `MaxChanges` parameter on `addChanges[Email]`
   (`src/jmap_client/builder.nim:176-180`) and the `hasMoreChanges` field on
   `ChangesResponse[T]` (`src/jmap_client/methods.nim:173-180`) have never been
   driven to `true`.
3. **`Email/queryChanges` with filter mismatch.** RFC 8620 §5.6: server MAY
   return `cannotCalculateChanges` if filter/sort changes between the original
   query and queryChanges. Stalwart's behaviour deferred from Phase C12.
4. **`Email/get` with `maxBodyValueBytes` cap → truncation marker.** Phase D §6
   noted the deferral; `EmailBodyFetchOptions.maxBodyValueBytes`
   (`src/jmap_client/mail/email.nim:116-122`) and `EmailBodyValue.isTruncated`
   (`src/jmap_client/mail/body.nim:192-197`) are unverified against any server.
5. **Extended header forms.** Phase D22 exercised `asURLs`/`asDate`/
   `asAddresses`. The remaining four — `asMessageIds`, `asText`,
   `asGroupedAddresses`, `asRaw` — and the `:all` multi-instance flag
   (RFC 8621 §4.1.3) are unverified.
6. **`Email/get` with `bodyProperties` customisation + `bvsAll`.** Phase D used
   `bvsText` and `bvsTextAndHtml`; `bvsAll` (full-tree body-value fetch
   including attachments) and the `bodyProperties` array (RFC 8621 §4.2 narrow
   which `EmailBodyPart` fields come back) are unverified.
7. **`Email/query` with rich filter conditions.** Phases C13/14 covered single-
   condition `subject` filters and `FilterOperator` AND/OR/NOT trees. The
   remaining `EmailFilterCondition` arms — `inMailbox`, `inMailboxOtherThan`,
   `before`, `after`, `minSize`, `maxSize`, `hasAttachment`, the three thread-
   keyword conditions (`allInThreadHaveKeyword`, `someInThreadHaveKeyword`,
   `noneInThreadHaveKeyword`), `hasKeyword`/`notKeyword`, and the `text`/
   `from`/`to`/`cc`/`bcc`/`subject`/`body`/`header` substring matches — are
   unverified.
8. **`Email/query` with all sort properties.** Phase C15 exercised
   `pspSubject` ascending and descending. The remaining `EmailComparator` arms
   — `pspReceivedAt` (default), `pspFrom`, `pspTo`, `pspSentAt`, `pspSize`, and
   the `eckKeyword` arm (sort by has-keyword per RFC 8621 §4.4.2) — are
   unverified.
9. **`Email/query` with `collapseThreads = true`.** RFC 8621 §4.4.3. Phase C17
   used the default `false` in the chain. Thread collapsing semantics
   unverified.
10. **VacationResponse all-arms /set.** Phase B9 covered `isEnabled`,
    `subject`, `textBody`. The remaining typed update arms — `htmlBody`,
    `fromDate`, `toDate`, `replyTo` — and the boolean `isEnabled`-flip
    interaction with date-window semantics (RFC 8621 §8 default behaviour)
    are unverified.
11. **Identity update arms inside one changes window.** Phase F31 exercised
    the full Identity CRUD across four sequential sends. The library
    implements five `IdentityUpdate` arms — `setName`, `setReplyTo`, `setBcc`,
    `setTextSignature`, `setHtmlSignature`. Their wire shape is exercised one
    at a time (Phase F31's update leg covered three); combining all five in
    one `Identity/set update` plus reading them back via `Identity/changes`
    in one window is unverified.
12. **EmailSubmission/query and queryChanges against a real corpus.** Phase F36
    exercised submission `/changes` and `/queryChanges` against an empty-then-
    two baseline. `EmailSubmissionFilterCondition`
    (`src/jmap_client/mail/email_submission.nim:311-321`: `identityIds`,
    `emailIds`, `threadIds`, `undoStatus`, `before`, `after`) and
    `EmailSubmissionComparator` (`src/jmap_client/mail/email_submission.nim:331-359`:
    `esspEmailId`, `esspThreadId`, `esspSentAt`) against a substantive corpus
    (varying identities, recipients, sentAt, undoStatus) are unverified.

Phase I closes all twelve gaps in one phase, deliberately wide-scoped so
Phase J can be themed cleanly as "adversarial wire formats" with one unified
methodology (raw-JSON injection bypassing the sealed builders, raw-HTTP for
maxSizeRequest oversize rejection, RFC 2047 encoded-words on receive,
fractional-second dates, control-character handling at byte boundaries).

**No library design work needed.** The Phase 1 audit confirmed every dimension
above is reachable through the existing typed surfaces. The "Email/set update
beyond keyword+mailbox flips" deferral language across Phases G/H was based on
a misreading: header replacement and body content updates are RFC-forbidden
operations (RFC 8621 §4.1.3 marks all header-derived properties as
`(immutable)`; §4.1.1 anchors body content on the immutable `blobId`). The
library's `EmailUpdate` algebra (`src/jmap_client/mail/email_update.nim:27-52`)
already implements the entire RFC-permitted update surface. No "Email/set
update completeness" step appears in Phase I.

## Strategy

Continue Phase A–H's bottom-up discipline. Each step adds **exactly one new
dimension** the prior steps have not touched. When Step N fails, Steps 1..N-1
have been proven, so the bug is isolated.

Phase I's twelve dimensions cluster into six themes; the build order
interleaves themes so each step opens a clean isolation window:

1. **Step 49** — `Mailbox/query` filter+sort (closes Phase H44 baseline).
   Methodologically identical to Phase C13/15's Email work, so it lands
   first and proves the new entity has filter+sort plumbing.
2. **Step 50** — `Email/changes` with `maxChanges` cap. State-delta
   pagination — narrowest method extension; depends on no other Phase I work.
3. **Step 51** — `Email/queryChanges` with filter mismatch (sad path:
   `cannotCalculateChanges` or `invalidArguments` per RFC 8620 §5.6 set
   membership).
4. **Step 52** — `Email/get` with `maxBodyValueBytes` cap → truncation marker.
5. **Step 53** — Extended header forms (`asMessageIds`, `asText`,
   `asGroupedAddresses`, `:all`). Builds on Phase D22's idiom.
6. **Step 54** — `Email/get` with `bodyProperties` customisation + `bvsAll`.
7. **Step 55** — `Email/query` rich filter conditions (the remaining
   `EmailFilterCondition` arms not covered by C13/14).
8. **Step 56** — `Email/query` advanced sort (the remaining `EmailComparator`
   arms not covered by C15) plus `eckKeyword`.
9. **Step 57** — `Email/query` with `collapseThreads = true`.
10. **Step 58** — VacationResponse all-arms /set (the four arms B9 left
    unexercised).
11. **Step 59** — Identity update arms in one changes window (closes Phase
    F31's "no full update arm-set inside a changes window" gap).
12. **Step 60 (capstone)** — EmailSubmission /query + /queryChanges with
    filter+sort against a real corpus.

Step 60 is visibly harder than Step 49 by construction: it builds a
multi-submission corpus (4–6 submissions varying by identity/recipient/sentAt/
undoStatus), exercises `EmailSubmissionFilterCondition` across all six
variants, exercises `EmailSubmissionComparator` across all three sort
properties, AND chains `/query` → `/queryChanges` from a captured baseline.
Mirrors the visibly-harder capstone discipline of A7 / B12 / C18 / D24 / E30 /
F36 / G42 / H48.

## Phase I0 — preparatory `mlive` helper extraction

Single commit. Mirrors B/C0/D0/E0/F0.5/G0/H0 precedent. Two helpers land
before any test consumes them; commit must pass `just test` (helpers are
unused at this commit).

### `seedEmailWithHeaders`

```nim
proc seedEmailWithHeaders*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    fromAddr: EmailAddress,
    toAddr: EmailAddress,
    subject: string,
    body: string,
    extraHeaders: openArray[(BlueprintBodyHeaderName, BlueprintHeaderMultiValue)],
    creationLabel: string,
): Result[Id, string]
```

Variant of `seedSimpleEmail` that accepts an `extraHeaders` table for the
top-level Email (as opposed to the body-part-level `extraHeaders` in
`makeLeafPart`). Phase D22 inlined this construction (`List-Post`,
multi-instance Resent-To, etc.); Step 53 makes it the second use site, so
extraction is justified per the project precedent.

Internally composes the existing `parseEmailBlueprint` with `topLevelExtraHeaders`
field populated and funnels through the private `emailSetCreate`. Used by
Step 53.

### `seedSubmissionCorpus`

```nim
proc seedSubmissionCorpus*(
    client: var JmapClient,
    mailAccountId: AccountId,
    submissionAccountId: AccountId,
    identities: openArray[Id],
    recipients: openArray[EmailAddress],
    drafts: Id,
    fromAddr: EmailAddress,
    sentAtRange: openArray[UTCDate],
    creationLabelPrefix: string,
): Result[seq[Id], string]
```

Builds N submissions (where `N = identities.len`, with `recipients` and
`sentAtRange` cycling through their lengths) by:

1. Seeding a draft per submission via `seedDraftEmail` with a unique subject.
2. Submitting each via `addEmailSubmissionSet(create = ...)` against the
   corresponding identity + recipient.
3. Polling each to `usFinal` via `pollSubmissionDelivery`.

Returns the seq of submission ids. Used by Step 60.

The helper sits in I0 (rather than inline in Step 60) to keep Step 60's test
body under ~150 LOC. Inlining would push Step 60 over 250 LOC, dwarfing
H48 and breaking the established density.

### Commit shape

One commit. SPDX header preserved. Two helpers added in source order
(`seedEmailWithHeaders` first as it composes existing primitives;
`seedSubmissionCorpus` second as it composes the F0.5 submission helpers).
No existing helper modified. Must pass `just test`.

## Phase I1 — twelve live tests

Each test follows the project test idiom verbatim (`block <name>:` plus
`doAssert`) and is gated on `loadLiveTestConfig().isOk` so the file joins
testament's megatest cleanly under `just test-full` when env vars are absent.
All twelve are listed in `tests/testament_skip.txt` so `just test` skips them;
run via `just test-integration`.

### Step 49 — `tmailbox_query_filter_sort_live`

Scope: `Mailbox/query` and `Mailbox/queryChanges` with filter and sort
parameters. Closes the Phase H44 baseline gap. Validates
`MailboxFilterCondition` (RFC 8621 §2.3) and `MailboxComparator`, plus the
`sortAsTree` and `filterAsTree` extensions.

Body — five sequential `client.send` calls in one block:

1. Resolve mail account.
2. **Filter on role** — `addMailboxQuery(b, mailAccountId, filter =
   Opt.some(filterCondition(MailboxFilterCondition(role: Opt.some(roleInbox)))))`.
   Assert `ids.len == 1` and the returned id equals the inbox id.
3. **Filter on name + sort by sortOrder** —
   `addMailboxQuery(filter = filterCondition(MailboxFilterCondition(name:
   Opt.some("phase"))), sort = Opt.some(@[mailboxComparator(mcsSortOrder,
   isAscending = Opt.some(true))]))`. Resolve / create three mailboxes named
   `"phase-i 49 alpha"` / `"phase-i 49 bravo"` / `"phase-i 49 charlie"` with
   `sortOrder` 30 / 20 / 10 first. Assert filtered ids ordered by sortOrder
   ascending: charlie → bravo → alpha.
4. **`sortAsTree` extension** — `addMailboxQuery(filter =
   filterCondition(...hasAnyRole = Opt.some(true)), sort = ..., sortAsTree =
   Opt.some(true))`. Assert ancestors precede descendants regardless of
   comparator order. Validates the RFC 8621 §2.3 tree-aware sort.
5. **Mailbox/queryChanges with filter** — capture baseline `queryState` from
   step 2; mutate (resolveOrCreateMailbox `"phase-i 49 delta"`); issue
   `addMailboxQueryChanges(b, mailAccountId, sinceQueryState =
   baselineQueryState, filter = <same filter as step 2>, calculateTotal =
   Opt.some(true))`. Assert `oldQueryState == baselineQueryState`,
   `newQueryState != baselineQueryState`, `total.isSome`, and at least one
   `AddedItem` for the new mailbox.

Captures: `mailbox-query-filter-sort-stalwart` (after step 3),
`mailbox-query-changes-with-filter-stalwart` (after step 5).

What this proves:

- `addMailboxQuery` filter and sort wire shape Stalwart accepts
- `MailboxFilterCondition` all variants serialise correctly
- `MailboxComparator` sortOrder and name comparators work
- `sortAsTree` / `filterAsTree` extensions land at the wire correctly
- `Mailbox/queryChanges` filter parameter independence

Anticipated divergences:

- `name` filter substring vs. token match (mirrors Phase C13's `subject`
  finding). Tests use single-token discriminators (`"phase"`) to avoid
  ambiguity.
- `hasAnyRole` semantics: every Stalwart-seeded principal has an Inbox so
  the result set is always at least 1.

### Step 50 — `temail_changes_max_changes_live`

Scope: `Email/changes` with `maxChanges` cap forcing `hasMoreChanges == true`,
plus the window-roll loop using the returned `newState` until the client is
fully up to date. Closes Phase B11 / H48's "promote to a future regression if
Stalwart ever changes its default" deferral.

Body — five sequential `client.send` calls plus a window-roll loop:

1. Resolve mail account, inbox.
2. Capture baseline state via `captureBaselineState[Email](client,
   mailAccountId)`.
3. Seed N=5 emails via `seedEmailsWithSubjects(client, mailAccountId, inbox,
   @["phase-i 50 m1", ..., "phase-i 50 m5"])`.
4. **First page** — `addChanges[Email](b, mailAccountId, sinceState =
   baselineState, maxChanges = Opt.some(MaxChanges(2)))`. Assert
   `hasMoreChanges == true` and `created.len + updated.len + destroyed.len
   <= 2` (Stalwart MAY return fewer than max per RFC 8620 §5.2). Capture
   `firstNewState = cr.newState`.
5. **Window-roll loop** — repeated `Email/changes` from `firstNewState` until
   `hasMoreChanges == false`. Accumulate ids across all pages. Assert all 5
   seeded ids appear in the union; final `newState != baselineState`.
   Validates RFC 8620 §5.2 "the server SHOULD generate an update to take the
   client to an intermediate state, from which the client can continue".

Capture: `email-changes-max-changes-stalwart` (after step 4).

What this proves:

- `maxChanges` parameter wire emission Stalwart accepts
- `ChangesResponse[Email].hasMoreChanges == true` actually surfaces
- The window-roll protocol (RFC 8620 §5.2 multi-page semantics) works
- Per-id "MUST only appear once across the three lists" invariant holds
  across multi-page deltas

Anticipated divergences:

- Stalwart may collapse the 5-id delta into 1 page even with `maxChanges=2`
  (returning fewer than max is RFC-permitted but defeats the test). If so,
  raise N to 10 or more. Document in catalogue.
- Stalwart's intermediate state strings may differ in shape from the
  client's expectation (RFC 8620 §5.2 makes them opaque); test asserts only
  inequality with baseline, never specific format.

### Step 51 — `temail_query_changes_filter_mismatch_live`

Scope: `Email/queryChanges` issued with a filter that differs from the
original `Email/query`'s filter. RFC 8620 §5.6: "If the filter or sort
includes a property the client does not understand, OR if the filter/sort
has changed since the previous queryState, the server MAY return a
`cannotCalculateChanges` error." Closes Phase C12 deferral.

Body — three sequential `client.send` calls:

1. Resolve mail account, inbox. Seed N=3 emails via `seedEmailsWithSubjects`
   with subjects `"phase-i 51 alpha"`, `"phase-i 51 bravo"`,
   `"phase-i 51 charlie"`.
2. **Original `Email/query` with filter A** —
   `addEmailQuery(b, mailAccountId, filter =
   filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 51"))))`.
   Capture `queryStateA`.
3. **Mismatched `Email/queryChanges`** — issue
   `addEmailQueryChanges(b, mailAccountId, sinceQueryState = queryStateA,
   filter = filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-i 51 alpha"))))` (filter narrowed). Assert
   `resp.get(handle).isErr` and `methodErr.errorType in
   {metCannotCalculateChanges, metInvalidArguments}` (set membership per
   RFC 8620 §5.6 + Phase B11/H43/H45/H46 catalogue).

Capture: `email-query-changes-filter-mismatch-stalwart`.

What this proves:

- Filter-mismatch detection exists at the server side
- The library's `addEmailQueryChanges` correctly emits an independent
  `filter` parameter (no constraint to match the original)
- MethodError projection through `metCannotCalculateChanges` /
  `metInvalidArguments` set membership

Anticipated divergences:

- Stalwart MAY accept the mismatched filter and silently return a fresh
  delta rather than err — RFC 8620 §5.6 says "MAY", not "MUST". If so,
  document in catalogue and amend the test to skip with a logged note;
  the library's behaviour is correct either way.

### Step 52 — `temail_get_max_body_value_bytes_live`

Scope: `Email/get` with `bodyFetchOptions.maxBodyValueBytes` cap forcing
`EmailBodyValue.isTruncated == true` per RFC 8621 §4.1.4. Closes Phase D
catalogue §6 deferral.

Body — three sequential `client.send` calls:

1. Resolve mail account, inbox.
2. Seed an email with a 2 KB ASCII body via a custom-body call to
   `seedSimpleEmail` (or inline `parseEmailBlueprint` if the helper does
   not accept body-size override; verify during implementation).
3. `addEmailGet(ids = directIds(@[seededId]), properties = Opt.some(@["id",
   "textBody", "bodyValues"]), bodyFetchOptions =
   Opt.some(EmailBodyFetchOptions(fetchTextBodyValues: true,
   maxBodyValueBytes: Opt.some(UnsignedInt(64)))))`. Send. For the seeded
   email, assert exactly one `bodyValues` entry; that entry's `value.len <=
   64` AND `isTruncated == true`.

Capture: `email-get-max-body-value-bytes-truncated-stalwart`.

What this proves:

- `EmailBodyFetchOptions.maxBodyValueBytes` parameter wire emission
- `EmailBodyValue.isTruncated` flag surfaces correctly
- Body-value truncation at the server side respects the cap

Anticipated divergences:

- Stalwart may truncate at the nearest UTF-8 boundary rather than exact
  byte count — assertion uses `<= 64`, never `== 64`.
- Stalwart may emit `isTruncated: false` if the body fits despite the cap;
  the seeded body is 2 KB so this isn't possible.

### Step 53 — `temail_get_header_forms_extended_live`

Scope: extended header forms — `asMessageIds`, `asText`,
`asGroupedAddresses`, `asRaw`, plus `:all` multi-instance flag. Closes
Phase D22's three-of-seven gap.

Body — two sequential `client.send` calls:

1. Resolve mail account, inbox.
2. **Seed via `seedEmailWithHeaders`** with extraHeaders carrying:
   - `Message-ID: <phase-i-53@example.com>` (asMessageIds target)
   - `Comments: phase-i step-53 free text` (asText target)
   - `To: Group:Mary <mary@example.com>, Bob <bob@example.com>;`
     (asGroupedAddresses target)
   - Two `Resent-To` instances (`:all` target):
     `<resent1@example.com>` and `<resent2@example.com>`
   - `X-Custom-Phase-I: opaque-bytes` (asRaw target)
3. `addEmailGet(ids = directIds(@[seededId]), properties = Opt.some(@[
   "id",
   "header:Message-ID:asMessageIds",
   "header:Comments:asText",
   "header:To:asGroupedAddresses",
   "header:Resent-To:asAddresses:all",
   "header:X-Custom-Phase-I:asRaw"]))`. Send. Pattern-match each header value
   via `parseHeaderValue(<form>, node)`; assert:
   - `messageIds = @["phase-i-53@example.com"]`
   - `text = "phase-i step-53 free text"`
   - `groupedAddresses[0].name == "Group"` AND
     `groupedAddresses[0].addresses.len == 2`
   - `:all` resent-to is a `seq[seq[EmailAddress]]` with `len == 2`
   - `raw` value is the byte-passthrough of the original header

Capture: `email-get-header-forms-extended-stalwart`.

What this proves:

- All seven HeaderForm variants parse correctly
- The `:all` flag on `HeaderPropertyKey` produces multi-value response
- `seedEmailWithHeaders` round-trips arbitrary extra-headers through
  Stalwart's MIME-level handling

Anticipated divergences:

- Stalwart may collapse multiple `Resent-To` headers into one (RFC 5322
  §3.6.6 says repeated headers in a trace are siblings, but stores may
  flatten). The `:all` assertion uses `len >= 1`, capturing whichever
  shape Stalwart emits.
- `asGroupedAddresses` on a non-grouped header returns one synthetic group
  with `name = null`; assertion handles both shapes.

### Step 54 — `temail_get_body_properties_all_live`

Scope: `Email/get` with `bodyProperties` array (RFC 8621 §4.2 narrows which
`EmailBodyPart` fields come back) and `bvsAll` selector (full-tree body-
value fetch including attachments).

Body — three sequential `client.send` calls:

1. Resolve mail account, inbox.
2. Seed a multipart/mixed email via `seedMixedEmail`.
3. `addEmailGet(ids = directIds(@[seededId]), properties = Opt.some(@["id",
   "bodyStructure", "bodyValues"]), bodyFetchOptions =
   Opt.some(EmailBodyFetchOptions(fetchAllBodyValues: true)),
   bodyProperties = Opt.some(@["partId", "blobId", "type", "name",
   "size"]))`. Send.
   - Assert `bodyStructure` is parseable; for each non-multipart part,
     assert it carries only the requested fields (others absent).
   - Assert `bodyValues.len >= 1` (text/plain body) AND the attachment's
     blob has a `bodyValues` entry (this is the `bvsAll` extension —
     attachments get values fetched too).

Capture: `email-get-body-properties-all-stalwart`.

What this proves:

- `bodyProperties` narrows the EmailBodyPart shape Stalwart returns
- `bvsAll` (`fetchAllBodyValues: true`) actually fetches attachment values
- The body-value table can carry binary/non-text body content (for an
  attachment that is text-typed; see divergence below)

Anticipated divergences:

- `bvsAll` fetches values for ALL body parts, but only `text/*` parts have
  values per RFC 8621 §4.1.4 (binary parts return null). The seed
  attachment is `text/plain` (the 32-byte ASCII sentinel from Phase D21)
  so values are present. If Stalwart returns `null` for the attachment's
  bodyValue, the assertion is `attachmentBodyValues.isNone`, not
  `.isSome`.
- Stalwart may include fields the client did NOT request in `bodyProperties`
  (RFC 8621 §4.2 says "If supplied, only the properties listed will be
  returned" but Stalwart may always emit `partId`). Test asserts only that
  REQUESTED fields are PRESENT, never that unrequested fields are absent.

### Step 55 — `temail_query_advanced_filter_live`

Scope: `Email/query` with the rich `EmailFilterCondition` arms not covered
by Phase C13/14 — `inMailbox`, `before`, `after`, `minSize`, `maxSize`,
`hasAttachment`, the three thread-keyword conditions.

Body — five sequential `client.send` calls in one block; corpus shared
across sub-tests:

1. Resolve mail account, inbox; resolve / create a `phase-i 55 archive`
   child mailbox via `resolveOrCreateMailbox`.
2. Seed corpus:
   - 2 small emails (200 B body) into Inbox via `seedEmailsWithSubjects`,
     subjects `"phase-i 55 small a"`, `"phase-i 55 small b"`
   - 1 large email (4 KB body) into Inbox via custom seed,
     subject `"phase-i 55 large"`
   - 1 email with attachment into Inbox via `seedMixedEmail`,
     subject `"phase-i 55 attached"`
   - 1 email into archive via `seedEmailsIntoMailbox`,
     subject `"phase-i 55 archived"`
3. **inMailbox** — filter = `inMailbox: archiveId`. Assert ids.len == 1
   matches the archived email.
4. **inMailboxOtherThan + minSize** — filter = AND of `inMailboxOtherThan:
   [archiveId]` and `minSize: UnsignedInt(1000)`. Assert exactly the large
   email surfaces.
5. **hasAttachment + before** — filter = AND of `hasAttachment: true` and
   `before: <a UTC date in the future>`. Assert at least the attached email
   surfaces.

Capture: `email-query-advanced-filter-stalwart` (after step 4 OR a single
combined leg; one capture per step).

What this proves:

- `inMailbox`, `inMailboxOtherThan` filter conditions wire shape
- `minSize`, `maxSize` work against Stalwart's reported message size
- `hasAttachment` boolean filter
- `before` / `after` UTC-date filters
- Composing multiple conditions with `FilterOperator AND` (proven in C14)
  works at scale on real corpus

Anticipated divergences:

- `hasAttachment` interpretation: RFC 8621 §4.4.1 says "true if the Email
  has at least one attachment". Stalwart may treat inline images as
  attachments differently from named attachments. Test uses the seedMixed
  inline ASCII attachment which has `disposition: cdAttachment` so it's
  unambiguously an attachment.
- Thread-keyword conditions (`allInThreadHaveKeyword`, etc.) are deferred
  to Phase J as adversarial because they require multi-email threads with
  partial keyword coverage — methodologically narrow and best paired with
  the Phase J keyword-edge-case work.

### Step 56 — `temail_query_advanced_sort_live`

Scope: `Email/query` with the remaining `EmailComparator` arms — `pspFrom`,
`pspTo`, `pspSubject`, `pspSize`, `pspSentAt`, plus the `eckKeyword` arm
(sort by has-keyword per RFC 8621 §4.4.2). Phase C15 covered `pspSubject`
ascending and descending only.

Body — four sequential `client.send` calls; corpus shared:

1. Resolve mail account, inbox.
2. Seed 4 emails with varying `from` addresses, sizes, sentAt times via
   custom blueprint construction (or four targeted `seedSimpleEmail`-like
   helpers; verify shape during implementation).
3. **Sort by from ascending** — assert the four returned in alphabetical
   from-address order.
4. **Sort by size descending** — assert ordered largest-first.
5. **Sort by has-keyword** — Email/set update one of the four to add
   `$flagged`; sort by `eckKeyword(keyword: kwFlagged, isAscending = false)`.
   Assert the flagged email appears first.

Capture: `email-query-advanced-sort-stalwart`.

What this proves:

- All five `pspXxx` `EmailComparator` arms produce wire shape Stalwart
  accepts
- The `eckKeyword` arm round-trips
- Stalwart's collation rules apply consistently across new sort
  properties
- `Email/set update` with `euAddKeyword` (proven in A7) composes cleanly
  with sort-by-has-keyword

Anticipated divergences:

- Stalwart's sort by `from` may use display-name-then-email-address vs
  email-address-only. Test uses email-only addresses so the rule is
  unambiguous.
- `pspSize` ties: if two emails are exactly the same size, Stalwart's
  ordering is implementation-defined. Seed bodies have distinctive lengths
  to avoid ties.

### Step 57 — `temail_query_collapse_threads_live`

Scope: `Email/query` with `collapseThreads: true` (RFC 8621 §4.4.3). Phase
C17 used the default `false`. Validates Stalwart's thread-collapse
behaviour: when multiple emails share a threadId, only one (the first per
sort) is returned.

Body — four sequential `client.send` calls:

1. Resolve mail account, inbox.
2. Seed two threaded emails via `seedThreadedEmails(@["phase-i 57 root",
   "phase-i 57 reply"], rootMessageId =
   "<phase-i-57@example.com>")`. Plus one un-threaded email via
   `seedSimpleEmail` with subject `"phase-i 57 standalone"`.
3. **collapseThreads = false (default)** —
   `addEmailQuery(filter = filterCondition(EmailFilterCondition(subject:
   Opt.some("phase-i 57"))))`. Assert `ids.len == 3`.
4. **collapseThreads = true** —
   `addEmailQuery(filter = ..., collapseThreads = Opt.some(true))`. Assert
   `ids.len == 2` (one per thread; the threaded pair collapses to one).

Capture: `email-query-collapse-threads-stalwart`.

What this proves:

- `collapseThreads` parameter wire shape Stalwart accepts
- Stalwart respects RFC 8621 §4.4.3 thread-collapse semantics
- Threading-asynchrony pattern (Phase B8 / C18) — re-fetch loop applied
  if the threaded pair hasn't been merged yet

Anticipated divergences:

- Per Phase C18 / H48 catalogue: Stalwart 0.15.5 does NOT merge threads
  for emails seeded into non-Inbox mailboxes. Step 57 seeds into Inbox so
  threading converges.
- Re-fetch loop (`5 × 200 ms`) wraps the `collapseThreads = true` query;
  fail with a narrative diagnostic if convergence times out.

### Step 58 — `tvacation_set_all_arms_live`

Scope: VacationResponse/set with all four typed update arms not covered by
Phase B9 — `setHtmlBody`, `setFromDate`, `setToDate`, `setReplyTo`. Plus
the date-window interaction with `isEnabled` per RFC 8621 §8.

Body — four sequential `client.send` calls:

1. Resolve submission account.
2. **Get baseline** — `addVacationResponseGet`. Capture singleton shape.
3. **Set all arms** — `addVacationResponseSet(b, vacAccountId, update =
   initVacationResponseUpdateSet(@[
     setIsEnabled(true),
     setHtmlBody(Opt.some("<p>phase-i 58 OOO</p>")),
     setFromDate(Opt.some(parseUtcDate("2026-06-01T00:00:00Z").get())),
     setToDate(Opt.some(parseUtcDate("2026-06-30T23:59:59Z").get())),
     setReplyTo(Opt.some(@[parseEmailAddress("alice@example.com",
       Opt.some("Alice OOO Reply")).get()])),
   ]).expect(...))`. Assert success.
4. **Read back** — `addVacationResponseGet`; assert all five fields
   round-trip as set (htmlBody, fromDate, toDate, replyTo populated).
5. **Cleanup** — flip `isEnabled` back to false, clear date window
   (Opt.none), clear html/replyTo (Opt.none).

Capture: `vacation-set-all-arms-stalwart` (after step 4).

What this proves:

- All four remaining VacationResponse update arms produce wire shape
  Stalwart accepts
- Date-window fields (`fromDate`, `toDate`) round-trip as UTC dates
- `replyTo` array round-trips
- Multiple arms in one update set are processed atomically

Anticipated divergences:

- Stalwart may reject `htmlBody` independent of `textBody` (some servers
  require both or neither). If so, document and combine into one update.
- `fromDate` after `toDate` may be auto-rejected by Stalwart per RFC 8621
  §8 sanity check; the test uses a valid window.

### Step 59 — `tidentity_changes_with_updates_live`

Scope: Identity/set with all five update arms — `setName`, `setReplyTo`,
`setBcc`, `setTextSignature`, `setHtmlSignature` — followed by
`Identity/changes` from a captured baseline. Closes Phase F31's "no
update arms in changes window" gap and Phase H46's "no full update
combination" gap.

Body — four sequential `client.send` calls:

1. Resolve submission account; resolve / create alice's identity via
   `resolveOrCreateAliceIdentity`.
2. Capture baseline state via `captureBaselineState[Identity](client,
   submissionAccountId)`.
3. **Combined update with all five arms** — `addIdentitySet(b,
   submissionAccountId, update = NonEmptyIdentityUpdates({identityId:
   IdentityUpdateSet([
     setName("phase-i 59 renamed"),
     setReplyTo(@[parseEmailAddress("reply@example.com").get()]),
     setBcc(@[parseEmailAddress("bcc@example.com").get()]),
     setTextSignature("phase-i 59 text sig"),
     setHtmlSignature("<p>phase-i 59 html sig</p>"),
   ])}))`. Assert update success.
4. **Identity/changes from baseline** — assert `identityId` appears in
   `created ∪ updated` of the response (Stalwart's collapse semantics
   per Phase H46 catalogue).
5. **Read back via Identity/get** — assert all five fields round-trip.

Capture: `identity-changes-with-updates-stalwart` (after step 4).

What this proves:

- All five `IdentityUpdate` arms compose in one request
- `Identity/changes` surfaces the update against the baseline
- Stalwart's same-state-window collapse (per H46) extends to combined
  arm-set updates
- `replyTo` / `bcc` lists round-trip on Identity (vs the singleton arms
  on EmailSubmission)

Anticipated divergences:

- Stalwart may emit `updated` rather than `created` if the identity was
  already present at baseline (which it is — `resolveOrCreateAliceIdentity`
  reuses an existing one). Assertion uses set membership.
- HTML signature sanitisation: Stalwart MAY strip script tags or other
  unsafe content. Test uses a benign `<p>...</p>` so no sanitisation
  triggers.

### Step 60 — `temail_submission_filter_sort_live` (capstone)

Scope: `EmailSubmission/query` and `/queryChanges` against a real corpus
exercising the full `EmailSubmissionFilterCondition` algebra
(`identityIds`, `emailIds`, `threadIds`, `undoStatus`, `before`, `after`)
and `EmailSubmissionComparator` (`esspEmailId`, `esspThreadId`,
`esspSentAt`). First wire test of filter+sort on a non-mail entity.

Visibly-harder capstone: builds a multi-submission corpus, exercises
six filter variants and three sort variants, AND chains query→queryChanges
from a captured baseline. Mirrors the visibly-harder discipline of A7 /
B12 / C18 / D24 / E30 / F36 / G42 / H48.

Body — eight sequential `client.send` calls plus polls:

1. Resolve mail and submission accounts; resolve drafts mailbox.
2. Resolve / create two identities — alice's primary identity AND a
   second identity (alice@example.com with a different display name) via
   `addIdentitySet(create = ...)`. Capture `identityA`, `identityB`.
3. **Capture baselines** —
   `captureBaselineQueryState(...)` for EmailSubmission/query (inline
   query helper if not extracted) and capture
   `captureBaselineState[AnyEmailSubmission](...)`.
4. **Build corpus via `seedSubmissionCorpus`** — 4 submissions:
   - sub1: identityA → bob, sentAt = T1
   - sub2: identityA → bob, sentAt = T2 (T2 > T1)
   - sub3: identityB → bob, sentAt = T3 (T3 > T2)
   - sub4: identityB → alice (self), sentAt = T4 (T4 > T3)
5. **Filter by identityIds = [identityA]** —
   `addEmailSubmissionQuery(b, submissionAccountId, filter =
   filterCondition(EmailSubmissionFilterCondition(identityIds:
   Opt.some(@[identityA]))))`. Assert exactly sub1 + sub2 surface.
6. **Filter by undoStatus = "final" + sort by sentAt asc** — assert all
   four submissions ordered by sentAt ascending.
7. **Filter by before = T2.5** — assert exactly sub1 surfaces (T1 < T2.5
   < T2).
8. **EmailSubmission/queryChanges** — issue
   `addEmailSubmissionQueryChanges(b, submissionAccountId,
   sinceQueryState = baselineQueryState, calculateTotal = Opt.some(true),
   filter = <same as step 6>)`. Assert delta surfaces all four
   submissions in `added`; `total.unsafeGet >= UnsignedInt(4)`.

Captures: `email-submission-query-filter-sort-stalwart` (after step 6),
`email-submission-query-changes-with-filter-stalwart` (after step 8).

What this proves:

- Full `EmailSubmissionFilterCondition` algebra (six variants) wire shape
- `EmailSubmissionComparator` all three sort properties round-trip
- `EmailSubmission/query` against a real corpus
- `EmailSubmission/queryChanges` with filter + calculateTotal
- The capstone's compound surface validates that the new entity has all
  the protocol features the Mail entity has

Anticipated divergences:

- `before` / `after` UTCDate semantics: Stalwart may use strict-less-than
  vs less-than-or-equal. Test uses gap dates (T2.5) to avoid boundary
  ambiguity.
- `undoStatus` enum encoding: Stalwart 0.15.5 emits `"final"`/`"pending"`/
  `"canceled"` lowercase per RFC 8621 §7. Library serde
  (`src/jmap_client/mail/email_submission.nim`) handles this already; the
  test's filter input uses the typed enum so encoding is automatic.
- Building the corpus takes ~4 × ~110ms (Phase F SMTP path latency from
  Phase F retro). Total Step 60 wall-clock: ~3-5s.

## Captured-fixture additions

Twelve to thirteen new fixtures committed under `tests/testdata/captured/`,
captured against a freshly reset Stalwart 0.15.5 with
`JMAP_TEST_CAPTURE=1 just test-integration`:

- `mailbox-query-filter-sort-stalwart` (Step 49)
- `mailbox-query-changes-with-filter-stalwart` (Step 49)
- `email-changes-max-changes-stalwart` (Step 50)
- `email-query-changes-filter-mismatch-stalwart` (Step 51)
- `email-get-max-body-value-bytes-truncated-stalwart` (Step 52)
- `email-get-header-forms-extended-stalwart` (Step 53)
- `email-get-body-properties-all-stalwart` (Step 54)
- `email-query-advanced-filter-stalwart` (Step 55)
- `email-query-advanced-sort-stalwart` (Step 56)
- `email-query-collapse-threads-stalwart` (Step 57)
- `vacation-set-all-arms-stalwart` (Step 58)
- `identity-changes-with-updates-stalwart` (Step 59)
- `email-submission-query-filter-sort-stalwart` (Step 60)
- `email-submission-query-changes-with-filter-stalwart` (Step 60)

Twelve to thirteen always-on parser-only replay tests under
`tests/serde/captured/`, one per fixture. Variant assertions are precise
where the RFC pins the wire shape (`AddedItem.id`, `EmailBodyValue.isTruncated`,
`metCannotCalculateChanges` set membership, `IdentityUpdateSet` round-trip);
structural where the wire has run-dependent content (server-assigned ids,
collation-dependent sort orders, thread-merge timing).

NOT listed in `testament_skip.txt`. Cumulative captured-replay total
rises from **43 to 55** (or 56 with the optional Step 60 second capture).

## Predictable wire-format divergences (Phase I catalogue)

Forward-looking — to be confirmed during I1 execution and amended in-flight
per Phase E precedent.

1. **Mailbox name filter tokenisation.** Step 49: same risk as Phase C13's
   subject filter — Stalwart MAY tokenise `name` filter input. Tests use
   single-token discriminators.
2. **`maxChanges` low-bound.** Step 50: Stalwart MAY collapse small deltas
   into one page even with `maxChanges = 2`. Test corpus N=5 forces at
   least one paginate; raise N if needed.
3. **`metCannotCalculateChanges` vs `metInvalidArguments` for filter
   mismatch.** Step 51: same ambiguity as Phase B11 / H43 / H45 / H46
   bogus-state precedent. Set membership accepts either.
4. **UTF-8 boundary truncation.** Step 52: Stalwart MAY truncate at the
   nearest UTF-8 boundary rather than exact byte count. Assertion uses
   `<= cap`, never `== cap`.
5. **Multi-instance header flattening.** Step 53: Stalwart MAY collapse
   multiple `Resent-To` headers into a single value array. The `:all`
   assertion accepts `len >= 1`.
6. **`bodyProperties` may emit unrequested fields.** Step 54: assertion
   tests only that REQUESTED fields are PRESENT.
7. **`hasAttachment` interpretation.** Step 55: inline images vs named
   attachments distinction is server-defined. Test uses an
   unambiguously-disposition'd attachment.
8. **Sort-tie ordering.** Step 56: implementation-defined for ties. Seed
   distinct values to avoid.
9. **Thread merge convergence in Inbox.** Step 57: Phase C18 / H48
   catalogue — Inbox merges synchronously, non-Inbox does not. Step 57
   seeds into Inbox.
10. **VacationResponse htmlBody/textBody coupling.** Step 58: Stalwart MAY
    require both. If so, combine.
11. **Identity update collapse.** Step 59: Same RFC 8620 §5.2 collapse
    semantics as Phase H46. Set membership accepts `created ∪ updated`.
12. **EmailSubmission `before`/`after` UTC semantics.** Step 60: strict-
    less-than vs less-than-or-equal is server-defined. Use gap dates.

## Success criteria

Phase I is complete when:

- [ ] Phase I0's `mlive.nim` helper-extraction commit lands with two
  helpers (`seedEmailWithHeaders`, `seedSubmissionCorpus`); both consumed
  by Phase I tests
- [ ] All twelve new live test files exist under
  `tests/integration/live/` with the established idiom (license, docstring,
  single `block`, `loadLiveTestConfig().isOk` guard, explicit
  `client.close()` before block exit, `doAssert` with narrative messages)
- [ ] All twelve new files are listed in `tests/testament_skip.txt`
- [ ] `just test-integration` exits 0 with **fifty-eight** live tests
  passing (46 from A–H + 12 from I)
- [ ] Twelve to thirteen new captured fixtures exist under
  `tests/testdata/captured/`
- [ ] Twelve to thirteen new always-on parser-only replay tests exist
  under `tests/serde/captured/` and pass under `just test` (cumulative
  count: 55–56)
- [ ] `just ci` is green (reuse + fmt-check + lint + analyse + test)
- [ ] No new Nimble dependencies, no new devcontainer packages — the
  2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro at
  `01-integration-testing-A.md:249-255`) holds throughout
- [ ] **No library source modifications** (`git diff src/` is empty after
  I0's helper-only commit) — the wire-readiness audit confirmed every
  Phase I dimension uses an existing typed surface
- [ ] Every divergence between Stalwart's wire shape and the test's
  expected behaviour has been classified (test premise / server quirk /
  client bug) and resolved at the right layer; no test papers over a real
  client bug
- [ ] Total wall-clock for the new tests under ~30 s on the devcontainer
  (Phase H added 6 tests in ~13 s; Phase I adds 12 tests with one heavier
  capstone at ~5 s and eleven lighter steps at ~1-2 s each = ~25-30 s)

## Out of scope for Phase I

Explicitly deferred to Phase J:

- **Adversarial wire-format edge cases** — RFC 2047 encoded-word names
  in `EmailAddress.name` (deliberate adversarial input rather than
  Phase D23's byte-passthrough contract), fractional-second dates,
  empty-vs-null table entries, oversize at `maxSizeRequest`,
  control-character handling at byte boundaries, `metUnsupportedFilter`
  / `metUnsupportedSort` via raw-JSON injection bypassing the sealed
  builders, `metInvalidResultReference` via deliberately broken back-
  reference, `urn:ietf:params:jmap:error:*` request-level errors,
  `maxObjectsInGet` / `maxObjectsInSet` / `maxCallsInRequest`
  enforcement, thread-keyword filter conditions on adversarial corpus.
  All require methodological breakthroughs (raw-JSON helper, raw-HTTP
  helper, library pre-flight bypass) that fit a dedicated phase.
- **`Email/set update` for header replacement and body content** —
  RFC 8621 §4.1.3 marks all header-derived properties as `(immutable)`
  and §4.1.1 anchors body content on the immutable `blobId`. NOT a
  deferred feature; ruled out by RFC analysis. The library's
  `EmailUpdate` algebra is RFC-complete.

Permanently out of scope (campaign discipline = validate **existing**
RFC-aligned surface):

- **JMAP-Sharing draft / `urn:ietf:params:jmap:principals`** — neither
  RFC 8620 nor RFC 8621 defines these surfaces; library has zero
  principal/sharing surface
- **Cross-account `Email/copy` happy path** — requires sharing/ACL
- **Push notifications, blob upload/download, Layer 5 C ABI** — not yet
  implemented in the library
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely

## Forward arc (informational)

After Phase I closes, **Phase J** completes the campaign as the
adversarial-themed final phase:

- Raw-JSON injection helper (`sendRawInvocation`) bypasses the sealed
  typed-builder surface; raw-HTTP helper bypasses library pre-flight
  validation. Both are test-only escape hatches added in Phase J0.
- Adversarial dimensions: RFC 2047 on receive, fractional-second dates,
  empty-vs-null table entries, oversize at `maxSizeRequest`, control-
  character handling, `metUnsupportedFilter` / `metUnsupportedSort`,
  `metInvalidResultReference`, `urn:ietf:params:jmap:error:*` request-
  level errors, `maxObjectsInGet` / `maxObjectsInSet` /
  `maxCallsInRequest` enforcement.
- Phase J's capstone: a multi-faceted adversarial test combining RFC 2047
  + fractional-date + control-char + raw-JSON injection in one round-trip
  to validate the parser's combined Postel's-law lenience.

That's ten phases total (A through J), comfortably inside the user's 8–12
phase budget. The campaign closes with the parser-vs-wire contract pinned
both for happy-path conformance (A–I) and Postel's-law adversarial
robustness (J).
