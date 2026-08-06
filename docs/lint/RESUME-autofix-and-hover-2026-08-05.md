# RESUME -- autofix coverage + hover defects (2026-08-05, evening session)

Read this first. Predecessor doc: `docs/lint/PLAN-lint-false-positives-2026-08-03.md`
(the ten defects from the earlier session -- all now committed).

---

## Status

Branch `main`. **Four commits, COMMITTED but NOT PUSHED.**

| commit | what |
|---|---|
| `9db27db` | the ten lint/index defects from the 2026-08-03/05 review (was uncommitted) |
| `02db60d` | hover content-sizing + user resize (was uncommitted) |
| `180dcbb` | **`lint --file` never handed the store over** -- IDE quick-fixes were dead |
| `fae61b6` | **hover follows the pointer**, signature moved to a title band |

Working tree is dirty with **the other group's stream only** -- do NOT `git add .`:
`FEATURES.txt`, `docs/editors/`, `docs/INBOX-editor-integration-and-delphilsp-union.md`,
`docs/INBOX-editor-native-extensions-and-build-orchestration.md`,
`docs/superpowers/specs/2026-08-05-delphilsp-union-design.md`.

Artifacts rebuilt and staged: `third_party/dll-win64/drag-lint.exe` and
`third_party/dll-win32/dclDragLintWizard.bpl` (+ `.dcp`).

Verification actually run:
- Full battery **215/215 PASS** (`pwsh`), after correcting the SARIF regression below.
- `run_pipeline_tests` 12/0 and `run_lint_tests` 156/0 re-run individually post-fix.
- `DataCopy.dproj` **compiles clean** (`BUILD_EXITCODE=0`, Win64 Debug, 28.5s) after 81 applied
  autofixes.

---

## 1. Autofix coverage -- the answer, with numbers

The question was "do we have an automatic fix for most of these messages (Delphi-case, adding F)?"

```
lint-all --db <DataCopy> --fix                     ->   8 fixable of 1130   (0.7%)
lint-all --db <DataCopy> --fix --config <opt-in>   -> 406 fixable of 1130   (36%), 4743 edits
```

| rule | findings | fixable | needs opt-in |
|---|---|---|---|
| `local-var-casing` | 367 | 324 | yes |
| `field-name-prefix` | 79 | 67 | yes |
| `redundant-parentheses` | 6 | 6 | no |
| `const-casing` | 5 | 4 | yes |
| `method-pascalcase` | 2 | 2 | yes |
| `reserved-word-casing` | 2 | 2 | no |
| `type-name-prefix` | 1 | 1 | yes |
| `doc-drift` | 6 | 0 | all 6 are report-only kinds |

**Why only 8 by default.** `DRagLint.CLI.pas:5298` requires `Cfg.IsAutoFix(F.RuleId)` for the six
naming rules -- they are opt-in via a lint config `"autofix": [...]` because they rewrite call sites
project-wide. DataCopy has no lint config, so all 454 naming findings were filtered out before
`BuildNamingFixEdits` was ever called. This is a deliberate design gate, NOT a bug.

`FIXABLE_RULE_IDS` (the full list of 17) is at `DRagLint.CLI.pas:4700`.

### What was applied to DataCopy

Pass 1 only -- `local-var-casing` plus the two always-on text rules -- restricted to the 12 units in
`DataCopy.dproj`, then compile-verified:

```
uConfigurationService 3   uMainZeissCopy 12   uFileUtils 14
uZeissRoutines       43   DPPRoutines     1   CSVRoutines  7   EExtraExceptionInfo 1
= 81 fixes across 6 files, .bak written for each
```

**Deliberately held back**, and why:
- `field-name-prefix` (67). drag-lint prints its own warning: a bare field read used as an expression
  operand (`X := client + 1`) is not indexed as a ref, so the fix can leave that site on the old name
  and produce code that does not compile, with exit code 0.
- `const-casing` / `method-pascalcase` / `type-name-prefix` (7 total). These route through the GLOBAL
  rename path, so the edit set spills into other files -- including the six retired legacy units that
  cannot be compiled on this machine, so the result would be unverifiable.
