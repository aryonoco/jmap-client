# Section A & B execution — durable progress log

**Survives container rebuilds (lives in the mounted workspace `.claude/`).** This is the
working log for the campaign to implement the remaining **Section A (Must FREEZE before
1.0)** and **Section B (Type-safety hardening)** items of
`docs/TODO/pre-1.0-api-alignment.md`, aligning the library with the 29 principles in
`docs/design/14-Nim-API-Principles.md`.

> The **authoritative per-item status** is the status marker on each `### …` heading in
> `docs/TODO/pre-1.0-api-alignment.md`. As each item lands, its marker flips to `✅ DONE`
> and its body is rewritten to describe what shipped (the doc is a living artefact). To
> see remaining work after a compaction: `grep -nE '^### (A|B)[0-9].*— (⬜ TODO|🟡 PARTIAL)' docs/TODO/pre-1.0-api-alignment.md`.

## Mandate (from the user, verbatim intent)
- Clean refactor. **No compatibility shims, no dead/legacy code.** Uplift all comments,
  docstrings, and tests as part of the refactor.
- **Tests are NOT a design input.** They are accommodated by other means. What
  `convenience.nim` / current callers use is not a design input — if a caller breaks under
  the principled cut, that is a finding, not a constraint.
- API design serves **future application developers only**. Model after libcurl + SQLite;
  avoid OpenSSL/libdbus failure modes.
- Quality is paramount — showcase for the user's team. Do not cut corners, do not leave
  anything half-baked. Blast radius / speed are not concerns.

## Remaining items at campaign start
Section A: A2b (🟡), A7d (🟡), A7e (⬜), A8b (⬜), A25 (⬜), A25b (⬜), A26 (⬜).
Section B: B2, B3, B4, B5, B6 (reserved/no-op), B7, B8, B9 (FREEZE-BLOCKING), B10,
B11 (FREEZE-BLOCKING). B1/B12 already ✅.

## Locked design decisions
- **B9 → (b)**: demote `Chained*` (ChainedHandles/ChainedResults) off the public hub; keep
  `Compound*` public. (Confirm via research that Chained* is internal plumbing, not an
  app-facing capability; if it is app-facing, reconsider (a) HandlePair merge.)
- **B11 → (b)**: smart constructor enforcing `bodyValues.len>0 ⇒ bodyStructure.isSome`
  (reject vs lenient-drop decided by research — emailFromJson is lenient-by-design/Postel).
- **A8b → seal** Credential + SessionEndpoint like SubmissionParam (private discriminator +
  public accessor) IF no external code field-reads `.scheme`/`.kind`; else boundary-reject.
- **B2**: one `SortDirection {sdServerDefault, sdAscending, sdDescending}` in framework.nim.
- **B3**: `foNot: child: Filter[C]` + `foAnd|foOr: conditions: NonEmptySeq[Filter[C]]`.
- **B7**: `HasAnyRoleFilter / SubscriptionFilter / HasAttachmentFilter` three-state enums.
- **B8**: `DeleteAuthority {daYes, daNo, daUnreported}`.

## Quality gates (run after each change; full pass at end)
- `just build`; compile touched module + its tests.
- `just fmt` (nph) — CI runs fmt-check.
- `just check` = fmt-check + lint + lint-isolated + lint-style + all H lints + analyse(nimalyzer).
- `just test` (fast suite; `just test-full` left for the user).
- Every `src/*.nim`: `{.push raises: [], noSideEffect.}` (L1-L3) / `{.push raises: [].}` (L4-L5)
  then `{.experimental: "strictCaseObjects".}`. `func` mandatory L1-L3.
- Sealed Pattern-A objects (private `rawValue`, smart ctors); H1/H1b enforce.
- Comments explain WHY not WHAT; British English; errors via `Result` not exceptions.
- Update `tcompile_*`/`treject_*` audits, property tests, and `tests/wire_contract/` snapshots
  when the surface changes. Update `docs/design/` narratives + the TODO doc markers/bodies.

## FINAL COMPLETION GATE (user-mandated, run at the very end)
Work is ONLY complete when both pass:
1. `just ci` (reuse + fmt-check + lint + analyse + test) passes.
2. THEN run, in this EXACT order: `just clean && just jmap-reset && just test-full`.
   If test-full fails: fix, then re-run `just clean && just jmap-reset && just test-full`
   (together) until everything passes. (jmap-reset brings up Stalwart+James for integration.)

