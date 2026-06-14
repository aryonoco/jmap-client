<!-- SPDX-License-Identifier: CC-BY-4.0 -->
# S0 — Truthful public-API contract — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax. Spec: `docs/superpowers/specs/2026-06-14-s0-truthful-contract-design.md`.

**Goal:** Replace the text-scraping public-API resolver (`scripts/api_surface.nim`)
with a compiler-as-library oracle that derives `public-api.txt` and
`type-shapes.txt` from the compiler's own post-sem symbol table, so the contract
faithfully describes the consumer-reachable surface.

**Architecture:** A standalone in-repo Nim program (`scripts/api_oracle.nim`)
loads a union probe of both hub entry points, runs `sem`, walks
`modulegraphs.allSyms` (own + re-exported symbols), and renders two views
(signatures + type shapes) exactly from the compiler AST. The `freeze-*` recipes
and H16/H17 lints are rewired onto it; the text scraper is retired.

**Tech Stack:** Nim 2.2.8, the `compiler/` package (`-d:nimcore --path:"$nim"`),
`just`, `nph`, nimalyzer, testament.

---

## STATE / HANDOFF  (read this first after any compaction)

**Campaign:** API → libcurl/SQLite refactor (version-agnostic, quality
showcase). Memories: `api-libcurl-sqlite-refactor`, `api-design-only-consumers`.
This is sub-project **S0 of 6** (S0 truthful contract → S1 one error rail → S2
read-model uniformity → S3 complete the core → S4 one-shots + easy-path; plus
the AUDIT Phase-2 triage ledger).

**Design lens (never violate):** the ONLY API design input is future application
developers (libcurl/SQLite, not OpenSSL/libdbus). Tests and current callers
(`convenience.nim`, the CLI, integration tests) do NOT shape the API; if one
breaks under a principled cut, that is a FINDING, not a constraint. (S0 is
tooling, not API — but the lens governs every justification.)

**Quality gates (every phase must end green):**
`just fmt-check` · `just lint` · `just analyse` · `just test` · `just reuse`
(all via `just ci`); plus `just lint-public-api` (H16) and `just lint-type-shapes`
(H17). Commits use the **Linux-kernel format** (subject `subsystem: short desc`
≤75 cols, imperative; body explains *why*, wrapped ~75) with these three trailers
and NO other AI attribution:
```
Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
```

**Branch:** `api/s0-truthful-contract` (off `main`).

**Progress ledger** (update the marker as each phase lands; record the commit
hash):
- [x] Phase 0 — branch + commit spec & plan — `b6d0666` (spec intentionally gitignored per `docs/superpowers/*`; plan tracked; spec on disk)
- [x] Phase 1 — oracle enumeration core (names + modules) — done: errorCounter=0, 1232 distinct names (strict superset of old 621, 0 regressions), swallowed families + operators recovered, build OK under repo config.nims with `--hints:off --warnings:off -d:nimcore --path:"$NIMPREFIX"` (NIMPREFIX via `dirname×2 readlink $(command -v nim)`); see git log
- [x] Phase 2 — signature rendering → `--mode:api` body — done: 1678 rows; signatures from compiler AST (routine [generics]+params+return, const types, type generic params); operators + grouped-const members present; nim-results provenance section; 0 phantom unbound-T rows; deterministic. Build: `nim c --hints:off --warnings:off -d:nimcore --path:"$NIMPREFIX" -o:/tmp/api_oracle scripts/api_oracle.nim`; run: `API_ORACLE_MODE=api /tmp/api_oracle check --mm:arc --threads:on --panics:on --path:src --path:vendor/nim-results scripts/api_probe.nim`. See git log.
- [ ] Phase 3 — type-shape rendering → `--mode:type-shapes` body — `<hash>`
- [ ] Phase 4 — rewire freeze recipes, retire scraper, regenerate baseline — `<hash>`
- [ ] Phase 5 — rewire H16/H17 lints + negative-control proof — `<hash>`
- [ ] Phase 6 — docstrings, full `just ci` green, PR — `<hash>`

**Known facts to rely on (verified during recon, transcript: workflow
`s0-contract-recon`):**
- Working prototype enumerator: `/tmp/api_enum.nim` (may be gone post-compaction;
  its full source is reproduced verbatim in Phase 1, Step 1).
