# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

system.switch("path", system.thisDir() & "/src")
# Compiler switches — duplicated from jmap_client.nimble because the Nim
# compiler reads config.nims but NOT .nimble files. Without these lines,
# the flags declared in the .nimble file are never enforced by nim c,
# testament, or nim check.

# Memory management — ARC for FFI shared library safety
system.switch("mm", "arc")

# Threading
system.switch("threads", "on")

# Experimental type safety
system.switch("experimental", "strictDefs")

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
system.switch("warningAsError", "Uninit")
system.switch("warningAsError", "UnsafeSetLen")

# Hints as errors
system.switch("hintAsError", "DuplicateModuleImport")

# Float safety
system.switch("floatChecks", "on")
