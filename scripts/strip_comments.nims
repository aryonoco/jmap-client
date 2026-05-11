# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# strip_comments.nims — produce comment-free copies of Nim source files for
# inspection, code review and diffing.
#
# Usage:
#   nim e scripts/strip_comments.nims <path>
#
# <path> is either a single .nim file or a directory.  In directory mode the
# script walks recursively, processing every *.nim it finds, except those
# under scripts/output/ (the script's own output tree, which would otherwise
# create a feedback loop on subsequent runs).  Each processed file is written
# to scripts/output/<input-path>, mirroring the input's cwd-relative layout.
# Absolute input paths have their leading '/' stripped so they nest under
# scripts/output/ cleanly.
#
# Comment forms recognised and removed:
#   #…           single-line
#   ##…          doc single-line
#   #[ … ]#      block (nestable)
#   ##[ … ]##    doc block (nestable)
#
# String and char literal contexts are tracked — including triple-quoted,
# raw, and generalised-raw forms — so a '#' inside a literal is preserved.
# A "'" directly after an alphanumeric/_ run is treated as a numeric type
# suffix marker (e.g. the apostrophe in 100'i32), not a char-literal opener.
#
# After stripping, lines that are whitespace-only are collapsed.  Note that
# this shifts line numbers in the output relative to the input.
#
# CAVEAT: a proc or block whose entire body is a doc comment becomes an
# empty body after stripping and will not compile.  Repairing this would
# need a real parser; this tool is for human reading and diffing, not for
# producing compilable output.

from std/os import splitFile, joinPath, isAbsolute
import std/strutils

# ----- comment stripper ------------------------------------------------------

type State = enum
  sCode
  sLineCmt
  sBlockCmt
  sStr
  sTripleStr
  sRawStr
  sRawTripleStr
  sChar

const SymChars = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xff'}
const SuffixHead = {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func stripComments(src: string): string =
  result = newStringOfCap(src.len)
  var state = sCode
  var depth = 0
  var i = 0
  let n = src.len

  template peek(off: int): char =
    if i + off < n: src[i + off] else: '\0'

  template prevEmitted(): char =
    if result.len > 0: result[result.len - 1] else: '\0'

  while i < n:
    let c = src[i]
    case state
    of sCode:
      if c == '#':
        if peek(1) == '[':
          state = sBlockCmt
          depth = 1
          i += 2
        elif peek(1) == '#' and peek(2) == '[':
          state = sBlockCmt
          depth = 1
          i += 3
        else:
          state = sLineCmt
          inc i
      elif c == '"':
        if peek(1) == '"' and peek(2) == '"':
          state = if prevEmitted() in SymChars: sRawTripleStr else: sTripleStr
          result.add('"'); result.add('"'); result.add('"')
          i += 3
        else:
          state = if prevEmitted() in SymChars: sRawStr else: sStr
          result.add('"')
          inc i
      elif c == '\'':
        if prevEmitted() in SuffixHead:
          result.add('\'')
        else:
          state = sChar
          result.add('\'')
        inc i
      else:
        result.add(c)
        inc i
    of sLineCmt:
      if c == '\n':
        result.add('\n')
        state = sCode
      inc i
    of sBlockCmt:
      if c == '#' and peek(1) == '[':
        inc depth
        i += 2
      elif c == ']' and peek(1) == '#':
        dec depth
        i += 2
        if depth == 0:
          state = sCode
      elif c == '\n':
        result.add('\n')
        inc i
      else:
        inc i
    of sStr:
      if c == '\\':
        result.add(c)
        if i + 1 < n:
          result.add(src[i + 1])
          i += 2
        else:
          inc i
      elif c == '"':
        result.add(c)
        state = sCode
        inc i
      else:
        result.add(c)
        inc i
    of sTripleStr:
      if c == '"' and peek(1) == '"' and peek(2) == '"' and peek(3) != '"':
        result.add('"'); result.add('"'); result.add('"')
        state = sCode
        i += 3
      else:
        result.add(c)
        inc i
    of sRawStr:
      if c == '"' and peek(1) == '"':
        result.add('"'); result.add('"')
        i += 2
      elif c == '"':
        result.add('"')
        state = sCode
        inc i
      else:
        result.add(c)
        inc i
    of sRawTripleStr:
      if c == '"' and peek(1) == '"' and peek(2) == '"' and peek(3) != '"':
        result.add('"'); result.add('"'); result.add('"')
        state = sCode
        i += 3
      else:
        result.add(c)
        inc i
    of sChar:
      if c == '\\':
        result.add(c)
        if i + 1 < n:
          result.add(src[i + 1])
          i += 2
        else:
          inc i
      elif c == '\'':
        result.add('\'')
        state = sCode
        inc i
      else:
        result.add(c)
        inc i

# ----- blank-line collapse ---------------------------------------------------

func collapseBlankLines(s: string): string =
  let lines = s.splitLines()
  var keep: seq[string] = @[]
  for line in lines:
    if line.strip().len > 0:
      keep.add(line)
  result = keep.join("\n")
  if result.len > 0 and not result.endsWith("\n"):
    result.add('\n')

# ----- argv parsing ----------------------------------------------------------

proc collectUserArgs(): seq[string] =
  ## Returns every argv entry after the .nims script path.
  ## When invoked as `nim e <script>.nims a b c`, paramStr/paramCount
  ## delegate to host argv (see compiler/scriptconfig.nim), so paramStr(0)
  ## is "nim", paramStr(1) is "e", etc.  We find the .nims token and take
  ## everything after it.
  result = @[]
  var passed = false
  for i in 0 .. paramCount():
    let p = paramStr(i)
    if passed:
      result.add(p)
    elif p.endsWith(".nims"):
      passed = true

# ----- output path -----------------------------------------------------------

proc outPathFor(inputPath: string): string =
  let rel =
    if isAbsolute(inputPath):
      inputPath[1 .. ^1]
    else:
      inputPath
  joinPath("scripts/output", rel)

# ----- directory walk --------------------------------------------------------

proc walkNimFiles(dir: string, acc: var seq[string]) =
  ## Recursive *.nim collector.  Refuses any directory whose normalised
  ## path is or ends in "scripts/output" — the feedback-loop guard against
  ## rerunning the script over its own output tree, applied at every entry
  ## (so an explicit top-level argument of scripts/output also no-ops).
  let d = dir.strip(trailing = true, chars = {'/'})
  if d == "scripts/output" or d.endsWith("/scripts/output"):
    return
  for f in listFiles(d):
    if splitFile(f).ext == ".nim":
      acc.add(f)
  for sub in listDirs(d):
    walkNimFiles(sub, acc)

# ----- per-file processing ---------------------------------------------------

proc processOne(inputPath: string) =
  let outPath = outPathFor(inputPath)
  let outDir = splitFile(outPath).dir
  if outDir.len > 0:
    mkDir(outDir)
  let stripped = collapseBlankLines(stripComments(readFile(inputPath)))
  writeFile(outPath, stripped)
  echo "stripped: ", outPath

# ----- entry point -----------------------------------------------------------

let args = collectUserArgs()
if args.len != 1:
  quit("usage: nim e scripts/strip_comments.nims <path>", 1)

let arg = args[0]
var inputs: seq[string] = @[]

if fileExists(arg) and splitFile(arg).ext == ".nim":
  inputs.add(arg)
elif dirExists(arg):
  walkNimFiles(arg, inputs)
else:
  quit("strip_comments: path not found or not a .nim file: " & arg, 1)

for path in inputs:
  processOne(path)
