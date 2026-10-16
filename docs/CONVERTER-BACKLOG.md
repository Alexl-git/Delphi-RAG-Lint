# CONVERTER backlog -- delayed tasks (do not lose; do not read every session)

Created 2026-10-16 from the resume doc, the archived 1.27 adoption ledger and the
editor CLAUDE.md hand-over notes. A handoff LINKS to this file instead of
repeating it. Open it when picking the next converter job, not at session start.

**Status caution:** items marked (re-check) were recorded before later merges and
may already be done. Measure against the tree before working on one.

## A. Queued work, in order

1. **Re-pin** once, after the engine's all-teams 1.22 extractor release + full
   re-parse (owner ruling relayed by ENGINE 2026-10-14). Verify the sha yourself.
   Procedure: editor CLAUDE.md "Re-pinning"; baseline model tests 2194/5, 13
   drivers; re-capture the `tests\fixtures\apply1270\` uses rows (1.28.1 changed
   them). Re-judge lint (editor 971 / tests 413) -- new rule
   `confusable-identifier` and naming fixes arrived after 1.27.0.
2. **Owner request: one-click "qualify #convert" quick fix** from apply/1
   `qualify_fixes[]` (capability `convert_qualify_fix`). Contract in
   `docs\NOTICE-2026-10-11-v1.28.3-released.md`. Brainstorm/spec first.
3. **Owner's minor reworks** -- section C below.
4. **C18 member replacement, slice 1** (`#migrate X -> DL_NONE` + rename) once
   the engine builds `docs\superpowers\specs\2026-10-11-member-replacement-design.md`
   (owner answered Q1-Q4, Q5 deferred).

## B. Engine-contract follow-ups (re-check each -- recorded 2026-10-06/07)

- Scoped note from `only_matched[]` / `only_unmatched[]` ("converted N of M").
- E10 refusal hint gated on `only_skips_unit_rules`.
- C13 index-gap REFUSED text shown as "fix the index", not "edit the book".
- Runner batch mode (`batch_units`, apply-batch/1; 45.7 s vs 114.7 s for 3 units).
- C8 code refs: keep only refs RESOLVED TO A FIELD (E5).
- Show `descendants[]` (descendant_warnings) on the converted ancestor's row + report.
- Distinct texts for "rolled back" vs "PARTLY converted"; show `only_included[]`;
  surface `unlinked[]` dropped collections on the row/report.
- Tighten the half-apply guard to the engine's all-or-nothing exit contract and
  drop the text match.
- E17 `#warn` / `#check-ref`: parser round-trip (ParseLine, Emit, BlockFile) +
  display of book-warning / ref-path-like / ref-dangling; then add
  `#warn IndexName "..."` and `#check-ref ConnectionName ...` to the BDE book.
- 1.26.7 `inherited_code_unconverted`: CodeUseNoteDue per engine state + a model
  test on a real 1.26.7 capture.
- 1.26.2 castlib key `dfmdata ...`: check the shared CastLib parser shows it.

## C. Deferred minors (owner reworks)

From the 1.27 adoption ledger
(`docs\superpowers\sdd-archive\2026-10-11-editor-1270-adoption\progress.md`):
- Picker does not offer StripDB for a `TFileName` From (string alias).
- Cast option Detail text never shown.
- `TestConvCatalogValueCast` SKIPs all 4 checks without `casts.castlib` beside the engine.
- `ParseApplyJson` default `AFeatures` = all is a trap; make `[]` the default.
- "Converted N of M" counts pairs never run after a stop.
- Report line order (inherited, glyph, new) differs from note order.
- Drive-by `TestGrammarGuard` path change; ConvertRun Remainder comment on a code
  line; ConvertRunner `TConvertStatus` remarks at column 0.
- Two books on one unit can list a global twice at shifted lines (Work list).
- A preflight-refused Convert keeps the previous Work list.
- Editor CLAUDE.md verification-kit paragraph wording; registry
  `convrules-work-list` since=1.28.0-alpha.

From earlier branches (editor CLAUDE.md):
- C8: multi-file drop of N descendants prompts once each on No (no "No to all");
  Convert gate Yes/No has no GUI check; `drive-inherited-offer.ps1` fixed 2 s sleep.
- C12: queued `ApplyConvertRequest` could run before the form is visible; a
  `--form` error is overwritten by the request status; whitespace-only required
  value reads "is missing"; unmatched-name hint fires on unparseable output.
- Depth: on a `bdsInvalid` book picking 5 does not fire OnChange; on
  `bdsDuplicate` the red note stays -- owner to accept or change.
- Pre-existing oddities: blank filename in `HeaderIndexFor`/`LoadFile` stale
  message; dead `BlockPercent` (H2219); stale hand comment above
  `HarvestUnitFile`; `HarvestFormTypes` comment; `FormTypeDrawItem` 4px inset
  written three times.

## D. Test-kit debts

- `drive-file-menu.ps1` exits 0 even with a FAIL.
- `drive-engine-wait.ps1` `wait.reload.no.window` flaky since 1.25.2 (cause
  unconfirmed); its `WaitIdle` still has the reused-PID child filter.
- `drive-file-menu` / `drive-engine-wait` fail once under machine load -- rerun alone.

## E. Housekeeping (owner)

- Trim `src\tools\convrules-editor\CLAUDE.md` (135 KB, ~34k tokens loaded by every
  converter session and subagent): move dated hand-over notes to a docs file,
  keep a current core of ~5-8 KB. Proposed 2026-10-16, awaiting owner go.
  **Proposal made 2026-10-16 (awaiting the owner's choice: all four files, or the editor CLAUDE.md first):**
  method = keep each rule, move its story into an archive, delete nothing.
  (1) editor CLAUDE.md 135 KB -> ~8 KB core (engine pin + drift check, re-pinning, test kit + baseline, a
  one-line-per-unit map, ~10 standing traps); dated hand-over sections moved word for word to
  `docs\convrules-editor-HANDOVER-ARCHIVE.md`. (2) `C:\Projects\CLAUDE.md`: no-grep rules kept complete
  as one ~3 KB block (exe, resolve-dbs, verb table, index-then-slice-Read, the 4 gap classes, both logs);
  incident detail goes to `docs\AI-USAGE.md`. (3) Rules the harness has outgrown: the Everything HTTP API;
  the MCP build tool (already denied in settings); Mercurial "use Bash" (contradicts the PowerShell rule);
  the PowerShell section -> 3 lines; the 2026-07-23 plan stats; the "under 200 words" rule only for
  general-purpose; the wiki section -> the `--check` command only; rules repeated across the 3 files
  stated once. (4) MEMORY.md: keep resume pointers + 10-15 live lessons, move the rest to a lessons
  index read on demand. Estimate ~50k -> ~12-15k tokens per session/subagent. Show the owner the list
  of every rule kept / shortened / moved / dropped before committing.
