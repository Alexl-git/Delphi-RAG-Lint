# Design: `duplicate-code` clone detection (v0.77 item #6)

> Authored 2026-07-01 (brainstorming). Closes the largest remaining MISSING-FEATURES
> #6 item: clone / duplicate-code detection. Read `docs/lint/PLAN-v076-close-sections.md`
> Phase 3 for how this fits the v0.77 milestone.

## Goal

Detect duplicated code: report pairs of routines (or blocks within them) that share a
long identical run of normalized tokens. Pure-AST, no persistent cross-invocation index.

## Decisions (locked in brainstorming)

| Axis | Decision |
|------|----------|
| Clone type | **Type-2 (renamed)** -- identifiers and literals normalized to placeholders so copy-paste-and-rename copies still match. NOT Type-3 (no statement reordering / structural canonicalization). |
| Scope | **Within-file AND cross-file** (project-wide, within a single `lint-all` run). |
| Granularity | **Sub-routine maximal token runs** >= threshold (not whole-routine-only). |
| Severity / default | **`info`, ON by default**, conservative threshold calibrated to ~0 FP on `src/`. |
| Algorithm | **Rolling-hash windowed maximal-match (Rabin-Karp).** |
| Rule id / category | **`duplicate-code`** in category `complexity`, with `MkParam('threshold','int','<W>')`. |

Rejected: suffix-array/automaton LCS (much more code+memory, no practical gain at our
thresholds); whole-routine body hashing (misses partial clones -- granularity decision rules it out).

## Architecture

New isolated unit **`src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas`** -- one job:
given N parsed files, find duplicated normalized token runs. Two public class methods on
`TCloneChecker`:

- `class function Check(const AFile: string; AMinTokens: Integer = <W>): TArray<TLintFinding>;`
  Single file -> within-file clones only. Parses `AFile` (via `TAstParseCache.Get`), runs
  the engine over that file's routines. Wired into the single-file `lint` path
  (`DRagLint.CLI.pas` DoLint, near the other per-file checks ~4905). Testable via `tests/lint`.

- `class function CheckProject(const AStore: ISymbolStore; AMinTokens: Integer = <W>): TArray<TLintFinding>;`
  Iterates `AStore.GetAllFileIds`, resolves each path (`GetFilePath`), parses via
  `TAstParseCache.Get`, runs the engine over ALL routines across all files -> within +
  cross-file clones. Wired into `DoLintAll` near `ProjectRules.Run` (~5827). Testable via a
  multi-file `tests/lint-store/duplicate-code/` case.

**No double-reporting rule:** in `lint-all`, ONLY `CheckProject` runs; the per-file `Check`
is NOT invoked from the DoLintAll per-file loop. `Check` runs only in the single-file `lint`
command. This mirrors how project rules (circular-uses) are separated from per-file checks.

**Why the AST is available project-wide:** `ProjectRules.Run` already parses every file via
`TAstParseCache.Get(path)` keyed by file path (see `ProjectRules.pas` ~159, ~290). The store
supplies the file list (`GetAllFileIds`/`GetFilePath`); the parse cache supplies the AST/tokens.
The store does NOT need to hold tokens.

## Component 1 -- token extraction + Type-2 normalization

For each routine (`defProc` node) in a file, walk its body subtree collecting **leaf tokens**
(nodes with `ChildCount = 0`). Map each leaf to an `Int32` code:

- identifier token  -> sentinel `TOK_ID`   (single fixed code)
- numeric / string / char literal -> sentinel `TOK_LIT` (single fixed code)
- everything structural (keywords, operators, punctuation) -> its grammar `Symbol` id
  (`TTSNode.Symbol`, a stable UInt16), offset so it never collides with the sentinels or barriers.

Per token, retain metadata: `(FileIndex, RoutineName, Line)` (`Line` from `StartPoint.Row + 1`).

**To resolve during implementation (grammar-probe, same discipline as the `case`-keyword-children
and `.NodeType`-on-NULL gotchas):** the exact node-type strings that count as identifier vs literal
in this tree-sitter-delphi grammar. Probe a sample `.pas` and confirm (candidates: identifiers =
`identifier`/`ident`; literals = `literalNumber`/`literalString`/`char`/`literalFloat`...). Guard every
`TTSNode` access with `.IsNull` before `.NodeType`.

**Nested routines:** a `defProc` local to another `defProc` is its own routine (own token stream);
do not include a nested routine's tokens in the outer routine's stream (mirror the existing
"recurse into nested defProcs" handling in DeadCodeChecks).

## Component 2 -- matching engine (Rabin-Karp maximal-match)

1. Concatenate every routine's token-code array into one global array `G`, inserting a **unique
   barrier sentinel** between routines (each barrier a distinct negative code) so no window/clone
   can span two routines.
2. Window size `W = AMinTokens` (the threshold). For every start index `i` where the W-window does
   not cross a barrier, compute a Rabin-Karp rolling hash `H(i)`.
