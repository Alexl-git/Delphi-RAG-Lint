# CONVERTER backlog -- delayed tasks (do not lose; do not read every session)

Created 2026-10-16 from the resume doc, the archived 1.27 adoption ledger and the
editor CLAUDE.md hand-over notes. A handoff LINKS to this file instead of
repeating it. Open it when picking the next converter job, not at session start.

**Re-triaged 2026-10-19** against pin `1.31.5-alpha-20261019-071827`, branches
`feat/convert-qualify-fix` (A2 done, worktree `..-wt\conv-qualify-fix`, HEAD 158bc5ae) and
`fix/converter-c-minors` (section C done except C-2, worktree `..-wt\conv-c-minors`, HEAD
68d4900f), both NOT merged. Every B item was measured with the pin's `drag-lint.exe` on a
scratch fixture (`scratchpad\agent-retriage\fx\`, dry run, scratch DB only; captures
`apply-batch.json`, `apply-gap.json`, `apply-skip.json`, `apply-desc.json` beside it).
Sizes S/M/L; model = haiku / sonnet / session (owner rule 2a).

**Status caution:** measure against the tree before working on an item; the two branches
above change what is true once merged.

## A. Queued work, in order

1. **C18 member replacement, slice 1** (`#migrate X -> Y` / `-> DL_NONE` + rename) --
   M, session. Gate: engine 1.22 (product 1.32.0) released and the **one re-pin** done
   (verify the sha yourself; procedure: editor CLAUDE.md "Re-pin"; baseline model tests
   are now **2249** on the qualify-fix branch, see 2d887f65; 13 drivers). Contract:
   `docs\NOTICE-2026-10-19-c18-slice1-migrate.md` (not yet written on 2026-10-19 -- do not
   start before it exists); spec `docs\superpowers\specs\2026-10-11-member-replacement-design.md`
   (owner answered Q1-Q4, Q5 deferred). Re-judge lint after the re-pin (new rule
   `confusable-identifier`). Re-capture the `tests\fixtures\apply1270\` rows needs item
   N3 first (capture project gone).
2. **Merge `feat/convert-qualify-fix` and `fix/converter-c-minors` to main** -- M,
   session (whole-branch review: lint the full `merge-base..HEAD` diff with the markers'
   `--enable` set, run the model tests + the touched drivers on the pin, announce the
   merge). c-minors carries the `ParseApplyJson` default change (`AFeatures = []`); the
   qualify-fix worktree still has the old default (`ConvRules.ConvertRun.pas:148-150`,
   signature at the `ParseApplyJson` declaration) -- resolve on merge.
3. **N1 Convert click lost while an analysis or Save validation is pending** -- M,
   session (root cause unconfirmed; driver repro first). See New items.
4. **B-batch: adopt the 1.31.5 apply/1 keys the editor already receives but drops** --
   B1 `only_matched[]/only_unmatched[]`, B3 index-gap refusal wording, B6 `descendants[]`,
   B7 `only_included[]`/`unlinked[]` -- M in total, sonnet (one plan, pure `ConvertRun`
   parse + note + report lines + model tests on the captures above).
5. **B8 half-apply guard on the engine's exit contract** -- M, sonnet.
6. **B9 `#warn` / `#check-ref` in the Model + display + BDE book lines** -- M, sonnet.
7. **D1 + N5 driver fixes** (`drive-file-menu.ps1` exit code; work-list clipboard retry)
   -- S, haiku.
8. **N2 QualifyFix retarget mutant test** -- S, sonnet.
9. **B4 runner batch mode** (`apply-batch/1`) -- L, session (changes the per-unit
   backup/restore/reindex loop).
10. **D4 / D6 qualify follow-ups** -- M each, sonnet, only if the owner wants them.
11. **B10 `inherited_code_unconverted` model test on a real capture** -- S, sonnet.
12. **N3 re-create the apply1270 capture project as a script** -- M, sonnet (before A1's
    re-capture).

## B. Engine-contract follow-ups (re-triaged 2026-10-19 on the 1.31.5 pin)

Legend: engine = what the pin's apply/1 JSON provides (measured); editor = what the
branches parse (`ParseApplyJson`, `ConvRules.ConvertRun.pas:1352-1399` reads only
`ok, converted, items, uses, uses_unresolved, uses_reindex, inherited, qualify_fixes,
pas_uses, reemit_notes, rule_errors, warnings, refused, reason, edits_count,
component_part`).

- **B1 Scoped note from `only_matched[]` / `only_unmatched[]`** -- STILL-OPEN, S, sonnet.
  Engine: both arrays on every unit, always present (`--only Label1,Label9,Nope` on
  FixUnit -> `only_matched ["Label1"]`, `only_unmatched ["Label9","Nope"]`). Editor: not
  read; `ConvRules.ConvertRequest.pas:258` still says "interim until the engine's
  only_matched[] is adopted" (`UnmatchedOnlyHintFor`, `:262`).
- **B2 E10 refusal hint gated on `only_skips_unit_rules`** -- DROP (owner may overrule).
  With uses reconciliation (1.27.0, default on) the engine KEEPS a watched unit instead
  of refusing ("R26's refusal becomes this", `--help`); the editor never passes
  `--no-reconcile-uses` (`ConvRules.Engine.pas` builds only `--only` / `--castlib`,
  `:1474`). Measured: `#unuse Vcl.StdCtrls` + `--only Label1` -> `ok=true, refused=false`,
  no `uses[]` row, no `unit-rule-skipped` item. `RefusalHint`
  (`ConvRules.ConvertRequest.pas:266-271`) can no longer fire on this pin; delete it with
  its test instead of gating it (S, haiku) -- or keep as dead code.
- **B3 C13 index-gap REFUSED shown as "fix the index", not "edit the book"** --
  STILL-OPEN, S, sonnet. Engine: exit 1, `refused=true`, `reason` = "Nowhere.TGhostLabel
  (line 1) resolves in no --db -- index gap in the library or project index; reindex, or
  report it, before converting" (`apply-gap.json`). Editor: generic csRefused
  'refused -- not changed' + the reason (`ConvRules.ConvertRunner.pas:1068-1076`,
  `:498`); no 'index gap' text anywhere in the editor (`query --text` 0 hits). Pure
  classifier on the reason -> a note that names the reindex, not the book.
- **B4 Runner batch mode (`batch_units`, apply-batch/1)** -- STILL-OPEN, L, session.
  Engine: two `--unit` -> ONE `apply-batch/1` document `{schema, mode, rules_file,
  units_count, ok, exit_code, ok_count, refused_count, failed_count, classes_built,
  units[]}` with one apply/1 per unit (`apply-batch.json`). Editor:
  `TEngineAdapter.ApplyConversion` takes one unit (`ConvRules.Engine.pas:1479,1484`);
  the runner reindexes between every unit x book (`ConvRules.ConvertRunner.pas:3-10`).
  Design needed: backups, per-unit restore and the reindex cadence all change.
- **B5 C8 code refs: keep only refs RESOLVED TO A FIELD (E5)** -- DROP (owner may
  overrule). The editor-side code-use note is already OFF when the engine reports
  `inherited_retype` (`CodeUseNoteDue`, `ConvRules.ConvertRunner.pas:371-380`; ruling M4:
  the engine's `inherited[]` is authoritative), and the pin reports it. The unfiltered
  refs (`ConvRules.InheritanceEngine.pas:154-159`) now only feed the pre-run C8 offers.
- **B6 Show `descendants[]` on the converted ancestor's row + report** -- STILL-OPEN, M,
  sonnet. Engine: `descendants [{unit:"DescUnit", name:"Label1", type:"TLabel", line:4,
  reason:"both"}]`, item kind `descendant-not-converted`, and a `warnings[]` line.
  Editor: no `descendants` key read, no `TApplyRow` field (`:153-222`); the text reaches
  the user only through `Remainder` (`warnings[]`). Typed row note + report line.
- **B7 Distinct texts "rolled back" vs "PARTLY converted"; show `only_included[]`;
  surface `unlinked[]`** -- split: texts DONE (`ConvertStatusText`,
  `ConvRules.ConvertRunner.pas:494-501`: 'rolled back' / 'FAILED -- restored' /
  'FAILED -- NOT restored' / 'refused -- not changed'; the half-written case has its own
  `HalfWrittenNote`, `ConvRules.ConvertRun.pas:1448`); `only_included[]` / `unlinked[]`
  STILL-OPEN, S, sonnet (engine: `unlinked [{from_type:"TLabel", path:"Hint", sites:1,
  instances:1}]`, `unlinked_source_properties`, `only_included []`; editor reads none;
  the unlinked warning text reaches `Remainder` only).
- **B8 Tighten the half-apply guard to the engine's all-or-nothing exit contract, drop
  the text match** -- STILL-OPEN, M, sonnet. Editor: `RefusalParts` /
  `ApplyEditSetRefused` regex-match `EditRefusals` text lines
  (`ConvRules.ConvertRun.pas:1425-1456`, `EDIT_REFUSAL_PATTERN`), and
  `ConvRules.ConvertRunner.pas:1080` still describes "ok=true and exit 0 but one file's
  edit set refused". Engine 1.25.1+: a failed write is rolled back byte-identical, exit 2,
  `ok=false`, `refused` is a JSON bool, `reason` the text (`--help`); measured
  `refused=false, reason=""` on every clean run. The pin is past 1.25.1, so the text
  path is legacy.
- **B9 E17 `#warn` / `#check-ref`: parser round-trip + display; then add them to the
  BDE book** -- STILL-OPEN, M, sonnet. Engine: capabilities `book_warn`, `check_ref`
  true (ENGINE-PIN.json); `#warn Caption "caption streamed: <value>"` -> item kind
  `book-warning {instance, path, text, line, rule_line, value}` + a `warnings[]` line
  (`apply-batch.json`). Editor: no `'#warn'`, `'#check-ref'`, `BookWarn`, `CheckRef`
  in any editor `.pas` (grep 0) -- the Model does not know the directives.
- **B10 1.26.7 `inherited_code_unconverted`: `CodeUseNoteDue` per engine state + a
  model test on a real capture** -- STILL-OPEN, S, sonnet. Engine: DescUnit alone ->
  `inherited [{action:"skipped", ancestor_state:"unconverted", reason:"declared in
  FixUnit, which still has TLabel -- convert FixUnit first (recommended)"}]`,
  `component_part "skipped-no-instances"` (`apply-desc.json`). Editor: parses
  `action` / `ancestor_state` (`ConvRules.ConvertRun.pas:1212-1213`, wording
  `:1540-1553`), but no `CAPABILITY_INHERITED_CODE_UNCONVERTED` const
  (`ConvRules.Engine.pas:65-108`) and `CodeUseNoteDue` gates on `inherited_retype` only
  (`ConvRules.ConvertRunner.pas:380`). Add the capability + a test on `apply-desc.json`.
- **B11 1.26.2 castlib key `dfmdata`** -- DONE. The shared parser reads it
  (`src\report\DRagLint.Convert.CastLib.pas:441`, field `DfmData` `:46`); the pin's
  `casts.castlib` carries `dfmdata graphic` (ENGINE-PIN.json "castlib"). Optional S/haiku:
  show `DfmData` in the cast option's Detail (`ConvRules.ConvCatalog.pas:56-62`, c-minors).

## C. Deferred minors (owner reworks)

Worked on `fix/converter-c-minors` from the plan
`docs\superpowers\plans\2026-10-19-converter-c-minors.md` (groups A-E done:
f00e5d2d, edfa6f12, 582b8359, 867972f4, d2c20bd0, 86252f0b, 68d4900f; NWI items 3 and 7
closed with reasons in the plan's triage table). Open:

- **C-1 Picker does not offer StripDB for a `TFileName` From** -- BLOCKED on ENGINE:
  routed to the engine's `casts.castlib` (`accepts string, TFileName`), plan 3.1
  recommendation (a); asked in
  `docs\INBOX-REPLY-2026-10-19-converter-to-engine-qualify-and-castlib.md:20`. No editor
  code; verify the picker after the castlib ships (S, haiku).
- **C-2 A preflight-refused Convert keeps the previous Work list** -- BLOCKED on the
  owner: plan 3.2, options (a) accept + reword `WorkList.pas:133-134`, (b) empty
  `TWorkRun` on refusal, (c) stamp the summary. Recommendation (a); S, haiku once chosen.
- Plan 3.3 (depth combo on `bdsInvalid` / `bdsDuplicate`) -- DONE as option (b),
  86252f0b.

## D. Test-kit debts

- **D1 `drive-file-menu.ps1` exits 0 even with a FAIL** -- STILL-OPEN, S, haiku. The
  script ends at the summary line (`tests\gui\drive-file-menu.ps1:295`, same on both
  branches); `drive-engine-wait.ps1:334` has the pattern to copy
  (`if ($script:fail -gt 0) { exit 1 }`). Audit the other 11 drivers in the same pass.
- **D2 `drive-engine-wait.ps1` `wait.reload.no.window` flaky since 1.25.2** --
  STILL-OPEN, M, sonnet. Check at `:330`; `WaitIdle` (`:316`) filters engine children by
  `ParentProcessId` only, no start-time filter (the reused-PID trap in the editor
  CLAUDE.md). Repro under load before changing it; the "rerun alone under machine load"
  note from the old D3 is folded in here.
- D3 (old) "fail once under load -- rerun alone" -- DROP as an item (a note, not work;
  kept inside D2).
- **N5 `drive-work-list.ps1` clipboard check flakes when another process holds the
  clipboard** -- STILL-OPEN, S, haiku. `:494-500` `Set-Clipboard` / `Get-Clipboard` once,
  no retry; retry 5 x 200 ms and report a clipboard that cannot be opened as SKIP, not
  FAIL.

## E. Housekeeping (owner)

- **Instruction-file trim** -- DONE 2026-10-19 (verified): editor CLAUDE.md is 7,555 B
  (was 135 KB); the hand-over notes are in
  `docs\handoffs\archive\convrules-editor-HANDOVER-ARCHIVE.md` (136,748 B); the
  drag-lint block lives once in the global CLAUDE.md; MEMORY.md carries an index
  (`lessons_index.md`).
- **Editor CLAUDE.md test-kit values are stale** -- S, haiku, after A2 merges: it says
  "2194 pass / 5 fail on the 1.27.0 pin"; the qualify-fix branch measured 2249 on the
  1.31.5 pin (2d887f65), and A2 adds a 14th driver (97c6e234). Re-measure on the merged
  tree, then edit the numbers.
- **Worktrees are outside the drag-lint manifest** -- DROP as a defect, S doc line
  (haiku). The editor has no `.dproj` anywhere (main tree too: only
  `ConvRulesEditor.dpr`, `tests\ConvRulesModelTests.dpr`), so `resolve-dbs --project`
  and `--in` answer "no index covers" for a worktree. The DBs under
  `<wt>\src\tools\convrules-editor\_D-RAG\` ARE the right layout; add one line to the
  editor CLAUDE.md: in a worktree pass `--db <wt>\src\tools\convrules-editor\_D-RAG\
  ConvRulesEditor.sqlite` explicitly and index with `index --project ConvRulesEditor.dpr`.

## New items (2026-10-19)

- **N1 Convert clicked right after adding a unit or after Save silently does nothing**
  -- STILL-OPEN (medium), M, session. Hypothesis, unconfirmed: the C8 analysis after an
  add runs under the modal progress window (`ConvRules.ConvertTab.pas:937-962`,
  `FAnalyzing` inside `FHost.RunLongCall`), Save's scoped validation likewise
  (`ConvRules.MainForm.pas:7505` `RunScopedValidate`); a click that lands while the
  main window is disabled is dropped, and `ConvertClick` (`:1353`) then never runs --
  every refusal inside it sets a status (`:1382, :1397, :1415, :1427`), so "nothing on
  the status bar" means the handler was not entered. Repro with a driver first (click
  at T+0 after Add / after Ctrl+S), then decide: disable the Convert button while
  `FAnalyzing` / validating, or queue the click.
- **N2 Mutant "retarget ignores Applied" in `ConvRules.QualifyFix` survives** --
  STILL-OPEN (low), S, sonnet. `ApplyQualifyPicks`, `ConvRules.QualifyFix.pas:305`:
  `if Result[J].Applied and (same RuleLine) and (same Current)`; the only test on that
  path, `qualify.apply.retarget.wrong.side` (`tests\ConvRulesModelTests.dpr:13421`),
  passes with `Result[J].Applied` removed. Add a pick J that is refused (NodeIndex
  stale) followed by a pick I on the same line: I must go through `ApplyQualifyPick`,
  not `ApplyAt(LRetarget)`.
- **N3 The `tests\fixtures\apply1270` capture project (`C:\fix\`) is gone** --
  STILL-OPEN, M, sonnet. `Test-Path C:\fix` = False; the captures name it
  (`apply-cast-site-1270.json`, `apply-exit6-castlib-1280.json`,
  `apply-pas-uses-1270.json`: `C:\\fix`). Write `tests\fixtures\apply1270\recapture.ps1`
  that builds the project in a temp folder from text (the `drive-convert-tab.ps1:300-398`
  template, extended with the cast-site / StripDB / pas-uses shapes the captures need),
  indexes it into a scratch DB and runs each capture command; needed before A1's
  re-capture.
- **N4 Worktree has no `.dproj`, `resolve-dbs --project` fails** -- see E (DROP as a
  defect; one doc line).
- **N5 Work-list driver clipboard flake** -- see D.
- **N6 Qualify follow-ups D4 (clickable `#use` alternative) and D6 ("Qualify all")** --
  STILL-OPEN, M each, sonnet, after A2 merges; spec
  `docs\superpowers\specs\2026-10-19-convert-qualify-fix-design.md:331-341` (D4 option B
  through `InsertUnitNode`; D6 option B needs the cross-book open loop). Owner to say
  whether either is wanted.
- **N7 C-2** -- see C (BLOCKED on the owner).
- **N8 C-1** -- see C (BLOCKED on ENGINE).
