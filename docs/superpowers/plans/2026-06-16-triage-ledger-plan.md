<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# Triage ledger — implementation plan (campaign's last item)

> **For agentic workers / post-compaction resume:** This is the
> **self-contained, durable execution record**. Use
> superpowers:subagent-driven-development for the code-fix tasks. The **STATE
> block (§0)** is the resume oracle — read it first, then continue at the first
> ⬜ task. Companion: the gitignored design spec
> `docs/superpowers/specs/2026-06-16-triage-ledger-design.md`; the canonical
> orientation `docs/superpowers/plans/2026-06-16-CAMPAIGN-HANDOFF-POST-S4-TRIAGE.md`.

**Goal:** Close the campaign's last item — reconcile the 98 `[open]` findings in
`examples/jmap-cli/AUDIT.md`, land two greenlit clean code fixes (the `asSeq`
family rename, test-hygiene), and audit Section C of the pre-1.0 tracker — to
exemplary, showcase quality with no shims, no dead code, and clean docstring/test
uplift.

**Architecture:** Branch `api/triage` off `main` (tip `a525d80`). Per-task
kernel commits, each green, STATE flipped in the same commit. Two code fixes go
through the full subagent loop + BOTH gates; the doc reconciliations go through a
Workflow (classify + adversarially verify) then controller-authored edits.

**Design lens (overrides any principle):** only design input = the future
application developer; libcurl/SQLite, not OpenSSL/libdbus. Tests are NOT a
design input; current callers are NOT constraints; 0 users, blast radius
irrelevant; version-agnostic; clean refactor — no compatibility shims, no
dead/legacy code, uplift all comments/docstrings/tests. **RFC text in
`docs/rfcs/` is authoritative; design docs are fallible** — tell every reviewer
to validate against the RFC.

---

## §0. STATE (resume oracle — flip in the SAME commit as each task)

- [x] **T0** — Land the canonical handoff doc (untracked on entry) + commit this plan ✅
- [x] **T1** — `asSeq` family rename + lent view + uplift + re-freeze contract ✅ (commit pending in this step)
- [x] **T2** — Test-hygiene cleanup (UnusedImport + Uninit) ✅
- [x] **T3** — AUDIT triage: flip 98 `[open]` tags + author `## S0 resolution` ✅ (12 NEEDS-DECISION adjudicated: 8 accept, 4 filed C20–C22; new Cn C11–C22)
- [x] **T4** — Full Section C audit + append new `filed-as-Cn` items ✅ (C1–C10 markers reconciled; C11–C22 appended; C13 RFC cite corrected §5.1→§5.3)
- [ ] **T5** — Final adversarial Workflow over the whole diff
- [ ] **T6** — BOTH gates green (controller-run), then refresh canonical handoff
- [ ] **T7** — Confirm push/PR/merge with the human; merge; verify main

**Position on entry:** branch `api/triage` off `main` `a525d80`. `just build` →
SuccessX; `check-public-only.sh` OK; `nim c examples/jmap-cli/jmap_cli.nim` →
SuccessX zero warnings (re-bench done 2026-06-16). The handoff doc
`…-POST-S4-TRIAGE.md` was UNTRACKED on entry → landed in T0.

---

## §1. The four+one decisions (human-approved 2026-06-16)

1. Positives → new **`affirmed`** tag (`affirmed (strengthened by Sn)` where applicable).
2. Author a **`## S0 resolution`** section in AUDIT.md (S0 oracle verified to list
   the once-missing symbols).
3. Do the two code fixes now (`asSeq` rename + test-hygiene), not file/accept.
4. **Full Section C audit** of `pre-1.0-api-alignment.md` + append new Cn items.
5. Rename scope = **family rename + lent view** (all six `toSeq*` → `asSeq* →
   lent seq[X]`; no alias kept).

## §2. Taxonomy (per-line, with one-line rationale)

`resolved-Sn` | `affirmed` | `accepted-as-trade-off` | `filed-as-Cn`. A finding
may carry a primary tag + a residual `filed-as-Cn` pointer. "Won't-fix by Sn
decision" = `resolved-Sn` (rationale notes the deliberate non-fix). The four
resolution sections stay; tags point into them; the new S0 section backs
`resolved-S0`.