- `modulegraphs.allSyms(graph, m)` yields own + re-exported `sfExported` syms
  because `semdata.exportSym` AND `reexportSym` both write `ifaces[m.position].interf`.
- Prototype result over a 2-hub probe: `errorCounter=0`, `repo_owned=1304`
  (vs 621 names in the old snapshot — a strict superset, 0 false negatives).
- `compiler/` package is importable in CI (nimalyzer/`just analyse` already use
  `--path:"$nim"`).
- Old snapshot was byte-identical to the live resolver (shared blind spot).
- Only 4 callers of the scraper: `scripts/freeze_public_api.nim`,
  `scripts/freeze_type_shapes.nim`, `tests/lint/h16_public_api_snapshot.nim`,
  `tests/lint/h17_type_shape_snapshot.nim`.

**Verification posture:** S0 verifies the TOOL (superset, determinism,
round-trip, and the decisive negative-control that the lint now actually locks).
It never shapes the API.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `scripts/api_probe.nim` | create | Union re-export of both hub entry points; the oracle's compile target (in-repo so `config.nims` applies). |
| `scripts/api_oracle.nim` | create | Compiler-as-library enumerator + renderer; `--mode:api` / `--mode:type-shapes`; emits header + body to stdout. |
| `scripts/api_surface.nim` | delete | The retired text scraper. |
| `scripts/freeze_public_api.nim` | delete | Folded into the oracle + recipe. |
| `scripts/freeze_type_shapes.nim` | delete | Folded into the oracle + recipe. |
| `justfile` | modify | `freeze-api`, `freeze-type-shapes`, `lint-public-api`, `lint-type-shapes` build+run the oracle. |
| `tests/lint/h16_public_api_snapshot.nim` | modify | Diff committed `public-api.txt` against the oracle's `--mode:api` output. |
| `tests/lint/h17_type_shape_snapshot.nim` | modify | Diff committed `type-shapes.txt` against `--mode:type-shapes` output. |
| `tests/wire_contract/public-api.txt` | regenerate | New honest baseline (large diff). |
| `tests/wire_contract/type-shapes.txt` | regenerate | New honest baseline (large diff). |

---

## Task 0: Branch and land the design artefacts

**Files:** none (git only).

- [ ] **Step 1: Create the S0 branch**

Run:
```bash
cd /workspaces/jmap-client
git checkout -b api/s0-truthful-contract
```
Expected: `Switched to a new branch 'api/s0-truthful-contract'`.

- [ ] **Step 2: Commit the spec and this plan**

Run:
```bash
git add docs/superpowers/specs/2026-06-14-s0-truthful-contract-design.md \
        docs/superpowers/plans/2026-06-14-s0-truthful-contract-plan.md
git commit -F - <<'EOF'
docs: add S0 truthful-contract spec and plan

The public-API contract (public-api.txt / type-shapes.txt) is generated
by a text scraper that mis-describes the hub surface in both directions:
~436 reachable symbols are invisible (typed-literal and inline-comment
runaways, grouped const/type-block members, hand-written and
template-generated operators) and ~22 phantom rows assert symbols that
do not exist. The generator and the H16/H17 lints share the resolver, so
the lint passes while the contract lies.

Record the design and the task-by-task plan to replace the scraper with
a compiler-as-library oracle that reads the compiler's own post-sem
symbol table — the literal definition of what `import jmap_client`
exposes. First sub-project of the API-to-libcurl/SQLite refactor.

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Expected: one commit created. Record the hash in the STATE ledger.

- [ ] **Step 3: Mark Phase 0 done** in the STATE ledger (`- [x] Phase 0 … <hash>`).

---

## Task 1: Oracle enumeration core (names + owning modules)

Prove the compiler oracle enumerates the reachable surface before any rendering.

**Files:**
- Create: `scripts/api_probe.nim`
- Create: `scripts/api_oracle.nim`

- [ ] **Step 1: Create the union probe**

Create `scripts/api_probe.nim`:
```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Union of the two public entry points, the single compile target for the
## API oracle (``scripts/api_oracle.nim``). Living in-repo means the project's
## own ``config.nims`` is found and applied when the oracle compiles it, so the
## enumerated surface is computed under the exact flags a consumer's build sees.