- The six retired legacy units entirely (`DataCopy2`, `CMMACPY`, `MainZeissConvert`, `DataCopy`,
  `Main_Copy_CSV_With_Tag`, `DPP2CSV_Main`). Not in `DataCopy.dproj`, cannot compile here.

Probe configs used (scratchpad, not in the repo):
`autofix-probe.json` (all six), `autofix-safe.json` (four), `autofix-pass1.json` (local-var only).

---

## 2. `lint --file` never passed AStore -- every IDE quick-fix was dead (`180dcbb`)

`FinalizeAndOutput` takes `AStore: ISymbolStore = nil` and gates every store-backed fix behind
`if AStore <> nil`. The single-file `lint` caller omitted the argument entirely.

```
lint --file uFileUtils.pas --db D --fix --fix-rule local-var-casing ->   0 fixable of 10
lint-all                   --db D --fix --fix-rule local-var-casing -> 324 fixable
```

`DragLint.Plugin.StructureForm` spawns `lint --file <F> --fix --fix-line <L> --fix-rule <id> --apply`
for "Fix it" and `lint --file <F> --fix --apply` for "Fix all in this file". So the six naming rules,
`doc-drift` and `missing-doc` could never be fixed from the IDE, while `lint-all` fixed them fine.

**The gate matters.** The store open is conditioned on `AArgs.Fix`. `OpenReadOnlyStore` writes a
schema-behind message to STDOUT; on `lint --db <older-db> --format sarif` that line lands inside the
SARIF document and it stops being parseable JSON. The first (ungated) cut of this fix broke
`tests/ergonomics/run_pipeline_tests.ps1` ("sarif parses", "sarif version 2.1.0") and
`tests/lint/run_lint_tests.ps1`. Both green with the gate.

---

## 3. Hover popup -- three reports, two of them one defect (`fae61b6`)

Reported after a live IDE session.

**(a) Signature line moved to a title band.** A one-line `TRichEdit` docked `alTop` with a hairline
separator, so the popup reads like the IDE's Code Insight window. Kept a rich edit (not a label) so
the per-token syntax colouring survives; `FEmitTarget` redirects `EmitSignatureHeader`'s runs. It is
still the definition link, now via `HandleTitleClick`; the "body line 0 is the definition" rule was
removed from `HandleMemoClick`, where it would otherwise fire on an ordinary content line.

**(b) The vertical scrollbar had a cause.** `FBody` is `WordWrap=False` + `ScrollBars=ssBoth`, so a
line wider than the client raises a HORIZONTAL scrollbar, which consumes `SM_CYHSCROLL` of the body's
own height and pushes the last line out of view -- bringing the vertical bar with it. They always
arrived together, which is why it looked like the body was simply one line short. Now the strip is
reserved when the widest BODY line really overflows (measured non-bold -- body text is not bold, and
measuring bold over-reserved). Moving the signature out also removes the widest line from the body.

**(c) "Wrong tab / previous popup" and "sometimes never pops" were THE SAME BUG.** The dwell tracker
placed the popup at the MOUSE but resolved its content from the CARET -- where the user last clicked.
Pointing at an identifier described whatever the caret sat on, in whatever unit that was. Not a stale
popup: a correctly-fresh popup about the wrong symbol. And because `FLastShownKey`/`FLastLspKey` key
on `(file,row,col)`, every token on a line produced the SAME caret key, so after one dwell the
"already shown for this caret" guard swallowed every later hover until the caret itself moved.

Fixed by resolving the cell under the pointer using the grid the gutter painter publishes.
`DragLint.Plugin.EditViewNotifier.PaintLine` now exports `GGutterCharWidth` (`CellSize.CX`) alongside
the existing line height; the IDE editor is fixed-pitch so the division is exact. Falls back to the
caret when the grid has not been painted yet.

Dwell cut 1.0s -> 0.6s (5 ticks -> 3). RAD Studio's own hover arms at roughly half a second, so 1.0s
always lost the race. **The remaining latency is not tunable here:** `TryBuildHoverModel` SPAWNS
`drag-lint hover --json` -- an out-of-process CLI start plus an index open. Closing that gap means
serving the model over the already-running LSP connection instead.