3. Bucket: `TDictionary<UInt64, TList<Integer>>` mapping hash -> start indices.
4. For each bucket with >= 2 starts, for each candidate pair `(i, j)`:
   - **Verify** `G[i..i+W-1] = G[j..j+W-1]` exactly (guard against hash collision).
   - **Extend right** while `G[i+k] = G[j+k]` and neither side crosses a barrier -> match length `L >= W`.
   - **Left-maximal dedup:** only accept the pair if it is NOT a right-shift of an already-accepted
     match (i.e. `G[i-1] <> G[j-1]` or a boundary) -- prevents reporting the same maximal run W times.
   - Skip pairs whose two occurrences are in the **same routine and overlap** (`|i - j| < L`).
5. Result: a set of maximal clone pairs, each `(startA, startB, L)`.

Complexity O(|G|) hashing + near-linear verification (collisions rare with a 64-bit rolling hash).

## Component 3 -- reporting

One `info` finding **per clone pair**, anchored at the **second** (later) occurrence's routine line:

```
duplicate-code  <fileB>:<lineB>
  message: "Duplicated code block (<L> tokens) -- also at <fileA>:<lineA>"
```

Within-file pairs: both sites in the same file. Cross-file: `<fileA>` differs from `<fileB>`.
De-dup identical (siteA, siteB) pairs so a pair is reported once. Deterministic ordering
(sort findings by file then line) so harness output is stable.

## Rule wiring (standard add-a-rule pattern)

- `RuleCatalog.pas`: `B('duplicate-code', 'complexity', 'info', 'Duplicated code block detected (Type-2, renamed-identifier tolerant)', True, [MkParam('threshold','int','<W>')]);`
- `CLI.pas`: allow-list guard + `--help` line + DoLint dispatch calling `TCloneChecker.Check`;
  DoLintAll calls `TCloneChecker.CheckProject(Store)` after the per-file loop (NOT per-file).
- Threshold plumbed from config `threshold` param (like cyclomatic/cognitive), default `<W>`.
- Catalog tests are relative -> no count bump needed.

## Testing

1. `tests/lint/duplicate-code.pas` -- two routines with the **same logic, renamed variables**
   (proves Type-2) whose shared run exceeds the test threshold; `expected`: `duplicate-code <line>`.
   Use a low `duplicate-code.config.json` threshold so a compact fixture triggers it.
2. `tests/lint/duplicate-code-none.pas` (or `!duplicate-code`) -- two superficially similar but
   genuinely different routines, assert NO finding.
3. `tests/lint-store/duplicate-code/` -- two `.pas` units containing the same block; `lint-all`
   over the case dir reports a **cross-file** `duplicate-code` finding (fileA:line <-> fileB:line).
4. **FP-sanity over `src/`** to set the shipped default `W`: start at 60 tokens, raise until
   findings on `src/` are ~0 / all legitimately-duplicated. Record the chosen default in CHANGELOG.

## Scope guard (YAGNI)

- Type-2 only: normalize identifiers + literals. No Type-3 (no statement reordering, no
  gapped/near-miss clones, no AST-subtree canonicalization).
- Cross-file = within one `lint-all` invocation only. No persistent cross-run clone index.
- No autofix (clones need human judgment to extract).
- Report pairs, not clone *classes* (N-way clusters); a 3-way clone surfaces as its constituent
  pairs. Acceptable for v0.77.

## Release

Folds into the v0.77 milestone alongside the CK suite and M2-flow items. Standard recipe
(`docs/lint/PLAN-v076-close-sections.md` "Release recipe"): build Win64, run
`run_lint_tests.ps1` + `run_store_tests.ps1` + `run_rulecatalog_tests.ps1`, FP-sanity, bump
VERSION/CHANGELOG, pack, tag, gh release. Ship v0.77 only when the other chosen items land too
(user directive: all of v0.77).

## Post-implementation calibration (2026-07-01)

Implemented on branch `feat/duplicate-code-clone-detection` (v0.77). Two refinements emerged from
FP-sanity on the project's own `src/` (110 files):

1. **Overlap suppression added.** The initial left-maximal dedup did not collapse self-similar
   repetitive regions (e.g. `PrintHelp`'s 58 consecutive `Writeln('...')` statements, long
   `case`/catalog lists), which produced hundreds of overlapping re-reports of one region. The
   engine now collects all candidate maximal matches, sorts them longest-first, and emits a
   candidate only if it is not already >= 50% covered on BOTH occurrences by a previously-emitted
   (longer) clone. This collapses the family to one finding per genuinely-duplicated region-pair.

2. **Literal normalization kept (user decision).** Literals remain normalized to a single `LIT`
   placeholder (so a copy that changed only string/number constants is still flagged), with the
   overlap suppression above taming the resulting DSL-block noise.

**Default threshold = 90 tokens** (near the PMD CPD default of 100, lowered so a verbatim copy of a
~12-line routine -- about 96 tokens -- is caught out of the box; a real BASICSF.pas copy sat at 96
and slipped under 100). Measured `duplicate-code` counts on `src/` after overlap suppression:
60 -> 446, 80 -> 260, 90 -> ~190, 100 -> 142, 120 -> 81, 150 -> 43, 200 -> 18. At 90 the surviving
findings are genuine structural duplication (spot-verified, e.g. the `while`/`for` CFG-emit blocks
in `DRagLint.Analysis.Cfg.pas`, and whole-routine copies). Tunable per-project via the
`threshold` param. Per-bucket comparison is capped at 400 windows (a stderr note is emitted when a
bucket is skipped -- no silent cap).