import jmap_client
import jmap_client/convenience

export jmap_client
export convenience
```

- [ ] **Step 2: Create the oracle, enumeration-only**

Create `scripts/api_oracle.nim` (this is the recon-verified prototype, made
prefix-portable via `std/compilesettings` instead of a hardcoded path):
```nim
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compiler-as-library oracle: enumerates the exported (own + re-exported)
## symbols of the public hub from the compiler's post-sem interface table —
## the literal definition of what ``import jmap_client`` exposes.
##
## Depends on compiler-INTERNAL API (``allSyms``, ``ModuleGraph.ifaces``,
## ``sfExported``, the ``semdata`` re-export path). These are not a
## stability-guaranteed public API; Nim is pinned via mise, the dependency is
## audited against ``/.nim-reference``, and a Nim upgrade must re-verify this
## tool. Built with ``nim c -d:nimcore --path:"$nim"`` (same mechanism
## nimalyzer/``just analyse`` already relies on).

import std/[algorithm, sequtils, parseopt, os, strutils, compilesettings]
import compiler/[
  ast, idents, modulegraphs, options, cmdlinehelper, commands, msgs,
  passes, passaux, sem, condsyms, pathutils,
]

const NimPrefix = querySetting(libPath).parentDir
  ## ``…/lib`` → Nim prefix; portable across machines/CI (no hardcoded path).

proc processCmdLine(pass: TCmdLinePass, cmd: string; config: ConfigRef) =
  var p = parseopt.initOptParser(cmd)
  var argsCount = 0
  config.commandLine.setLen 0
  while true:
    parseopt.next(p)
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      config.commandLine.add " "
      config.commandLine.addCmdPrefix p.kind
      config.commandLine.add p.key.quoteShell
      if p.val.len > 0:
        config.commandLine.add ':'
        config.commandLine.add p.val.quoteShell
      if p.key == "":
        p.key = "-"
        if processArgument(pass, p, argsCount, config): break
      else:
        processSwitch(pass, p, config)
    of cmdArgument:
      config.commandLine.add " "
      config.commandLine.add p.key.quoteShell
      if processArgument(pass, p, argsCount, config): break

proc loadGraph(): (ModuleGraph, ConfigRef) =
  let cache = newIdentCache()
  let conf = newConfigRef()
  let self = NimProg(supportsStdinFile: true, processCmdLine: processCmdLine)
  conf.prefixDir = AbsoluteDir NimPrefix
  self.initDefinesProg(conf, "api_oracle")
  self.processCmdLineAndProjectPath(conf)
  var graph = newModuleGraph(cache, conf)
  if not self.loadConfigsAndProcessCmdLine(cache, conf, graph):
    quit "api_oracle: config/cmdline failed"
  if conf.cmd == cmdCheck and conf.backend == backendInvalid:
    conf.backend = backendC
  if conf.selectedGC == gcUnselected and conf.backend != backendJs:
    initOrcDefines(conf)
  registerPass(graph, verbosePass)
  registerPass(graph, semPass)
  compileProject(graph)
  (graph, conf)

proc main() =
  let (graph, conf) = loadGraph()
  let m = graph.getModule(conf.projectMainIdx)
  if m == nil:
    quit "api_oracle: no main module symbol"
  var rows: seq[string] = @[]
  for s in allSyms(graph, m):
    if s == nil or sfExported notin s.flags: continue
    let modPath = toFullPath(conf, s.info.fileIndex)
    rows.add($s.kind & "\t" & s.name.s & "\t" & modPath)
  rows.sort()
  rows = deduplicate(rows)
  stderr.writeLine "api_oracle: errorCounter=" & $conf.errorCounter &
    " exported=" & $rows.len
  for r in rows:
    echo r

main()
```

- [ ] **Step 3: Build the oracle**

Run:
```bash
nim c -d:nimcore --path:"$nim" -o:/tmp/api_oracle scripts/api_oracle.nim
```
Expected: compiles, exit 0. If `compiler/...` is not found, confirm the prefix:
`nim --eval:'import std/compilesettings, std/os; echo querySetting(libPath).parentDir'`
and that `<prefix>/compiler/modulegraphs.nim` exists.

- [ ] **Step 4: Run it over the probe under the project flags**

Run:
```bash
/tmp/api_oracle check --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim \
  > /tmp/oracle_names.txt
