# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# strip_comments.nims — produce comment-free copies of Nim source files.
#
# Usage:
#   nim e scripts/strip_comments.nims [--help|--test] <path>
#
# <path> is a single .nim file or a directory.  In directory mode the script
# walks recursively, processing every *.nim it finds, except those under
# scripts/output/ (the script's own output tree).  Outputs land in
# scripts/output/<input-path>, with leading '/' stripped from absolute
# inputs.
#
# Architecture:
#   Token     — a discriminated union of code / literal / comment events.
#   tokenize  — an iterator that lexes Nim source into a Token stream.
#   stripComments  — a five-line consumer that drops comment tokens.
#   dropBlankLines — collapses the whitespace-only lines left behind.
#
# Comment forms recognised: # … , ## … , #[ … ]# (nestable), ##[ … ]##
# (nestable).  String, raw string, triple-string, and char-literal contexts
# are tracked so '#' inside a literal is preserved.  A "'" directly after
# an alphanumeric/_ run is treated as a numeric suffix marker (e.g. the
# apostrophe in 100'i32), not a char-literal opener.
#
# CAVEAT: a proc/block whose entire body is a doc comment becomes an empty
# body after stripping and will not compile.  This tool is for reading and
# diffing, not for producing compilable output.

import std/[os, strutils, strformat, sugar, parseopt, editdistance]

const
  Usage = """usage: nim e scripts/strip_comments.nims [options] <path>

options:
  -h, --help    print this usage and exit
  --test        run inline test suite and exit"""
  OutputSubdir = "scripts/output"
  KnownOptions = ["help", "h", "test"]

# ============================================================================
# Pure core
# ============================================================================

{.push raises: [].}
{.push noSideEffect.}
{.experimental: "strictCaseObjects".}

const
  SymChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '\x80' .. '\xff'}
  SuffixHead = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}

# ---- Token: a discriminated event from the lexer ---------------------------

type
  TokenKind = enum
    tkCode
    tkStringLit
    tkRawStringLit
    tkTripleStringLit
    tkCharLit
    tkLineComment
    tkBlockComment

  Token = object
    case kind: TokenKind
    of tkCode:
      ch: char
    of tkStringLit, tkRawStringLit, tkTripleStringLit, tkCharLit:
      content: string
    of tkLineComment, tkBlockComment:
      discard

func code(ch: char): Token =
  Token(kind: tkCode, ch: ch)

func stringLit(s: string): Token =
  Token(kind: tkStringLit, content: s)

func rawStringLit(s: string): Token =
  Token(kind: tkRawStringLit, content: s)

func tripleStringLit(s: string): Token =
  Token(kind: tkTripleStringLit, content: s)

func charLit(s: string): Token =
  Token(kind: tkCharLit, content: s)

func lineComment(): Token =
  Token(kind: tkLineComment)

func blockComment(): Token =
  Token(kind: tkBlockComment)

static:
  doAssert TokenKind.high == tkBlockComment
  doAssert SymChars.card >= 62
  doAssert '_' in SuffixHead

# ---- Lexer: classifier + scanners + driver ---------------------------------

func peekAt(src: string, i, off: int): char =
  if i + off < src.len:
    src[i + off]
  else:
    '\0'

func classifyHash(src: string, i: int): TokenKind =
  if peekAt(src, i, 1) == '[' or (peekAt(src, i, 1) == '#' and peekAt(src, i, 2) == '['):
    tkBlockComment
  else:
    tkLineComment

func classifyQuote(src: string, i: int): TokenKind =
  if peekAt(src, i, 1) == '"' and peekAt(src, i, 2) == '"':
    tkTripleStringLit
  elif i > 0 and src[i - 1] in SymChars:
    tkRawStringLit
  else:
    tkStringLit

func classifyApostrophe(src: string, i: int): TokenKind =
  if i > 0 and src[i - 1] in SuffixHead: tkCode else: tkCharLit

func classifyAt(src: string, i: int): TokenKind =
  case src[i]
  of '#':
    classifyHash(src, i)
  of '"':
    classifyQuote(src, i)
  of '\'':
    classifyApostrophe(src, i)
  else:
    tkCode

