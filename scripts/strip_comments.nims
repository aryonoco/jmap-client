# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tokenised Nim comment stripper used by the comment-base and comment-nim
## skills. Walks a .nim file or directory tree and writes comment-free
## copies under ``scripts/output/<input-path>``, with leading ``/`` stripped
## from absolute inputs.
##
## Usage: ``nim e scripts/strip_comments.nims [--help|--test] <path>``
##
## Architecture:
##   - ``InputPath`` / ``OutputPath`` — distinct strings; mistakes are compile errors.
##   - ``CliOption`` / ``Action``     — typed CLI dispatch; ``reduceArgs`` is the pure reducer.
##   - ``Token`` / ``TokenKind``      — discriminated union of code / literal / comment.
##   - ``tokenize``                   — iterator lexing Nim source into a Token stream.
##   - ``stripComments``              — five-line consumer that drops comment tokens.
##   - ``dropBlankLines``             — collapses whitespace-only lines.
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

# Pure core: types, lexer, reducers — no IO.

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
  ## String form of an ``InputPath``.

func `$`(p: OutputPath): string {.borrow.}
  ## String form of an ``OutputPath``.

func `==`(a, b: InputPath): bool {.borrow.}
  ## Equality delegated to the underlying string.

func `==`(a, b: OutputPath): bool {.borrow.}
  ## Equality delegated to the underlying string.

type CliOption = enum
  coHelp
  coTest

func name(opt: CliOption): string =
  ## User-facing option name; the form printed in ``--help`` and by the
  ## typo suggester. Round-trip partner of ``parseCliOption``.
  case opt
  of coHelp: "help"
  of coTest: "test"

func parseCliOption(s: string): Option[CliOption] =
  ## Maps a flag string back to its ``CliOption``; ``none`` for unknowns.
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

# Token: a discriminated event from the lexer.

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
  ## Wraps a single source character as a ``tkCode`` token.
  Token(kind: tkCode, ch: ch)

func stringLit(s: string): Token =
  ## Wraps a regular ``"..."`` literal as a ``tkStringLit`` token.
  Token(kind: tkStringLit, content: s)

func rawStringLit(s: string): Token =
  ## Wraps a raw ``r"..."`` literal as a ``tkRawStringLit`` token.
  Token(kind: tkRawStringLit, content: s)

func tripleStringLit(s: string): Token =
  ## Wraps a ``""" ... """`` literal as a ``tkTripleStringLit`` token.
  Token(kind: tkTripleStringLit, content: s)

func charLit(s: string): Token =
  ## Wraps a ``'...'`` literal as a ``tkCharLit`` token.
  Token(kind: tkCharLit, content: s)

func lineComment(): Token =
  ## Marker for a line-comment span (content discarded by ``stripComments``).
  Token(kind: tkLineComment)

func blockComment(): Token =
  ## Marker for a block-comment span (content discarded by ``stripComments``).
  Token(kind: tkBlockComment)

# Path helpers — input and output never mix.

func isOutputTree(p: InputPath): bool =
  ## True when ``p`` points at the script's own output subdirectory; the
  ## walker uses this to avoid feedback loops on subsequent runs.
  let n = p.string.normalizedPath
  n == OutputSubdir or n.endsWith("/" & OutputSubdir)

func outPathFor(input: InputPath): OutputPath =
  ## Maps an input path to its destination under ``scripts/output/``.
  let s = input.string
  let rel =
    if s.isAbsolute:
      s[1 .. ^1]
    else:
      s
  OutputPath(OutputSubdir / rel)

# Lexer state machine: classify → scan → emit.

func peekAt(src: string, i, off: int): char =
  ## Returns ``src[i + off]`` or ``'\0'`` past the end (bounds-safe peek).
  if i + off < src.len:
    src[i + off]
  else:
    '\0'

func classifyHash(src: string, i: int): TokenKind =
  ## Disambiguates ``#`` (line comment) from ``#[`` / ``##[`` (block comment).
  if peekAt(src, i, 1) == '[' or (peekAt(src, i, 1) == '#' and peekAt(src, i, 2) == '['):
    tkBlockComment
  else:
    tkLineComment

func classifyQuote(src: string, i: int): TokenKind =
  ## Picks between triple-, raw-, and regular-string lexer states for ``"``.
  if peekAt(src, i, 1) == '"' and peekAt(src, i, 2) == '"':
    tkTripleStringLit
  elif i > 0 and src[i - 1] in SymChars:
    tkRawStringLit
  else:
    tkStringLit

