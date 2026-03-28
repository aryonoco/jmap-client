# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

switch("path", thisDir() & "/src")

# Compiler switches — duplicated from jmap_client.nimble because the Nim
# compiler reads config.nims but NOT .nimble files. Without these lines,
# the experimental flags declared in the .nimble file are never enforced.
#
# Three flags are safe to apply globally (stdlib/deps compile clean):
#   strictDefs, strictFuncs, strictNotNil
#
# strictCaseObjects CANNOT be enforced — it breaks std/json and nim-results
# (case-object field accesses that rely on runtime asserts, not compile-time
# proof). Both global (config.nims) and per-module ({.experimental.} or
# {.push experimental.}) application fails because the flag leaks through
# generic instantiation into nim-results' Result/Opt internals. Blocked
# until nim-results 0.5.1 is updated. Case-object safety in project code
# is enforced by convention (exhaustive case, uncheckedAssign patterns).
switch("experimental", "strictDefs")
switch("experimental", "strictFuncs")
switch("experimental", "strictNotNil")