**Disposition buckets (approx; exact per-line in T3):** resolved-S0 ≈ 7
(snapshot/tooling cluster), resolved-S1 ≈ 6 (error-rail), resolved-S2 ≈ 10
(read-model), resolved-S3 ≈ 8 (readers/predicates), resolved-S4 ≈ 12
(connect/get/query/send/dissolve), affirmed ≈ 14 (positives), accepted ≈ 12,
filed-as-Cn ≈ 10. Build-environment (3): `build:no-strictness-leak`/`build:
config-inheritance` → affirmed; `build:transport-deps` → accepted;
`build:module-name` → accepted (incidental).

---

## T0 — Land the handoff + commit the plan

**Files:** `docs/superpowers/plans/2026-06-16-CAMPAIGN-HANDOFF-POST-S4-TRIAGE.md`
(untracked → add), this plan, the spec is gitignored (not staged).

- [ ] Stage the handoff doc + this plan (explicit paths, never `git add -A`).
- [ ] Commit: `docs/triage: land post-S4 handoff and triage plan`. Flip **T0** ✅
      in §0 in the same commit.

---

## T1 — `asSeq` family rename + lent view (clean cut, no alias)

**Why:** the generic `NonEmptySeq[T]` borrows its backing seq as `asSeq → lent
seq[T]`, named `asSeq` *to avoid the `std/sequtils.toSeq` clash* (its own
docstring). Six dedicated sealed wrappers reintroduce that clash via `toSeq →
seq[X]` (a copy). Unify on one verb + one zero-copy-view semantics. No `toSeq`
retained — clean refactor.

**Ripple ledger (fresh grep 2026-06-16 — the implementer MUST re-grep to confirm
nothing was missed):**

*Definitions (6) — rename `func toSeq*` → `func asSeq*`; return `seq[X]` → `lent
seq[X]`; docstring "Value-projection accessor — returns a copy" → "Borrow-
projection accessor — returns a read-only view of the underlying seq" (mirror the
generic `asSeq` docstring):*
- `src/jmap_client/internal/types/primitives.nim:410` — `NonEmptyIdSeq`
- `src/jmap_client/internal/mail/email_update.nim:135` — `EmailUpdateSet`
- `src/jmap_client/internal/mail/mailbox.nim:525` — `MailboxUpdateSet`
- `src/jmap_client/internal/mail/vacation.nim:196` — `VacationResponseUpdateSet`
- `src/jmap_client/internal/mail/identity.nim:173` — `IdentityUpdateSet`
- `src/jmap_client/internal/mail/email_submission.nim:588` — `NonEmptyOnSuccessDestroyEmail`

*Stale docstring (uplift):*
- `src/jmap_client/internal/types/validation.nim:174-175` — "reached via `toSeq`
  (defined in `primitives.nim`)" → "reached via `asSeq`". (Body already uses
  `asSeq`; the comment is wrong.)

*src/ call-sites (`.toSeq` → `.asSeq`):*
- `serde_vacation.nim:139`, `serde_identity_update.nim:54`, `serde_mailbox.nim:385`,
  `serde_email_update.nim:59`, `email_submission.nim:690`,
  `serde_email_submission.nim:240`. **Correction (implementer + both reviewers,
  verified):** the originally-listed `email_update.nim:281` is NOT a wrapper
  call-site — that `updates.toSeq` is `std/sequtils.toSeq` over the
  `openArray[EmailUpdate]` parameter of `initEmailUpdateSet` (the wrapper does
  not exist yet at that point), so it correctly stays `toSeq`. Real src/ ripple
  is **6 sites, not 7.**

*tests/ call-sites (`.toSeq` → `.asSeq`):*
- `mfixtures.nim:2183-2184` (`emailUpdateSetEq`), `unit/mail/tthread.nim:42`,
  `property/tprop_mail_f.nim:178`, `integration/live/tthread_get_live.nim:88`
  (LIVE shard — only runs in `test-full`), `serde/mail/tserde_thread.nim:42,48`.
- **DO NOT TOUCH** `serde/mail/tserde_email_blueprint.nim:378,424,449` — those
  are `sequtils.toSeq(obj{...}.keys)` (the std template over `Table.keys`),
  unrelated to the sealed-wrapper rename.

*examples/jmap-cli (comment uplift):*
- `commands/thread.nim:27` — comment mentions ".toSeq"; reword.

