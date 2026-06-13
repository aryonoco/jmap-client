# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
##
## Usage: ``nim e scripts/strip_comments.nims [--help|--test] <path>``
##
##
## **CAVEAT** — a proc/block whose entire body is a doc comment becomes an
## empty body after stripping and will not compile. This tool is for
## reading and diffing, not for producing compilable output.

import
  std/[
    os, strutils, strformat, sugar, sequtils, options, parseopt, editdistance,
    macros,
  ]

const
  Usage =
    """usage: nim e scripts/strip_comments.nims [options] <path>

options:
  -h, --help    print this usage and exit
  --test        run inline test suite and exit"""
  OutputSubdir = "scripts/output"

{.push staticBoundChecks: on.}
{.push warning[ProveField]: on.}
{.push warningAsError[ProveField]: on.}
{.push warning[ProveIndex]: on.}
{.push warningAsError[ProveIndex]: on.}
{.push hintAsError[Name]: on.}
{.push raises: [].}
{.push noSideEffect.}
{.experimental: "strictCaseObjects".}
{.experimental: "strictDefs".}
{.experimental: "strictFuncs".}
{.experimental: "strictNotNil".}

type
  InputPath = distinct string
  OutputPath = distinct string

func `$`(p: InputPath): string {.borrow.}

func `$`(p: OutputPath): string {.borrow.}

func `==`(a, b: InputPath): bool {.borrow.}

func `==`(a, b: OutputPath): bool {.borrow.}

type CliOption = enum
  coHelp
  coTest

func name(opt: CliOption): string =
  case opt
  of coHelp: "help"
  of coTest: "test"

func parseCliOption(s: string): Option[CliOption] =
  case s
  of "h", "help": some(coHelp)
  of "test": some(coTest)
  else: none(CliOption)

type
  ActionKind = enum
    akStrip
    akTest
    akUsage
    akError

  Action = object
    case kind*: ActionKind
    of akStrip:
      path*: InputPath
    of akError:
      msg*: string
      exitCode*: int
    of akTest, akUsage:
      discard

const
  SymChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '\x80' .. '\xff'}
  SuffixHead = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}

type
  TokenKind = enum
    tkCode
    tkStringLit
    tkRawStringLit
    tkTripleStringLit
    tkCharLit
    tkLineComment
    tkBlockComment

  LiteralKind = range[tkStringLit .. tkCharLit]

  Token = object
    case kind*: TokenKind
    of tkCode:
      ch*: char
    of tkStringLit, tkRawStringLit, tkTripleStringLit, tkCharLit:
      content*: string
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

func isOutputTree(p: InputPath): bool =
  let n = p.string.normalizedPath
  n == OutputSubdir or n.endsWith("/" & OutputSubdir)

func outPathFor(input: InputPath): OutputPath =
  let s = input.string
  let rel =
    if s.isAbsolute:
      s[1 .. ^1]
    else:
      s
  OutputPath(OutputSubdir / rel)

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
  return src[start ..< i]

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
  return src[start ..< i]

func scanTripleString(src: string, i: var int): string =
  let start = i
  i += 3
  while i < src.len:
    if src[i] == '"' and peekAt(src, i, 1) == '"' and peekAt(src, i, 2) == '"' and
        peekAt(src, i, 3) != '"':
      i += 3
      return src[start ..< i]
    inc i
  return src[start ..< i]

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
  return src[start ..< i]

func scanLiteral(src: string, i: var int, kind: LiteralKind): Token =
  case kind
  of tkStringLit: stringLit(scanRegularString(src, i))
  of tkRawStringLit: rawStringLit(scanRawString(src, i))
  of tkTripleStringLit: tripleStringLit(scanTripleString(src, i))
  of tkCharLit: charLit(scanCharLiteral(src, i))

func nextToken(src: string, i: var int): Token =
  let kind = classifyAt(src, i)
  case kind
  of tkCode:
    result = code(src[i])
    inc i
  of tkLineComment:
    scanLineComment(src, i)
    result = lineComment()
  of tkBlockComment:
    scanBlockComment(src, i)
    result = blockComment()
  of tkStringLit, tkRawStringLit, tkTripleStringLit, tkCharLit:
    result = scanLiteral(src, i, LiteralKind(kind))

iterator tokenize(src: string): Token =
  var i = 0
  while i < src.len:
    yield nextToken(src, i)

func stripComments(src: string): string =
  result = newStringOfCap(Natural(src.len))
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

func suggestOption(typo: string): Option[string] =
  type Candidate = tuple[name: string, dist: int]
  let candidates = collect:
    for opt in CliOption:
      let n = name(opt)
      (name: n, dist: editDistance(typo, n))
  let best = candidates.foldl(if b.dist < a.dist: b else: a)
  if best.dist <= 2: some(best.name) else: none(string)