func classifyApostrophe(src: string, i: int): TokenKind =
  ## Distinguishes a char literal from a numeric suffix marker (e.g.
  ## the apostrophe in ``100'i32``).
  if i > 0 and src[i - 1] in SuffixHead: tkCode else: tkCharLit

func classifyAt(src: string, i: int): TokenKind =
  ## Top-level classifier: inspects ``src[i]`` and returns the next token's
  ## kind without consuming any input.
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
  ## Advances ``i`` to the end of the current line (the newline itself is
  ## left for the next iteration as a code character).
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
  ## Consumes a ``"..."`` literal honouring ``\`` escapes; returns the
  ## matched span (quotes included).
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
  ## Consumes a raw string literal where a doubled ``""`` is a literal
  ## quote and ``\`` is not an escape.
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
  ## Consumes a ``""" ... """`` literal; the closer is the first run of
  ## exactly three quotes not followed by a fourth.
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
  ## Consumes a ``'...'`` literal honouring ``\`` escapes; returns the
  ## matched span (apostrophes included).
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
  ## Dispatches to the per-kind scanner and wraps the result in a Token.
  case kind
  of tkStringLit: stringLit(scanRegularString(src, i))
  of tkRawStringLit: rawStringLit(scanRawString(src, i))
  of tkTripleStringLit: tripleStringLit(scanTripleString(src, i))
  of tkCharLit: charLit(scanCharLiteral(src, i))

func nextToken(src: string, i: var int): Token =
  ## Lexer driver: classifies the position at ``i`` and emits one Token.
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
  ## Yields every Token in ``src``; the yielded events exactly cover the
  ## input with no gaps or overlaps.
  var i = 0
  while i < src.len:
    yield nextToken(src, i)

# Token-stream consumer: drops comment tokens.

func stripComments(src: string): string =
  ## Re-emits ``src`` with every comment token discarded; code and literal
  ## content pass through untouched.
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
  ## Removes whitespace-only lines, leaving a single trailing newline if
  ## any content remains.
  let kept = collect:
    for line in s.splitLines():
      if line.strip().len > 0:
        line
  result = kept.join("\n")
  if result.len > 0 and not result.endsWith("\n"):
    result.add('\n')

# Min-fold over enum variants picks the nearest known option.

func suggestOption(typo: string): Option[string] =
  ## Returns the nearest known option (within edit distance 2 of ``typo``)
  ## or ``none`` if every candidate is too far away.
  type Candidate = tuple[name: string, dist: int]
  let candidates = collect:
    for opt in CliOption:
      let n = name(opt)
      (name: n, dist: editDistance(typo, n))
  let best = candidates.foldl(if b.dist < a.dist: b else: a)
  if best.dist <= 2: some(best.name) else: none(string)

# Pure reducer: (opts, positional, unknown) → Action.

func reduceArgs(
    opts: seq[CliOption], positional: seq[string], unknown: Option[string]
): Action =
  ## Pure reducer mapping parsed CLI tokens to a single typed ``Action``.
  ## All dispatch decisions live here; the impure shell only executes.
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

# Impure shell: IO, CLI parsing, entry point.

template check(actual, expected: untyped) =
  ## Asserts ``actual == expected``; on mismatch raises ``AssertionDefect``
  ## with a ``got X expected Y`` diagnostic for the surrounding ``test``.
  let got = actual
  let want = expected
  doAssert got == want, "got " & got.repr & " expected " & want.repr

template test(name, body: untyped) =
  ## Names a group of ``check`` calls; on the first failure quits with
  ## ``FAIL: <name> — <msg>`` and exit code 1.
  block:
    try:
      body
    except AssertionDefect as ex:
      quit("FAIL: " & astToStr(name) & " — " & ex.msg, 1)

proc runTests() =
  ## Inline test suite executed by ``--test``; prints ``ok`` on success.
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
  ## parseopt's NimScript handling skips the .nims token automatically.
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
  ## Yields every *.nim path under `dir`, pruning the script's own output
  ## tree to avoid feedback loops on subsequent runs.
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
  ## Expands a single-file or directory argument to the list of input
  ## paths that ``processOne`` will operate on.
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
  ## Reads ``input``, strips comments, and writes the result under
  ## ``scripts/output/<input>``; reports the destination path.
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