wc -l /tmp/oracle_names.txt
grep -cE "	(send|freeze|newBuilder|fetchSession)	" /tmp/oracle_names.txt
grep -cE "	(EmailUpdateSet|NonEmptyEmailUpdates|initEmailUpdateSet)	" /tmp/oracle_names.txt
grep -cE "	(egpId|kwSeen|roleInbox|ResponseHandle)	" /tmp/oracle_names.txt
grep -E "	==	|	\\$	" /tmp/oracle_names.txt | head
```
Expected: `errorCounter=0` on stderr; line count clearly > 621; each `grep -c`
returns ≥1 (the previously-swallowed symbols are now present); operators appear.

- [ ] **Step 5: Verify superset over the old snapshot (no regressions)**

Run:
```bash
# Extract bare names the old snapshot listed (decl lines: "<kind> <name> …").
grep -E "^(type|func|proc|template|iterator|const|macro) " \
  tests/wire_contract/public-api.txt | awk '{print $2}' | sort -u > /tmp/old_names.txt
cut -f2 /tmp/oracle_names.txt | sort -u > /tmp/new_names.txt
echo "old-only (should be ONLY the ~22 phantom generic rows, e.g. unbound T):"
comm -23 /tmp/old_names.txt /tmp/new_names.txt
```
Expected: the `old-only` list is empty or contains ONLY the known phantom
template-body artefacts (`hash`, `len`, `accountId`, `items`, `pairs`, … that
were bogus). Any *real* symbol appearing here is a regression — investigate
before proceeding.

- [ ] **Step 6: Commit**

```bash
git add scripts/api_probe.nim scripts/api_oracle.nim
git commit -F - <<'EOF'
scripts: add compiler-as-library API oracle (enumeration core)

Introduce api_oracle.nim, which loads a union probe of both public hub
entry points, runs sem, and walks modulegraphs.allSyms to enumerate the
exported own-plus-re-exported symbols from the compiler's interface
table. This is the consumer-reachable surface by construction, immune to
the text scraper's typed-literal/comment runaways and able to see the
template-generated operators no text process can expand.

The probe lives in-repo so the project config.nims applies, and the Nim
prefix is resolved via std/compilesettings rather than hardcoded, so the
tool is portable across machines and CI.

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Record the hash; mark Phase 1 done in the STATE ledger.

---

## Task 2: Signature rendering → `--mode:api` body

Turn enumerated symbols into the `public-api.txt` body: `## <module>` section
headers, then `<kind> <name> <signature>` lines, deterministic, with operators
and grouped-const members included, nim-results re-exports in their own section.

**Files:** Modify `scripts/api_oracle.nim`.

- [ ] **Step 1: Add module-key, partition, and signature helpers**

Add to `api_oracle.nim` (above `main`). Render signatures from the symbol's AST
using the compiler `renderer`; verify the exact form by output in Step 3.
```nim
import compiler/renderer  # renderTree / $PNode

type Origin = enum oRepo, oResults, oOther

func originOf(modPath: string): Origin =
  if "/jmap-client/src/" in modPath: oRepo
  elif "/nim-results/" in modPath: oResults
  else: oOther

func moduleKey(modPath: string): string =
  ## ".../jmap-client/src/jmap_client/internal/types/session.nim"
  ##   -> "jmap_client/internal/types/session"
  let marker = "/jmap-client/src/"
  let i = modPath.find(marker)
  let rel = if i >= 0: modPath[i + marker.len .. ^1] else: modPath
  rel.changeFileExt("")

proc renderSignature(s: PSym): string =
  ## Routine signature (params + return) for skProc/skFunc/skTemplate/skMacro/
  ## skIterator; the type for skConst; empty for plain types (shapes live in
  ## type-shapes). Exact spelling is taken from the compiler AST, not regex.
  case s.kind
  of skProc, skFunc, skMethod, skConverter, skTemplate, skMacro, skIterator:
    # s.ast[paramsPos] is the formal params node; render and normalise spaces.
    if s.ast != nil and s.ast.len > paramsPos and s.ast[paramsPos] != nil:
      result = renderTree(s.ast[paramsPos], {renderNoComments}).splitWhitespace().join(" ")
    else:
      result = ""
  of skConst, skVar, skLet:
    result = typeToString(s.typ)
  else:
    result = ""
```
Note: `paramsPos` is from `compiler/ast`. If `renderTree` of the params node is
awkward, fall back to `typeToString(s.typ)` (a `proc (…): R` form) — Step 3
decides which reads cleanest; pick one and apply it uniformly.