## Commit convention (only when user asks to commit)
Linux-kernel style subject `subsystem: short imperative <75 chars`; body wrapped ~75 cols
explaining WHY; footer exactly:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-5-fable
```

## Progress (update as items land)
- **B7 ✅ DONE** — three-state filter enums (HasAnyRoleFilter/SubscriptionFilter/
  HasAttachmentFilter, *NoConstraint = ordinal 0) in mail_filters.nim; serde via
  exhaustive case; tests updated; compiles + passes. TODO marker flipped.
- **B8 ✅ DONE** — DeleteAuthority{daUnreported,daYes,daNo} on Identity + IdentityCreatedItem;
  PartialIdentity keeps Opt[bool] (projection axis); serde parseMayDelete/emitMayDelete
  (lenient on absent → daUnreported, the security-relevant fix). MailboxRights.mayDelete
  untouched. Tests updated incl. fromJsonMissingMayDelete now asserts daUnreported. Passes.
- **Research maps extracted** → `.claude/notes/section-ab-research.md` (12 authoritative
  per-item change-maps with exact file:line caller inventories). Consult per item:
  B2/B3/B4/B5/B7/B8/B9/B10/B11/A8b/A7d/A25-26-A2b each have a `## SOURCE agent-…` section.
  A7d map = agent-a0091272 (largest). USE THESE — they list every caller/test/serde site.
- **B5 ✅ DONE** — registerExtractableEntity in entity.nim; gates 5 FULL entities only in
  mail_entities.nim (partials excluded: compiles-probe spuriously drags FieldEcho.fromJson →
  false-negative; documented). tentity.nim pos/neg mocks + tcompile_a1b declared. Passes.
- **B2 🟡 SRC DONE, tests in progress** — SortDirection{sdServerDefault,sdAscending,sdDescending}
  in framework.nim (ordinal0=serverDefault); renamed isAscending→direction on Comparator/
  EmailComparator/EmailSubmissionComparator + their 3 ctors. serde_helpers gained
  emitSortDirection/sortDirectionFromWire (the single wire-map). serde_framework/serde_email/
  serde_email_submission rewired. Library BUILDS. REMAINING: ~25 test files (see B2 map in
  section-ab-research.md "All sites→tests/"). Mechanical: isAscending=true→direction=sdAscending,
  =false→sdDescending, Opt.some(true)→sdAscending, Opt.some(false)→sdDescending, Opt.none(bool)→
  sdServerDefault; field reads .isAscending→.direction. WIRE-RULE assertions need care:
  Comparator/EmailSubmissionComparator now OMIT isAscending on sdServerDefault (was always-emit) —
  tserde_email_submission.nim:257-277, tserde_framework.nim:96-104/187-190. mfixtures makeComparator
  default → sdAscending (keep comparatorToJsonFieldNames meaningful). Add SortDirection to
  tcompile_a1_public_surface.nim. tserde_framework wrong-kind test still errs (keep strict check).
- **B2 ✅ DONE** — full suite passes + nph clean. SortDirection + direction rename landed across
  src + ~25 test files; emitSortDirection/sortDirectionFromWire shared L2 helpers. Intended wire
  change: Comparator/EmailSubmissionComparator now omit isAscending on sdServerDefault.
- WAVE plan: B7✅ B8✅ B5✅ B2✅; NEXT B4 (vacation window), B3 (filter arity — NOTE: trfc_8620.nim
  has filter tests at ~801-831 that test the OLD permissive foNot/foAnd behaviour B3 forbids; also
  ttypes/tframework/tprop_framework/tserde_framework/tserde_adversarial/tstress/tadversarial/
  temail_query_filter_tree_live + mfixtures.filterEq + mproperty.genFilter touch Filter). Then
  B9/B11 (freeze-blocking), B10, A8b, A7d, A7e, A25/A25b/A26/A2b. Maps in section-ab-research.md.
- **B4 ✅ DONE** — module-private sound utcInstantLeq + windowOrderConflict in vacation.nim;
  initVacationResponseUpdateSet rejects both-endpoints from>to (from==to allowed); receive types/
  serde/wire untouched. tvacation.nim section D (incl. fractional-second soundness). §7→§8 comment
  fix in vacation/serde_vacation/mail_methods. Builds + passes + nph clean.
