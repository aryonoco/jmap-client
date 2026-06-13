# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Public-API surface resolver (shared by ``freeze_public_api.nim`` and the
## H16 ``public-api.txt`` snapshot lint). Resolves the ``export`` /
## ``export … except …`` graph from the two public entry points
## (``src/jmap_client.nim`` and ``src/jmap_client/convenience.nim``) and scrapes
## every reachable module's ``*``-exported declarations, minus the symbols its
## parents filter out with ``except``.
##
## Text-based (not ``nim jsondoc``): jsondoc of the hub yields zero entries (it
## does not follow re-exports), jsondoc ``--project`` over-captures and is
## fragile, and the compiler AST is unavailable — so the only faithful
## enumeration is to resolve the export graph from source. Text-scraping is also
## toolchain-stable (no inferred-pragma churn).
##
## Lives under ``scripts/`` (exempt from the ``src/`` L1–L3 pragmas). Both the
## generator and the lint import it, so the two cannot drift.

{.push raises: [].}

import std/[os, strutils, sets, tables, algorithm]

const
  SrcRoot* = currentSourcePath().parentDir.parentDir / "src"
    ## Absolute ``<repo>/src`` (``scripts/api_surface.nim`` → repo → src), so the
    ## resolver works regardless of the caller's working directory.
  EntryPoints* = ["jmap_client.nim", "jmap_client/convenience.nim"]
    ## Relative to ``SrcRoot`` — the two public module paths (A10).
  DeclKinds = ["type ", "func ", "proc ", "template ", "iterator ", "const ", "macro "]
  # ``export results`` / ``export <std>`` re-export an external dependency
  # (pinned separately, D4); they are not part of the library's own contract,
  # so the resolver records them as edges to skip rather than scraping their
  # symbols.
  ExternalExports = ["results"]

type Decl* = object ## A single ``*``-exported declaration.
  kind*: string ## ``type`` / ``func`` / ``proc`` / ``template`` / …
  name*: string ## the exported identifier
  signature*: string ## the declared signature up to ``=`` / pragma (normalised)
  module*: string ## owning module path, e.g. ``jmap_client/internal/types/session``

func moduleKey(srcRelPath: string): string =
  ## ``jmap_client/internal/types/session.nim`` → ``jmap_client/internal/types/session``.
  srcRelPath.changeFileExt("")

func stripComment(line: string): string =
  ## Drops a trailing ``##`` / ``#`` doc/line comment for delimiter counting.
  ## Naive (ignores ``#`` inside string literals), which is acceptable for the
  ## declaration headers this resolver scans — none carry a ``#`` in a string
  ## default.
  let h = line.find('#')
  if h < 0:
    line
  else:
    line[0 ..< h]

func delimDepth(s: string): int =
  ## Net ``()[]{}`` nesting of ``s`` (ignoring chars inside ``"…"`` / ``'…'``).
  var depth = 0
  var inStr = false
  var inChar = false
  var i = 0
  while i < s.len:
    let c = s[i]
    if inStr:
      if c == '\\':
        inc i
      elif c == '"':
        inStr = false
    elif inChar:
      if c == '\\':
        inc i
      elif c == '\'':
        inChar = false
    else:
      case c
      of '"':
        inStr = true
      of '\'':
        inChar = true
      of '(', '[', '{':
        inc depth
      of ')', ']', '}':
        dec depth
      else:
        discard
    inc i
  depth

func logicalLines(raw: string): seq[string] =
  ## Joins physical-line continuations so a multi-line declaration header,
  ## ``export X except a,\n b`` clause, or ``import …`` reads as one logical
  ## line. A line continues while the accumulated text has unbalanced
  ## ``()[]{}`` delimiters, ends in ``,``, or ends in the bare keyword
  ## ``except``.
  result = @[]
  var acc = ""
  for physical in raw.splitLines():
    let t = physical.strip(leading = false, trailing = true)
    let body = t.strip()
    if acc.len == 0:
      acc = t
    else:
      acc = acc & " " & body
    if body.endsWith(",") or body == "except" or body.endsWith(" except") or
        delimDepth(stripComment(acc)) > 0:
      continue
    result.add(acc)
    acc = ""
  if acc.len > 0:
    result.add(acc)

func nameEnd(s: string, start: int): int =
  var i = start
  while i < s.len and s[i] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}:
    inc i
  i

func findBodyEq(s: string): int =
  ## Index of the space before the declaration's body ``=`` — the ``=`` at
  ## delimiter-depth 0, not a default-argument ``=`` inside the param parens
  ## (``timeout: int = 30000``). Returns -1 when there is no body ``=`` (a
  ## forward declaration or a field-less type header on one line).
  var depth = 0
  var inStr = false
  var inChar = false
  var i = 0
  while i < s.len:
    let c = s[i]
    if inStr:
      if c == '\\':
        inc i
      elif c == '"':
        inStr = false
    elif inChar:
      if c == '\\':
        inc i
      elif c == '\'':
        inChar = false
    else:
      case c
      of '"':
        inStr = true
      of '\'':
        inChar = true
      of '(', '[', '{':
        inc depth
      of ')', ']', '}':
        dec depth
      of '=':
        if depth == 0 and i > 0 and s[i - 1] == ' ':
          return i - 1
      else:
        discard
    inc i
  -1

