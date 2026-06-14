# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

version = "0.1.0"
author = "Aryan Ameri"
description = "Sample consumer CLI exercising the jmap_client public API (P29 bench)"
license = "BSD-2-Clause"
srcDir = "."
# Entry module is jmap_cli.nim (Nim module names cannot contain hyphens).
# The conventional run-name is `jmap-cli`, produced by the documented
# `nim c -o:/tmp/jmap-cli examples/jmap-cli/jmap_cli.nim` build.
bin = @["jmap_cli"]

requires "nim >= 2.2.0"
# jmap_client is resolved in-tree via nim.cfg --path (no published package yet).