**Not verified in a live IDE.** All three compile clean; (c) is the one worth testing hardest.

---

## 4. IDE Messages window -- already shipping, no work needed

`Run Lint All` already posts every finding as a clickable `AddToolMessage` (double-click jumps to
file:line), capped at `LINTALL_MSG_CAP = 2000` per run --
`DragLint.Plugin.Editor.pas:4762` / `PostLintReportToMessages`. 1130 findings is well under the cap,
so they should all already be clickable.

---

## 5. DONE in the unattended window -- `uppercase-compare` split three ways + two new fixes

The rules turned out to be **declarative tree-sitter `.scm` queries under `rules\`** (loaded at
runtime from `<exe-dir>\rules`, sidecar `.json` for id/severity/message), not Delphi code -- so the
rule half needed no rebuild at all. `rules\README.md` documents the format and the supported
predicates, including `#match?` / `#not-match?`, which is what made the split expressible as data.

**The three-way split, exactly as asked:**

| shape | rule | severity |
|---|---|---|
| `UpperCase(S) = 'ABC'` -- literal agrees with the conversion | `uppercase-compare` | warning |
| `UpperCase(S) = 'abc'` -- literal CONTRADICTS it, can never be equal | `uppercase-compare-always-false` | **error** |
| `UpperCase(S) = '+'` -- no cased characters, `UpperCase` is a no-op | *nothing fires* | -- |

The always-false case is the one that mattered: a style rule was sitting on top of a correctness
bug. `'='` is unconditionally False and `'<>'` unconditionally True whatever the variable holds, so
the branch is dead. Now reported at **error** with its own message.

Each rule is TWO patterns because the exclusion is direction-dependent -- `UpperCase` must reject a
literal containing lowercase, `LowerCase` the reverse. The base rule uses `#not-match?` so the two
rules never double-report the same site.

**Three autofixes added** (`BuildAutofixEdits`, all pure text, no store needed), registered in
`FIXABLE_RULE_IDS`:
- `nil-comparison`: `X <> nil` -> `Assigned(X)`, `X = nil` -> `not Assigned(X)` (note the polarity
  inversion).
- `uppercase-compare`: -> `SameText(X, 'ABC')`, `<>` -> `not SameText(...)`.
- `uppercase-compare-always-false`: **recases the literal** (`= 'abc'` -> `= 'ABC'`) rather than
  rewriting to SameText. SameText would also work, but it changes case-sensitivity AND revives the
  dead branch in one step; recasing preserves the author's evident intent and changes one thing.
  Registered in `RISKY_FIX_RULE_IDS` -- a test that could never pass can now pass, which is the
  point, but a human must confirm the branch was meant to run.

Verified on a probe covering the edge cases (all 7 correct):
```
Obj <> nil                  -> Assigned(Obj)
Obj = nil                   -> not Assigned(Obj)
UpperCase(S) = 'abc'        -> UpperCase(S) = 'ABC'          (always-false recase)
LowerCase(Trim(S)) = 'ABC'  -> LowerCase(Trim(S)) = 'abc'    (nested parens)
UpperCase(S) = 'ABC'        -> SameText(S, 'ABC')
LowerCase(S) <> 'abc'       -> not SameText(S, 'abc')
UpperCase(S) = 'A<>B'       -> SameText(S, 'A<>B')           ('<>' inside the literal is NOT
                                                              mistaken for the operator: the
                                                              operator is sought only BEFORE the
                                                              first quote)
```

Fixture `tests/lint/uppercase-compare.pas` + `.expected` extended to 11 assertions covering all
three shapes in both directions. `uppercase-compare-always-false` added to `ScmCategory`'s
`bug-patterns` list (the only Delphi change on the rule side, and purely cosmetic).

**If a battery suite regresses on this**, the likely cause is another fixture that asserts
`uppercase-compare` on a literal that no longer qualifies (non-casable, or the always-false shape
which now belongs to the new rule id) -- check the `.expected` rather than assuming the rule is wrong.

