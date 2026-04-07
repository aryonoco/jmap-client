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

# Defect handling — Defects are programmer errors; abort immediately
system.switch("panics", "on")

# Experimental type safety
system.switch("experimental", "strictDefs")

# styleCheck:error intentionally omitted: test files use underscored block names
# (rfc8620_S1_2_..., regression_2026_03_...) as a deliberate naming convention
# for traceability. The flag remains declared in .nimble for library builds.

# =============================================================================
# Warnings as errors — every on-by-default warning promoted to an error.
# Grouped by category for readability.
# =============================================================================

# --- Correctness ---
when not defined(nimMegatest):
  # UnusedImport guarded: testament's auto-generated megatest.nim (-d:nimMegatest)
  # imports split modules that trigger false-positive UnusedImport errors.
  system.switch("warningAsError", "UnusedImport")
system.switch("warningAsError", "Deprecated")
system.switch("warningAsError", "XIsNeverRead")
system.switch("warningAsError", "XmightNotBeenInit")
system.switch("warningAsError", "UnreachableCode")
system.switch("warningAsError", "UnreachableElse")
system.switch("warningAsError", "ResultShadowed")
system.switch("warningAsError", "UnsafeDefault")
system.switch("warningAsError", "UnsafeCode")
system.switch("warningAsError", "ImplicitDefaultValue")
# Off-by-default, explicitly enabled: experimental strict funcs analysis
system.switch("warning", "ObservableStores:on")
system.switch("warningAsError", "ObservableStores")
system.switch("warningAsError", "CaseTransition")

# --- Type safety ---
system.switch("warningAsError", "CStringConv")
system.switch("warningAsError", "EnumConv")
system.switch("warningAsError", "HoleEnumConv")
system.switch("warningAsError", "PtrToCstringConv")
system.switch("warningAsError", "CastSizes")
system.switch("warningAsError", "EachIdentIsTuple")
system.switch("warningAsError", "InheritFromException")
# Off-by-default, explicitly enabled: stricter than EnumConv
system.switch("warning", "AnyEnumConv:on")
system.switch("warningAsError", "AnyEnumConv")
# Off-by-default, explicitly enabled: bare except catches Defects
system.switch("warning", "BareExcept:on")
system.switch("warningAsError", "BareExcept")

# --- Initialisation & memory safety ---
system.switch("warningAsError", "ProveInit")
system.switch("warningAsError", "Uninit")
system.switch("warningAsError", "UnsafeSetLen")
system.switch("warningAsError", "WriteToForeignHeap")
system.switch("warningAsError", "GcMem")
system.switch("warningAsError", "GcUnsafe2")
system.switch("warningAsError", "Destructor")
system.switch("warningAsError", "CycleCreated")
system.switch("warningAsError", "GlobalVarConstructorTemporary")

# --- Thread safety ---
system.switch("warningAsError", "LockLevel")
system.switch("warningAsError", "Effect")

# --- Compiler/config ---
system.switch("warningAsError", "CannotOpenFile")
system.switch("warningAsError", "CannotOpen")
system.switch("warningAsError", "FileChanged")
system.switch("warningAsError", "ConfigDeprecated")
system.switch("warningAsError", "UnknownMagic")
system.switch("warningAsError", "UnknownNotes")
system.switch("warningAsError", "UnknownSubstitutionX")
system.switch("warningAsError", "RedefinitionOfLabel")
system.switch("warningAsError", "IgnoredSymbolInjection")
system.switch("warningAsError", "ImplicitTemplateRedefinition")

# --- Style & formatting ---
system.switch("warningAsError", "DotLikeOps")
system.switch("warningAsError", "SmallLshouldNotBeUsed")
system.switch("warningAsError", "Spacing")
system.switch("warningAsError", "OctalEscape")
system.switch("warningAsError", "LongLiterals")
system.switch("warningAsError", "UnnamedBreak")
system.switch("warningAsError", "StmtListLambda")
system.switch("warningAsError", "TypelessParam")
system.switch("warningAsError", "UseBase")
system.switch("warningAsError", "AboveMaxSizeSet")
system.switch("warningAsError", "IndexCheck")
system.switch("warningAsError", "StrictNotNil")
# Off-by-default, explicitly enabled: flag ambiguous std/ imports
system.switch("warning", "StdPrefix:on")
system.switch("warningAsError", "StdPrefix")

# --- Documentation ---
system.switch("warningAsError", "AmbiguousLink")
system.switch("warningAsError", "BrokenLink")
system.switch("warningAsError", "warnRstStyle")
system.switch("warningAsError", "CommentXIgnored")
system.switch("warningAsError", "LanguageXNotSupported")
system.switch("warningAsError", "FieldXNotSupported")
system.switch("warningAsError", "UnusedImportdoc")

# --- Meta ---
system.switch("warningAsError", "User")

# Off-by-default warnings NOT enabled (rationale):
#   ImplicitRangeConversion — fires inside stdlib (system/indices.nim); unfixable
#   ProveField / ProveIndex — experimental, extremely noisy
#   GcUnsafe — fires from proc callback parameters in generics; GcUnsafe2 suffices
#   ResultUsed — requires `discard` on every function return value

# Hints as errors
system.switch("hintAsError", "DuplicateModuleImport")

# Float safety
system.switch("floatChecks", "on")

# Integer overflow safety
system.switch("overflowChecks", "on")

# =============================================================================
# Explicit runtime safety checks — default-on, made explicit to survive -d:danger
# =============================================================================
system.switch("boundChecks", "on")
system.switch("objChecks", "on")
system.switch("rangeChecks", "on")
system.switch("fieldChecks", "on")
system.switch("assertions", "on")

# staticBoundChecks intentionally omitted: fires inside stdlib
# (system/indices.nim, collections/tables.nim); unfixable

# strictNotNil intentionally omitted: generic/template instantiation from
# stdlib (Option[T], seq, Table) fires inside user modules even with
# per-module {.experimental: "strictNotNil".} pragmas; unfixable in Nim 2.2