func scanLineComment(src: string, i: var int) =
  inc i
  while i < src.len and src[i] != '\n':
    inc i

func scanBlockComment(src: string, i: var int) =
  ## Advances `i` past a balanced block comment.  When closing the outermost
  ## block via `]#`, also consumes a trailing `#` to match a `##[` opener.
  i += (if peekAt(src, i, 1) == '#': 3 else: 2)
  var depth = 1
  while i < src.len and depth > 0:
    if src[i] == '#' and peekAt(src, i, 1) == '[':
      inc depth
      i += 2
    elif src[i] == ']' and peekAt(src, i, 1) == '#':
      dec depth
      i += 2
      if depth == 0 and peekAt(src, i, 0) == '#':
        inc i
    else:
      inc i

func scanRegularString(src: string, i: var int): string =
  let start = i
  inc i
  while i < src.len:
    let c = src[i]
    if c == '\\' and i + 1 < src.len:
      i += 2
      continue
    if c == '"':
      inc i
      return src[start ..< i]
    inc i
  src[start ..< i]

func scanRawString(src: string, i: var int): string =
  let start = i
  inc i
  while i < src.len:
    if src[i] == '"' and peekAt(src, i, 1) == '"':
      i += 2
      continue
    if src[i] == '"':
      inc i
      return src[start ..< i]
    inc i
  src[start ..< i]

func scanTripleString(src: string, i: var int): string =
  let start = i
  i += 3
  while i < src.len:
    if src[i] == '"' and peekAt(src, i, 1) == '"' and peekAt(src, i, 2) == '"' and
        peekAt(src, i, 3) != '"':
      i += 3
      return src[start ..< i]
    inc i
  src[start ..< i]

func scanCharLiteral(src: string, i: var int): string =
  let start = i
  inc i
  while i < src.len:
    let c = src[i]
    if c == '\\' and i + 1 < src.len:
      i += 2
      continue
    if c == '\'':
      inc i
      return src[start ..< i]
    inc i
  src[start ..< i]

func nextToken(src: string, i: var int): Token =
  case classifyAt(src, i)
  of tkCode:
    result = code(src[i])
    inc i
  of tkLineComment:
    scanLineComment(src, i)
    result = lineComment()
  of tkBlockComment:
    scanBlockComment(src, i)
    result = blockComment()
  of tkStringLit:
    result = stringLit(scanRegularString(src, i))
  of tkRawStringLit:
    result = rawStringLit(scanRawString(src, i))
  of tkTripleStringLit:
    result = tripleStringLit(scanTripleString(src, i))
  of tkCharLit:
    result = charLit(scanCharLiteral(src, i))

iterator tokenize(src: string): Token =
  var i = 0
  while i < src.len:
    yield nextToken(src, i)

# ---- Five-line stripper: the consumer of the Token stream ------------------

func stripComments(src: string): string =
  result = newStringOfCap(src.len)
  for tok in tokenize(src):
    case tok.kind
    of tkCode:
      result.add(tok.ch)
    of tkStringLit, tkRawStringLit, tkTripleStringLit, tkCharLit:
      result.add(tok.content)
    of tkLineComment, tkBlockComment:
      discard

func dropBlankLines(s: string): string =
  let kept = collect:
    for line in s.splitLines():
      if line.strip().len > 0:
        line
  result = kept.join("\n")
  if result.len > 0 and not result.endsWith("\n"):
    result.add('\n')

func isOutputTree(p: string): bool =
  let n = p.normalizedPath
  n == OutputSubdir or n.endsWith("/" & OutputSubdir)

func outPathFor(inputPath: string): string =
  let rel =
    if inputPath.isAbsolute:
      inputPath[1 .. ^1]
    else:
      inputPath
  OutputSubdir / rel

func suggestOption(typo: string): string =
  ## Returns the nearest known option (≤2 edits away), or "" if none.
  var best = ""
  var bestDist = high(int)
  for opt in KnownOptions:
    let d = editDistance(typo, opt)
    if d < bestDist:
      bestDist = d
      best = opt
  if bestDist <= 2: best else: ""

# ---- Action: type-distinct CLI modes ---------------------------------------

type
  ActionKind = enum
    akStrip
    akTest

  Action = object
    case kind: ActionKind
    of akStrip:
      path: string
    of akTest:
      discard

