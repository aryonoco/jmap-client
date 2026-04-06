# JMAP Client - Project Overview

**Purpose**: Cross-platform JMAP (RFC 8620/8621) client library in Nim, exposing C API as shared library

**Tech Stack**: 
- Language: Nim 2.2.8+
- Memory: ARC (no GC, FFI-safe)
- Build: Nimble
- Testing: Testament (Nim's test framework)
- Dependencies: results >= 0.5.1

**Architecture**:
- Functional core (Layers 1-3), imperative shell
- ARC memory management
- C API boundary with exception handling
- Very early prototype stage

**Key Settings** (from jmap_client.nimble):
- Compiler: ARC memory management, strict type checking
- Style: styleCheck:error (enforced)
- Safety: All warnings-as-errors, runtime checks enabled
- Defects: panics:on (abort on programmer errors)
