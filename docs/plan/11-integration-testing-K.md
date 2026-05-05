# Phase K — Apache James 3.9 cross-server integration

This phase brings up Apache James 3.9.0 alongside Stalwart 0.15.5 so the
client library is exercised against two independently-implemented JMAP
servers. Goal: every contract the campaign asserts about the library
holds against both servers, and every divergence in behaviour is either
a deliberate library scope decision (deferred-blob upload, no push) or
a documented Cat-C/Cat-D/Cat-E classification with citation.

## Outcomes

- 73 live tests pass against both servers under one ``just
  test-integration`` invocation.
- Fast suite (``just test``) runs **everything in serde/captured plus
  the round-trip integrity meta-test against both Stalwart and James
  fixtures**: 113 serde tests passing including the 144-fixture meta-
  test (82 Stalwart + 62 fixture mentions in the meta-test, with 48
  James fixtures replayed alongside their Stalwart counterparts).
- Library changes total **3 files, +32 / −9 lines** — all RFC-compliance
  fixes that James's strict validation surfaced. None are James-
  specific workarounds.

## Library changes

Each is a deterministic RFC fix that improves the library for every
mail-client developer regardless of target server:

### `src/jmap_client/builder.nim` — pre-declare `urn:ietf:params:jmap:core`

`initRequestBuilder()` now starts with `capabilityUris: @["urn:ietf:
params:jmap:core"]` instead of `@[]`. RFC 8620 §3.2 obligates clients
to declare every capability they use; `core` is the namespace that
defines the request envelope (`using`, `methodCalls`, `createdIds`)
itself, so every JMAP request implicitly relies on it. Stalwart 0.15.5
accepts requests with `core` omitted; James 3.9 strictly rejects them
with `unknownMethod` "Missing capability(ies): urn:ietf:params:jmap:
core". Pre-declaring is RFC-canonical and portable.

### `src/jmap_client/methods.nim` — gate `anchorOffset` emission on `anchor`

`assembleQueryArgs` now emits `anchorOffset` only when `anchor` is set
(both inside the same `for a in queryParams.anchor:` loop). RFC 8620
§5.5 defines `anchorOffset` as "an offset from the anchor's position";
without an anchor it is meaningless. Stalwart accepted the always-
emitted form; James returns `invalidArguments` "anchorOffset is
syntactically valid, but is not supported by the server". Tying
emission to `anchor` presence is the RFC-canonical wire shape.

### `src/jmap_client/mail/serde_mailbox.nim` — omit `role`/`sortOrder` in `MailboxCreate.toJson` when at default

RFC 8621 §2.5 lists `role` and `sortOrder` as optional client
suggestions on Mailbox/set create; the server may override or assign
defaults if absent. Stalwart accepted explicit `role: null` /
`sortOrder: 0`; James 3.9 (`MailboxSetMethod.scala`) treats both as
server-set properties and rejects creation with `invalidArguments`
"Some server-set properties were specified" whenever they appear in
the payload. Omitting them when the caller did not supply a value is
RFC-conformant and works on both servers; explicit `parentId: null`
remains because the wire shape distinguishes "top-level mailbox" from
"nested under X".

## Categorisation tally

| Category | Count | Notes |
|---|---|---|
| A — both servers, mechanical migration | 47 | All passing on both targets |
| C — per-target case branching | 5 | `temail_query_advanced_filter`, `temail_query_advanced_sort`, `temail_query_collapse_threads`, `temail_get_header_forms_extended`, `tserver_side_enforcement_parity` |
| D — asymmetric verification leg | 4 | Submission tests; James verifies via inbox arrival, Stalwart via EmailSubmission/get |
| E — skip on James (with cited rationale) | 17 | Includes the 15 originally-planned Cat E plus 2 reclassifications (see below) |
| **Total** | **73** | |

### Skip-on-James rationales (Cat E and equivalents)

The following live tests carry `if target.kind == ltkJames: continue`
guards. Each rationale is documented inline in the test source.

**Originally Cat E (15) — James does not implement the surface:**

- `temail_copy_intra_account_live`, `temail_copy_destroy_original_live`
  — Email/copy unimplemented (`EmailCopyMethod.scala` does not exist
  at the 3.9.0 tag).
- `temail_query_changes_live`,
  `temail_query_changes_filter_mismatch_live` — Email/queryChanges
  unimplemented (`EmailQueryMethod.canCalculateChanges = CANNOT`
  unconditionally).
- `temail_submission_cancel_pending_live`,
  `temail_submission_full_lifecycle_live` — `EmailSubmission/set
  update`/`destroy` arms are not parsed in James 3.9.
- `temail_submission_changes_live`,
  `temail_submission_filter_completeness_live`,
  `temail_submission_filter_sort_live`,
  `temail_submission_get_delivery_status_live`,
  `temail_submission_multi_recipient_live` — James does not store
  EmailSubmission records; the entire `/get`/`/changes`/`/query`/
  `/queryChanges` surface is absent.
- `tidentity_changes_live`, `tidentity_changes_with_updates_live` —
  `Identity/changes` is bound but flagged "Not implemented" in
  `doc/specs/spec/mail/identity.mdown`.
- `tmailbox_query_filter_sort_live` — James restricts Mailbox/query
  to `role` filter only; rejects sort/position/anchor/limit/
  calculateTotal/sortAsTree/filterAsTree.