*Contract:*
- `tests/wire_contract/public-api.txt` — six `func toSeq (...)` entries for these
  types become `func asSeq (...): lent seq[...]`. Regenerate via `just
  freeze-api` (the S0 oracle). `type-shapes.txt` lists fields not these funcs →
  re-freeze is a no-op there but run it for completeness.

**`lent` safety note:** every call-site is read-only (`for u in x.asSeq:`,
`x.asSeq.mapIt`, `assertEq …x.asSeq…, @[…]`, `x.asSeq[0]`, `seededId in
x.asSeq`, `let xs = x.asSeq` which binds a copy). `lent` is safe; no lifetime
escapes.

**Steps:**
- [ ] Implementer re-greps `\.toSeq\b` and `func toSeq` across `src tests
      examples` to confirm the ledger is complete (handoff warns ripple was
      under-named before).
- [ ] Rename the 6 definitions + flip to `lent` + uplift the 6 docstrings.
- [ ] Fix the stale `validation.nim` comment.
- [ ] Update all src/ + tests/ call-sites; uplift the example comment.
- [ ] `just fmt` (covers src + tests, NOT examples — hand-format the example).
- [ ] `just freeze-api` to regenerate `public-api.txt`; eyeball the six entries.
- [ ] Controller re-runs **Gate 1** (`just ci`). Then **Gate 2** at T6.
- [ ] Commit: `types: unify sealed-seq projection on asSeq (drop toSeq)`. Flip **T1** ✅.

## T2 — Test-hygiene cleanup

**Why:** two test files fail strict standalone-compile (pass only via the
megatest JOIN). Clean them so they self-compile under the full battery.

- [ ] `tests/serde/mail/tserde_email_submission.nim:32` — remove the unused
      `errors` import (confirmed `imported and not used: 'errors'`). Re-grep the
      file to ensure `errors` is truly unused after the asSeq ripple (T1 touched
      `serde_email_submission.nim`, a different file).
- [ ] `tests/lint/h15_error_message_snapshot.nim:348` — `diffPairs` needs
      explicit `result = @[]` init (confirmed `Uninit`). Add it; keep the helper
      a `proc` with its `##` docstring.
- [ ] Verify both now standalone-compile: `nim c <file>` → SuccessX zero warnings.
- [ ] Controller re-runs **Gate 1**. Commit: `tests: fix standalone-compile
      hygiene (UnusedImport, Uninit)`. Flip **T2** ✅.

## T3 — AUDIT triage: flip 98 `[open]` tags + author the S0 section

**Why:** Phase 1 logged every finding `[open]`; the S-campaign resolved most but
never flipped the inline tags per-line.

- [ ] Update the AUDIT preamble (lines 8-12): the observe-only convention is
      superseded — this is Phase 2 (triage). State the new taxonomy.
- [ ] **Workflow:** classify each of the 98 `[open]` findings → a disposition +
      one-line rationale, cross-checked against the S1–S4 resolution sections and
      (for resolved-S0) the verified `public-api.txt`. Adversarially verify every
      `resolved-Sn` claim (is the named symbol actually shipped? does the
      resolution section back it?). Positives → `affirmed`.
- [ ] Controller applies the verified dispositions in place (flip each `[open]`).
- [ ] Author `## S0 resolution` section (parallel to S1–S4), grounded in the
      verified oracle/contract: the snapshot-integrity cluster, the `egp*`/`kw*`
      grouped-const drops, `addEmailQueryWithSnippets`/`SearchSnippetGetResponse`
      truncation, `directIds`/`roleInbox` unlisted — all now correctly
      enumerated by `scripts/api_oracle.nim` and present in `public-api.txt`.
- [ ] Fix the Summary counts (line ~31-35: "92 ledger lines" etc.) to the
      post-triage reality, and any now-stale cross-refs.
