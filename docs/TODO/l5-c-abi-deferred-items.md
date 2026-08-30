# L5 C ABI — deferred items

**Written:** 2026-08-30T12:46:54Z
**Commit:** `0e46514245d90d3b0c7014edb893fae6ceba90be` (branch `api/l5-c-abi`, 80 commits from `d234e03`)

Everything the L5 C ABI work surfaced and did not fix. Ordered most
important first. Items whose original IDs came from the branch's working
register are kept so earlier discussion still resolves.

Nothing here blocks the branch: `just ci`, `just test-c` (14 programs,
ASan+UBSan, zero suppressions) and `just build-c-bench` are green, and
the Nim public surface did not move.

---

## 1. Consumer-facing API gaps

**D1 — the C surface cannot reply in-thread, and cannot render read state.**
Send expresses none of `replyTo`, `inReplyTo`, `references`, `htmlBody`,
attachments or `sendAt`. Separately, `jmap_email` exposes nine getters and
`keywords` is not among them, so a consumer can *filter* by read state
(`JMAP_Q_READ_STATE`) but cannot *display* it — a mailbox list view every
mail client has. Neither is a substrate limit: L4's `Email` carries all of
it (`internal/mail/email.nim:477-497`), so both are additive L5 work.
The strongest post-1.0 candidate.

**E14 — no way to learn a borrow's length.** Nothing reports a borrow's
length and no accessor copies into a caller-supplied buffer, so a consumer
keeping a value past the call that invalidates it must `strlen`+`malloc` or
guess a cap. The bench guessed (`examples/jmap-c-cli/jmap_c_cli.c:287`) and
hand-rolled a truncation check. Closing it is an API shape decision.

**E12 — the header is silent on a callback freeing the in-flight client.**
A transport callback calling `jmap_client_free` on the client it is serving
is a use-after-free with no stated contract. `jmap_send_fn` has the same
gap, so this is house-wide rather than local.

**E1 — `jmap_init`'s latch is a non-atomic `bool` under `--threads:on`.**
Two threads racing it can both run `NimMain()`. The header now documents
this (added in the final review wave); the underlying non-atomicity remains
a caller burden.

---

## 2. Latent safety and rot risk

**E7 — nothing guards recurrence of the `=destroy` field-leak shape.**
Adding a field to `TransportObj` silently re-breaks what `0bd94a3` fixed
(~3.1 KB stranded per `connect()`), because a user-declared `=destroy`
replaces generated field destruction outright. No lint; `public-api.txt`
pins only the hook signature. Needs a real gate.

**D6 — `internal/submission_status.nim:391` slices without a length guard.**
`line[4 .. line.high]` raises `RangeDefect` on a short string. Safe today:
the only caller guards `line.len < 3` at `:376` and the proc is
module-private. It is the raw-index audit's one live example of its
disclosed slice blind spot.

**E6 — `transport.nim:113`'s `addr(t.field)[]` rests on unpinned codegen**
(a non-`var` object parameter passed by reference). Sound today; nothing
in-tree asserts it.

**D7 — `tests/compliance/tffi_panic_surface.nim`'s `Guarded` table has no
staleness detection**, unlike the raw-index audit's self-verifying `Exempt`
table. A row naming a vanished field stops matching silently — the same rot
class fixed elsewhere on this branch, in the same file.

**E5 — `tests/wire_contract/public-api.txt` pins `proc =destroy (t:
TransportObj)`**, ruling out the stdlib-idiomatic `var TransportObj` form
and forcing the `addr(t.field)[]` workaround above.

---

## 3. CI and tooling

**E15 — hosted CI runs a strict subset of `just ci`.** The H1/H1b/H10–H13
boundary lints and H15–H17 snapshot locks run locally but are not steps in
`.github/workflows/ci.yml`, so "green in CI" is the weaker claim, and it is
the one a PR displays. Predates this branch.

**D5 — every lint gate shares a fixed `/tmp/jmap_*` path.** Two concurrent
checkouts on one machine collide, and cleanup fails if another user owns the
path. A `mktemp` convention would fix it house-wide.

**D4 — hosted ASan startup may need `vm.mmap_rnd_bits` lowered** on newer
Ubuntu runner kernels. Not verifiable from this environment; if a hosted run
fails at startup rather than on an assertion, this is why.

**E17 — the C suite's program count is asserted in three places** (doc 17
`:634` and `:730`, `pre-1.0-api-alignment.md:3251`) with nothing holding it
to the `ctests/t*.c` glob `just test-c` drives. Adding a `t15` falsifies all
three. True today; all three sites are dated records.

**E13 — nimble packaging of `include/` and `ctests/` is unresolved.**
`jmap_client.nimble` sets only `srcDir = "src"`.

---

## 4. Documentation and internal consistency

**E16 — `docs/design/00-architecture.md` §5 points at doc 17's handle
taxonomy**, which is now correct only when read together with the dated
amendments below it. Whether an overview tracks amendments or deliberately
lags them is an editorial policy question.

**E8 — `config.nims`' `typeBoundOps` rationale is stale.** It asserts "the
project does not define custom lifetime hooks"; `TransportObj`'s hook
predates this branch.

**E11 — two session caches with no shared invalidation.** `fetchSession`
always performs a network GET, so the L5 cache and L4's `client.session`
can diverge.

**E9 — L5's private `normaliseContentType` duplicates L4's private
`readContentType`.** Consistent duplication, the best available under the
no-widening invariant, but the contract lives in two places.

**E4 — `justfile`'s `LSAN_OPTIONS` export clobbers** rather than appends to
an operator-set value.

**D3 — `src/jmap_client.nim` is ~2,450 lines.** Architectural rather than
accidental: A10 mandates a single L5 export hub. Worth watching as the C
surface grows.

**E10 — a source comment uses generic "this task" phrasing.**

**E2 / E3 — two entries recorded as self-resolving** (the header's contract
summary, and `{.used.}` docstrings that narrated future work). Both believed
closed by later work; neither re-verified.

---

## 5. Decided — no action

**C1 — scaffolding in commit messages. Owner decision 2026-08-30: leave the
history as it is.** Three subjects read like "…review round 1" (`e53da2c`
vacation-view, `d06f635` email-view, `1b9ad12` mailbox-view), and roughly
fourteen bodies reference tasks or rounds, which `CLAUDE.md` forbids. Closed as won't-fix. This also leaves
`2b97fb2`'s body overstating what the header snapshot gate catches, since
that correction was folded into the same decision.

**D2 — `jmap_sync_has_more` returns 0 for a NULL handle**, so "bad handle"
and "delta complete" are indistinguishable. LEAVE: it matches every other
pure-read accessor, and changing one would make it the inconsistent one.

**C2 — not a violation.** `4c87d7d` and `d874dcb` use the word "plan" as a
self-reference to the document they edit.

**A1 — wrong RFC citation in `one_shot.nim`'s `sendPlainText` docstring**
(cited §5.4 `/copy`; correct is RFC 8621 §7.5). Fixed at source.

**A2 — the header's query section carried no RFC citation.** Fixed (RFC 8621
§4.4 for `Email/query`, §4.2 for `Email/get`).

**B1 / B2 — two plan listings drifted from landed code** (`setQueryLimit`
replacing the whole `QueryParams` object; `fillFromEmailSet`'s ptr-mutating
form). Both corrected in `ecac442`.