- [ ] **Step 2: Emit the `--mode:api` body**

Replace `main`'s emit loop with a mode-aware renderer:
```nim
proc emitApi(graph: ModuleGraph, conf: ConfigRef, m: PSym) =
  type Row = object
    module, kind, name, sig: string
    origin: Origin
  var rows: seq[Row] = @[]
  for s in allSyms(graph, m):
    if s == nil or sfExported notin s.flags: continue
    let mp = toFullPath(conf, s.info.fileIndex)
    let origin = originOf(mp)
    if origin == oOther: continue  # neither repo nor nim-results: a finding
    if s.kind == skType: discard  # types appear by name (shapes -> type-shapes)
    rows.add Row(
      module: (if origin == oRepo: moduleKey(mp) else: "nim-results"),
      kind: ($s.kind).replace("sk", "").toLowerAscii,
      name: s.name.s, sig: renderSignature(s), origin: origin)
  # Deterministic order: repo modules first (by module,name,sig), then results.
  rows.sort(proc(a, b: Row): int =
    result = cmp(a.origin, b.origin)
    if result == 0: result = cmp(a.module, b.module)
    if result == 0: result = cmp(a.name, b.name)
    if result == 0: result = cmp(a.sig, b.sig))
  rows = deduplicate(rows)
  var lastModule = ""
  for r in rows:
    let header =
      if r.origin == oResults: "## re-exported from nim-results (pinned dependency)"
      else: "## " & r.module
    if r.module != lastModule:
      if lastModule.len > 0: echo ""
      echo header
      lastModule = r.module
    if r.sig.len > 0: echo r.kind & " " & r.name & " " & r.sig
    else: echo r.kind & " " & r.name
```
Add a `--mode` parse in `main` (default `api`), and an emitted `#`-comment
header block mirroring the current file's header but with wording updated to
"faithful description of the consumer-reachable surface" (drop "1.0 contract").

- [ ] **Step 3: Build, run, inspect the body**

Run:
```bash
nim c -d:nimcore --path:"$nim" -o:/tmp/api_oracle scripts/api_oracle.nim
/tmp/api_oracle check --mode:api --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim > /tmp/api_body.txt
sed -n '1,40p' /tmp/api_body.txt
grep -nE "^func `==`|^func `\\$`" /tmp/api_body.txt | head
grep -n "## re-exported from nim-results" /tmp/api_body.txt
```
Expected: clean `## <module>` sections; readable signatures; operator lines
present with backtick names; a nim-results section near the end. If signatures
read poorly, switch `renderSignature` to the `typeToString` form (Step 1 note)
and rebuild.

- [ ] **Step 4: Determinism check**

Run:
```bash
/tmp/api_oracle check --mode:api --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim > /tmp/api_body2.txt
diff /tmp/api_body.txt /tmp/api_body2.txt && echo "DETERMINISTIC"
```
Expected: `DETERMINISTIC` (no diff).

- [ ] **Step 5: Commit**

```bash
git add scripts/api_oracle.nim
git commit -F - <<'EOF'
scripts: render public-api body from the oracle symbol walk

Render each exported symbol as "<kind> <name> <signature>" grouped under
per-module headers, with signatures taken from the compiler AST rather
than regex normalisation. Hand-written and template-generated operators
and grouped-const members now appear; nim-results re-exports are listed
in a clearly-marked section, since a consumer reaches them through the
single import and the contract must say so.

Output is deterministic (sorted by module, name, signature; deduplicated).

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Record the hash; mark Phase 2 done.

---

## Task 3: Type-shape rendering → `--mode:type-shapes` body

Emit `type-shapes.txt`: `## <Type> [<module>]` then public-field shape lines
(object fields, case scaffolding) or enum members, matching the existing file's
structure. Private `raw*` fields excluded (keep only `sfExported` members).

