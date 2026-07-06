# Delphi Preprocessor Port -- Design Spec

**Date:** 2026-07-06
**Status:** Approved (brainstorm complete)
**Milestone:** Preprocessor adoption for indexing (resolve `{$IFDEF}` before parsing)

## Goal

Resolve Delphi conditional compilation (`{$IFDEF}` / `{$IF}` / `{$ELSE}` / `{$DEFINE}`
/ `{$UNDEF}` / `{$I}`) **before** tree-sitter parses each `.pas`, so the index
reflects exactly one build configuration accurately. This closes the
`{$IFDEF}`-cross-branch parse-failure class (the largest single class of misses on
real corpora: ~98.2% -> ~99.3% on the grammar team's 17k-file corpus) and removes
phantom/cross-branch symbols from the index.

The preprocessor is implemented as **in-process Object Pascal** -- no Node.js
runtime dependency in the shipped exe, no subprocess, no IPC. drag-lint stays a
Delphi exe plus its C tree-sitter DLLs.

## Background / current state (verified 2026-07-06)

- The parser binds the FULL grammar: `DRagLint.Parser.Delphi13.pas:31-32`
  (`external 'tree-sitter-delphi13'`), set as the language at `:1277`. The grammar
  is C-compiled to a DLL (`third_party/dll-win64/tree-sitter-delphi13.dll`); it is
  NOT Delphi. Its "THEN-wins" path parses both `{$IFDEF}` arms structurally --
  ~98.2% clean.
- The indexer feeds raw bytes straight to the grammar with NO IFDEF resolution:
  `DRagLint.Core.Indexer.pas:249` reads bytes -> `:268`
  `Utf8 := EnsureUtf8Bytes(Source)` -> parse.
- `DRagLint.Index.Closure.pas:17-18`: the uses/closure scanner does NOT evaluate
  `{$IFDEF}` -- it scans ALL branches to discover `uses`d units across platforms,
  textually stripping directive braces (`:213`) so directive words are not mistaken
  for unit names.
- There is NO per-project define-profile mechanism today. This spec adds one.
- The grammar team's preprocessor (`tree-sitter-delphi13` repo, `preprocessor/`) is
  plain JavaScript (`lexer.js` 150, `evalExpr.js` 151, `preprocess.js` 196; zero
  external deps -- `fs`/`path` only for include reads + the CLI wrapper). It runs
  only under Node. They shipped a `defines-only` include mode + a persistent
  `serve.js` (measured 0.77 ms/file), documented in
  `docs/INBOX-tree-sitter-delivered.md`.

## Key decisions (from brainstorm)

1. **Port the preprocessor to Object Pascal (no Node).** Reimplement ~497 lines of
   pure JS as in-process Pascal units. `serve.js` / the frame protocol / the Node
   dependency are NOT adopted. The JS stays as the reference test oracle.
2. **Fully per-config.** BOTH within-file symbol extraction AND the closure
   uses-scanner honor the active define profile. The index reflects exactly one
   build config. Cross-platform coverage is preserved at the multi-DB level
   (separate `library-Win32` / `library-Win64` DBs), not within a single DB.
3. **Build against the CURRENT full grammar first.** The preprocessor blanks
   inactive branches to spaces, so the full grammar (a superset that also parses
   resolved input) parses the resolved single-branch text fine. This is a valid,
   shippable INTERMEDIATE. The `pure` grammar DLL is a LATER follow-up (request it
   from the grammar team only after the port is built + working) for the final
   accuracy polish.
4. **`defines-only` semantics for includes.** `{$I X.inc}`: read the include's
   `{$DEFINE}`/`{$UNDEF}` and propagate them to the parent's live defines set, but
   do NOT splice the include body (blank the `{$I}` directive to spaces). This
   keeps `output.length == input.length` (offset-identity) AND resolves parent
   `{$IFDEF}`s correctly, while drag-lint indexes the `.inc` as its own unit. We
   port ONLY the `defines-only` and `off` modes; we do NOT port `expand`
   (body-splicing), so our port cannot shift offsets.
5. **Offsets are 1:1 -> no source map.** Because inactive branches + directives are
   blanked to spaces (never deleted) and we never splice includes, a tree-sitter
   node's `(startByte, endByte)` in the resolved text points at the exact same
   bytes in the original `.pas`. Spans are stored as original-file offsets
   directly. No map file, no remap.

## Architecture

### New pipeline

    raw bytes
      -> EnsureUtf8Bytes                          (existing, Indexer.pas:268)
      -> Preprocess(utf8, profile)                (NEW: in-process, defines-only)
      -> parse resolved text with the grammar     (full grammar for now; pure later)
      -> store tree-sitter spans as ORIGINAL-file byte/line offsets (1:1, no map)

The preprocess stage sits exactly where the transcode already is. A
`--no-preprocess` flag (and automatic per-file fallback on a preprocess exception)
routes back to raw-bytes + full grammar -- the current behavior, untouched.

### New units (the port -- mirrors the JS modules)

- **`DRagLint.Preprocess.Lexer.pas`** (<- `lexer.js`, ~150 lines): splits UTF-8
  source into a chunk sequence -- text chunks and directive chunks -- each carrying
  `SrcStart`/`SrcEnd` byte offsets.
- **`DRagLint.Preprocess.Expr.pas`** (<- `evalExpr.js`, ~150 lines): recursive-
  descent boolean evaluator for `{$IF expr}` -- `or` / `and` / `not` /
  `defined(X)` / int comparisons, over a defines set. `declared(X)` returns false
  (matches JS MVP). Self-contained, no I/O.
- **`DRagLint.Preprocess.pas`** (<- `preprocess.js`, ~196 lines): the directive
  walk -- maintains the live defines set, blanks inactive branches + directives to
  spaces, handles `defines-only` + `off` include modes. Public API:
  `function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes`.
  One in-process call, synchronous.

### Define-profile resolver

- **`DRagLint.Index.DefineProfile.pas`** (NEW): inputs (a `.dproj` path OR an
  explicit platform + config) -> output (`TDefineProfile`: the active defines list
  + numeric defines).
  - **Project index:** derive from the `.dproj`: platform built-ins (from a static
    table -- `WIN64`+`CPU64BITS`+`CPUX86_64` vs `WIN32`+`CPUX86`; plus universal
    `MSWINDOWS`, `UNICODE`, `CONDITIONALEXPRESSIONS`, `COMPILER_VERSION_37`/`VER370`,
    etc.) UNION the **Base + Release** config `DCC_Define` list from the `.dproj`
    XML. (`--config Debug` overrides to the Debug config.)
  - **Library scan:** no `.dproj` -> platform built-ins only (`WIN64` set for
    `library-Win64`, `WIN32` set for `library-Win32`). Already separate runs/DBs.
  - **Fallback:** `.dproj` missing/unparseable, or a loose folder -> default
    Delphi-13 **Win64** built-ins.
  - **Override:** Win64 is the default platform; `--platform win32` (or `--config`)
    overrides what is read (for the Win32/Paradox-compat case, and forced runs).
  - DEFERRED (YAGNI): path-regex profiles for vendored third-party code
    (EurekaLog/AsyncPro/FireDAC). Add later if a project needs it.

### Per-config closure

`DRagLint.Index.Closure` runs the SAME `Preprocess()` over a file before extracting
`uses` clauses. A unit `uses`d only under an inactive branch (e.g. `{$IFDEF LINUX}`)
is blanked out of the resolved text, so the closure scanner never discovers it ->
it is not pulled into the index. One preprocessor, two consumers (symbol extraction
AND file discovery). The existing textual brace-stripping (`:213`) stays for the
full-grammar / `--no-preprocess` path.

### Grammar binding

For the intermediate path, no grammar change: preprocess -> the CURRENT full
grammar. When the pure DLL lands (follow-up), add `tree_sitter_delphi13_pure` as a
second `external` binding + bundle its win64/win32 DLLs in `third_party/`, and
select pure for the preprocess path. (Full grammar remains the `--no-preprocess`
fallback either way.)

## Error handling / fallback

- **Preprocess exception on a file** -> catch, log, fall back to full grammar +
  raw bytes for THAT file only. One bad file never aborts the run or loses the file.
- **`--no-preprocess`** -> whole run uses the current raw-bytes + full-grammar path.
- The preprocessor being behind a flag until proven means the existing battery
  cannot regress during development.

## Testing strategy

- **Oracle-diff (the strongest test):** the grammar team's `preprocess.js` is the
  reference. A corpus of `.pas` fixtures (IFDEF-heavy, includes, `{$IF}`
  expressions, `{$UNDEF}`, nested conditionals) is run through BOTH the JS
  (`node preprocessor/cli.js` or a small harness) AND our Pascal `Preprocess()`
  under the same profile; the resolved bytes MUST be identical. Any divergence is a
  port bug. Node is a **TEST-ONLY / dev dependency** here -- the shipped exe never
  calls it.
- **Property tests:** for every fixture, `Length(output) == Length(input)`
  (offset-identity -- the invariant the no-source-map design rests on) and
  inactive-branch bytes are spaces.
- **Empirical intermediate de-risk (EARLY task, and a GATE):** preprocess an
  IFDEF-heavy real file -> feed the CURRENT full-grammar DLL -> confirm it parses at
  least as well as raw. The grammar team's corpus tested preprocess->PURE, not
  preprocess->full, so this must be verified before committing to the intermediate
  path. If preprocess->full is WORSE than raw->full on the sample, STOP: either wait
  for the pure DLL (making it a prerequisite after all) or reconsider the
  intermediate. Do not build the full wiring on an unverified assumption.
- **Guardrail:** lint 154 / store 16 / autodoc 7 / autofix 9 / callresolve 12 stay
  green throughout (preprocessor behind a flag).

## Sequence

1. Build the port (lexer/expr/preprocess units) + the define-profile resolver.
2. Oracle-diff + property tests green (port matches JS byte-for-byte).
3. Empirical de-risk: preprocess -> current full grammar parses resolved input.
4. Wire the preprocess stage into the indexer + closure, behind a flag; measure the
   pass-rate gain on drag-lint's own tree + a project.
5. Enable per-config indexing; full battery stays green.
6. **Follow-ups (post-milestone):** notify the grammar team the preprocessor is
   ported + passing vs their oracle (and that `serve.js` is not consumed); request
   the `pure` grammar DLL; swap it in behind the preprocess path for the final
   accuracy polish. Also: the free v1.1.x full-DLL refresh (97.3%->99.1% on our
   tree, CLI.pas 39->1 leaf errors) can happen any time as an independent win.

## Non-goals

- No Node.js runtime dependency in the shipped exe.
- No `expand` include mode (body-splicing) -- offsets must stay 1:1.
- No source map / span remapping.
- No `serve.js` / IPC / frame protocol.
- No path-regex vendored-defines profiles (deferred).
- No pure-grammar swap in this milestone (follow-up).
