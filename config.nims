# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

system.switch("path", system.thisDir() & "/src")
system.switch("path", system.thisDir() & "/vendor/nim-results")

# Compiler switches — duplicated from jmap_client.nimble because the Nim
# compiler reads config.nims but NOT .nimble files. Without these lines,
# the flags declared in the .nimble file are never enforced by nim c,
# testament, or nim check.
#
# strictCaseObjects: enforced per-module via {.experimental: "strictCaseObjects".}
# in each src/ file. Global enablement breaks std/json (variant field access
# behind `if` guards). nim-results is vendored at vendor/nim-results/ and
# patched for compliance (if→case in mapConvertErr/mapCastErr, cast pragmas
# on raiseResultOk/raiseResultError).

# Memory management — ARC for FFI shared library safety
system.switch("mm", "arc")

# Threading
system.switch("threads", "on")

# Experimental type safety
system.switch("experimental", "strictDefs")
system.switch("experimental", "strictFuncs")

# strictNotNil crashes nimsuggest (IndexDefect on startup — Nim 2.2.x bug).
# Guard it so the flag still applies during normal compilation and CI.
when not defined(nimsuggest):
  system.switch("experimental", "strictNotNil")

# styleCheck:error intentionally omitted: test files use underscored block names
# (rfc8620_S1_2_..., regression_2026_03_...) as a deliberate naming convention
# for traceability. The flag remains declared in .nimble for library builds.

# Warnings as errors
# UnusedImport guarded: testament's auto-generated megatest.nim (-d:nimMegatest)
# imports split modules that trigger false-positive UnusedImport errors.
when not defined(nimMegatest):
  system.switch("warningAsError", "UnusedImport")
system.switch("warningAsError", "Deprecated")
system.switch("warningAsError", "CStringConv")
system.switch("warningAsError", "EnumConv")
system.switch("warningAsError", "HoleEnumConv")
system.switch("warningAsError", "ProveInit")
# Uninit and UnsafeSetLen intentionally omitted: both fire at generic
# instantiation sites (every importing module), not at definition sites.
# Nim's {.push warning[...]: off.} only affects the current module, making
# per-module suppression ineffective. Uninit is triggered by initResultErr
# (deliberate zero-init for case objects); UnsafeSetLen by seq[Id] (Id is
# {.requiresInit.} distinct string). Both flags remain in .nimble for
# documentation.

# Hints as errors
system.switch("hintAsError", "DuplicateModuleImport")

# Float safety
system.switch("floatChecks", "on")
