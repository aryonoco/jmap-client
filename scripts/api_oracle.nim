# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compiler-as-library oracle: enumerates the exported (own + re-exported)
## symbols of the public hub from the compiler's post-sem interface table —
## the literal definition of what ``import jmap_client`` exposes — and renders
## two contract views: ``--mode:api`` (the public-api.txt body) and
## ``--mode:type-shapes`` (the type-shapes.txt body). Mode is selected via the
## ``API_ORACLE_MODE`` environment variable (``api`` default) so it does not
## collide with the Nim command line the oracle hands to ``compileProject``.
##
## Depends on compiler-INTERNAL API (``allSyms``, ``ModuleGraph.ifaces``,
## ``sfExported``, the ``semdata`` re-export path, the AST renderer). These are
## not a stability-guaranteed public API; Nim is pinned via mise, the dependency
## is audited against ``/.nim-reference``, and a Nim upgrade must re-verify this
## tool. Built with ``nim c -d:nimcore --path:"$nim"`` (the same mechanism
## nimalyzer / ``just analyse`` already relies on).

import std/[algorithm, sequtils, parseopt, os, strutils, compilesettings]
import compiler/[
  ast, idents, modulegraphs, options, cmdlinehelper, commands, msgs,
  passes, passaux, sem, condsyms, pathutils, renderer, types,
]

const NimPrefix = querySetting(libPath).parentDir
  ## ``…/lib`` → Nim prefix; portable across machines/CI (no hardcoded path).

# ---------------------------------------------------------------------------
# Compiler graph bootstrap (cribbed from nim.nim / nimsuggest.nim)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

proc rnd(n: PNode): string =
  ## Render an AST node to its source-like spelling (no comments), collapsed
  ## to single spaces for a stable one-line form.
  if n == nil: ""
  else: renderTree(n, {renderNoComments}).splitWhitespace().join(" ")

func kindWord(k: TSymKind): string =
  ## ``skFunc`` → ``func``; the contract uses the source keyword.
  ($k)[2 ..^ 1].toLowerAscii

func moduleKey(modPath: string): string =
  ## ``…/jmap-client/src/jmap_client/internal/types/session.nim``
  ##   → ``jmap_client/internal/types/session``
  const marker = "/jmap-client/src/"
  let i = modPath.find(marker)
  let rel = if i >= 0: modPath[i + marker.len .. ^1] else: modPath
  os.changeFileExt(rel, "")

proc renderParams(fp: PNode): string =
  ## ``(name: Type = default, …): Return`` from an nkFormalParams node.
  var parts: seq[string] = @[]
  for i in 1 ..< fp.len:
    let idef = fp[i]
    if idef.kind notin {nkIdentDefs, nkConstDef} or idef.len < 2:
      continue
    let typ = idef[idef.len - 2]
    let def = idef[idef.len - 1]
    var names: seq[string] = @[]
    for j in 0 ..< idef.len - 2:
      names.add(rnd(idef[j]))
    var piece = names.join(", ")
    if typ != nil and typ.kind != nkEmpty:
      piece &= ": " & rnd(typ)
    if def != nil and def.kind != nkEmpty:
      piece &= " = " & rnd(def)
    parts.add(piece)
  result = "(" & parts.join(", ") & ")"
  if fp.len > 0 and fp[0] != nil and fp[0].kind != nkEmpty:
    result &= ": " & rnd(fp[0])

proc routineGenerics(s: PSym): string =
  ## ``[T]`` / ``[T; U]`` generic-param clause of a routine (already bracketed
  ## by the renderer), or empty for a non-generic routine.
  if s.ast != nil and s.ast.safeLen > genericParamsPos and
      s.ast[genericParamsPos] != nil and
      s.ast[genericParamsPos].kind == nkGenericParams:
    rnd(s.ast[genericParamsPos])
  else:
    ""

