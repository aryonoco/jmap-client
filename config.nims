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

# Memory management — ARC for FFI shared library safety

system.switch("mm", "arc")

# Threading
system.switch("threads", "on")

# Defect handling — Defects are programmer errors; abort immediately
system.switch("panics", "on")

# Experimental type safety
system.switch("experimental", "strictDefs")
system.switch("experimental", "strictEffects")

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

# Hints as errors
system.switch("hintAsError", "DuplicateModuleImport")
# Diagnostic hints — uncomment one at a time, fix surfaces, verify.
# Order: ascending expected code-fix cost. Rationale in
# /home/vscode/.claude/plans/document-all-of-these-deep-blanket.md
system.switch("hintAsError", "XCannotRaiseY")                  # raises list contains impossible exception
# system.switch("hintAsError", "UnknownRaises")                # forward decl without explicit .raises
# system.switch("hintAsError", "ExprAlwaysX")                  # expression constant-folds to literal
# system.switch("hintAsError", "CondTrue")                     # condition always true
# system.switch("hintAsError", "CondFalse")                    # condition always false
# system.switch("hintAsError", "ConvToBaseNotNeeded")          # redundant upcast to base object
# system.switch("hintAsError", "User")                         # {.hint: "msg".} pragma in user code
# system.switch("hintAsError", "UserRaw")                      # raw user hint
# system.switch("hintAsError", "XDeclaredButNotUsed")          # unused symbol
# system.switch("hintAsError", "ConvFromXtoItselfNotNeeded")   # T(x) where x: T
# Note: "Name" deliberately NOT listed here — see .nimble file. Promoting it
# requires --styleCheck:hint|error, which config.nims omits so testament can
# use rfc8620_S1_2_... underscored block names (see line 30-32 comment above).

# Float safety
system.switch("floatChecks", "on")

# Integer overflow safety
system.switch("overflowChecks", "on")

# =============================================================================
# Diagnostic probe — ImplicitRangeConversion under -d:probeImplicitRange
# =============================================================================
# Off by default. Enable with:
#   nim check -d:probeImplicitRange src/jmap_client.nim
# Stdlib diagnostics (under */nim-*/lib/) are expected and structurally
# unsuppressible; any diagnostic under src/ is a regression. See the
# "Intentionally omitted" section below for the full rationale.
when defined(probeImplicitRange):
  system.switch("warning", "ImplicitRangeConversion:on")
  system.switch("warningAsError", "ImplicitRangeConversion")

# =============================================================================
# Explicit runtime safety checks — default-on, made explicit to survive -d:danger
# =============================================================================
system.switch("boundChecks", "on")
system.switch("objChecks", "on")
system.switch("rangeChecks", "on")
system.switch("fieldChecks", "on")
system.switch("assertions", "on")

# =============================================================================
# Intentionally omitted — each fires in stdlib or dependencies, unfixable
# =============================================================================

# --- Warnings NOT promoted to errors ---
#
#   ResultUsed — compiler bug in Nim 2.2.8 (compiler/semexprs.nim:1388–1401):
#     the warning fires inside the `of skVar, skLet, skResult, skForVar:`
#     branch with no guard on `s.kind == skResult`, so it triggers on every
#     variable access, not just the implicit `result` variable. Non-functional
#     until the compiler is patched.
#
#   ImplicitRangeConversion — detects implicit narrowing conversions to
#     range types (int -> Natural, int -> Positive, etc.). Triggers live
#     in stdlib generic bodies that receive int / int-literal arguments
#     into Natural/Positive-typed parameters — initTable, newSeq,
#     newStringOfCap, HashSet, strutils.find, strutils.toHex. Specific
#     firing sites: system.nim, system/seqs_v2.nim, pure/strutils.nim,
#     pure/collections/{tables, tableimpl, sets, setimpl, sequtils}.nim.
#     The diagnostic is reported at the stdlib file/line, NOT at the
#     user's instantiation site, so a
#     {.push warning[ImplicitRangeConversion]: off.} in user code cannot
#     reach it. Enabling the flag project-wide therefore requires
#     upstream Nim to retype those parameters as plain int. Off until
#     then. The probe gate below lets a developer verify user-code
#     cleanliness on demand (src/ is known-clean as of 2026-04-23).
#
#   ProveField — experimental dataflow analysis for case-object field access.
#     Extremely noisy; fires on valid patterns in both project and stdlib code.
#
#   ProveIndex — experimental dataflow analysis for array/seq indexing.
#     Extremely noisy; fires on valid patterns in both project and stdlib code.
#
#   GcUnsafe — fires from proc callback parameters in generic functions
#     (hidden pointer indirection). GcUnsafe2 covers real GC-safety issues
#     without false-positiving on callback signatures.