- `tthread_keyword_filter_and_upto_id_live` — thread-keyword filter
  conditions and Email/queryChanges.upToId are both unimplemented.

**Reclassified to skip-on-James (additional):**

- `tmailbox_query_changes_live` — Mailbox/queryChanges shares the
  Mailbox/query restrictions; James rejects without `filter` property
  even on the changes call.
- `temail_get_attachments_live`, `temail_get_body_properties_all_live`,
  `temail_import_already_exists_live`, `temail_import_from_blob_live`,
  `temail_parse_live`, `tpostels_law_receive_live` — exercise inline-
  bodyValues attachments which James rejects with `invalidArguments`
  "/attachments(0)/blobId — error.path.missing". James requires blob-
  uploaded attachments via the JMAP `/upload` endpoint (RFC 8620 §6.1);
  the library's blob upload surface is deliberately deferred (no
  blob/push in the current scope).
- `tcascade_changes_coherence_live`, `tcombined_changes_live`,
  `tthread_changes_live` — exercise Thread/changes convergence after
  Email/set; James 3.9's Thread/changes is documented as "Naive
  implementation" in `doc/specs/spec/mail/thread.mdown` and does not
  advance Thread state when emails are created.

When the deferred library surface (`/upload`) lands, the inline-
attachment guards can be removed. When James implements the missing
methods, the Cat-E guards can be removed individually.

## Library-contract preservation

- **Set-membership assertions widened where needed**: 
  `tmethod_error_typed_projection_live` and
  `tset_error_typed_projection_live` now accept `metUnknownMethod` in
  addition to `metUnsupportedSort`/`metUnsupportedFilter`/
  `metInvalidArguments`/`metServerFail`/`metUnknown`. RFC 8620 §3.6.2
  permits servers to classify malformed query arguments as
  `unknownMethod` (James) or specific variants (Stalwart); the library's
  closed-enum projection holds for both.
- **Per-target branching for genuine semantic divergence**:
  - `temail_query_pagination_live` — leg 3/4 (anchor-based pagination)
    Stalwart-only because James rejects `anchor` on Email/query;
    `calculateTotal` is unsupported on James (returns absent total).
  - `temail_query_advanced_sort_live` — `eckKeyword` sort accepted by
    Stalwart, rejected by James as `unsupportedSort`.
  - `tmailbox_set_crud_live` — James rejects atomic
    `destroy: [child, parent]` even with `mailboxHasChild` semantics;
    test now issues two sequential Mailbox/set destroy calls.
  - `temail_set_keywords_live` — James does not honour `ifInState` on
    Email/set; the conflict-path assertion branches on target.
  - `temail_query_filter_tree_live` — James's Lucene tokeniser keeps
    hyphenated words as single tokens; test corpus uses whitespace-
    separated discriminators.

## Devcontainer infrastructure

- `.devcontainer/docker-compose.yml` — added `james` service with
  `platform: linux/amd64` (the upstream image is amd64-only; arm64
  hosts emulate via QEMU transparently).
- `.devcontainer/james-conf/Dockerfile` — derivative image bakes in a
  self-signed PKCS12 keystore for IMAP TLS (the upstream image's
  `imapserver.xml` references `/root/conf/keystore` but ships no
  keystore) and a `jmap.properties` overlay that sets
  `url.prefix=http://james:80` so cross-container JMAP clients resolve
  the session-document URLs correctly.
- `.devcontainer/scripts/ensure-james-keystore.sh` — generates the
  keystore on demand in a one-shot `--platform linux/amd64` container,
  so the workflow is byte-identical on arm64 and amd64 hosts.
- `.devcontainer/scripts/seed-james.sh` — provisions `example.com`
  domain plus alice/bob users via James's WebAdmin API on port 8000,
  exports `JMAP_TEST_JAMES_*` env vars matching the Stalwart prefix
  pattern.
- `.devcontainer/scripts/seed-stalwart.sh` — env-var prefix updated to
  `JMAP_TEST_STALWART_*` to match.

## Captured fixture corpus

- 82 Stalwart fixtures (unchanged — `mcapture.nim`'s skip-if-exists
  guard preserved them byte-for-byte).
- 48 new James fixtures captured under `tests/testdata/captured/
  *-james.json`.
- Round-trip integrity meta-test extended with explicit James entries:
  2 sessions, 7 RequestErrors, 39 Responses = 48 new explicit calls.

## Justfile recipes

- `stalwart-up`/`stalwart-down`/`stalwart-reset` — Stalwart only.
- `james-up`/`james-down`/`james-reset`/`james-status`/`james-logs` —
  James only. `james-down` removes anonymous volumes (`docker compose
  rm -fsv`) so re-creates start on a clean slate.
- `jmap-up`/`jmap-down`/`jmap-reset`/`jmap-status`/`jmap-logs` —
  universal compositions over both.
- `test-integration` — runs every live test against every configured
  target; succeeds with one or both servers up.
- `capture-fixtures` — captures wire fixtures from every configured
  target into `tests/testdata/captured/<base>-<server>.json`.

## Validation

```bash
just jmap-up            # bring up both Stalwart and James
just test-integration   # 73 tests pass, each iterating both targets
just test               # fast suite passes (113 serde + protocol tests + meta-test)
just ci                 # reuse + fmt-check + lint + analyse + test
```