**Files:** Modify `scripts/api_oracle.nim`.

- [ ] **Step 1: Walk the type record / enum AST**

Add a renderer that, for each exported `skType`, walks `s.typ`:
- enum (`s.typ.kind == tyEnum`): list each member symbol's name (with `= "wire"`
  backing where present) from `s.typ.n`.
- object/case (`tyObject`): recurse `s.typ.n` (the record node), emitting only
  fields whose symbol has `sfExported`; preserve `case`/`of`/`else` scaffolding
  so variants read structurally (mirror the current `type-shapes.txt` format).
Render field types via `typeToString(field.typ)`. Use the compiler `renderer`
for case-branch labels. Verify exact form by output in Step 2 against the
current file's style for a known type (e.g. `EmailUpdate`, a case object).

- [ ] **Step 2: Build, run, compare structure**

Run:
```bash
nim c -d:nimcore --path:"$nim" -o:/tmp/api_oracle scripts/api_oracle.nim
/tmp/api_oracle check --mode:type-shapes --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim > /tmp/shapes_body.txt
# Compare a stable, simple type's block against the current committed shape:
awk '/^## MailboxRights /{f=1} f&&/^## /&&!/MailboxRights/{exit} f' \
  tests/wire_contract/type-shapes.txt
echo "--- new ---"
awk '/^## MailboxRights /{f=1} f&&/^## /&&!/MailboxRights/{exit} f' /tmp/shapes_body.txt
grep -c "^## " /tmp/shapes_body.txt   # section count >= current
```
Expected: the new `MailboxRights` block matches the old (nine `may*` bools);
enum members now appear for enum types that previously lacked them; total
section count ≥ the current file.

- [ ] **Step 3: Determinism check**, then **Commit**

```bash
/tmp/api_oracle check --mode:type-shapes --mm:arc --threads:on --panics:on \
  --path:src --path:vendor/nim-results scripts/api_probe.nim > /tmp/shapes_body2.txt
diff /tmp/shapes_body.txt /tmp/shapes_body2.txt && echo DETERMINISTIC
git add scripts/api_oracle.nim
git commit -F - <<'EOF'
scripts: render type-shape body from the oracle type walk

Emit the public-field shape of every reachable type and every enum's
members by walking the compiler's type AST, keeping only exported fields
so internal sealing refactors do not churn the snapshot. Enum members,
previously absent, are now captured.

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Record the hash; mark Phase 3 done.

---

## Task 4: Rewire freeze recipes, retire the scraper, regenerate the baseline

**Files:** Modify `justfile`; delete `scripts/api_surface.nim`,
`scripts/freeze_public_api.nim`, `scripts/freeze_type_shapes.nim`; regenerate
both snapshots.

- [ ] **Step 1: Update the `freeze-api` / `freeze-type-shapes` recipes**

In `justfile`, change both recipes to build + run the oracle. Replace the
`nim r ... scripts/freeze_public_api.nim` invocation (justfile:462 region) with:
```make
freeze-api:
    nim c -d:nimcore --path:"$nim" -o:/tmp/jmap_api_oracle scripts/api_oracle.nim
    /tmp/jmap_api_oracle check --mode:api --mm:arc --threads:on --panics:on \
      --path:src --path:vendor/nim-results scripts/api_probe.nim \
      > tests/wire_contract/public-api.txt