- NEXT: B3 (filter arity: foNot=1 child Filter[C], foAnd|foOr=NonEmptySeq[Filter[C]]). NOTE
  trfc_8620.nim:801-831 has tests asserting the OLD permissive behaviour (foNot multiple children
  accepted, foAnd empty accepted) — those must be rewritten to assert the new rejection. filterOperator
  ctor signature changes → mfixtures.makeFilterAnd/Or, mproperty.genFilter, + many filter tests.
- **B3 ✅ DONE** — sealed flat Filter[C] (private rawOperands: NonEmptySeq), filterNot/filterAnd/
  filterOr replace filterOperator; operands* accessor; wire byte-identical; fromJson tightened
  (NOT≠1→svkArrayLength, empty AND/OR→svkEmptyRequired). ~10 test files updated incl. inverted
  permissive-arity assertions; fixed pre-existing tstress import break (mserde_fixtures int.toJson).
  Full fast suite PASSES + nph clean.
- DONE SO FAR: B2 B3 B4 B5 B7 B8 (+ B1/B12 pre-done). REMAINING: B9 (freeze-blocking, recommend
  (b)/(b-clean) demote Chained* — see B9 map agent-affeebabf), B11 (freeze-blocking, smart-ctor
  parseEmail bodyValues⇒bodyStructure — map agent-aba0157e), B10 (lent accessors — map agent-a4e51939),
  A8b (seal Credential+SessionEndpoint like SubmissionParam — map agent-a8f4db16), A7d (uncopyable
  RequestBuilder — map agent-a0091272, BIG test friction), A7e (async policy doc), A2b (Invocation
  round-trip prop test), A25/A25b/A26 (snapshot infra — map agent-aeaf29ce).
- **B9 ✅ DONE** (freeze-blocking) — (b-clean): deleted single-use Chained* generic from dispatch.nim;
  EmailQuerySnippetChain now bespoke record + getBoth in mail_methods.nim (mirrors EmailQueryThreadChain);
  hub now has exactly CompoundHandles/CompoundResults (P9). tcompile_a1b flipped to `not declared`;
  live test reads .query/.snippets. Full fast suite PASSES + nph clean.
- **B11 ❌ DROPPED** (premise invalid per RFC 8621 §4.2: bodyValues IS a default Email/get prop,
  bodyStructure is NOT; the "incoherent" shape is the normal default text-fetch. Reject would fail
  conformant servers + contradict A3). Corrective: docstrings on Email/ParsedEmail.bodyValues cite
  §4.1.4/§4.2; serde gate fromJsonBodyValuesWithoutBodyStructureIsCoherent locks acceptance;
  tprop_mail_d comment. Builds + passes. NOTE: at end, update dashboard counts (B11→DROPPED, remove
  from freeze-blocking list line ~80) + P16 tracker row.
- **B10 ✅ DONE** — 14 raw-passthrough accessors → `lent T` + borrow docstrings. Computed
  capabilities* (Session + RequestBuilder) SKIPPED (lent dangles — punch-list corrected); sealed
  projection accessors left by-value. Existing suites pass. nph clean.
- **A8b ✅ DONE** — full-seal Credential (rawScheme) + SessionEndpoint (rawKind) like SubmissionParam;
  scheme/kind accessors; supersedes boundary-reject. resolveEndpoint uses asDirectUrl/asDiscoveryDomain
  (unaffected). treject_a20/a21 now assert discriminator inaccessible; tcompile_a20a21 adds seal asserts.
  Docs (A8b/A30b-residue/A8-inventory/A20/A21 snippets) updated. Full fast suite PASSES.
- **A7d ✅ DONE** — RequestBuilder uncopyable (=copy/=dup {.error.}). Documented friction was stale:
  testCase wraps bodies in procs (no top-level issue), production compiles (only addPartialEmailGet:227
  needed let-brand fix). Only 3/319 test files broke: massertions.assertOk/Err now borrow (not copy);
  2 submission live tests use move(r.value). treject_a7d_{freeze_consumes_builder,post_freeze_add} pass.
  builder.nim comment+freeze docstring+submission docstring document the move idiom for app devs. A7
  umbrella now only awaits A7e. Full fast suite PASSES.
- REMAINING: A7e (policy doc docs/policy/03-rfc-extension-policy.md + RequestBuilder/BuiltRequest
  docstring pointers), A2b (Invocation round-trip prop test), A25/A25b/A26 (snapshot infra — agent-aeaf29ce).
