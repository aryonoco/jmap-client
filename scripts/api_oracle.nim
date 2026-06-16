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

func stripGensym(s: string): string =
  ## Template-expanded symbols render with a ``\`gensymN`` suffix (e.g.
  ## ``a\`gensym3``) on their introduced identifiers. It is an expansion
  ## artefact — never part of the contract — and its counter can shift between
  ## builds, so drop it for a stable, readable snapshot.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '`' and s.continuesWith("gensym", i + 1):
      i += 1 + "gensym".len
      while i < s.len and s[i] in {'0' .. '9'}:
        inc i
    else:
      result.add s[i]
      inc i

proc rnd(n: PNode): string =
  ## Render an AST node to its source-like spelling (no comments), collapsed to
  ## single spaces and with template gensym suffixes stripped, for a stable
  ## one-line form.
  if n == nil:
    ""
  else:
    stripGensym(renderTree(n, {renderNoComments}).splitWhitespace().join(" "))

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
  echo "# `import jmap_client`, enumerated"
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
# Emit: --mode:type-shapes
# ---------------------------------------------------------------------------

func indentOf(level: int): string =
  ## The contract's structural indent — two spaces per nesting level.
  spaces(level * 2)

func stripQualifiers(s: string): string =
  ## ``typeToString`` qualifies a generic *argument* with its owning module or
  ## type (``Opt[system.string]``, ``Table[headers.Foo, …]``,
  ## ``GetResponse[Owner.T]``) while leaving the head and plain field types
  ## bare. The contract names every type by its lone identifier, so drop each
  ## ``<qualifier>.`` segment, keeping the final component. A qualifier is an
  ## identifier run immediately followed by ``.`` and another identifier; the
  ## ``..`` of a range never matches (the char before the dot is an ident char,
  ## never another dot), so only type spellings are touched.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] in IdentStartChars:
      var j = i
      while j < s.len and s[j] in IdentChars:
        inc j
      if j + 1 < s.len and s[j] == '.' and s[j + 1] in IdentStartChars:
        i = j + 1 # drop the run and its dot — a qualifier prefix
      else:
        result.add s[i ..< j]
        i = j
    else:
      result.add s[i]
      inc i

proc emitRecord(n: PNode, level: int, acc: var seq[string]) =
  ## Walk a post-sem record node (``nkRecList`` / ``nkRecCase`` / ``nkSym``),
  ## emitting one line per EXPORTED field. The sealed ``raw*`` backing fields
  ## carry no ``sfExported`` flag, so they are dropped here — internal
  ## representation never leaks into the contract. Case scaffolding (the
  ## discriminator, each ``of`` label list, ``else``) is preserved so the
  ## variant structure stays legible even when a branch has no public fields.
  if n == nil:
    return
  case n.kind
  of nkRecList:
    for child in n:
      emitRecord(child, level, acc)
  of nkSym:
    if sfExported in n.sym.flags:
      acc.add indentOf(level) & n.sym.name.s & "*: " &
        stripQualifiers(typeToString(n.sym.typ))
  of nkRecCase:
    # The discriminator is the case node's first child; its own ``*`` reflects
    # whether it is exported (a sealed ``rawKind`` discriminator is not).
    if n.len > 0 and n[0].kind == nkSym:
      let disc = n[0].sym
      let star = if sfExported in disc.flags: "*" else: ""
      acc.add indentOf(level) & "case " & disc.name.s & star & ": " &
        stripQualifiers(typeToString(disc.typ))
    for i in 1 ..< n.len:
      let branch = n[i]
      case branch.kind
      of nkOfBranch:
        var labels: seq[string] = @[]
        for j in 0 ..< branch.len - 1:
          labels.add rnd(branch[j])
        acc.add indentOf(level) & "of " & labels.join(", ") & ":"
        emitRecord(branch[^1], level + 1, acc)
      of nkElse:
        acc.add indentOf(level) & "else:"
        emitRecord(branch[^1], level + 1, acc)
      else:
        discard
  else:
    discard

proc emitEnum(t: PType, acc: var seq[string]) =
  ## One line per enum member. A member declared ``name = "wire"`` carries its
  ## string literal on the member symbol's ``ast`` (attached at sem time, per
  ## the compiler's own ``genEnumInfo``); a member with no explicit backing has
  ## a nil ``ast`` and renders as the bare identifier. ``t.n`` children are the
  ## member symbols in ordinal order.
  for i in 0 ..< t.n.len:
    let field = t.n[i].sym
    if field.ast != nil and field.ast.kind in {nkStrLit, nkRStrLit, nkTripleStrLit}:
      acc.add indentOf(1) & field.name.s & " = \"" & field.ast.strVal & "\""
    else:
      acc.add indentOf(1) & field.name.s

