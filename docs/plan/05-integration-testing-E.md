# Integration Testing Plan — Phase E

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **E0 — `mlive` helper extraction** | **Done** (2026-05-02) | Three new helpers landed in `tests/integration/live/mlive.nim`: `resolveOrCreateMailbox`, `seedEmailsIntoMailbox`, `getFirstAttachmentBlobId`. Mirrors Phase B's preparatory commit `e11ca86` and Phase C0 / Phase D0 precedent. Commit `9c1cd73`. |
| **E1 — Server-side data motion + pagination (six steps)** | **Done** (2026-05-02) | Six live tests (Steps 25–30) covering `Email/copy` (rejection-path), `Email/import` (happy path + no-dedup structural), `Email/query` pagination (position+limit, tolerant anchor+offset, `metAnchorNotFound`), and the `Mailbox/set destroy` `onDestroyRemoveEmails` semantic that Phase B Step 10 deferred. Cumulative live tests 28/28. The full Phase E suite ran in ~10 s wall-clock — well under the 60 s plan target. |
| **Captured-fixture additions** | **Done** (2026-05-02) | Eight new fixtures + eight new always-on parser-only replay tests; cumulative captured-replay total rises from 15 to 23. |

Live-test pass rate (cumulative across Phase A + B + C + D + E): **28 / 28**
(`*_live.nim` files run by `just test-integration`). Three test premises
in the original Phase E plan did not hold against the RFC text or
Stalwart 0.15.5 and were amended in-flight; one Stalwart-specific
quirk in anchor+offset window-sizing was absorbed via client-side
tolerance. No client-codebase bugs were identified.

## Context

Phase D closed on 2026-05-01 with the body-content / header-form /
`Email/parse` surface fully exercised against Stalwart 0.15.5 and the
captured-fixture loop in place. The integration-testing campaign had
covered every read-side mail surface RFC 8621 specifies plus the
entity-creation half of `Mailbox/set`, `Identity/set`,
`VacationResponse/set`, and the keyword-flip half of `Email/set`.

Three RFC 8621 surfaces remained unexercised against any server: the
*server-side* `Email/copy` data-motion method (§5.4), the
`Email/import` blob-to-email path (§4.8), and the `EmailSubmission`
end-to-end pipeline (§7). Two RFC 8620 surfaces remained unexercised:
query pagination (`position`, `anchor`, `anchorOffset`,
`calculateTotal` — §5.5 and the `metAnchorNotFound` MethodError
variant), and the *semantic* effect of `Mailbox/set destroy` with
`onDestroyRemoveEmails=true` (Phase B Step 10 proved structural
emission of the flag but never that emails inside the destroyed
mailbox actually disappear).

Phase E closed the first four of those gaps in one phase.
EmailSubmission is reserved for Phase F because it requires bob as a
real recipient principal, depends on Stalwart's outbound SMTP routing,
and exercises the larger `onSuccessUpdateEmail`/`DestroyEmail`
chained-success machinery — none of which Phase E touched.
Multi-account ACL, adversarial wire-format edge cases, and the
campaign-deferred surfaces (push notifications, blob upload/download,
Layer 5 C ABI) remain in Phases G and H and outside the campaign
respectively.

## Strategy

Phase E followed Phase A–D's bottom-up discipline. Each step adds
exactly one new dimension the prior steps have not touched. When the
live tests ran for the first time, four divergences surfaced (three
test-premise errors mine, one Stalwart-specific quirk); each was
investigated to a definitive verdict before any test was amended,
following the project's tolerance mission ("work with stalwart even
if it is not fully RFC compliant"). The amendments preserved the
phase's six-step shape but redirected each test's assertion target to
what is robustly observable across server implementations.

Phase E's dimensions, in build order:

1. The simplest server-side data-motion shape — `Email/copy` with
   `fromAccountId == accountId`. RFC 8620 §5.4 explicitly forbids
   this; the test pins Stalwart's rejection wire shape.
2. The chained-success extension — `addEmailCopyAndDestroy` under the
   same constraint. The compound is rejected at the method level
   before any implicit destroy fires.
3. The first import shape — `Email/import` against a `BlobId` the test
   acquires by seeding a multipart/mixed message and reading the
   attachment's blobId back.
4. Server-permitted duplicate imports — re-issue the same import
   tuple. RFC 8621 §4.8 makes dedup `MAY`; Stalwart accepts both
   imports with separate ids per the RFC's separate-id mandate.