- THEN: update dashboard counts + run FINAL GATE (just ci, then just clean && just jmap-reset && just test-full).
- CHECKPOINT: full `just check` (lints+analyse) not yet run this campaign — run before final. `just
  test` (fast) PASSES as of B9.
- REMINDER: at end of campaign, update the TODO "Status dashboard" counts + run
  `just fmt` + full `just check` + `just test`.

## POST-COMPACTION CONTINUATION (2026-06-13)
- **A7e ✅ DONE** (prior session) — docs/policy/03-rfc-extension-policy.md created (RFC reservation
  table + async dispatch section, no inline SPDX — REUSE.toml covers docs/** CC-BY-4.0). builder.nim
  docstrings point to it.
- **A2b ✅ DONE** (prior session) — tprop_envelope.nim propInvocationRoundTrip (all MethodName +
  mnUnknown vendor name via parseInvocation; imports serde_envelope per H10).
- **A26 ✅ DONE** — export-graph resolver scripts/api_surface.nim (reachableSurface/snapshotLines;
  text-based: jsondoc-of-hub=0 entries). Generator scripts/freeze_public_api.nim. Snapshot
  tests/wire_contract/public-api.txt (848 lines, deterministic). Lint tests/lint/h16_public_api_snapshot.nim
  (recompute+set-diff bidirectional; loadSnapshotBody strips `# ` header but keeps `## module`).
  justfile: freeze-api + lint-public-api recipes; lint-public-api wired into check + ci. PASSES + neg-test.
- **A25/A25b ✅ DONE** — api_surface.typeShapeLines()/typeShapeBody() capture public-field shape per
  public type (object fields + case discriminator/arms + enum members; private raw* excluded; relative
  indent preserved). Generator scripts/freeze_type_shapes.nim. Snapshot tests/wire_contract/type-shapes.txt
  (1513 lines, deterministic). Lint tests/lint/h17_type_shape_snapshot.nim. justfile: freeze-type-shapes +
  lint-type-shapes recipes; lint-type-shapes wired into check + ci. PASSES + neg-test.
- **F6 ✅ DONE** — implemented as the H16 self-checking lint (recompute-in-memory, not git-diff), wired
  into check+ci. TODO body updated.
- NOTE: `just fmt` reformatted 30 uncommitted src/ files (my B-series work was uncommitted in working
  tree; git-status snapshot at session start was stale). Regenerated BOTH snapshots post-fmt; both lints
  pass; fmt-check clean (425 files).
- TODO doc: A25/A25b/A26/F6 → ✅ DONE with impl notes + pointers. Dashboard recomputed via grep:
  DONE=67 PARTIAL=4 TODO=43 DEFERRED=1 DROPPED=2 RESOLVED=1. Freeze-blocking now only C1/C1.1.
  P16 trace row: B11 removed (dropped), status 🟡 (only B6 open). Decision-gates line updated.
  Fixed stale A27 ChainedHandles ref (B9 removed it → EmailQuerySnippetChain bespoke).
- **NEXT = FINAL GATE**: `just ci` must pass, THEN `just clean && just jmap-reset && just test-full`
  (exact order), iterate until all green. Servers via `just jmap-up` if needed for test-full.

## ✅ FINAL GATE PASSED (2026-06-13)
- `just ci` → PASS (reuse 844/844, fmt-check 425 files, all lints incl. new H16/H17, nimalyzer, fast suite).
  Fixes en route: (1) repaired broken `reuse` uv-tool via `uv tool install --force reuse --with
  charset-normalizer` (was NoEncodingModuleError — missing encoding backend, env issue not code);
  (2) nimalyzer `hasdoc` fired on undocumented `proc main` (h16/h17) + `proc misuse` (treject_a7d×2,
  uncaught from prior session since analyse hadn't run) — added `##` body docstrings to all four.
- `just clean && just jmap-reset && just test-full` → PASS. 242 PASS / 0 FAIL across all shards
  (unit/serde/property/compliance/stress + live integration vs Stalwart + James + Cyrus). "All shards passed."
- CAMPAIGN COMPLETE: all Section A + Section B items resolved (DONE or principled DROP). Dashboard:
  DONE=67 PARTIAL=4 TODO=43 (only C1/C1.1 freeze-blocking, both the sample-CLI gate — out of A/B scope).