func reduceArgs(
    opts: seq[CliOption], positional: seq[string], unknown: Option[string]
): Action =
  if unknown.isSome:
    let u = unknown.get
    let s = suggestOption(u)
    let hint =
      if s.isSome:
        &" (did you mean --{s.get}?)"
      else:
        ""
    return Action(
      kind: akError,
      msg: &"strip_comments: unknown option --{u}{hint}",
      exitCode: 2,
    )
  if coHelp in opts:
    return Action(kind: akUsage)
  if coTest in opts:
    return Action(kind: akTest)
  if positional.len != 1:
    return Action(kind: akError, msg: Usage, exitCode: 1)
  Action(kind: akStrip, path: InputPath(positional[0]))

static:
  doAssert TokenKind.high == tkBlockComment
  doAssert SymChars.card >= 62
  doAssert '_' in SuffixHead
  doAssert CliOption.low.ord <= CliOption.high.ord
  for opt in CliOption:
    doAssert parseCliOption(name(opt)).get == opt
  doAssert InputPath("a") != InputPath("b")

{.pop.}
{.pop.}

template check(actual, expected: untyped) =
  let got = actual
  let want = expected
  doAssert got == want, "got " & got.repr & " expected " & want.repr

template test(name, body: untyped) =
  block:
    try:
      body
    except AssertionDefect as ex:
      quit("FAIL: " & astToStr(name) & " — " & ex.msg, 1)

proc runTests() =
  test stripping:
    check stripComments("a # b\n"), "a \n"
    check stripComments("a #[ b ]# c\n"), "a  c\n"

  test docBlockCloserBugFix:
    check stripComments("a ##[ doc ]## b\n"), "a  b\n"
    check stripComments("a ##[ x ##[ y ]## z ]## b\n"), "a  b\n"

  test literalsArePreserved:
    check stripComments("\"# in str\"\n"), "\"# in str\"\n"
    check stripComments("'#'\n"), "'#'\n"
    check stripComments("100'i32\n"), "100'i32\n"
    check stripComments("r\"# raw\"\n"), "r\"# raw\"\n"
    check stripComments("\"\"\"# trip\"\"\"\n"), "\"\"\"# trip\"\"\"\n"

  test blankLines:
    check dropBlankLines("a\n\nb\n"), "a\nb\n"
    check dropBlankLines("\n\n"), ""

  test paths:
    check outPathFor(InputPath("src/foo.nim")).string, "scripts/output/src/foo.nim"
    check outPathFor(InputPath("/abs/foo.nim")).string, "scripts/output/abs/foo.nim"

  test outputTree:
    check isOutputTree(InputPath("scripts/output")), true
    check isOutputTree(InputPath("foo/scripts/output")), true
    check isOutputTree(InputPath("myscripts/output")), false
    check isOutputTree(InputPath("scripts/output_other")), false

  test typoSuggestion:
    check suggestOption("hlep"), some("help")
    check suggestOption("teest"), some("test")
    check suggestOption("xyzzy"), none(string)

  test reducerDispatch:
    check reduceArgs(@[coHelp], @[], none(string)).kind, akUsage
    check reduceArgs(@[coTest], @[], none(string)).kind, akTest
    check reduceArgs(@[], @["x.nim"], none(string)).kind, akStrip
    check reduceArgs(@[], @[], some("hlep")).kind, akError

  echo "ok"

proc parseArgs(): tuple[
    opts: seq[CliOption], positional: seq[string], unknown: Option[string]
] =
  result.opts = @[]
  result.positional = @[]
  result.unknown = none(string)
  for kind, key, _ in getopt():
    case kind
    of cmdArgument:
      result.positional.add(key)
    of cmdShortOption, cmdLongOption:
      let parsed = parseCliOption(key)
      if parsed.isSome:
        result.opts.add(parsed.get)
      elif result.unknown.isNone:
        result.unknown = some(key)
    of cmdEnd:
      discard

iterator nimFilesUnder(dir: InputPath): InputPath =
  if not dir.isOutputTree:
    var stack = @[dir]
    while stack.len > 0:
      for kind, path in walkDir(stack.pop().string):
        case kind
        of pcFile, pcLinkToFile:
          if path.endsWith(".nim"):
            yield InputPath(path)
        of pcDir, pcLinkToDir:
          let child = InputPath(path)
          if not child.isOutputTree:
            stack.add(child)

proc expandInputs(input: InputPath): seq[InputPath] =
  let s = input.string
  if fileExists(s) and s.endsWith(".nim"):
    @[input]
  elif dirExists(s):
    collect:
      for f in nimFilesUnder(input):
        f
  else:
    quit(&"strip_comments: path not found or not a .nim file: {s}", 1)

proc processOne(input: InputPath) =
  let output = outPathFor(input)
  let outDir = output.string.parentDir
  if outDir.len > 0:
    mkDir(outDir)
  writeFile(output.string, dropBlankLines(stripComments(readFile(input.string))))
  echo &"stripped: {output.string}"

# Entry

let parsed = parseArgs()
let action = reduceArgs(parsed.opts, parsed.positional, parsed.unknown)
case action.kind
of akUsage:
  echo Usage
of akError:
  quit(action.msg, action.exitCode)
of akTest:
  runTests()
of akStrip:
  for path in expandInputs(action.path):
    processOne(path)
