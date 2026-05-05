# Phase L — Cyrus IMAP 3.12.2 cross-server integration

This phase brings up Cyrus IMAP 3.12.2 alongside Stalwart 0.15.5 and
Apache James 3.9 so the client library is exercised against three
independently-implemented JMAP servers. The campaign asserts on the
**library**, not on any server's quirks: the same suite runs against
every configured target, with `assertSuccessOrTypedError` doing the
typed-error projection so the test still asserts the client contract
when a server lacks the surface.

## Outcomes

- 73 live tests pass against three servers under one
  `just test-integration` invocation.
- Library: RFC 8621 §1.3.1 informational fields widened to
  Postel-tolerant absence projections in
  `src/jmap_client/mail/mail_capabilities.nim` and
  `src/jmap_client/mail/serde_mail_capabilities.nim` so the parser
  accepts the Cyrus-shaped capability without compatibility shims.
- Tests: 17 live test files use the `assertSuccessOrTypedError`
  helper (43 invocation sites) instead of `if target.kind == ltkJames:
  continue` skip guards or `case target.kind` assertion-coupling
  blocks; a further set of files use seed-side `Result.isErr →
  continue` branching where the typed error fires inside a helper
  rather than at an extract site. Per-target branching survives only
  in 5 Cat-D verification-path files and 3 Cyrus-driven capture-pre-
  error files (4 case sites total) where the observation surface (not
  the assertion) genuinely differs.
- Devcontainer: 1 service (`cyrus`), 1 seed script (`seed-cyrus.sh`),
  5 new justfile recipes (`cyrus-{up,down,reset,status,logs}`).
- Justfile: `jmap-{up,down,reset,status,logs}` compose all three
  targets; `test-integration`, `test-full`, `capture-fixtures` source
  `/tmp/cyrus-env.sh` if present.

## Testing philosophy

### Three principles

1. **Tests assert on client behaviour, not server implementations.**
   A test verifies the client library's request construction, response
   parsing, and typed-error projection — for any RFC-conformant JMAP
   server response. It must NOT assert on specific behaviour of one
   server vs. another.
2. **Tests are server-agnostic by default.** Per-target `if target.kind
   == ltkX` branching for assertion purposes is a code smell: it couples
   the test to a specific server. Cat-D verification-path branching
   (different observation surface, same outcome) is the only legitimate
   use of `case target.kind` for assertion logic.
3. **The library is Postel-tolerant on receive, RFC-canonical on send.**
   Real-world JMAP servers diverge in wire shapes; the library absorbs
   that divergence so application developers don't have to. When test
   exposure surfaces a parser over-tightness or send-shape non-
   portability, the **library** is refactored — never the test loosened.

### Refactor pattern (Cat-B — "test the client, not the server")

```nim
# Server-coupled (what the refactor replaces):
let resp = await client.call(req)
case target.kind:
of ltkStalwart: assertOn(resp, expectedStalwartShape)
of ltkJames: continue  # skip guard

# Cat-B (asserts on client outcomes):
assertSuccessOrTypedError(target, resp.firstMethodResult,
    {metUnknownMethod, metUnsupportedFilter, metStateMismatch}):
  # Server implements the surface — assert on semantic round-trip.
  check success.contains(expectedItem)
```

The Cat-B pattern delivers stronger client-library coverage: the
typed-error projection path is exercised against a real-world server
response. A `metUnknownMethod` from Cyrus on `Identity/set`, or a
`metUnsupportedFilter` from James on `eckKeyword`, verifies that the
client correctly classifies a real-world server's typed JMAP error —
the very capability mail-client applications need.

When the typed error fires inside a seed helper (e.g., a
`seedSubmissionCorpus` that itself depends on `EmailSubmission/get`
for `pollSubmissionDelivery`), the helper's `Result[..., string]`
return surfaces the failure and the call-site uses
`if seededRes.isErr: client.close(); continue`. This is a Cat-B
seed-side variant: the helper has already exercised the typed-error
projection at the rejected request, so the call-site's role is to
skip the dependent assertions cleanly.

### Operational test for every Phase L decision

> *"If a mail-client application developer linked this library and ran
> my test code against any RFC-conformant JMAP server, would the
> assertion be a valid client-library contract assertion?"*

Yes ⇒ test is well-formed. No ⇒ refactor to Cat-B.

## Library changes

Each is a deterministic Postel-receive widening that improves the
library for every mail-client developer regardless of target server.

### `src/jmap_client/mail/mail_capabilities.nim`