proc renderSignature(s: PSym): string =
  ## Routine: ``[Generics](params): Return``. Const: ``: Type``. Type: generic
  ## params ``[T]`` if any (the field shape lives in type-shapes). Empty else.
  if s.kind in routineKinds:
    if s.ast != nil and s.ast.safeLen > paramsPos and s.ast[paramsPos] != nil and
        s.ast[paramsPos].kind == nkFormalParams:
      routineGenerics(s) & renderParams(s.ast[paramsPos])
    else:
      ""
  elif s.kind == skConst:
    if s.typ != nil: ": " & typeToString(s.typ) else: ""
  elif s.kind == skType:
    # Generic params live at index 1 of the type's defining nkTypeDef; the
    # renderer already brackets them, so emit as-is (no extra brackets).
    if s.ast != nil and s.ast.kind == nkTypeDef and s.ast.safeLen > 1 and
        s.ast[1] != nil and s.ast[1].kind == nkGenericParams:
      rnd(s.ast[1])
    else:
      ""
  else:
    ""

# ---------------------------------------------------------------------------
# Emit: --mode:api
# ---------------------------------------------------------------------------

type Origin = enum
  oRepo
  oResults

type Row = object
  module: string
  kind: string
  name: string
  sig: string
  origin: Origin

proc collectRows(graph: ModuleGraph, conf: ConfigRef, m: PSym): seq[Row] =
  result = @[]
  for s in allSyms(graph, m):
    if s == nil or sfExported notin s.flags:
      continue
    let mp = toFullPath(conf, s.info.fileIndex)
    let isRepo = "/jmap-client/src/" in mp
    let isResults = "/nim-results/" in mp
    if not (isRepo or isResults):
      continue # neither repo nor pinned dependency: would be a finding
    let origin = if isRepo: oRepo else: oResults
    result.add Row(
      module: (if isRepo: moduleKey(mp) else: "nim-results"),
      kind: kindWord(s.kind),
      name: s.name.s,
      sig: renderSignature(s),
      origin: origin,
    )
  result.sort(
    proc(a, b: Row): int =
      result = cmp(ord(a.origin), ord(b.origin))
      if result == 0:
        result = cmp(a.module, b.module)
      if result == 0:
        result = cmp(a.name, b.name)
      if result == 0:
        result = cmp(a.sig, b.sig)
  )
  result = deduplicate(result, isSorted = true)

proc emitApi(rows: seq[Row]) =
  echo "# Public-API surface — every symbol reachable through"
  echo "# `import jmap_client` and `import jmap_client/convenience`, enumerated"
  echo "# from the compiler's post-sem symbol table by scripts/api_oracle.nim."
  echo "# A faithful description of the consumer-reachable surface; locked by"
  echo "# tests/lint/h16_public_api_snapshot.nim so any drift is deliberate."
  echo "# Regenerate with: just freeze-api"
  var lastModule = ""
  for r in rows:
    if r.module != lastModule:
      if lastModule.len > 0:
        echo ""
      if r.origin == oResults:
        echo "## re-exported from nim-results (pinned dependency)"
      else:
        echo "## " & r.module
      lastModule = r.module
    if r.sig.len > 0:
      echo r.kind & " " & r.name & " " & r.sig
    else:
      echo r.kind & " " & r.name

# ---------------------------------------------------------------------------

proc main() =
  let mode = getEnv("API_ORACLE_MODE", "api")
  let (graph, conf) = loadGraph()
  let m = graph.getModule(conf.projectMainIdx)
  if m == nil:
    quit "api_oracle: no main module symbol"
  let rows = collectRows(graph, conf, m)
  stderr.writeLine "api_oracle: mode=" & mode & " errorCounter=" &
    $conf.errorCounter & " rows=" & $rows.len
  case mode
  of "api":
    emitApi(rows)
  of "type-shapes":
    quit "api_oracle: type-shapes mode lands in Phase 3"
  else:
    quit "api_oracle: unknown API_ORACLE_MODE: " & mode

main()
