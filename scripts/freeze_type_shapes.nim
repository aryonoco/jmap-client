# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Regenerates ``tests/wire_contract/type-shapes.txt`` — the frozen snapshot of
## the public-field signature of every public type reachable through the hub
## (A25). Emits to stdout; the ``just freeze-type-shapes`` recipe redirects it
## into the committed file.
##
## A type's shape is a public commitment distinct from its mere existence (which
## H16 locks): silently adding, removing, or retyping a public field changes the
## wire/FFI contract consumers depend on. Private ``raw*`` fields are excluded,
## so internal sealing refactors do not churn the snapshot. Any diff here
## requires the ``[TYPE-SHAPE-CHANGE]`` PR label; the H17 lint fails CI on
## un-frozen drift.

{.push raises: [].}

import ./api_surface

proc main() =
  echo "# Public-type-shape snapshot — the public-field signature of every type"
  echo "# reachable through `import jmap_client` / `import jmap_client/convenience`"
  echo "# (A25). Private fields are excluded. Locked by"
  echo "# tests/lint/h17_type_shape_snapshot.nim (P1/P2)."
  echo "# Regenerate with: just freeze-type-shapes"
  echo "# Update PR label: [TYPE-SHAPE-CHANGE]"
  for line in typeShapeLines():
    echo line

main()