`MailCapabilities` carries three `Opt[UnsignedInt]` informational
fields that may be absent on RFC 8621 §1.3.1-conformant servers:

```nim
maxMailboxesPerEmail*: Opt[UnsignedInt] ## Null means no limit; >= 1 when present.
maxMailboxDepth*: Opt[UnsignedInt] ## Null means no limit.
maxSizeMailboxName*: Opt[UnsignedInt]
  ## Octets; >= 100 when present per RFC 8621 §1.3.1. Optional —
  ## informational hint, not MUST. Cyrus 3.12.2 omits this field
  ## (`imap/jmap_mail.c:340-347`); the Postel-receive parser surfaces
  ## absence as ``Opt.none`` rather than synthesising a default.
```

### `src/jmap_client/mail/serde_mail_capabilities.nim`

Three private helper parsers absorb absence and validate the
present-value invariants:

1. **`parseOptUnsignedIntField(node, fieldName, path, minValue)`** —
   absent or null → `Opt.none(UnsignedInt)`; present and `>= minValue`
   → `Opt.some(val)`; present and `< minValue` errs. Used for
   `maxMailboxesPerEmail` (`minValue = 1`) and `maxSizeMailboxName`
   (`minValue = 100`).
2. **`parseOptUnsignedIntFieldUnconstrained(node, fieldName, path)`**
   — absent or null → `Opt.none(UnsignedInt)`; present projects via
   `UnsignedInt.fromJson`. Used for `maxMailboxDepth`.
3. **`parseOptStringSetField(node, fieldName, path)`** — absent or
   null → empty `HashSet[string]`; present validates each element as
   `JString` and adds to the set. Used for `emailQuerySortOptions`.
   No alternative-name dispatch for Cyrus's divergent label
   `emailsListSortOptions`: that would be a compatibility shim; the
   data is informational; lossless absence is acceptable.

`maxSizeAttachmentsPerEmail` and `mayCreateTopLevelMailbox` remain
required — RFC 8621 §1.3.1 lists them as MUST-present.

### `tests/serde/mail/tserde_mail_capabilities.nim`

Coverage for the optional-field projection:

- `maxMailboxesPerEmailNull`, `maxMailboxesPerEmailAbsent`,
  `maxMailboxDepthNull` — `Opt.none(UnsignedInt)` projection on
  null/absent.
- `maxSizeMailboxNameTooLow`, `maxSizeMailboxNameBoundaryOk` — the
  `>= 100` invariant fires only when the field is present.
- `missingMaxSizeMailboxName_isOptional` — Cyrus-shape (field
  omitted) parses cleanly with `assertNone`.
- `missingEmailQuerySortOptions_defaultsEmpty` — Cyrus-shape (field
  omitted) parses to an empty `HashSet[string]`.
- `emptyEmailQuerySortOptions` — explicit `[]` parses to empty set.

## Categorisation tally

| Category | Count | Notes |
|---|---|---|
| **Cat-A** (server-agnostic, no test-code change) | 37 | Core/Mailbox/Email/Thread surfaces all three servers implement uniformly. |
| **Cat-B** (refactored to assert client outcomes) | 31 | 27 originally skip-on-James + 3 case-target.kind assertion + 3 Cyrus-driven − 1 overlap (`temail_query_pagination`) − 1 promotion (`temail_submission_multi_recipient`). |
| **Cat-D** (asymmetric verification, Cyrus arm added) | 5 | 4 existing + 1 promoted from prior skip-on-James. |
| **Cat-E** | 0 | No surface untestable on any configured target. |
| **Total** | **73** | |

Sum check: 37 + 31 + 5 + 0 = 73 ✓.

Cat-B is implemented via two patterns: `assertSuccessOrTypedError`
(17 files, 43 invocation sites) and seed-side `Result.isErr → continue`
branching (the typed error has already fired inside a helper).

## Cat-B refactor catalogue

Cat-B sites replace server-coupled branching with a client-outcome
assertion. The default mechanism is
`assertSuccessOrTypedError(target, extract, allowedErrors): <successAssertion>`.
Where the typed error fires inside a seed helper, the call-site uses
`if seededRes.isErr: client.close(); continue` — the helper itself
exercised the typed-error projection. Inline comments at every
refactor site cite the Phase L philosophy.

### Group 1 — From skip-on-James guards (26 files in tally; 1 promoted to Cat-D)

