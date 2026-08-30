# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Canonical render of the C ABI contract in ``include/jmap_client.h``,
## and the header parser the C-header gates share.
##
## Run as a program it writes the render to stdout: ``just
## snapshot-c-header`` redirects that onto
## ``tests/wire_contract/c-header.txt``, and ``just
## lint-c-header-snapshot`` diffs a fresh render against the committed
## one. Imported as a module it hands
## ``tests/lint/h18_c_header_inventory.nim`` the same parse, and
## ``tests/lint/h20_c_header_types.nim`` both that parse and the
## tokeniser it reads Nim's emitted prototypes with, so no two gates can
## disagree about what the header declares — the
## ``scripts/api_oracle.nim`` division of labour: one parser, several
## consumers.
##
## Comments, blank lines and formatting are dropped; what the header
## states about the ABI is kept, grouped into four sections that each
## preserve the order the header states them in:
##
##   ``## macros``    — every ``#define`` bar the include guard
##   ``## types``     — opaque struct typedefs and callback typedefs
##   ``## enums``     — each enum's members with their ordinals
##   ``## functions`` — return type, name, and each parameter TYPE
##
## Whitespace inside a declaration is normalised and parameter NAMES are
## dropped: renaming a parameter is documentation, retyping or
## reordering one is an ABI change. Enum ordinals are rendered
## explicitly, including the implicit ones, because a member's value is
## what C callers compiled against.
##
## The parse is deliberately narrow. It accepts the shapes above and
## aborts on anything else rather than silently dropping a declaration
## it does not understand. The preprocessor directives it accepts are
## ``#include``, ``#define``, the include guard, the ``#ifdef
## __cplusplus`` extern-"C" wrapper and their ``#endif``s; any other
## conditional aborts, because a declaration inside one is conditional
## and the render has no way to say so — rendering it unconditionally
## would state a declaration that some builds do not have.
##
## Two assumptions remain. A string literal must not contain a comment
## opener, which would normally surface as a statement the parser
## rejects; and every parameter must be named, which would not — a
## parameter's trailing identifier is taken for its name, so an unnamed
## multi-word type such as ``unsigned int`` would quietly lose its last
## word. That is why the second one is stated here rather than left to
## the parser.

{.push raises: [].}

import std/[os, parseutils, sequtils, strutils]

type
  Section* = enum ## The render's four groups, in output order.
    secMacros = "macros"
    secTypes = "types"
    secEnums = "enums"
    secFunctions = "functions"

  Declaration* = object
    ## One parsed declaration. A function is kept as its parts — the
    ## render is derived from them, and the type cross-check reads them
    ## directly — so no second copy of a signature can disagree with the
    ## first. Every other section renders to lines with no further
    ## structure worth keeping.
    name*: string
    case section*: Section
    of secFunctions:
      returnType*: string
      paramTypes*: seq[string]
    of secMacros, secTypes, secEnums:
      lines*: seq[string]

const
  IdentStart = {'A' .. 'Z', 'a' .. 'z', '_'}
  IdentChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_'}
  PunctChars = {'*', '(', ')', ',', '{', '}', '=', '-'}
  IncludeGuardStart = "#ifndef "
  DefineStart = "#define "
  CplusplusGuard = "#ifdef __cplusplus"
  InertDirectives = ["#include ", "#endif"]
  HeaderRelPath* = "include" / "jmap_client.h"
  Preamble* = """# Canonical render of the C ABI contract in include/jmap_client.h,
# produced by scripts/render_c_header.nim and locked by
# tests/lint/h19_c_header_snapshot.nim. The library is pre-1.0, so this
# is a change detector rather than a compatibility promise: it makes a
# change to a parameter type, an enum ordinal or a version macro
# deliberate instead of accidental.
# Regenerate with: just snapshot-c-header
# Update PR label: [C-ABI-CHANGE]"""

proc fail(msg: string) {.noreturn.} =
  ## Aborts with a diagnostic. A header shape the parser does not
  ## understand must stop the gate, never be silently skipped: a
  ## dropped declaration would be a hole in both gates at once.
  quit("render_c_header: " & msg, 1)

proc stripComments(source: string): string =
  ## Removes ``/* … */`` and ``// …`` comments, preserving the newlines
  ## inside block comments so the line structure survives for the
  ## preprocessor pass.
  result = newStringOfCap(source.len)
  var i = 0
  while i < source.len:
    let twoChars = i + 1 < source.len
    if twoChars and source[i] == '/' and source[i + 1] == '*':
      i += 2
      while i + 1 < source.len and not (source[i] == '*' and source[i + 1] == '/'):
        if source[i] == '\n':
          result.add('\n')
        inc i
      i += 2
    elif twoChars and source[i] == '/' and source[i + 1] == '/':
      while i < source.len and source[i] != '\n':
        inc i
    else:
      result.add(source[i])
      inc i