{.pop.}
{.pop.}

# ============================================================================
# Impure shell
# ============================================================================

template check(actual, expected: untyped): untyped =
  let (a, e) = (actual, expected)
  if a != e:
    let info = instantiationInfo()
    quit(
      "check failed at " & info.filename & ":" & $info.line & ": got " & a.repr &
        " expected " & e.repr,
      1,
    )

proc runTests() =
  block stripping:
    check stripComments("a # b\n"), "a \n"
    check stripComments("a #[ b ]# c\n"), "a  c\n"

  block docBlockCloserBugFix:
    check stripComments("a ##[ doc ]## b\n"), "a  b\n"
    check stripComments("a ##[ x ##[ y ]## z ]## b\n"), "a  b\n"

  block literalsArePreserved:
    check stripComments("\"# in str\"\n"), "\"# in str\"\n"
    check stripComments("'#'\n"), "'#'\n"
    check stripComments("100'i32\n"), "100'i32\n"
    check stripComments("r\"# raw\"\n"), "r\"# raw\"\n"
    check stripComments("\"\"\"# trip\"\"\"\n"), "\"\"\"# trip\"\"\"\n"

  block blankLines:
    check dropBlankLines("a\n\nb\n"), "a\nb\n"
    check dropBlankLines("\n\n"), ""

  block paths:
    check outPathFor("src/foo.nim"), "scripts/output/src/foo.nim"
    check outPathFor("/abs/foo.nim"), "scripts/output/abs/foo.nim"

  block outputTree:
    check isOutputTree("scripts/output"), true
    check isOutputTree("foo/scripts/output"), true
    check isOutputTree("myscripts/output"), false
    check isOutputTree("scripts/output_other"), false

  block typoSuggestion:
    check suggestOption("hlep"), "help"
    check suggestOption("teest"), "test"
    check suggestOption("xyzzy"), ""

  echo "ok"

proc handleOption(key: string, testMode: var bool) =
  if key in ["h", "help"]:
    echo Usage
    quit(0)
  elif key == "test":
    testMode = true
  else:
    let s = suggestOption(key)
    let hint =
      if s.len > 0:
        &" (did you mean --{s}?)"
      else:
        ""
    quit(&"strip_comments: unknown option --{key}{hint}", 2)

proc parseArgs(): Action =
  ## parseopt's NimScript handling skips the .nims token automatically.
  var positional: seq[string] = @[]
  var testMode = false
  for kind, key, _ in getopt():
    case kind
    of cmdArgument:
      positional.add(key)
    of cmdShortOption, cmdLongOption:
      handleOption(key, testMode)
    of cmdEnd:
      discard
  if testMode:
    return Action(kind: akTest)
  if positional.len != 1:
    quit(Usage, 1)
  Action(kind: akStrip, path: positional[0])

iterator nimFilesUnder(dir: string): string =
  ## Yields every *.nim path under `dir`, pruning the script's own output
  ## tree to avoid feedback loops on subsequent runs.
  if not dir.isOutputTree:
    var stack = @[dir]
    while stack.len > 0:
      let d = stack.pop()
      for kind, path in walkDir(d):
        case kind
        of pcFile, pcLinkToFile:
          if path.endsWith(".nim"):
            yield path
        of pcDir, pcLinkToDir:
          if not path.isOutputTree:
            stack.add(path)

proc expandInputs(path: string): seq[string] =
  if fileExists(path) and path.endsWith(".nim"):
    @[path]
  elif dirExists(path):
    collect:
      for f in nimFilesUnder(path):
        f
  else:
    quit(&"strip_comments: path not found or not a .nim file: {path}", 1)

proc processOne(inputPath: string) =
  let outPath = outPathFor(inputPath)
  let outDir = outPath.parentDir
  if outDir.len > 0:
    mkDir(outDir)
  writeFile(outPath, dropBlankLines(stripComments(readFile(inputPath))))
  echo &"stripped: {outPath}"

# ============================================================================
# Entry
# ============================================================================

let action = parseArgs()
case action.kind
of akStrip:
  for path in expandInputs(action.path):
    processOne(path)
of akTest:
  runTests()