---

## Not done yet -- in priority order

1. **New autofix: `unused-local` (44 findings).** Delete the declaration; the compiler proves it
   correct. Needs care collapsing a `var` block that becomes empty. Highest value of the remaining
   724 findings.
3. **Full battery re-run** after 1 (`pwsh tests/run_battery.ps1`), then rebuild + stage.
4. **Nine-DB manifest reindex to schema v19** (carried over from 2026-08-03):
   `drag-lint index --all --config third_party\dll-win64\drag-lint.json --jobs 0`
   (`--jobs` does nothing without `--config`), then fill section 6 of
   `docs/INBOX-index-schema-v19-reindex-for-converter.md`. Wants RAD Studio CLOSED.
   Note `--force-reparse` is needed once for the B1 unit-level-`var` extractor to take effect.
5. **Shellshock bisect** -- `docs/INBOX-parse-error-shellshock-units.md`: 3 units parse to 0 symbols;
   the `{$I+}` hypothesis is DISPROVED in the doc. Bisect `StShlCtl.pas` for the real construct.
6. **Answer the other group.** Their message puts three questions to us, the sharpest being whether a
   compiler-exact resolver subsumes their open finding 2.5 (bare `TEdit` resolving FMX-first, for
   which they proposed `--prefer-namespace Vcl`). Shipping both would be two overlapping mechanisms.
7. **Push** the four commits when ready (nothing has been pushed).

### Minor observations (for a later sweep, not filed)

- `--fix --apply` writes a `.bak` even for files where it applied NOTHING -- 10 `.bak` in
  `C:\Projects\DataCopy`, but only 6 files were actually changed. Harmless, but it makes "which files
  did the fixer touch?" unanswerable from the backups alone.
- `local-var-casing` reports 367 but only 324 are fixable, `field-name-prefix` 79 -> 67. The ~55
  skipped are silent (unresolved symbol / rename conflict). A `--fix --explain` that says WHY a
  fixable-rule finding produced no edit would make this self-service.

---

## Gotchas that will bite a cold start

1. **Run the battery with `pwsh`.** Under Windows PowerShell every `$proc.ExitCode` is null and all
   215 falsely FAIL while the per-runner logs show clean passes.
2. **Never rebuild `drag-lint.exe` while the battery runs** -- runners resolve
   `src\cli\Win64\Debug\drag-lint.exe` and a mid-run swap invents a phantom failure. Building the
   **BPL** during a battery IS safe (different artifact, not used by the runners).
3. **IDE availability changes what you can build.** While RAD Studio is open the BPL is LOCKED
   (cannot rebuild) and the LSP server can hold `drag-lint.exe` and the index DBs, blocking exe
   rebuilds and reindexing. **As of 2026-08-05 ~23:00 the user is AWAY for a few hours and the IDE is
   CLOSED**, so plugin rebuilds and the v19 reindex are unblocked in that window. Check
   `Get-Process bds` before assuming either way.
   Note also that `drag-lint.exe` rebuilds and a running reindex conflict with each other: a reindex
   holds the exe, so a rebuild cannot overwrite it. Sequence the two -- rebuild first, reindex after.
4. **Do not open a store on a non-fix `lint` path** -- see section 2. Gate on `AArgs.Fix`.
5. `deploy-staged.bat` REGRESSES the plugin: it copies the BPL from `C:\TEMP1\bpl_staging`, a July 5
   build. The plugin build writes straight to `third_party\dll-win32`.
6. Rebuilding the BPL needs RAD Studio CLOSED.
7. `index <folder> --db <large.sqlite>` never terminates -- see
   `docs/INBOX-incremental-index-hangs-on-large-db.md`; commit-then-kill workaround.
8. Never `COLLATE NOCASE` on `symbols.name` (measured: query 0.63s -> 2.77s). `refs.name_text` is
   free and already does.
9. Delphi lookups go to the **drag-lint index first, Grep second** -- including in this repo. The
   self-index is `C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`; it was refreshed this session
   (`index src --db ...`, 34s, 9 files reparsed).