proc tokenise*(statement: string): seq[string] =
  ## Splits a comment-free C statement into identifier tokens and
  ## single-character punctuation. Exported because the type
  ## cross-check reads Nim's emitted prototypes with it.
  result = @[]
  var i = 0
  while i < statement.len:
    let c = statement[i]
    if c in Whitespace:
      inc i
    elif c in IdentChars:
      let start = i
      while i < statement.len and statement[i] in IdentChars:
        inc i
      result.add(statement[start ..< i])
    elif c in PunctChars:
      result.add($c)
      inc i
    else:
      fail("unexpected character '" & $c & "' in: " & statement)

proc renderTypeTokens*(tokens: openArray[string]): string =
  ## Joins type tokens with single spaces, keeping a pointer run
  ## together so ``char * *`` renders as ``char **``.
  result = ""
  for token in tokens:
    if result.len == 0:
      result = token
    elif token == "*" and result.endsWith("*"):
      result.add("*")
    else:
      result.add(" " & token)

proc splitOnCommas(tokens: openArray[string]): seq[seq[string]] =
  ## Splits a token run on its top-level commas. Parenthesis depth is
  ## tracked so a function-pointer parameter would not be split apart.
  result = @[]
  var current: seq[string] = @[]
  var depth = 0
  for token in tokens:
    if token == "(":
      inc depth
    elif token == ")":
      dec depth
    if token == "," and depth == 0:
      result.add(current)
      current = @[]
    else:
      current.add(token)
  if current.len > 0:
    result.add(current)

proc paramType(tokens: seq[string], statement: string): string =
  ## Renders one parameter as its type alone. A trailing identifier is
  ## the parameter's name — documentation, not ABI — and is dropped
  ## unless it is the whole parameter, as in ``(void)``.
  if tokens.len == 0:
    fail("empty parameter in: " & statement)
  if tokens.len > 1 and tokens[^1][0] in IdentStart:
    renderTypeTokens(tokens[0 ..^ 2])
  else:
    renderTypeTokens(tokens)

proc paramTypesOf*(tokens: openArray[string], statement: string): seq[string] =
  ## Renders a parenthesised parameter list as its parameter types.
  ## Exported alongside ``tokenise``: Nim's emitted prototypes are C
  ## declarations of the same shape, so the cross-check reads them with
  ## the same three primitives rather than a second parser.
  splitOnCommas(tokens).mapIt(paramType(it, statement))

proc parseFunction(tokens: seq[string], statement: string): Declaration =
  ## Parses ``<return type> <name>(<parameters>)``.
  let open = tokens.find("(")
  if open < 2 or tokens[^1] != ")":
    fail("not a function declaration: " & statement)
  Declaration(
    section: secFunctions,
    name: tokens[open - 1],
    returnType: renderTypeTokens(tokens[0 ..< open - 1]),
    paramTypes: paramTypesOf(tokens[open + 1 ..^ 2], statement),
  )

proc parseOrdinal(tokens: seq[string], statement: string): int =
  ## Reads an enum member's explicit value. Only a plain decimal
  ## integer is accepted: anything else would make the rendered ordinal
  ## a guess, so it aborts instead.
  result = 0
  let text = tokens.join("")
  let consumed =
    try:
      parseutils.parseInt(text, result)
    except ValueError:
      0
  if text.len == 0 or consumed != text.len:
    fail("enum member value is not a plain integer ('" & text & "') in: " & statement)

proc parseEnum(tokens: seq[string], statement: string): Declaration =
  ## Parses ``typedef enum { … } <name>``, rendering every member with
  ## the ordinal it actually has, implicit ones included.
  let close = tokens.find("}")
  if tokens.len < 6 or tokens[2] != "{" or close < 3 or close != tokens.len - 2:
    fail("not an enum typedef: " & statement)
  let name = tokens[^1]
  var lines = @["enum " & name]
  var next = 0
  for member in splitOnCommas(tokens[3 ..< close]):
    if member.len == 0 or member[0][0] notin IdentStart:
      fail("unrecognised enum member in: " & statement)
    let value =
      if member.len == 1:
        next
      elif member.len > 2 and member[1] == "=":
        parseOrdinal(member[2 ..^ 1], statement)
      else:
        fail("unrecognised enum member '" & member.join(" ") & "' in: " & statement)
    lines.add("  " & member[0] & " = " & $value)
    next = value + 1
  Declaration(section: secEnums, name: name, lines: lines)

proc parseOpaqueTypedef(tokens: seq[string], statement: string): Declaration =
  ## Parses ``typedef struct <tag> <name>`` — the opaque handle shape.
  if tokens.len != 4 or tokens[2][0] notin IdentStart or tokens[3][0] notin IdentStart:
    fail("not an opaque struct typedef: " & statement)
  Declaration(
    section: secTypes,
    name: tokens[3],
    lines: @["typedef struct " & tokens[2] & " " & tokens[3]],
  )