func extractDecl(line: string, module: string): Decl =
  ## Parses an exported declaration line into a ``Decl`` (empty ``name`` when the
  ## line is not a ``*``-exported declaration). Recognises ``kind name*…`` with
  ## leading whitespace tolerated; captures the signature up to ``=`` or the
  ## trailing pragma.
  result = Decl(module: module)
  let s = line.strip(leading = true, trailing = false)
  for kind in DeclKinds:
    if not s.startsWith(kind):
      continue
    let rest = s[kind.len ..^ 1]
    if rest.len == 0 or rest[0] notin {'A' .. 'Z', 'a' .. 'z', '_'}:
      return
    let i = nameEnd(rest, 0)
    # Backtick-quoted operator names (``func `==`*``) are not covered — none of
    # the public surface exports an operator that is not also covered by a named
    # decl on the same type; the snapshot intentionally tracks named symbols.
    if i >= rest.len or rest[i] != '*':
      return
    let name = rest[0 ..< i]
    var sigEnd = rest.len
    let eq = findBodyEq(rest)
    if eq >= 0:
      sigEnd = eq
    var sig = rest[i + 1 ..< sigEnd].strip()
    # Collapse internal whitespace runs and tidy the join artifacts left by
    # multi-line headers, for a stable, readable normal form.
    sig = sig.splitWhitespace().join(" ")
    for (a, b) in [("( ", "("), (" )", ")"), ("[ ", "["), (" ]", "]"), (" ,", ",")]:
      sig = sig.replace(a, b)
    return Decl(kind: kind.strip(), name: name, signature: sig, module: module)

proc parseImports(srcLines: seq[string], dir: string): Table[string, string] =
  ## Maps a module's local import idents to source-relative module keys, e.g.
  ## ``import ./session`` → {"session": "<dir>/session"} and
  ## ``import jmap_client/internal/types`` → {"types": "jmap_client/internal/types"}.
  result = initTable[string, string]()
  for line in srcLines:
    let s = line.strip()
    if not s.startsWith("import "):
      continue
    # Single-module imports only (the hubs use one ``import`` per module).
    let spec = s["import ".len ..^ 1].strip()
    if spec.len == 0 or ',' in spec:
      continue
    let path =
      if spec.startsWith("./") or spec.startsWith("../"):
        # Relative to the importing module's directory.
        normalizedPath(dir / spec).replace('\\', '/')
      elif spec.startsWith("jmap_client"):
        spec
      else:
        continue # std/<x> or external — not part of the export graph
    result[spec.splitPath().tail] = path

iterator exportClauses(
    srcLines: seq[string]
): tuple[ident: string, excepts: seq[string]] =
  ## Yields each ``export <ident> [except a, b, …]`` clause (idents only;
  ## ``export a, b`` multi-ident forms are not used by the hubs).
  for line in srcLines:
    let s = line.strip()
    if not s.startsWith("export "):
      continue
    let rest = s["export ".len ..^ 1].strip()
    if rest.len == 0:
      continue
    let exceptIdx = rest.find(" except ")
    let identPart = (if exceptIdx >= 0: rest[0 ..< exceptIdx] else: rest).strip()
    if ',' in identPart or identPart.len == 0:
      continue # not a single-module re-export
    var excepts: seq[string] = @[]
    if exceptIdx >= 0:
      for raw in rest[exceptIdx + " except ".len ..^ 1].split(','):
        let e = raw.strip()
        if e.len > 0:
          excepts.add(e)
    yield (identPart, excepts)

proc reachableSurface*(): seq[Decl] =
  ## Resolves the export graph and returns every public ``Decl`` reachable
  ## through the two entry points, with parent ``except`` filters applied.
  ## Sorted by (module, name) for a deterministic snapshot.
  var
    visited = initHashSet[string]() # module keys already scraped
    # filtered[moduleKey] = names its parents excluded from re-export
    filtered = initTable[string, HashSet[string]]()
    queue: seq[string] = @[]
    decls: seq[Decl] = @[]
  for ep in EntryPoints:
    queue.add(moduleKey(ep))
    filtered[moduleKey(ep)] = initHashSet[string]()
  while queue.len > 0:
    let modKey = queue.pop()
    if modKey in visited:
      continue
    visited.incl(modKey)
    let srcPath = SrcRoot / (modKey & ".nim")
    if not fileExists(srcPath):
      continue
    var raw = ""
    try:
      raw = readFile(srcPath)
    except IOError, OSError:
      continue
    let lines = logicalLines(raw)
    let imports = parseImports(lines, modKey.splitPath().head)
    let myFilter = filtered.getOrDefault(modKey, initHashSet[string]())
    # Re-export edges.
    for clause in exportClauses(lines):
      if clause.ident in ExternalExports:
        continue
      let childKey = imports.getOrDefault(clause.ident, "")
      if childKey.len == 0:
        continue # std/<x> or unresolved — skip
      var childFilter = filtered.getOrDefault(childKey, initHashSet[string]())
      for e in clause.excepts:
        childFilter.incl(e)
      filtered[childKey] = childFilter
      queue.add(childKey)
    # Own declarations (a hub may both re-export and declare its own symbols).
    for line in lines:
      let d = extractDecl(line, modKey)
      if d.name.len == 0:
        continue
      if d.name in myFilter:
        continue
      decls.add(d)
  decls.sort(
    proc(a, b: Decl): int =
      result = cmp(a.module, b.module)
      if result == 0:
        result = cmp(a.name, b.name)
      if result == 0:
        result = cmp(a.signature, b.signature)
  )
  decls

