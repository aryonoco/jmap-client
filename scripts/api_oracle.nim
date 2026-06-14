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
## tool. Built with ``nim c -d:nimcore --path:"$nim"`` (the same mechanism
## nimalyzer / ``just analyse`` already relies on).

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
    if s == nil or sfExported notin s.flags:
      continue
    let modPath = toFullPath(conf, s.info.fileIndex)
    rows.add($s.kind & "\t" & s.name.s & "\t" & modPath)
  rows.sort()
  rows = deduplicate(rows)
  stderr.writeLine "api_oracle: errorCounter=" & $conf.errorCounter &
    " exported=" & $rows.len
  for r in rows:
    echo r

main()