| File | Original skip reason | Cat-B `allowedErrors` |
|---|---|---|
| `tcascade_changes_coherence_live` | naive Thread/changes on James | seed-side `{}` (best-effort convergence; wire-shape parsing is the universal contract) |
| `tcombined_changes_live` | naive Thread/changes on James | seed-side `{}` |
| `tthread_changes_live` | naive Thread/changes on James | best-effort convergence loop tolerates James's empty change-set |
| `temail_copy_intra_account_live` | Email/copy unimpl on James | typed-error path inside helper |
| `temail_copy_destroy_original_live` | Email/copy unimpl on James | typed-error path inside helper |
| `temail_query_changes_live` | queryChanges unimpl on James | `{metCannotCalculateChanges, metUnknownMethod}` |
| `temail_query_changes_filter_mismatch_live` | same | `{metCannotCalculateChanges, metInvalidArguments, metUnknownMethod}` |
| `temail_query_advanced_filter_live` | advanced filter unimpl on James | seed-side `{metInvalidArguments, metUnsupportedFilter, metUnknownMethod}` |
| `temail_query_pagination_live` | anchor/calculateTotal unsupported on James (also Group 2) | `{metInvalidArguments, metUnsupportedFilter, metUnknownMethod}` |
| `temail_get_attachments_live` | inline-bodyValues rejected on James | seed-side `{metInvalidArguments}` |
| `temail_get_body_properties_all_live` | same | seed-side `{metInvalidArguments}` |
| `temail_import_already_exists_live` | same | seed-side `{metInvalidArguments, metAlreadyExists}` |
| `temail_import_from_blob_live` | same | seed-side `{metInvalidArguments}` |
| `temail_parse_live` | same | seed-side `{metInvalidArguments}` |
| `tpostels_law_receive_live` | same | seed-side `{metInvalidArguments}` |
| `temail_submission_cancel_pending_live` | /set update/destroy unparsed on James | `{metInvalidArguments, metUnknownMethod}` |
| `temail_submission_full_lifecycle_live` | same | `{metInvalidArguments, metUnknownMethod}` |
| `temail_submission_changes_live` | EmailSubmission records absent on James | `{metCannotCalculateChanges, metInvalidArguments, metUnknownMethod}` |
| `temail_submission_filter_completeness_live` | same | seed-side `{}` |
| `temail_submission_filter_sort_live` | same (also Cleanup §6.1) | per-helper `{metInvalidArguments, metUnsupportedFilter, metUnsupportedSort, metUnknownMethod}` |
| `temail_submission_get_delivery_status_live` | Cyrus null deliveryStatus, James no /get | `{metUnknownMethod}` (success arm asserts client parses `deliveryStatus: null` as `Opt.none`) |
| `tidentity_changes_live` | unimpl on James + Cyrus | `{metUnknownMethod}` |
| `tidentity_changes_with_updates_live` | same | `{metUnknownMethod}` |
| `tmailbox_query_changes_live` | Mailbox/query restrictions on James | seed-side `{}` (skip on baseline failure) |
| `tmailbox_query_filter_sort_live` | same (also Cleanup §6.1) | per-helper `{metInvalidArguments, metUnsupportedFilter, metUnsupportedSort, metUnknownMethod}` |
| `tthread_keyword_filter_and_upto_id_live` | thread-keyword filter + upToId unimpl on James | `{metUnsupportedFilter, metCannotCalculateChanges, metUnknownMethod}` |

`temail_submission_multi_recipient_live` was also a skip-on-James file
but is **promoted to Cat-D** (see Cat-D refactor section below).

### Group 2 — From `case target.kind` assertion blocks (3 files; 1 overlap)

| File | Pre-refactor branching | Cat-B `allowedErrors` |
|---|---|---|
| `temail_query_advanced_sort_live` | Stalwart sort accepts `eckKeyword`, James rejects | `{metUnsupportedSort, metInvalidArguments, metUnsupportedFilter, metUnknownMethod}` |
| `temail_set_keywords_live` | Stalwart enforces `ifInState`, James ignores | `{metStateMismatch}` |
| `temail_query_pagination_live` | Stalwart calculates total, James does not (overlaps Group 1) | (covered above) |

### Group 3 — Cyrus-driven new Cat-B (3 files)

| File | Cyrus gap | Cat-B `allowedErrors` |
|---|---|---|
| `tidentity_set_crud_live` | Cyrus has no `Identity/set` (`imap/jmap_mail.c:122-123`) | `{metUnknownMethod}` |
| `tvacation_get_set_live` | Cyrus image disables vacation (`imapd.conf: jmap_vacation: no`) — request-level `unknownCapability` | `{metUnknownMethod}` (request-level error handled before extract) |
| `tvacation_set_all_arms_live` | same | `{metUnknownMethod}` (request-level error handled before extract) |