- [ ] Re-bench: `check-public-only.sh` + `nim c examples/jmap-cli/jmap_cli.nim`
      still green (T1's rename may ripple the bench — re-verify).
- [ ] Controller re-runs **Gate 1** (reuse covers AUDIT.md SPDX). Commit:
      `examples/jmap-cli: triage the audit ledger to its resolved state`. Flip **T3** ✅.

## T4 — Full Section C audit + new `filed-as-Cn` items

**Why:** `filed-as-Cn` items land in Section C of
`docs/TODO/pre-1.0-api-alignment.md`; several existing C-items were overtaken by
the S-campaign and read stale.

- [ ] Reconcile every existing C-item's status marker with one-line "superseded
      by Sn / done / moot" notes: **C1/C1.1** (CLI bench + AUDIT) → DONE;
      **C2** → already DONE; **C3** (`byIds`/`directIds`) → reconcile vs S4;
      **C4** (MailboxRights roll-up) → resolved S3 WON'T-FIX (rights stay
      orthogonal); **C5/C8** (capability discovery) → DONE in S3 (`requireMail`/
      `requireSubmission`/`requireVacation`); **C6** (version surface) → assess;
      **C7/C9/C10** (convenience.nim charter) → MOOT (module dissolved in S4 —
      `convenience.nim` no longer exists); **C5b** (HttpTransportConfig) →
      reassess under version-agnostic lens.
- [ ] Append the new `filed-as-Cn` items (the §6.2 parking lot): a read-side
      `EmailLeaf` view type for `leafTextParts`; `leafTextParts`/`limit` naming +
      raw `Blueprint*` ctor publicness (P15 tightening); the broad D5 `toJson`
      null-for-none serde audit (RFC 8620 §5.1); `ParsedEmail` body-reader
      overloads + `htmlBodies()`/`allBodies()`; **no Email/set write one-shot**
      (flag/move/vacation-set); **no search-snippet one-shot**. Mark the
      `asSeq` rename and test-hygiene as DONE-in-triage (not open).
- [ ] Each new item: P-principle cite, file location, why, and that it is a
      future *additive* pass (NOT freeze-blocking; the campaign is
      version-agnostic).
- [ ] Controller re-runs **Gate 1**. Commit: `docs/TODO: reconcile Section C
      against the S-campaign`. Flip **T4** ✅.

## T5 — Final adversarial Workflow

- [ ] Multi-lens Workflow over the whole `api/triage` diff: RFC-conformance /
      29-principles / purity / libcurl-SQLite lens / completeness / "any
      mis-tagged finding, any shim or dead code left, any docstring not uplifted".
      Each finding adversarially refuted. Land confirmed findings (surface any
      contract-shape decision to the human). Flip **T5** ✅.

## T6 — Both gates (controller-run) + refresh handoff

- [ ] **Gate 1:** `just ci` → green.
- [ ] **Gate 2:** `just clean && just jmap-reset && just test-full` (background;
      await "All shards passed"; confirm all four shards via
      `testresults/test-full/*.log` — live ≈ 73 PASS each, joinable ≈ 23).
- [ ] Refresh `…-POST-S4-TRIAGE.md` "next job" → "campaign complete; only the
      parking lot / a future additive pass remains, at the human's discretion".
- [ ] Update memory `api-libcurl-sqlite-refactor` (triage merged). Flip **T6** ✅.

## T7 — Push / PR / merge (CONFIRM WITH HUMAN FIRST)

- [ ] Confirm with the human. Then push `api/triage` → open PR (NO Claude footer)
      → merge to `main` → `git checkout main && git pull` → verify main's tree is
      byte-identical to the gates-green branch tip + ghost-free. Flip **T7** ✅.

---

## §3. Conventions & gates (MANDATORY — see handoff §7)

- **Layers/purity:** L1–L3 `func`/`iterator` only under `{.push raises: [],
  noSideEffect.}` + `strictCaseObjects`; L4/L5 `{.push raises: [].}`. nim-results.
  No catch-all `else` on finite enums. Never `Table.[]`.
- **`hasdoc`** fires over `tests/` too and rejects a docstring trailing a `=
  object` line. **Never** suppress a nimalyzer rule or loosen a setting —
  decompose to comply. British why-focused docstrings citing RFC sections only —
  no design-doc/campaign cross-refs in *code* comments (AUDIT.md / Section C MAY
  reference Sn — that's their purpose).
- **Run the gate YOURSELF** — implementers/reviewers have BOTH claimed green when
  `analyse` actually failed.
- **Commit trailers (every commit), no other AI attribution; PR body NO Claude footer:**
  ```
  Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
  Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
  Assisted-by: Claude:claude-4.8-opus
  ```
- **Stage explicit paths; never `git add -A`.** Branch `api/triage`; never commit
  to `main`. Flip the STATE block (§0) in the same commit as each task.