5. The pagination dimension — `Email/query` with `position+limit`,
   then `anchor+anchorOffset` (tolerant), then a synthetic anchor that
   surfaces `metAnchorNotFound`.
6. The deferred Phase B semantic — `Mailbox/set destroy` on a child
   mailbox carrying live emails, asserting both happy-path
   (`onDestroyRemoveEmails=true` removes the contained emails) and
   sad-path (`onDestroyRemoveEmails=false` projects
   `setMailboxHasEmail`).

Step 30 is the visibly harder capstone, mirroring Phase A Step 7,
Phase B Step 12, Phase C Step 18, and Phase D Step 24. The asymmetry
is intentional: the climb stays inside Phase E rather than spilling
into Phase F.

## Phase E0 — preparatory `mlive` helper extraction

Three new helpers added to `tests/integration/live/mlive.nim` ahead of
any test that consumes them. One commit, single-purpose, mirrors the
Phase B preparatory commit `e11ca86`, Phase C0, and Phase D0
precedents. Compiles and passes `just test` because no test reads the
new symbols yet.

### `resolveOrCreateMailbox`

```nim
proc resolveOrCreateMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    name: string,
): Result[Id, string]
```

Issues `Mailbox/get`, scans `list` for a mailbox whose `name` field
matches the supplied string, and returns its id when present.
Otherwise issues `Mailbox/set create` with the name and a `parentId`
of the inbox (resolved via `resolveInboxId`), returns the freshly
assigned id. Idempotent on re-runs against the same Stalwart
instance.

### `seedEmailsIntoMailbox`

```nim
proc seedEmailsIntoMailbox*(
    client: var JmapClient,
    mailAccountId: AccountId,
    mailbox: Id,
    subjects: openArray[string],
): Result[seq[Id], string]
```

Variant of `seedEmailsWithSubjects` parametrised on the destination
mailbox rather than always the inbox. Internally funnels through the
existing private `emailSetCreate` proc; reuses `makeLeafPart` and
`buildAliceAddr` verbatim. Used by Step 30.

### `getFirstAttachmentBlobId`

```nim
proc getFirstAttachmentBlobId*(
    client: var JmapClient,
    mailAccountId: AccountId,
    emailId: Id,
): Result[BlobId, string]
```

Issues `addEmailGet(ids = directIds(@[emailId]), properties =
Opt.some(@["id", "attachments"]))`, parses `attachments[0]` via
`EmailBodyPart.fromJson` (the same parser Phase D Step 24 uses), and
returns its `blobId`. Used by Steps 27 and 28 to bridge a seeded
email to a fresh `BlobId` without going through a separate blob
upload endpoint.

## Phase E1 — six live tests

Each test follows the project test idiom verbatim (`block <name>:` +
`doAssert`) and is gated on `loadLiveTestConfig().isOk` so the file
joins testament's megatest cleanly under `just test-full` when env
vars are absent. All six are listed in `tests/testament_skip.txt` so
`just test` skips them; run via `just test-integration`.

### Step 25 — `temail_copy_intra_account_live`

Pins the rejection wire shape for `Email/copy` with `fromAccountId
== accountId`. RFC 8620 §5.4 mandates "The id of the account to copy
records to. This MUST be different to the 'fromAccountId'." Stalwart
0.15.5 enforces this with a method-level `metInvalidArguments` error.

Sequence: resolve inbox, seed a single text/plain email, issue
`addEmailCopy` with both account ids equal, assert `resp.get(handle)
.isErr` and `methodErr.errorType == metInvalidArguments`. Cleanup leg
destroys the seed and asserts success — the source survived because
the rejection occurred before any state change.

Capture: `email-copy-intra-rejected-stalwart`.

The original Step 25 plan was a happy-path "intra-account copy" test;
amended to the rejection-path form once live execution surfaced the
RFC-mandated rejection. See "Catalogued divergences" §1 below.

### Step 26 — `temail_copy_destroy_original_live`

Same RFC mandate as Step 25 applied to `addEmailCopyAndDestroy`. The
compound issues `Email/copy` with `onSuccessDestroyOriginal: true`;
Stalwart rejects at the method level before any implicit destroy can
fire. The captured fixture pins the compound rejection wire.

Sequence: resolve inbox, seed `sourceId`, issue
`addEmailCopyAndDestroy` with both account ids equal, assert
`resp.getBoth(handles).isErr` with `errorType ==
metInvalidArguments`. Cleanup leg destroys the seed.

