# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
# Package

version = "0.1.0"
author = "Aryan Ameri"
description = "Cross-platform JMAP client library"
license = "BSD-2-Clause"
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
--threads:
  on

# Defect handling — Defects are programmer errors; abort immediately
--panics:
  on

# Style enforcement
--styleCheck:
  error

# =============================================================================
# Warnings as errors — every on-by-default warning promoted to an error.
# Grouped by category for readability.
# =============================================================================

# --- Correctness ---
--warningAsError:
  UnusedImport
--warningAsError:
  Deprecated
--warningAsError:
  XIsNeverRead
--warningAsError:
  XmightNotBeenInit
--warningAsError:
  UnreachableCode
--warningAsError:
  UnreachableElse
--warningAsError:
  ResultShadowed
--warningAsError:
  UnsafeDefault
--warningAsError:
  UnsafeCode
--warningAsError:
  ImplicitDefaultValue
--warningAsError:
  CaseTransition
# Off-by-default, explicitly enabled: experimental strict funcs analysis
--warning:
  ObservableStores:on
--warningAsError:
  ObservableStores

# --- Type safety ---
--warningAsError:
  CStringConv
--warningAsError:
  EnumConv
--warningAsError:
  HoleEnumConv
--warningAsError:
  PtrToCstringConv
--warningAsError:
  CastSizes
--warningAsError:
  EachIdentIsTuple
--warningAsError:
  InheritFromException
# Off-by-default, explicitly enabled: stricter than EnumConv
--warning:
  AnyEnumConv:
    on
--warningAsError:
  AnyEnumConv
# Off-by-default, explicitly enabled: bare except catches Defects
--warning:
  BareExcept:
    on
--warningAsError:
  BareExcept

# --- Initialisation & memory safety ---
--warningAsError:
  ProveInit
--warningAsError:
  Uninit
--warningAsError:
  UnsafeSetLen
--warningAsError:
  WriteToForeignHeap
--warningAsError:
  GcMem
--warningAsError:
  GcUnsafe2
--warningAsError:
  Destructor
--warningAsError:
  CycleCreated
--warningAsError:
  GlobalVarConstructorTemporary

# --- Thread safety ---
--warningAsError:
  LockLevel
--warningAsError:
  Effect

# --- Compiler/config ---
--warningAsError:
  CannotOpenFile
--warningAsError:
  CannotOpen
--warningAsError:
  FileChanged
--warningAsError:
  ConfigDeprecated
--warningAsError:
  UnknownMagic
--warningAsError:
  UnknownNotes
--warningAsError:
  UnknownSubstitutionX
--warningAsError:
  RedefinitionOfLabel
--warningAsError:
  IgnoredSymbolInjection
--warningAsError:
  ImplicitTemplateRedefinition

# --- Style & formatting ---
--warningAsError:
  DotLikeOps
--warningAsError:
  SmallLshouldNotBeUsed
--warningAsError:
  Spacing
--warningAsError:
  OctalEscape
--warningAsError:
  LongLiterals
--warningAsError:
  UnnamedBreak
--warningAsError:
  StmtListLambda
--warningAsError:
  TypelessParam
--warningAsError:
  UseBase
--warningAsError:
  AboveMaxSizeSet
--warningAsError:
  IndexCheck
--warningAsError:
  StrictNotNil
# Off-by-default, explicitly enabled: flag ambiguous std/ imports
--warning:
  StdPrefix:
    on
--warningAsError:
  StdPrefix

# --- Documentation ---
--warningAsError:
  AmbiguousLink
--warningAsError:
  BrokenLink
--warningAsError:
  warnRstStyle
--warningAsError:
  CommentXIgnored
--warningAsError:
  LanguageXNotSupported
--warningAsError:
  FieldXNotSupported
--warningAsError:
  UnusedImportdoc

# --- Meta ---
--warningAsError:
  User

# Off-by-default warnings NOT enabled (rationale):
#   ImplicitRangeConversion — fires inside stdlib (system/indices.nim); unfixable
#   ProveField / ProveIndex — experimental, extremely noisy
#   GcUnsafe — fires from proc callback parameters in generics; GcUnsafe2 suffices
#   ResultUsed — requires `discard` on every function return value

--hintAsError:
  DuplicateModuleImport
--floatChecks:
  on
--overflowChecks:
  on

# Explicit runtime safety checks — default-on, made explicit to survive -d:danger
--boundChecks:
  on
--objChecks:
  on
--rangeChecks:
  on
--fieldChecks:
  on
--assertions:
  on

# staticBoundChecks intentionally omitted: fires inside stdlib
# (system/indices.nim, collections/tables.nim); unfixable

# strictNotNil intentionally omitted: fires inside stdlib
# (system/seqs_v2.nim, pure/collections/tables.nim); unfixable

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

requires "nim >= 2.2.8"
requires "results >= 0.5.1"

# Tasks

task test, "Run tests":
  exec "testament --backendLogging:off all"

task clean, "Clean build artifacts":
  exec "rm -rf bin/ nimcache/ htmldocs/"
