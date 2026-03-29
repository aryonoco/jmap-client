# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#
# Package

version = "0.1.0"
author = "Aryan Ameri"
description = "Cross-platform JMAP client library"
license = "BSL-1.0"
srcDir = "src"

# =============================================================================
# Configuration
# =============================================================================

# Memory management — ARC for FFI shared library safety
--mm:
  arc

# Type safety
--experimental:
  strictDefs
--experimental:
  strictNotNil
--experimental:
  strictFuncs
--experimental:
  strictCaseObjects
--threads:
  on

# Style enforcement
--styleCheck:
  error

# Warnings as errors
--warningAsError:
  UnusedImport
--warningAsError:
  Deprecated
--warningAsError:
  CStringConv
--warningAsError:
  EnumConv
--warningAsError:
  HoleEnumConv
--warningAsError:
  Uninit
--warningAsError:
  ProveInit
--warningAsError:
  UnsafeSetLen
--hintAsError:
  DuplicateModuleImport
--floatChecks:
  on

# Debug build (default `nimble build`)
when not defined(release):
  --debugger:
    native
  --lineDir:
    on
  --stackTrace:
    on
  --lineTrace:
    on
  --excessiveStackTrace:
    on
  --assertions:
    on
  --checks:
    on
  --opt:
    none

# Dependencies

requires "nim >= 2.2.0"
# Vendored at vendor/nim-results/ (patched for strictCaseObjects)
# requires "results == 0.5.1"

# Tasks

task test, "Run tests":
  exec "testament pattern \"tests/t*.nim\""

task clean, "Clean build artifacts":
  exec "rm -rf bin/ nimcache/ htmldocs/"