Capture: `email-copy-destroy-original-rejected-stalwart`.

Same amendment story as Step 25. See "Catalogued divergences" §1.

### Step 27 — `temail_import_from_blob_live`

The first `Email/import` test. Validates `addEmailImport`,
`EmailImportItem` serialisation, `NonEmptyEmailImportMap`
construction via `initNonEmptyEmailImportMap`, and
`EmailImportResponse` deserialisation.

Sequence: resolve inbox, seed a multipart/mixed email with a 32-byte
ASCII attachment via `seedMixedEmail`, capture the attachment's
`BlobId` via `getFirstAttachmentBlobId`, build a one-entry
`NonEmptyEmailImportMap` targeting the inbox and the attachment
blobId, issue `addEmailImport`, assert
`createResults[parseCreationId("import27").get()].isOk`. Read-back
via `Email/get` confirms the imported email exists. Cleanup leg
destroys both the seed and the imported email.

Capture: `email-import-from-blob-stalwart`.

This step passed against Stalwart on the first run — no amendment.

### Step 28 — `temail_import_already_exists_live`

The original Step 28 plan asserted that re-importing the same
dedup tuple `(blobId, mailboxIds, keywords, receivedAt)` would surface
`setAlreadyExists`. RFC 8621 §4.8 makes dedup `MAY`, not `MUST`;
Stalwart 0.15.5 takes the `MAY`-permits path: a second import with
identical tuple succeeds with a fresh server-assigned `Id`. The test
was amended to the no-dedup structural form: both imports must
succeed AND the two ids must differ (RFC §4.8: "If duplicates are
allowed, the newly created Email object MUST have a separate id and
independent mutable properties to the existing object").

Sequence: resolve inbox, seed mixed email, acquire blobId. Issue two
`Email/import` invocations with identical `receivedAt =
parseUtcDate("2026-05-01T00:00:00Z")` and creation ids `"import28a"`
/ `"import28b"`. Assert both `isOk`; assert
`firstImportedId != secondImportedId`. Cleanup leg destroys the seed
and both imported emails.

Capture: `email-import-no-dedup-stalwart` (the second invocation).

The dedup-rejection branch (the err path with `setAlreadyExists` and
`existingId`) is covered at the parser layer by
`tests/serde/mail/tserde_email_import.nim`. The codebase is
dedup-ready; this live test pins Stalwart's actual no-dedup
behaviour. See "Catalogued divergences" §2.

### Step 29 — `temail_query_pagination_live`

Closes the Phase C deferral. Validates `QueryParams` serialisation
across `position`, `limit`, `anchor`, `anchorOffset`, and
`calculateTotal`, plus the `metAnchorNotFound` MethodError variant.
Subjects share the disjoint discriminator `"fritter29"` so
accumulation across runs only widens the result set.

Four legs:

1. **Position+limit**: `position=2, limit=2, calculateTotal=true`.
   Asserts `ids.len == 2`, `position == 2`, `total.isSome AND
   total.unsafeGet >= 5`. Capture:
   `email-query-pagination-position-stalwart`.
2. **Anchor baseline**: filter only, `QueryParams()` defaults.
   Captures `baselineIds` for leg 3 cross-checks. Asserts `len >=
   5`. No capture.
3. **Anchor + anchorOffset (tolerant)**: `anchor = baselineIds[2]`,
   `anchorOffset = JmapInt(-1)`, `limit = UnsignedInt(2)`. Asserts:
   `ids.len >= 1`; every returned id is in `baselineIds` (the
   response is a slice of the baseline); `baselineIds[1]` or
   `baselineIds[2]` (the anchor or the item before it) appears in
   the result set. Capture:
   `email-query-pagination-anchor-offset-stalwart`.
4. **`metAnchorNotFound`**: synthetic 28-octet `'z'` anchor that
   cannot collide with any allocated id. Asserts
   `methodErr.errorType == metAnchorNotFound` AND `methodErr.rawType
   == "anchorNotFound"`. RFC 8620 §5.5: "If the anchor is not found,
   the call is rejected with an 'anchorNotFound' error." Capture:
   `email-query-pagination-anchor-not-found-stalwart`.

The original plan asserted leg 3 with strict-RFC item count and
exact-id equality. Stalwart 0.15.5 returns 1 item where a strict-RFC
reading would predict 2; the assertions were relaxed to structural
invariants that hold under both interpretations. See "Catalogued
divergences" §3.

### Step 30 — `tmailbox_destroy_remove_emails_live`

Closes the Phase B Step 10 deferral. Validates the *semantic* effect
of `onDestroyRemoveEmails`: emails inside the destroyed mailbox
actually disappear. Bundles the happy path and the corresponding sad
path into one file, mirroring Phase A Step 7's combined-paths-in-one-
test precedent.

Three legs:

- **Leg A (happy)**: resolve / create child-a, seed three emails into
  it, destroy with `onDestroyRemoveEmails = true`. Assert success;
  child-a is absent from `Mailbox/get`; every seeded email surfaces
  in `Email/get notFound`. Capture:
  `mailbox-set-destroy-with-emails-stalwart` after the destroy.
- **Leg B (sad, no flag)**: resolve / create child-b, seed two
  emails, destroy without the flag. Assert err with
  `errorType == setMailboxHasEmail` and `rawType ==
  "mailboxHasEmail"` (RFC 8621 §2.5).
- **Leg C (cleanup)**: repeat leg B's destroy with
  `onDestroyRemoveEmails = true` so subsequent runs see a clean
  baseline.

The initial commit was missing `import std/tables`; trivially fixed
in commit `829128f`. See "Catalogued divergences" §4.

## Captured-fixture additions

Eight new fixtures committed under `tests/testdata/captured/`,
captured against a freshly reset Stalwart 0.15.5 with
`JMAP_TEST_CAPTURE=1 just test-integration`:

- `email-copy-intra-rejected-stalwart`
- `email-copy-destroy-original-rejected-stalwart`
- `email-import-from-blob-stalwart`
- `email-import-no-dedup-stalwart`
- `email-query-pagination-position-stalwart`
- `email-query-pagination-anchor-offset-stalwart`
- `email-query-pagination-anchor-not-found-stalwart`
- `mailbox-set-destroy-with-emails-stalwart`

Eight always-on parser-only replay tests under
`tests/serde/captured/`, one per fixture. Variant assertions are
precise where the RFC pins the wire shape (`metInvalidArguments`,
`metAnchorNotFound`); structural where the wire has run-dependent
content (the no-dedup fixture asserts `createResults[import28b].isOk`
and a non-empty id; the anchor+offset fixture asserts `ids.len >=
1`).

NOT listed in `testament_skip.txt` — these are always-on parser
regressions that run under `just test` and `just ci`.

## Catalogued divergences

The Phase E live execution surfaced four divergences between
plan-as-written and reality. Three were test-premise errors
(RFC-text misreadings); one was a Stalwart-specific quirk in
anchor+offset window-sizing absorbed via client-side tolerance. No
client-codebase bugs were identified — wire emission, parsers, and
smart constructors are all RFC-correct.

1. **Email/copy intra-account is RFC-forbidden, not RFC-permitted**
   (Steps 25, 26). RFC 8620 §5.4 lines 2228-2229: "The id of the
   account to copy records to. This MUST be different to the
   'fromAccountId'." Stalwart correctly rejects with method-level
   `metInvalidArguments`. The original plan's "intra-account copy"
   framing contradicted the RFC. **Resolution**: tests amended to
   validate the rejection wire shape; captured fixtures pin
   Stalwart's rejection bytes; parser-only replays validate
   `MethodError.fromJson` against the wire. Commits `cc6ac21`
   (Step 25) and `1e0aba9` (Step 26).

2. **Email/import dedup is RFC `MAY`, not RFC `MUST`** (Step 28).
   RFC 8621 §4.8 lines 3031-3038: "The server **MAY** forbid two
   Email objects with the same exact content [RFC5322] … If
   duplicates are allowed, the newly created Email object MUST have
   a separate id and independent mutable properties to the existing
   object." Stalwart 0.15.5 takes the `MAY`-permits path: a second
   import with identical `(blobId, mailboxIds, keywords, receivedAt)`
   tuple succeeds with a fresh server-assigned Id. The original
   plan's "second import is err with `setAlreadyExists`" assertion
   was non-normative. **Resolution**: test amended to no-dedup
   structural — both imports succeed; assert separate ids per the
   RFC's MUST mandate. The dedup-rejection branch's parser-level
   coverage already exists at
   `tests/serde/mail/tserde_email_import.nim`. Commit `8a8379b`.

3. **Email/query anchor+offset window-sizing is server-implementation-
   defined in practice** (Step 29 leg 3). RFC 8620 §5.5 lines
   2448-2460 describe a window where the computed position is
   `anchor index + anchorOffset`, used "exactly as though it were
   supplied as the 'position' argument". A strict-RFC reading with
   `anchor=k, anchorOffset=-1, limit=2` would yield items at indices
   `[k-1, k]` (2 items). Stalwart 0.15.5 returns 1 item from the
   offset window. Per the project's tolerance mission, the test
   accepts Stalwart's actual behaviour. **Resolution**: leg 3's
   strict `ids.len == 2` and exact-id assertions replaced with
   structural-tolerant invariants — `ids.len >= 1`, every returned id
   in `baselineIds`, anchor or item-before-anchor present in the
   response. The captured fixture pins Stalwart's actual response;
   the parser-only replay validates the wire parses cleanly. Wire
   emission and parser were verified RFC-correct
   (`src/jmap_client/methods.nim:329-350` for `assembleQueryArgs`,
   `methods.nim:763-794` for `QueryResponse.fromJson`); no client-
   side change. Commit `cb221ef`.

4. **Step 30 missing `std/tables` import** — trivial test-code bug.
   The initial Step 30 commit (`09e1b57`) omitted `import
   std/tables`, causing `withValue` to fail to resolve at compile
   time when running `just test-integration`. Fixed in commit
   `829128f`.

## Success criteria

Phase E is complete when:

- [x] Phase E0's `mlive.nim` helper-extraction commit lands and the
  three new helpers are exported and consumed by Phase E tests
- [x] All six new live test files exist under
  `tests/integration/live/` with the established idiom
- [x] All six new files are listed in `tests/testament_skip.txt`
  alongside the Phase A six, Phase B five, Phase C six, Phase D six
- [x] `just test-integration` exits 0 with **twenty-eight** live
  tests passing (22 existing `*_live.nim` files + 6 new from Phase E
  — `tsession_discovery.nim` does not match `*_live.nim` and is not
  run by the integration runner; the original plan's "29/29" target
  was an off-by-one)
- [x] Eight new captured fixtures exist under
  `tests/testdata/captured/`
- [x] Eight new always-on parser-only replay tests exist under
  `tests/serde/captured/` and pass under `just test`
- [x] The twenty-eight live tests run in ~10 s wall-clock on the
  devcontainer, well under the 60 s plan target
- [x] No new Nimble dependencies, no new devcontainer packages — the
  2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro at
  `01-integration-testing-A.md:249-255`) holds throughout
