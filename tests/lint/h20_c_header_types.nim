# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H20 — the hand-written header's types must match the Nim exports.
##
## H18 holds the two inventories to each other by NAME and H19 holds the
## header to a snapshot of itself. Neither compares a declaration in
## ``include/jmap_client.h`` against the Nim proc it stands for, and
## nothing else does either: C linkage carries no type information, so
## the linker matches by name alone, and a C consumer only ever checks
## its call sites against this header. A header that lies about a
## parameter type therefore builds, links and runs — and a ``size_t``
## written as ``int`` returns right answers on a 64-bit host while being
## wrong on a 32-bit one, which is exactly the mistake a cross-platform
## library cannot afford to make silently.
##
## So this lint compares the two. ``nim c --header:`` emits a C
## prototype for every exported symbol, straight from the Nim
## signatures; the ``lint-c-header-types`` recipe produces it and passes
## its path as the first argument. Both sides are read with the
## primitives in ``scripts/render_c_header.nim`` and reduced to a
## canonical ABI shape, then compared name by name: arity first, then
## the return type, then each parameter positionally.
##
## **What the canonical shape keeps.** Scalar width and signedness
## (``i32``, ``u32``, ``i64``, ``usize``), pointer versus scalar,
## pointer depth (``ptr1``, ``ptr2``), function pointers, and ``void``.
## A C ``enum`` reduces to ``i32``, which is what every ABI this library
## targets gives an enum of these values and what Nim emits for the
## ``cint`` the export actually takes.
##
## **What it deliberately drops, and why.** The pointee type: on every
## mainstream C ABI a pointer is passed identically whatever it points
## at, and the two sides could not be compared on it anyway — Nim emits
## hash-mangled struct names (``tyObject_MailboxItem__Poq5…``) that no
## rule maps onto ``jmap_mailbox`` without a hand-kept table that would
## drift. ``const`` goes with it, being no part of the ABI.
##
## **What therefore passes this gate.** Two declarations that differ only
## inside a reduction are equal here. ``jmap_status`` written as ``int``
## passes, because both reduce to ``i32``. ``const jmap_mailbox *``
## written as ``const jmap_email *`` passes, because both reduce to
## ``ptr1``. Neither is an ABI lie — a caller compiled against either
## spelling links and runs correctly — but both are documentation lies,
## and nothing in this repository catches them.
##
## **What it does not reach.** Only function prototypes are compared.
## The three callback typedefs' own parameter lists are not: Nim emits
## them under hash-mangled ``tyProc__…`` names, and pairing those with
## ``jmap_send_fn``, ``jmap_close_fn`` and ``jmap_debug_fn`` needs
## inference this lint does not do. Their types are unchecked.
##
## The library is pre-1.0 and this is not a compatibility promise; it is
## the check that the header describes the library it ships with.

import std/[algorithm, os, sequtils, sets, strutils, tables]
import ../../scripts/render_c_header

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  EmittedMarker = "N_LIB_IMPORT N_CDECL("

type Signature = tuple[returnType: string, paramTypes: seq[string]]

proc abort(msg: string) =
  ## Exits non-zero on input the lint cannot read. A type spelling it
  ## does not know must stop the gate: reducing it to a guess would let
  ## the mismatch it exists to catch through.
  stderr.writeLine "H20: " & msg
  quit(2)

func scalarAbi(base: string): string =
  ## The canonical shape of a non-pointer C spelling, or "" when the
  ## spelling is not one of the scalars this header uses.
  case base
  of "void": "void"
  of "int": "i32"
  of "int64_t": "i64"
  of "uint32_t": "u32"
  of "size_t": "usize"
  else: ""

proc handAbi(spelling: string, enums, callbacks: HashSet[string]): string =
  ## Reduces a spelling from ``include/jmap_client.h`` to its canonical
  ## shape. Enum and callback typedef names come from the header's own
  ## parse, so the lint never carries a second list of them.
  let depth = spelling.count('*')
  if depth > 0:
    return "ptr" & $depth
  let base = spelling.replace("const ", "").strip()
  result = scalarAbi(base)
  if result.len == 0:
    result =
      if base in enums:
        "i32"
      elif base in callbacks:
        "fnptr"
      else:
        abort("unknown type in include/jmap_client.h: '" & spelling & "'")
        ""

proc nimAbi(spelling: string): string =
  ## Reduces a spelling from Nim's emitted header to its canonical
  ## shape. ``NCSTRING`` is ``char *``, so it carries one pointer level
  ## of its own; ``tyEnum_…`` is emitted as a 32-bit integer.
  let depth = spelling.count('*')
  let base = spelling.strip(chars = {'*', ' '})
  if base == "NCSTRING":
    return "ptr" & $(depth + 1)
  if base.startsWith("tyProc__") and depth == 0:
    return "fnptr"
  if depth > 0:
    return "ptr" & $depth
  if base.startsWith("tyEnum_"):
    return "i32"
  result = scalarAbi(base)
  if result.len == 0:
    result =
      case base
      of "NI32":
        "i32"
      of "NI64":
        "i64"
      of "NU32":
        "u32"
      else:
        abort("unknown type in Nim's emitted header: '" & spelling & "'")
        ""

