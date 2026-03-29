# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#
# begin Nimble config (version 2)
when system.withDir(system.thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

system.switch("path", system.thisDir() & "/src")
system.switch("path", system.thisDir() & "/vendor/nim-results")

# Compiler switches — duplicated from jmap_client.nimble because the Nim
# compiler reads config.nims but NOT .nimble files. Without these lines,
# the experimental flags declared in the .nimble file are never enforced.
#
# strictDefs, strictFuncs, strictNotNil: safe to apply globally.
#
# strictCaseObjects: enforced per-module via {.experimental: "strictCaseObjects".}
# in each src/ file. Global enablement breaks std/json (variant field access
# behind `if` guards). nim-results is vendored at vendor/nim-results/ and
# patched for compliance (if→case in mapConvertErr/mapCastErr, cast pragmas
# on raiseResultOk/raiseResultError).
system.switch("experimental", "strictDefs")
system.switch("experimental", "strictFuncs")
system.switch("experimental", "strictNotNil")