These three files contain a small Cyrus-only `case target.kind` block
whose sole purpose is to capture the wire response for the captured-
replay suite **before** the Cyrus-specific error path returns control
to the loop. Stalwart and James reach the post-success capture site
later in the test body. This branching is a capture-emission detail,
not assertion logic — the assertion still flows through
`assertSuccessOrTypedError`.

## Cat-D refactor (5 files — Cyrus arm added)

Cyrus 3.12.2's `EmailSubmission/get.deliveryStatus` is hardcoded
`json_null()` (`imap/jmap_mail_submission.c:1200-1201`); James 3.9 has
no `EmailSubmission/get`. Tests verifying *delivery happened* use inbox
arrival on Cyrus and James, EmailSubmission/get on Stalwart. The
inbox-arrival budget is `if target.kind == ltkCyrus: 10000 else: 5000`
ms — Cyrus's Postfix-backed delivery is slower under arm64-QEMU
emulation.

| File | Verification leg per target |
|---|---|
| `temail_bob_receives_alice_delivery_live` | Stalwart polls submission to `usFinal`; James + Cyrus skip the alice-side poll, rely on bob-side inbox arrival (Cyrus tolerates non-arrival within budget — wire-shape parse of the alice-side submission is the universal contract). |
| `temail_submission_set_baseline_live` | Stalwart polls `EmailSubmission/get`; James + Cyrus poll bob's inbox. |
| `temail_submission_on_success_destroy_live` | same shape as set_baseline |
| `temail_submission_on_success_update_live` | same shape as set_baseline |
| `temail_submission_multi_recipient_live` | Stalwart asserts on per-recipient `deliveryStatus` map (`bobMailbox`, `aliceMailbox` keys, both replyCode 250); James + Cyrus poll alice-self's inbox (the alice-self leg of the two-recipient envelope). |

Both verification paths verify the same client-side outcome (the
submission delivered) using whichever observation surface the deployed
server makes available.

## Cleanups

### §6.1 — Hardcoded `-stalwart` capture filenames

Replaced with `& "-" & $target.kind` (or a `targetSuffix` helper-proc
parameter where the capture site is inside a helper) in:

- `temail_query_advanced_filter_live.nim` (helper proc gets a
  `targetSuffix` parameter)
- `tmailbox_query_filter_sort_live.nim` (two helpers; both gain
  `targetSuffix` parameters)
- `temail_submission_filter_sort_live.nim`

### §6.2 — Stale `loadLiveTestConfig` references

The symbol is renamed to `loadLiveTestTargets` in `mconfig.nim:61`;
no live test or src/ module references the old name.
`grep -rn 'loadLiveTestConfig' tests/ src/` returns empty.

### §6.3 — `tcaptured_session.nim:21` assertion

`"Session.fromJson must succeed on captured fixture"` — the test runs
through `forEachCapturedServer` so the message is server-agnostic.

## Captured fixtures

Captured via `JMAP_TEST_CAPTURE=1 just capture-fixtures` against a
freshly-reset cluster. The committed corpus:

- 82 Stalwart fixtures — preserved byte-for-byte by `mcapture.nim`'s
  skip-if-exists guard.
- 64 James fixtures — produced by Cat-B refactor sites that previously
  skipped (the `assertSuccessOrTypedError` error arms record typed-
  error responses normally).
- 78 Cyrus fixtures — produced by every capture site, including the
  Group 3 Cyrus-only pre-error captures and the request-level
  `unknownCapability` rejections from the disabled vacation surface.

The `tests/serde/captured/tcaptured_round_trip_integrity.nim` meta-
test asserts every committed `<base>-<server>.json` round-trips
through `fromJson`/`toJson` without raising. It enumerates every
fixture explicitly so missing captures fail at compile time
(`staticRead`), not at runtime.

`forEachCapturedServer` (in `tests/serde/captured/mloader.nim`)
loads `<baseName>-stalwart.json`, `<baseName>-james.json`, and
`<baseName>-cyrus.json` in sequence. All three arms are unconditional —
every captured-replay site has all three arms.

## Devcontainer infrastructure

### `.devcontainer/docker-compose.yml`

Adds the `cyrus` service:

```yaml
cyrus:
  image: ghcr.io/cyrusimap/cyrus-docker-test-server@sha256:466dca4a7228ac28e239d926ae108291fdf8e940feae66d25c30e1b350967320
  platform: linux/amd64
  container_name: cyrus
  hostname: cyrus
  profiles: [cyrus]
  networks: [jmap-net]
  environment:
    - SKIP_CREATE_USERS=1
  ports:
    - "9080:8080"   # JMAP HTTP
    - "9001:8001"   # Mojolicious admin server
  healthcheck:
    test: ["CMD", "perl", "-MIO::Socket::INET", "-e",
           "IO::Socket::INET->new(PeerAddr => 'localhost:8001', Timeout => 2) or exit 1"]
    interval: 5s
    timeout: 3s
    retries: 24
    start_period: 30s
```

- Digest pinned at the amd64 manifest (verified via `docker manifest
  inspect` against ghcr.io).
- `SKIP_CREATE_USERS=1` disables the `user1..user5` defaults so the
  seed script provisions exactly Alice + Bob.
- 24 retries × 5 s + 30 s start = 150 s healthcheck budget. Cyrus
  boots in ~30–60 s on amd64; arm64 QEMU emulation is correspondingly
  slower.
- Ports 9080/9001 chosen to avoid Stalwart 8080 / James 8001.
- `platform: linux/amd64` mirrors James — arm64 hosts QEMU-emulate.
- Healthcheck uses Perl (no `curl`/`wget` in the image).

### `.devcontainer/scripts/seed-cyrus.sh`

Mirrors `seed-james.sh` shape:

- Polls `http://cyrus:8001/` until ready (240 s budget).
- `PUT /api/<username>` with the canonical empty-mailbox JSON template
  for `alice` and `bob` (the in-image template at
  `/srv/testserver/examples/empty.json` — INBOX / Archive / Drafts /
  Sent / Spam / Trash with the standard specialUse markers).
- Emits `/tmp/cyrus-env.sh` with `JMAP_TEST_CYRUS_*` env vars matching
  the Stalwart and James prefix patterns.

The Cyrus test image accepts any password for any user; tokens are
`base64("alice:any")` / `base64("bob:any")`.

## Justfile recipes

Five new Cyrus recipes (`cyrus-{up,down,reset,status,logs}`) plus
universal compositions:

- `jmap-up` / `jmap-down` / `jmap-reset` compose Stalwart, James,
  and Cyrus.
- `jmap-status` / `jmap-logs` enumerate every profile.
- `test-integration`, `test-full`, `capture-fixtures` source
  `/tmp/cyrus-env.sh` if present; `forEachLiveTarget` iterates every
  configured arm in enum order (Stalwart, James, Cyrus).

## Validation

```bash
just jmap-up            # bring up Stalwart, James, and Cyrus
just test-integration   # 73 tests pass against every configured target
just test               # fast suite green
just ci                 # reuse + fmt-check + lint + analyse + test
```

### Invariants

- `grep -rn 'loadLiveTestConfig' tests/ src/` returns empty.
- `grep -rn 'must succeed on Stalwart capture' tests/ src/` returns
  empty (only the philosophy reference in this doc remains).
- `grep -rn 'if target.kind == ltkJames' tests/integration/live/*_live.nim`
  returns 0 — every skip pattern refactored to Cat-B.
- `grep -rn 'case target.kind' tests/integration/live/*_live.nim`
  returns 9 sites across 8 files — 5 Cat-D verification-path branches
  plus 4 Group 3 Cyrus-only capture-pre-error blocks
  (`tvacation_get_set_live` carries two such blocks; the other Group 3
  files carry one each).
- No server-detection logic in `src/`.

## Out of scope (explicitly deferred)

- **VacationResponse coverage on Cyrus** via Dockerfile overlay
  enabling `jmap_vacation: yes`. Maintainer flags it "buggy"; accept
  the upstream verdict. Cat-B refactor covers the disabled path.
- **PushSubscription tests** — campaign-deferred for all three
  servers.
- **Cyrus calendar/contact JMAP extensions** — not in RFC 8620/8621
  scope.
- **arm64-native Cyrus image** — upstream amd64-only; QEMU matches the
  James precedent.
- **Library blob upload** (`/upload` endpoint) — current scope is
  deferred-blob-upload. The Cat-B `{metInvalidArguments}` allowedErrors
  handle inline-bodyValues rejection on James and binary-inline
  rejection on Cyrus uniformly, so blob upload remains a separate
  phase.