proc parseCallbackTypedef(tokens: seq[string], statement: string): Declaration =
  ## Parses ``typedef <return type> (*<name>)(<parameters>)``.
  let open = tokens.find("(")
  if open < 2 or tokens.len < open + 6 or tokens[open + 1] != "*" or
      tokens[open + 3] != ")" or tokens[open + 4] != "(" or tokens[^1] != ")":
    fail("not a callback typedef: " & statement)
  let name = tokens[open + 2]
  Declaration(
    section: secTypes,
    name: name,
    lines: @[
      "typedef " & renderTypeTokens(tokens[1 ..< open]) & " (*" & name & ")(" &
        paramTypesOf(tokens[open + 5 ..^ 2], statement).join(", ") & ")"
    ],
  )

proc parseStatement(statement: string): Declaration =
  ## Classifies one ``;``-terminated header statement and parses it.
  let tokens = tokenise(statement)
  if tokens.len == 0:
    fail("empty statement")
  if tokens[0] != "typedef":
    parseFunction(tokens, statement)
  elif tokens.len > 1 and tokens[1] == "enum":
    parseEnum(tokens, statement)
  elif tokens.len == 4 and tokens[1] == "struct":
    parseOpaqueTypedef(tokens, statement)
  else:
    parseCallbackTypedef(tokens, statement)

proc macroName(line: string): string =
  ## The symbol a ``#define`` or ``#ifndef`` line names.
  let fields = line.splitWhitespace()
  if fields.len < 2:
    fail("preprocessor line without a symbol: " & line)
  fields[1]

proc parseMacro(line: string): Declaration =
  ## Parses ``#define <name> [<value>]``. A value-less define is a
  ## feature flag a consumer tests with ``#ifdef``, so its name alone is
  ## what it states and its name alone is what renders.
  let fields = line.splitWhitespace()
  Declaration(section: secMacros, name: fields[1], lines: @[fields[1 ..^ 1].join(" ")])

proc parseHeader*(source: string): seq[Declaration] =
  ## Parses the whole header into declarations. Every ``#define`` is a
  ## macro a caller can compile against, so all of them are rendered
  ## bar the include guard, which the first ``#ifndef`` names. Includes
  ## and ``#endif`` carry no ABI and are skipped, and the ``#ifdef
  ## __cplusplus`` wrapper's contents are language linkage rather than
  ## declarations. Any other conditional aborts: its body is
  ## conditional, and rendering that body unconditionally would state a
  ## declaration some builds do not have.
  result = @[]
  var body: seq[string] = @[]
  var guard = ""
  var inCplusplus = false
  for raw in stripComments(source).splitLines():
    let line = raw.strip()
    if line.len == 0:
      continue
    if inCplusplus:
      if line.startsWith("#endif"):
        inCplusplus = false
      continue
    if line.startsWith(CplusplusGuard):
      inCplusplus = true
    elif line.startsWith(IncludeGuardStart) and guard.len == 0:
      guard = macroName(line)
    elif line.startsWith(DefineStart):
      if macroName(line) != guard:
        result.add(parseMacro(line))
    elif line.startsWith("#"):
      if not InertDirectives.anyIt(line.startsWith(it)):
        fail("unsupported preprocessor directive: " & line)
    else:
      body.add(line)
  for statement in body.join(" ").split(';'):
    if statement.strip().len > 0:
      result.add(parseStatement(statement))

proc renderHeader*(declarations: seq[Declaration]): seq[string] =
  ## Renders parsed declarations as the snapshot body: one ``## section``
  ## header per section, then that section's declarations in order.
  result = @[]
  for section in Section:
    result.add("")
    result.add("## " & $section)
    for declaration in declarations.filterIt(it.section == section):
      case declaration.section
      of secFunctions:
        result.add(
          declaration.returnType & " " & declaration.name & "(" &
            declaration.paramTypes.join(", ") & ")"
        )
      of secMacros, secTypes, secEnums:
        for line in declaration.lines:
          result.add(line)

proc readHeaderSource*(repoRoot: string): string =
  ## Reads ``include/jmap_client.h`` from the repository root.
  result = ""
  try:
    result = readFile(repoRoot / HeaderRelPath)
  except IOError, OSError:
    fail("cannot read " & (repoRoot / HeaderRelPath))

proc main() =
  ## Writes the canonical render to stdout.
  let repoRoot = currentSourcePath().parentDir.parentDir
  echo Preamble
  for line in renderHeader(parseHeader(readHeaderSource(repoRoot))):
    echo line

when isMainModule:
  main()