func toBody(t: PType): PType =
  ## A generic type definition presents as ``tyGenericBody`` wrapping the
  ## structural type we render; unwrap to the body so ``Foo[T] = object`` and
  ## ``Foo = object`` are treated alike.
  result = t
  while result != nil and result.kind == tyGenericBody:
    result = result.last

proc shapeOf(s: PSym): seq[string] =
  ## The public shape lines for one type symbol, rendered from the compiler
  ## type AST (never from source text). Objects and ref/ptr-to-object yield
  ## their exported fields; enums their members; distincts their underlying
  ## type; everything else (proc types, tuples, aliases) falls back to a single
  ## ``typeToString`` line, suppressed when it would merely echo the type name.
  result = @[]
  let st = toBody(s.typ)
  if st == nil:
    return
  case st.kind
  of tyObject:
    emitRecord(st.n, 1, result)
  of tyEnum:
    emitEnum(st, result)
  of tyDistinct:
    result.add indentOf(1) & "distinct " & stripQualifiers(typeToString(st.last))
  of tyRef, tyPtr:
    # A ``ref Obj`` handle: surface the pointee's exported fields (none, for the
    # sealed handles whose state hides behind accessors).
    let inner = toBody(st.last)
    if inner != nil and inner.kind == tyObject:
      emitRecord(inner.n, 1, result)
  else:
    # Proc types, generic aliases, and tuples carry no record fields, so render
    # the type-definition RHS (the nkTypeDef body) to capture the proc
    # signature or alias target — information a consumer genuinely needs (e.g.
    # the Transport SendProc/CloseProc shapes a custom backend must satisfy).
    # Falls back to typeToString, suppressed when it would merely echo the name.
    if s.ast != nil and s.ast.kind == nkTypeDef and s.ast.safeLen > 2 and
        s.ast[2] != nil and s.ast[2].kind != nkEmpty:
      result.add indentOf(1) & stripQualifiers(rnd(s.ast[2]))
    else:
      let rendered = stripQualifiers(typeToString(s.typ))
      if rendered != s.name.s:
        result.add indentOf(1) & rendered

type Shape = object
  name: string
  module: string
  lines: seq[string]

proc collectShapes(graph: ModuleGraph, conf: ConfigRef, m: PSym): seq[Shape] =
  ## Every repo-owned exported ``skType`` reachable through the hub, with its
  ## rendered shape. nim-results types are out of scope here — their existence
  ## is already recorded in the ``--mode:api`` view. Sorted by ``(name,
  ## module)`` and de-duplicated (a re-exported type surfaces through several
  ## hubs) for a deterministic snapshot.
  result = @[]
  for s in allSyms(graph, m):
    if s == nil or s.kind != skType or sfExported notin s.flags:
      continue
    let mp = toFullPath(conf, s.info.fileIndex)
    if "/jmap-client/src/" notin mp:
      continue
    result.add Shape(name: s.name.s, module: moduleKey(mp), lines: shapeOf(s))
  result.sort(
    proc(a, b: Shape): int =
      result = cmp(a.name, b.name)
      if result == 0:
        result = cmp(a.module, b.module)
  )
  var unique: seq[Shape] = @[]
  for sh in result:
    if unique.len == 0 or unique[^1].name != sh.name or unique[^1].module != sh.module:
      unique.add sh
  result = unique

proc emitTypeShapes(shapes: seq[Shape]) =
  echo "# Public-type-shape surface — the public-field shape of every"
  echo "# repo-owned type reachable through `import jmap_client`, rendered"
  echo "# from the compiler's"
  echo "# post-sem type AST by scripts/api_oracle.nim. A faithful description"
  echo "# of public type shapes (private fields excluded); locked by"
  echo "# tests/lint/h17_type_shape_snapshot.nim so any drift is deliberate."
  echo "# Regenerate with: just freeze-type-shapes"
  var first = true
  for sh in shapes:
    if not first:
      echo ""
    first = false
    echo "## " & sh.name & " [" & sh.module & "]"
    for line in sh.lines:
      echo line

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
    emitTypeShapes(collectShapes(graph, conf, m))
  else:
    quit "api_oracle: unknown API_ORACLE_MODE: " & mode

main()
