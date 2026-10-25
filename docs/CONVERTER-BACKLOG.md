# CONVERTER backlog -- delayed tasks (do not lose; do not read every session)

Created 2026-10-16; **rewritten 2026-10-19** from the re-triage proposal
`docs\handoffs\CONVERTER-BACKLOG-proposed-2026-10-19.md` (full measurements, file:line
evidence and the engine JSON shapes live THERE -- open it when working an item) with the
owner's 2026-10-19 answers applied. A handoff LINKS to this file instead of repeating it.
Open it when picking the next converter job, not at session start.

Sizes S/M/L; model = haiku / sonnet / session (owner rule 2a). **Measure against the tree
before working on an item.**

## State 2026-10-23 (autonomous run 20261023-1100-converter3d) -- supersedes the lists below

* DONE on local main: A1 re-pin (1.33.0, 10-20), A2/A3 merges (faffc407, d7a289ba),
  C-1 (ENGINE castlib 8d0e2e3b + test 06439a4e), E2 (3200fc0e), B2 (c8e33da7, caller removed
  too), B9 (Model part was in faffc407; BDE book lines 8af2f8a5), N3 (e17f455c, 9ff9b242:
  recapture.ps1 + fixtures on 1.33.0), N2 / D4 / D6 (already in faffc407; verified, N2 mutant
  RED/GREEN), item F (registry review, 20ffb523). Item F's URL form is
  `/help/dl/features/<id>/`, not `/help/<id>/` (www-40, 2026-10-23).
* A4 #migrate: spec + plan written 2026-10-23 (`docs\superpowers\specs|plans\2026-10-23-converter-migrate-slice1*`,
  gitignored). OWNER DECIDED 2026-10-24: all recommendations, with D0 = B (build after ENGINE's
  final deploy + re-parse + re-pin, dropping the G4/G7/G8/G9 workarounds); D5 and D6-B as
  follow-ups. Spec section 12a records it. NEXT after the re-pin.
  Engine gaps G8/G9/G10 filed `docs\INBOX-2026-10-23-converter-to-engine-migrate-gaps.md`
  (ENGINE lane e3d/migrate-gaps).
* DONE later the same day: N1 (9941b39e), D2 (ecc90bfd), B10 (45c149e1), Qualify-all driver
  (dea6c6f4), featuregen site fields (02b11037), **B4 batch mode** (2b713460..eec26734; model
  2571/5/0, drive-convert-batch 22/0). Pin 1.33.0-alpha-20261021-122057 ADOPTED (2460/5, 14
  drivers; pin editor = main 1dc238da build).
* Owed after ENGINE's final deploy (end of day 3, owner rule: no approval-needing step mid-run):
  `featuregen verify --id convert-apply` / `convert-scaffold --by CONVERTER`; re-pin + baseline.