proc parsePrototype(line: string): tuple[name: string, signature: Signature] =
  ## Reads one ``N_LIB_IMPORT N_CDECL(<return>, <name>)(<parameters>)``
  ## line into the same shape the hand-written header parses to.
  let statement = line.strip().strip(chars = {';'})
  let tokens = tokenise(statement)
  let comma = tokens.find(",")
  if tokens.len < 8 or tokens[2] != "(" or comma < 4:
    abort("cannot read emitted prototype: " & statement)
  let close = comma + 2
  if tokens[close] != ")" or tokens[close + 1] != "(" or tokens[^1] != ")":
    abort("cannot read emitted prototype: " & statement)
  (
    name: tokens[comma + 1],
    signature: (
      returnType: renderTypeTokens(tokens[3 ..< comma]),
      paramTypes: paramTypesOf(tokens[close + 2 ..^ 2], statement),
    ),
  )

proc emittedSignatures(path: string): Table[string, Signature] =
  ## Every exported prototype in Nim's emitted header, by symbol name.
  result = initTable[string, Signature]()
  let raw =
    try:
      readFile(path)
    except IOError, OSError:
      abort("cannot read " & path)
      ""
  for line in raw.splitLines():
    if line.startsWith(EmittedMarker):
      let prototype = parsePrototype(line)
      result[prototype.name] = prototype.signature

proc describe(signature: Signature, canonical: proc(s: string): string): string =
  ## One line naming a signature as written and as reduced, so a report
  ## shows both the spelling that differs and the shape it differs on.
  let written = signature.returnType & " (" & signature.paramTypes.join(", ") & ")"
  let shape =
    canonical(signature.returnType) & " (" &
    signature.paramTypes.mapIt(canonical(it)).join(", ") & ")"
  written & "   ⇒ " & shape

proc compare(
    functions: seq[Declaration],
    emitted: Table[string, Signature],
    hand: proc(s: string): string,
    nim: proc(s: string): string,
): seq[string] =
  ## One report line per declaration whose canonical shape differs from
  ## the prototype Nim emits for it, or that Nim emits no prototype for.
  result = @[]
  for declaration in functions:
    let declared: Signature =
      (returnType: declaration.returnType, paramTypes: declaration.paramTypes)
    if declaration.name notin emitted:
      result.add(declaration.name & ": no prototype emitted for this symbol")
      continue
    let exported = emitted[declaration.name]
    if declared.paramTypes.mapIt(hand(it)) == exported.paramTypes.mapIt(nim(it)) and
        hand(declared.returnType) == nim(exported.returnType):
      continue
    result.add(
      declaration.name & ":\n      header: " & describe(declared, hand) &
        "\n      nim:    " & describe(exported, nim)
    )

proc main() =
  ## Compares every function the header declares against the prototype
  ## Nim emits for it, and exits non-zero on any difference.
  if paramCount() < 1:
    stderr.writeLine "H20: usage: h20_c_header_types <nim-emitted-header>"
    quit(1)
  let declarations = parseHeader(readHeaderSource(RepoRoot))
  let enums = declarations.filterIt(it.section == secEnums).mapIt(it.name).toHashSet
  let callbacks = declarations
    .filterIt(it.section == secTypes and it.lines.anyIt("(*" in it))
    .mapIt(it.name).toHashSet
  let emitted = emittedSignatures(paramStr(1))

  let hand = proc(s: string): string =
    handAbi(s, enums, callbacks)
  let nim = proc(s: string): string =
    nimAbi(s)

  let functions = declarations.filterIt(it.section == secFunctions)
  if functions.len == 0:
    abort(
      "include/jmap_client.h declares no functions — with nothing to compare " &
        "this gate would pass on nothing"
    )

  let mismatches = compare(functions, emitted, hand, nim)
  if mismatches.len == 0:
    echo "H20 C header types: ", functions.len, " declarations match the Nim exports"
    return

  stderr.writeLine "H20 C-header type mismatch."
  stderr.writeLine ""
  stderr.writeLine "  The header describes a different ABI from the one Nim exports."
  stderr.writeLine "  Nothing else catches this: C linkage matches by name alone."
  for mismatch in mismatches.sorted():
    stderr.writeLine "    " & mismatch
  stderr.writeLine ""
  stderr.writeLine "Fix the declaration in include/jmap_client.h to match the Nim"
  stderr.writeLine "signature (or the Nim signature, if the header is the intent), then:"
  stderr.writeLine "    just snapshot-c-header   # rewrites tests/wire_contract/c-header.txt"
  quit(1)

when isMainModule:
  main()
