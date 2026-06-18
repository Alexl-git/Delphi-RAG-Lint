# BACKLOG: Index DCU-only libraries (no .pas source)

Status: **future work / not started.** Captured 2026-06-18 from a design discussion.

## Why

Some Delphi editions ship without RTL/VCL source, and many third-party vendors
ship their controls as compiled `.dcu` only (no `.pas`/`.dfm`). Today drag-lint
can't index those, so completion / hover / go-to-decl / "what implements this
interface" go blank for closed-source units. Goal: extract the symbol surface
from a `.dcu` when (and only when) no `.pas` exists.

## Key framing decisions

- **NOT tree-sitter.** A `.dcu` is a *binary* container (symbol table + compiled
  machine code + debug line tables), not text. There is no grammar to write. The
  tool is a **binary DCU decoder**, not a tree-sitter grammar. "tree-sitter-dcu"
  is a misnomer.

- **Interface granularity only.** From a DCU you can reliably recover the
  *interface* surface: unit name + `uses`, public/published types (classes,
  records, interfaces, enums, sets, aliases), class members (fields, methods with
  full signatures incl. calling convention / virtual / override / abstract /
  visibility, properties with read/write specifiers), standalone routines,
  constants, typed constants, resourcestrings, global vars.
  You **cannot** recover (it's compiled to machine code): implementation bodies,
  so no intra-body call graph / "find usages" *inside* a closed-source unit, no
  locals, no comments / DocInsight `///`, no source text, no `{$IFDEF}` structure
  (already resolved away). The call-sites we care about (our code calling *into*
  the library) are found from our open-source side anyway.

- **A DCU reflects ONE platform + ONE config.** Fits drag-lint's existing
  per-platform library DBs (`library-Win32.sqlite` / `library-Win64.sqlite`),
  sourced from `...\lib\win32\release\*.dcu`, `...\lib\win64\release\*.dcu`.

## Proposed approach (reuse the existing pipeline)

1. Decode `.dcu` -> emit a `.pas`-shaped **interface stub** ("pasu" = a unit
   derived from a DCU, NOT real source).
2. Feed the stub through the **existing tree-sitter-delphi indexer** -> same
   symbol rows, no new extraction code, no schema change.
   (Alternative: decoder writes `ISymbolStore` rows directly -- faster but
   duplicates logic.)

## CRITICAL invariant: "pasu" stubs are NOT true source, and real .pas wins

The units we synthesize from a DCU are *derived/synthetic*, not authoritative
source. The index must never confuse them with real code, and real source must
always take precedence:

- **Mark the origin.** Tag DCU-derived units distinctly -- e.g. a `.pasu`
  extension and/or an `origin = 'dcu'` column on the file/symbol records (vs
  `origin = 'pas'`). Stamp a header comment in generated stubs so a human opening
  one knows it's reconstructed.
- **.pas supersedes .dcu, always.** Gating: if a `.pas` for a unit is present,
  index it and **skip the `.dcu` entirely** (the DCU adds nothing useful for
  *source-level* indexing -- it's only the resolved single-config view). If only
  a `.dcu` exists, index the stub.
- **Re-scan on source arrival.** If real `.pas` later becomes available (vendor
  ships source, edition upgrade, etc.), it must get scanned **in place of** the
  DCU-derived entry: drop/replace the `origin='dcu'` rows for that unit and index
  the real source. A pasu stub must never shadow or block real source.

## Prior art (don't start from scratch)

- **DCU32INT** -- canonical DCU decoder, dumps the interface; **written in
  Delphi** (fits the pure-Object-Pascal / no-LLM constraint -> vendor or port;
  check its license first).
- **IDR (Interactive Delphi Reconstructor)** -- heavier reconstruction.
- The IDE itself reads DCUs for Code Insight on closed-source units, so the info
  is definitely extractable; just not via a clean CLI (`dcc -JL` HPP gen needs the
  `.pas`; map files only give addresses; no `dcc -dumpsymbols`).

## Dominant risk

**Version fragility.** The DCU layout is undocumented and shifts per compiler
release. RAD Studio 37 / Delphi 13 Florence is brand new; an existing decoder may
not handle its DCUs yet.

## Entry point: a 1-day de-risking spike (do this FIRST)

1. Pick a unit we *have* source for (e.g. `System.SysUtils`) + its matching
   Florence `.dcu` under the Studio `lib` tree.
2. Run DCU32INT (or whichever decoder) against it.
3. Diff the extracted interface vs the known `.pas`.

That answers the two questions that decide everything: *does any existing decoder
parse RAD 37 DCUs at all*, and *how complete/accurate is the extracted interface*.
If solid, the rest is plumbing into the per-platform library DB with the
`origin`/supersede rules above.