* DONE in wave 3: **N9** 6b21a559 (drive-convert-tab 3b fails cleanly without the progress
  window); **N8** e52df7bb (converted-ancestor code use with mapped pas_uses is not "left");
  **N7 + N11** a246e716 (`ConvRules.InputGate` on Application.OnMessage refuses main-form
  clicks/commands while busy, reports the first, never queues; `ConvRulesEditor.Busy` message for
  drivers' WaitIdle; drive-convert-tab 32/0 x6, batch-driver Add retry removed; model 2615/5/0).
* Open todos from this run:
  * DONE: **N7 leftover** 72ec46ed (drive-engine-wait 9 -> 16: File|Save under the progress
    window refused + reported; the Ctrl+S check cannot go red -- regression guard only);
    B4 test-dpr lint debt 328f8569 (44 -> 0 on B4 lines); **N10** in the run's scratch
    `gui-lock.ps1` (stale = over 60 min, or over 10 min with no ConvRulesEditor running;
    positive + negative control passed) -- the lock is scratch, not tracked.
  * DONE 2026-10-24: **FG-M + FG-N** merged 8234fe33 after ENGINE's 1.34.0-alpha deploy
    (0b308ab9); featuregen 244/0, registry + docs-sync guards PASS; convert-apply /
    convert-scaffold verified by CONVERTER on 1.34.0-alpha. Also helpOrder tiebreak 2c912ce4 and
    the frozen-banner test 65550658.
  * **FG-O** (medium) `Live.HarvestEveryKindNonEmpty` (FeatureGenTests.dpr ~1914) crashes with an
    AV (EmptyLiveKinds(nil)) instead of failing cleanly when the harvest raises -- e.g. on a stale
    plugin DB, where menu-tree exits 3. Make it report a FAIL.
  * **FG-P** (low) run_feature_registry_guard.ps1 needs pwsh 7.3; under Windows PowerShell 5.1 it
    errors. Say so in its header or make it 5.1-safe.
  * **Re-pin** after ENGINE's "re-parse done" (engine 1.34.0-alpha, sha 7EF273E2...), full
    baseline, then **A4** slice 1.
  * **FG-M** featuregen: Harvest via `menu-tree --format json`, path-based checks B/C, caption-key
    parity vector, drop 14 stale exemptions (in flight, branch feat/conv-fgm-menu-tree).
  * B4 left 44 findings (magic numbers, `C:\fix` fixture paths) on its lines in
    ConvRulesModelTests.dpr (file total 509, outside the editor DB) -- fold into the D-list test debt.
  * `GlyphForm.pas:60` unused `dl:ok` marker (review-marker-unused).
* E3 + this run's worktrees `C:\Projects\Delphi-RAG-lint-wt\conv-*`: owner removes (approval).

## State at the rewrite

* Pin `third_party\engine-pinned\1.31.5-alpha-20261019-071827`; re-pin to 1.32.0-alpha
  (extractor 1.22) waits for ENGINE's "re-parse done".
* On main (pushed 4fa585c4): A2 qualify fix (3cdadd60), C minors + `#depth` repair (1d888db1).
  Merged-tree baseline on the 1.31.5 pin: model tests 2281 pass / 5 fail (VARINSP), 14 drivers.
* Unmerged, under review: `feat/converter-apply-fields` (B1 B3 B6 B7 B8, C-2, B4 helpers) and
  `fix/converter-testkit` (D1, N5); worktrees `C:\Projects\Delphi-RAG-lint-wt\conv-apply-fields`
  and `conv-testkit`.

## F. Feature-registry review (owner request 2026-10-20, via www-2a) -- after E18 + next release

CONVERTER owns the coordination (featuregen is ours); each team (ENGINE, CONVERTER, CHARTS,
YADF) reviews its OWN entries. Start only after ENGINE E18 is merged AND the next release is
published. Not urgent. Review every entry for:

* (a) outdated features (owner saw at least one stale item on the GitHub wiki);
* (b) features with no IDE menu access;
* (c) features needing 2-3 IDE clicks: spell out "where to click"; owner wants unique help ids
  at that granularity (one page per id, maybe anchors per click path).

**Registry ids are now PUBLIC URLs** (www-2a renders `WWW\help\dl\features\<id>.md` at
`https://www.delphi-rag-lint.com/help/<id>/`): treat ids as permanent; a rename needs a
redirect. www-2a uses `featuregen build --site` and will ask before relying on front-matter
beyond id/title/summary/group/order/since/status/updated. ENGINE separately owns an IDE help
framework keyed by the registry help id.

## A. Queued work, in order

1. **Re-pin to 1.32.0 + baseline** -- S, session. After "re-parse done". Procedure: editor
   CLAUDE.md "Re-pin"; then model tests + all 14 drivers on main; re-judge lint (new rule
   `confusable-identifier`).
2. **Merge `feat/converter-apply-fields`** -- M, session. Review + mutation positive controls,
   `ParseApplyJson` bad-shape reads, B8 legacy text match keep/drop; drivers owed: convert-tab,
   convert-request, work-list (+ refused Convert keeps rows with the "previous run" summary),
   validate-scope, inherited-offer.
3. **Merge `fix/converter-testkit`** -- S, sonnet. Run drive-file-menu with a forced FAIL
   (must exit 1) and drive-work-list.
4. **A4 C18 member replacement, slice 1** (`#migrate X -> Y` / `-> DL_NONE` + rename) -- M,
   session. Contract `docs\NOTICE-2026-10-19-c18-slice1-migrate.md`; design
   `docs\superpowers\specs\2026-10-11-member-replacement-design.md` (Q1-Q4 answered, Q5
   deferred). Spec + plan first, owner approves, then implement on the 1.32.0 pin.
5. **N1 Convert click lost while an analysis or Save validation is pending** -- M, session.
6. **N3 re-create the apply1270 capture project as a script**, then re-capture the
   `tests\fixtures\apply1270\` uses rows -- M, sonnet. Needs an indexed unit (after the re-parse).
7. **B9 `#warn` / `#check-ref` in the Model + display + BDE book lines** -- M, sonnet.
8. **D4 + D6 qualify follow-ups** -- M each, sonnet. Owner ADDED both 2026-10-19.
9. **B4 runner batch mode** (`apply-batch/1`) -- L, session. Parse helpers exist on
   apply-fields (not wired).
10. **B10 `inherited_code_unconverted` capability + model test on a real capture** -- S, sonnet.
11. **N2 QualifyFix mutant Q08 "retarget ignores Applied" survives** -- S, sonnet (low).
12. **D2 `drive-engine-wait.ps1` `wait.reload.no.window` flake** -- M, sonnet.
13. **E2 one doc line: in a worktree pass `--db <wt>\src\tools\convrules-editor\_D-RAG\
    ConvRulesEditor.sqlite` and index with `--project ConvRulesEditor.dpr`** -- S, haiku.

## B. Engine-contract follow-ups

- **B1** scoped note from `only_matched[]` / `only_unmatched[]` -- on apply-fields (A2 above).
- **B2** E10 refusal hint gated on `only_skips_unit_rules` -- DROPPED (owner 2026-10-19):
  never fires on 1.31.5 (uses reconciliation keeps the unit). `RefusalHint` is dead code;
  delete it with its test when next in `ConvertRequest` (S, haiku).
- **B3** C13 index-gap refusal reads "fix the index" -- on apply-fields.
- **B4** runner batch mode -- A9.
- **B5** C8 code refs filtered to field-resolved -- DROPPED (owner 2026-10-19): the engine's
  `inherited[]` is authoritative (ruling M4) and the note is off when it reports.
- **B6** `descendants[]` on the ancestor's row + report -- on apply-fields.
- **B7** `only_included[]` / `unlinked[]` -- on apply-fields (texts were already done).
- **B8** half-apply guard on the exit contract -- on apply-fields; text match kept as a legacy
  fallback pending the review's keep/drop decision.
- **B9** `#warn` / `#check-ref` -- A7.
- **B10** `inherited_code_unconverted` -- A10.
- **B11** castlib `dfmdata` -- DONE (shared parser reads it).

## C. Owner minors

- **C-1 Picker does not offer StripDB for a `TFileName` From** -- BLOCKED on ENGINE castlib
  (`accepts string, TFileName`), asked in
  `docs\INBOX-REPLY-2026-10-19-converter-to-engine-qualify-and-castlib.md`. Then verify the
  picker (S, haiku).
- **C-2 Refused Convert keeps the previous Work list** -- DONE on apply-fields (owner chose:
  keep rows, label "from the previous run ...; the last Convert was refused").
- All other section-C minors -- DONE, merged in 1d888db1 (plan
  `docs\superpowers\plans\2026-10-19-converter-c-minors.md`, triage table names the closed ones).

## D. Test-kit debts

- **D1** `drive-file-menu.ps1` exit 1 on FAIL -- on fix/converter-testkit (A3).
- **D2** `wait.reload.no.window` flake -- A12.
- **D3** "rerun alone under load" -- DROPPED as an item (note kept in D2).
- **D4 / D6** -- A8.
- **N5** `drive-work-list.ps1` clipboard retry -- on fix/converter-testkit (A3).

## E. Housekeeping

- **E1 instruction-file trim** -- DONE 2026-10-19 (editor CLAUDE.md 7.5 KB, archive in
  `docs\handoffs\archive\convrules-editor-HANDOVER-ARCHIVE.md`).
- **E2 worktree `--db` doc line** -- A13 (N4 "no .dproj" is not a defect).
- **E3 merged/scratch worktrees** (conv-trial, conv-qualify-fix, conv-c-minors,
  conv-integrate + branches tmp/conv-trial, feat/convert-qualify-fix, fix/converter-c-minors,
  conv/integrate) -- remove, owner approval batched.