proc snapshotLines*(): seq[string] =
  ## The header-free snapshot body — a ``## <module>`` section header per
  ## reachable module, then one ``<kind> <name> <signature>`` line per public
  ## declaration. Shared by ``freeze_public_api.nim`` and the H16 lint so their
  ## formats cannot drift.
  result = @[]
  var lastModule = ""
  for d in reachableSurface():
    if d.module != lastModule:
      if result.len > 0:
        result.add("")
      result.add("## " & d.module)
      lastModule = d.module
    if d.signature.len > 0:
      result.add(d.kind & " " & d.name & " " & d.signature)
    else:
      result.add(d.kind & " " & d.name)

# =============================================================================
# Type-shape capture (A25)
# =============================================================================

func leadingSpaces(s: string): int =
  var i = 0
  while i < s.len and s[i] == ' ':
    inc i
  i

func isPublicTypeHeader(line: string, name: string): bool =
  ## True if ``line`` declares ``type <name>*`` (standalone) or ``<name>*``
  ## (inside a ``type`` block).
  let s = line.strip()
  let withKw = "type " & name & "*"
  let bareForm = name & "*"
  (
    s.startsWith(withKw) and
    (s.len == withKw.len or s[withKw.len] in {' ', '*', '{', '['})
  ) or (
    s.startsWith(bareForm) and
    (s.len == bareForm.len or s[bareForm.len] in {' ', ':', '{', '['})
  )

proc typeShapeBody(physical: seq[string], name: string, isEnum: var bool): seq[string] =
  ## Public-field shape lines for the type ``name``: every more-indented body
  ## line that declares a public member (``ident*: …`` / a ``case``
  ## discriminator) or an enum member, with comments and private fields
  ## dropped. ``isEnum`` is set when the header declares ``= enum``.
  result = @[]
  isEnum = false
  var headerIndent = -1
  var capturing = false
  for raw in physical:
    let line = stripComment(raw).strip(leading = false, trailing = true)
    if not capturing:
      if isPublicTypeHeader(line, name):
        headerIndent = leadingSpaces(line)
        capturing = true
        isEnum = " enum" in line or line.strip().endsWith("enum")
      continue
    if line.strip().len == 0:
      continue # blank inside the body — tolerate
    let indent = leadingSpaces(line)
    if indent <= headerIndent:
      break # dedented to the next declaration — body ends
    let body = line.strip()
    # Keep relative indentation so nested case arms read structurally.
    let kept = line[headerIndent .. ^1]
    if isEnum:
      # Enum member: a leading identifier (optionally ``= "wire"`` backing).
      let idEnd = nameEnd(body, 0)
      if idEnd > 0:
        result.add(kept)
    else:
      # Object/case: keep public members and the case scaffolding.
      if "*" in body or body.startsWith("case ") or body.startsWith("of ") or
          body == "else:" or body.startsWith("else:"):
        result.add(kept)

proc typeShapeLines*(): seq[string] =
  ## The header-free type-shape snapshot body — one ``## <Type> [<module>]``
  ## section per public type, then its public-field / enum-member lines.
  ## Captures the public field signature of every public type reachable through
  ## the hub (A25); private ``raw*`` fields are excluded, so internal field
  ## renames do not churn the snapshot. Types alphabetical by name.
  result = @[]
  var typeDecls: seq[Decl] = @[]
  for d in reachableSurface():
    if d.kind == "type":
      typeDecls.add(d)
  typeDecls.sort(
    proc(a, b: Decl): int =
      result = cmp(a.name, b.name)
      if result == 0:
        result = cmp(a.module, b.module)
  )
  var fileCache = initTable[string, seq[string]]()
  for d in typeDecls:
    let srcPath = SrcRoot / (d.module & ".nim")
    if d.module notin fileCache:
      var raw = ""
      try:
        raw = readFile(srcPath)
      except IOError, OSError:
        raw = ""
      fileCache[d.module] = raw.splitLines()
    var isEnum = false
    let body = typeShapeBody(fileCache.getOrDefault(d.module, @[]), d.name, isEnum)
    if result.len > 0:
      result.add("")
    result.add("## " & d.name & " [" & d.module & "]")
    for b in body:
      result.add(b)