```
and the `freeze-type-shapes` recipe (justfile:481 region) analogously with
`--mode:type-shapes` → `tests/wire_contract/type-shapes.txt`. Keep the existing
recipe doc-comments about the `[API-CHANGE]` / `[TYPE-SHAPE-CHANGE]` labels.

- [ ] **Step 2: Delete the retired scraper and freeze wrappers**

Run:
```bash
git rm scripts/api_surface.nim scripts/freeze_public_api.nim scripts/freeze_type_shapes.nim
```

- [ ] **Step 3: Regenerate both snapshots**

Run:
```bash
just freeze-api
just freeze-type-shapes
git --no-pager diff --stat tests/wire_contract/public-api.txt tests/wire_contract/type-shapes.txt
```
Expected: both files rewritten; large additions (~+436 to `public-api.txt`,
enum members to `type-shapes.txt`) and removal of the ~22 phantom rows.

- [ ] **Step 4: Audit the diff deliberately**

Run:
```bash
git --no-pager diff tests/wire_contract/public-api.txt | sed -n '1,120p'
```
Read it. Every addition must be a genuinely reachable symbol; every removal must
be a phantom/template-body artefact (not a real symbol). If any *real* symbol is
removed, STOP — that is a regression, not the intended honest baseline. Note
anything surprising in the STATE ledger.

- [ ] **Step 5: Commit**

```bash
git add justfile tests/wire_contract/public-api.txt tests/wire_contract/type-shapes.txt
git commit -F - <<'EOF'
scripts: drive the contract from the oracle; retire the text scraper

Point the freeze-api / freeze-type-shapes recipes at the compiler oracle
and remove api_surface.nim and the two freeze wrappers. Regenerate both
snapshots as the new honest baseline: the public surface is described at
its true size for the first time (~436 previously-invisible symbols
appear, ~22 phantom generic-template rows are gone). This is a
description fix, not an API change — no public behaviour moves.

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Record the hash; mark Phase 4 done.

---

## Task 5: Rewire the H16/H17 lints + the decisive negative-control proof

**Files:** Modify `tests/lint/h16_public_api_snapshot.nim`,
`tests/lint/h17_type_shape_snapshot.nim`, and the `lint-public-api` /
`lint-type-shapes` recipes in `justfile`.

- [ ] **Step 1: Make the lints diff committed-vs-oracle**

Rewrite `h16_public_api_snapshot.nim` so it no longer imports `api_surface`.
The lint reads the committed snapshot body and the oracle's live `--mode:api`
output (passed as a file path argument by the recipe), and diffs them
bidirectionally — keeping the existing helpful "REMOVED / ADDED" reporting.
Skeleton:
```nim
# args: <committed public-api.txt> <live oracle output>
import std/[os, strutils, sets, sequtils, algorithm]
proc body(path: string): seq[string] = ...   # reuse existing header-stripping
proc main() =
  let committed = body(paramStr(1))
  let live = body(paramStr(2))   # oracle output already header-stripped or stripped here
  # ... existing set-diff + REMOVED/ADDED reporting + quit(1) on drift ...
main()
```
Apply the same change to `h17_type_shape_snapshot.nim`.

- [ ] **Step 2: Update the lint recipes to feed the oracle output**

In `justfile`, make `lint-public-api` build+run the oracle to a temp file, then
run the lint with both paths:
```make
lint-public-api:
    nim c -d:nimcore --path:"$nim" -o:/tmp/jmap_api_oracle scripts/api_oracle.nim
    /tmp/jmap_api_oracle check --mode:api --mm:arc --threads:on --panics:on \
      --path:src --path:vendor/nim-results scripts/api_probe.nim > /tmp/jmap_api_live.txt
    nim r --hints:off tests/lint/h16_public_api_snapshot.nim \
      tests/wire_contract/public-api.txt /tmp/jmap_api_live.txt
```
and `lint-type-shapes` analogously.

- [ ] **Step 3: Round-trip — lints pass on the fresh baseline**

Run:
```bash
just lint-public-api && echo H16-OK
just lint-type-shapes && echo H17-OK
```
Expected: both print OK (the committed baseline from Task 4 matches the oracle).

- [ ] **Step 4: NEGATIVE CONTROL — prove the lint now actually locks**

This is the decisive correctness proof: the old lint was blind to additions.
```bash
# Add a throwaway export to a hub-reachable module:
printf '\nfunc s0NegativeControlProbe*(): int = 42\n' >> src/jmap_client/internal/transport.nim
just lint-public-api; echo "exit=$?"   # expect: FAIL (exit 1) listing the new symbol as ADDED
git checkout -- src/jmap_client/internal/transport.nim
just lint-public-api && echo "RESTORED-OK"
```
Expected: the middle run **fails** and names `s0NegativeControlProbe` as ADDED;
after revert, the lint passes again. If the failing run passes, the lint is
still blind — STOP and fix before continuing. (Throwaway only — never commit it.)