# --- Experimental features NOT enabled ---
#
#   staticBoundChecks — compile-time array/seq bounds proving. Fires inside
#     stdlib (system/indices.nim, collections/tables.nim) on internal index
#     arithmetic. Cannot be suppressed from user code.
#
#   strictFuncs — stricter side-effect analysis for `func` declarations.
#     Catches mutations through object fields and reference indirection that
#     the default checker misses. Already partially covered: the
#     ObservableStores warning (enabled above) is the diagnostic this
#     feature produces. Cannot enable because std/json's JsonNode is a ref
#     type whose core operations (%, []=, add) are side-effectful procs.
#     Enabling strictFuncs would force every toJson/fromJson func in the
#     serde layer to become proc, losing the func purity guarantee on the
#     entire serialisation surface despite the functions being logically pure.
#
#   strictNotNil — compile-time nil safety. Generic/template instantiation
#     from stdlib (Option[T], seq, Table) fires inside user modules even
#     with per-module {.experimental: "strictNotNil".} pragmas. Unfixable
#     in Nim 2.2.
#
#   strictCaseObjects — not enabled globally here because stdlib/JsonNode
#     patterns fire under the checker. Enabled per-file in src/ via
#     {.experimental: "strictCaseObjects".}; see CLAUDE.md. Requires the
#     vendored nim-results copy at vendor/nim-results/, which case-wraps
#     the raise*/map*Err helpers that cannot be expressed strict-clean
#     under upstream 0.5.1.
#
#   views — enables borrowing/view types (`openArray` as first-class view,
#     `lent` returns). Experimental lifetime tracking; fires on valid stdlib
#     patterns. Better suited to per-module opt-in once stable.
#
#   inferGenericTypes — allows omitting explicit generic type parameters
#     when the compiler can infer them from arguments. Young feature;
#     interaction with the project's heavy use of distinct types is untested.
#
#   openSym — changes symbol capture in generic routines and templates to
#     prefer the symbol visible at instantiation over the one at definition.
#     Intended to become the default in a future Nim version. Not yet stable;
#     may change template expansion semantics in subtle ways.
#
#   genericsOpenSym — alternative to openSym scoped to generic routines only.
#     Same maturity concerns as openSym.
#
#   vtables — switches method dispatch from inline-if chains to vtable
#     lookup. This project does not use `method`; flag is irrelevant.
#
#   typeBoundOps — allows user-defined `=copy`, `=sink`, `=destroy`, `=dup`,
#     `=deepCopy` as regular overloaded procs rather than type-bound hooks.
#     Not needed; the project does not define custom lifetime hooks.
#
#   dotOperators — enables custom `.` and `.=` operator overloading.
#     Not needed; the project does not define dot operators.
#
#   callOperator — enables `()` operator overloading on non-proc types.
#     Not needed; the project does not overload the call operator.
#
#   parallel — enables the `parallel` statement for structured parallelism
#     with compile-time data-race checking. Requires the threadpool module.
#     Not needed; the project uses explicit threading, not spawn/parallel.
#
#   codeReordering — allows top-level declarations in any order within a
#     module. Fragile; known to interact poorly with macros and templates.
#
#   compiletimeFFI — allows calling C libraries at compile time via the VM.
#     Requires building Nim with -d:nimHasLibFFI. Not needed.
#
#   vmopsDanger — enables dangerous VM operations (file I/O, process exec)
#     at compile time. Security risk; not needed.
#
#   flexibleOptionalParams — relaxes rules for optional parameters in
#     routine signatures. Not needed; all project signatures use explicit
#     defaults.
#
#   dynamicBindSym — enables runtime symbol lookup in macros via bindSym
#     with a non-literal argument. Not needed; the project does not use
#     dynamic macro symbol resolution.