- [x] Every divergence between Stalwart's wire shape and the test's
  expected behaviour has been classified (test premise / server quirk
  / client bug) and resolved at the right layer; no test papers over
  a real client bug

## Out of scope for Phase E

Explicitly deferred to later phases:

- **EmailSubmission end-to-end** (alice → bob delivery, `Identity/set`
  fuller round-trip, `EmailSubmission/{set,get,changes,queryChanges}`,
  `onSuccessUpdateEmail`/`DestroyEmail` implicit chaining,
  `DeliveryStatus` shape, `ParsedSmtpReply` round-trip with real
  RFC 3464 enhanced status codes) — Phase F. Requires bob as a real
  recipient principal and Stalwart's outbound SMTP routing — neither
  of which Phase E touches.
- **Multi-account ACL** (alice ↔ bob shared mailbox access,
  `Email/copy` *across* `accountId` boundaries with
  `fromAccountId != accountId`, `forbidden` SetError variants on
  cross-account writes) — Phase G.
- **Adversarial wire-format edge cases** (RFC 2047 encoded-word names
  in `EmailAddress.name`, fractional-second dates, empty-vs-null
  table entries, oversize at `maxSizeRequest`, control-character
  handling at byte boundaries, `maxBodyValueBytes` truncation
  marker, `metUnsupportedFilter` and `metUnsupportedSort` via raw-
  JSON injection bypassing the sealed builders) — Phase H.
- **Push notifications, blob upload/download, Layer 5 C ABI** — not
  yet implemented in the library; not part of the integration-
  testing campaign at all until they exist.
- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in `tests/stress/`
  if/when it becomes a goal.

Phase F will exercise EmailSubmission against a real bob principal
and the larger `onSuccess*` machinery once Phase E's intra-account
data-motion surface is proven.