- [ ] **Step 5: Commit**

```bash
git add tests/lint/h16_public_api_snapshot.nim tests/lint/h17_type_shape_snapshot.nim justfile
git commit -F - <<'EOF'
tests: lock the contract against the oracle, not the scraper

Rewire the H16/H17 snapshot lints to diff the committed contract against
the compiler oracle's live output instead of the retired text resolver.
The generator and the lint now share ground truth rather than a shared
blind spot, so a drift the old lint could not see — a newly exported
symbol on a hub-reachable module — now fails CI (verified by negative
control).

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```
Record the hash; mark Phase 5 done.

---

## Task 6: Docstrings, full gate, PR

**Files:** docstring touch-ups in the oracle/lints as needed; no new code.

- [ ] **Step 1: Reconcile contract framing**

Grep the rewired files and the snapshot headers for "1.0 contract" / "the moment
1.0 ships" framing and reword to the version-agnostic, consumer-faithfulness
language (the contract is a *faithful description of the consumer-reachable
surface*, locked so drift is deliberate). Do not touch unrelated docs.
```bash
grep -rn "1.0" tests/lint/h16_public_api_snapshot.nim tests/lint/h17_type_shape_snapshot.nim \
  tests/wire_contract/public-api.txt tests/wire_contract/type-shapes.txt
```

- [ ] **Step 2: Format + REUSE**

Run:
```bash
just fmt
just fmt-check
just reuse
```
Expected: `fmt-check` clean (oracle/probe are nph-formatted; if `nph` reformats
the compiler-API code, accept its output); `reuse` passes (scripts carry inline
SPDX headers; docs/snapshots covered by REUSE.toml globs).

- [ ] **Step 3: Full CI gate**

Run:
```bash
just ci
```
Expected: reuse + fmt-check + lint + analyse + test all green. If `just analyse`
(nimalyzer) or `just lint` scans `scripts/` and objects to the compiler-API
imports, scope the analyser config to exclude the oracle the same way other
script tooling is handled — record the resolution in the STATE ledger. If
`just test` runs H16/H17 via testament, confirm they consume the oracle path
(they are invoked through the recipes, not directly compiled against
`api_surface`).

- [ ] **Step 4: Commit any doc/format fixes**

```bash
git add -A
git commit -F - <<'EOF'
scripts: reconcile contract docstrings to the consumer-faithfulness framing

Drop the "1.0 contract" wording from the snapshot tooling in line with
the version-agnostic refactor: the contract's role is a faithful,
locked description of the consumer-reachable surface.

Co-developed-by: Aryan Ameri <github@aryan.ameri.coffee>
Signed-off-by: Aryan Ameri <github@aryan.ameri.coffee>
Assisted-by: Claude:claude-4.8-opus
EOF
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin api/s0-truthful-contract
gh pr create --fill --title "API refactor S0: truthful public-API contract"
```
Mark Phase 6 done in the STATE ledger; update the campaign memory that S0 is
complete and S1 (one error rail) is next.

---

## Self-Review (run before declaring the plan ready)

- **Spec coverage:** oracle (§4.1)→T1–T3; integration freeze (§4.2)→T4; lints
  (§4.2)→T5; retire scraper (§4.1)→T4; scope decisions (§5)→T2 (nim-results
  section), T3 (two-file split); verification (§8) superset→T1.5, determinism→
  T2.4/T3.3, round-trip→T5.3, negative control→T5.4, full gate→T6.3; docstrings
  (§9)→T6.1. The optional jsondoc second opinion (§8.5) is deliberately not a
  task (cost/benefit decided against during execution unless trivial).
- **Placeholders:** signature/type-shape *rendering* (T2.1, T3.1) specifies the
  compiler functions (`renderTree`, `typeToString`, walk `s.typ.n`) and a
  verify-by-output gate rather than a final literal string — this is a genuine
  discovery step against the compiler AST, not a hand-wave; the exact form is
  pinned by its inspection step.
- **Type consistency:** `api_oracle.nim`, `api_probe.nim`, `--mode:api` /
  `--mode:type-shapes`, `Origin`/`moduleKey`/`renderSignature` are used
  consistently across tasks.
