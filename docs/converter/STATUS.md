# Converter Editor -- STATUS / resume

**Branch:** `feat/converter-editor` (worktree `C:\Projects\Delphi-RAG-lint-converter`,
from `main@cf372f8`). **UNPUSHED** -- user holds push. Working tree clean.

## Milestone 1 -- unit-replacement rules: DONE (2026-07-20)

Design: `docs/converter/2026-07-20-converter-editor-unit-replacement-design.md`
Plan:   `docs/converter/2026-07-20-converter-editor-unit-replacement-plan.md`

8 commits (2 docs + 6 impl), each TDD + built + verified:

| # | Commit | What | Verified |
|---|--------|------|----------|
| 1 | `6666d1f` | engine parser recognizes `#use`/`#useswap` (parse-only) + CLI print-parsed labels | autotest 26/0, `#link` unregressed |
| 2 | `8c3a2ff` | editor model `rnkUse`/`rnkUseSwap` nodes + `UnitNodes` | model 117/0, byte-faithful round-trip |
| 3 | `6a229d0` | pure `ConvRules.Units` -- normalize (ADD/REMOVE, dedup, ADD-wins) + auto-derive | model 124/0 |
| 4 | `8ab81ff` | `TEngineAdapter.DeclaringUnitOf` (TcxButton -> cxButtons) | model 125/0 (real-index test) |
| 5 | `8dca2ab` | Unit Rules tab (add/delete/derive/check) + library filter | builds clean, headless load smoke |
| 6 | `ff6b91a` | docs: `#use`/`#useswap` in CONVERSION-RULES.md | -- |

**New DSL:** `#use <unit>`; `#useswap <Old> -> <New1>[, <New2> ...]` (sugar for
`#unuse Old` + `#use New...`). File-level; one-to-many; auto-derivable from
`#convert` types; deduped ("no doubles", ADD wins on conflict).

**Only shared/core file touched:** `src/report/DRagLint.Convert.Rules.pas` +
`src/cli/DRagLint.CLI.pas` (additive; the CLI/parser recognition). All else under
`src/tools/convrules-editor/`.

## NOT done (by design -- next phases)

1. **Live click-through of the Unit Rules tab** by a human (headless smoke only).
2. **Phase 2 -- the actual replacement:** teach `convert-apply` to EXECUTE
   `#use`/`#useswap` against a real `.pas` `uses` clause (add missing, remove
   unneeded, dedup, ADD-wins). The normalization rule is already specced +
   implemented pure in `ConvRules.Units.NormalizeUnitSets` -- reuse it.
3. **DFM inventory** (form-driven "add component as From") -- layers on library-first.
4. **Value/enum property casts** (old "Feature B").
5. **AI apply-by-name / library discovery** wiring.

## Build / test quick ref

- Editor:  `dcc64 -B ConvRulesEditor.dpr` in `src/tools/convrules-editor/`
  (worktree-targeted; the repo `build/_build_convrules_editor.bat` hardcodes the
  MAIN checkout path -- use a worktree wrapper).
- Tests:   `dcc64 -B -NS... ConvRulesModelTests.dpr` in `.../tests/`, run the exe
  (`model-tests: N pass / 0 fail`).
- CLI:     `build/build_draglint_win64.bat` (relative-path safe) -> stages
  `third_party/dll-win64/drag-lint.exe`.
- Autotest: `tests/autotest/run_convert_rules.ps1 -Exe <deployed drag-lint.exe>`
  (the `src/cli/Win64/Debug/` copy crashes -- missing tree-sitter DLL beside it).
