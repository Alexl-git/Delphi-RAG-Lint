# Plan TT-PUBLISH-UI -- editor "Publish to Firebird..." + IDE row (W4)

> **SUPERSEDED 2026-11-22** by `docs\superpowers\specs\2026-11-22-field-repository-v2-design.md` (section 11: publish-fb dropped, column triage dropped, FIB$ reader inventory deferred to 1.54). Do not execute.

Spec: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` section 5 (U1-U3). Depends on
TT-PUBLISH (unit `DRagLint.FieldRepo.FbPublish`, verb `repo publish-fb`) AND TT-TRIAGE (Form.pas one-liner)
being merged into `lane/v153-int` first -- if either is not merged at W4 dispatch, this lane rolls over.
Model: sonnet. Worktree `C:\TEMP\claude\lanes\v153\TT-PUBLISH-UI\wt`, branch `lane/v153-tt-publish-ui`.

## File fence

| File | Change |
|---|---|
| `src\tools\field-repo\DRagLint.FieldRepoEd.Form.pas` | sixth button `Publish to Firebird...` (BTN_COUNT 6, BTN_PUBLISH 5); `PublishClick` |
| `src\tools\field-repo\DRagLint.FieldRepoEd.SelfTest.pas` | `PASS publish-dry-run` check (U1) |
| `src\tools\field-repo\dl-field-repo.dpr`, `dl-field-repo-std.dpr` (+ their .dproj) | add `DRagLint.FieldRepo.FbImport` and `DRagLint.FieldRepo.FbPublish` (FireDAC FB driver units come with FbImport) |
| `src\delphi-plugin\DragLint.Plugin.Cmd.FieldRepo.pas` | row `field-repository-07-publish`, caption `Publish to Firebird...`, `InvokePublish` |
| `features\entries\field-repository.json` (featuregen only) | ide-menu surface with full path + steps |
| `docs\wiki\field-repository.md` | editor + IDE paragraphs |

## Tasks

1. **Blast radius first:** `featuregen blast-radius --menu-path "drag-lint > Field Repository"`; paste the output
   into REPORT (U3).
2. **Editor (TDD via self test).** Add to SelfTest: build a scratch SQLite stand-in with `"FIB$..."` tables
   (reuse the helper shape of `tests\fieldrepo\FbPublishTests.dpr` -- copy, do not link the test program), fill the
   fixture repo, run `RunPublish` with Apply=False against the stand-in, assert insert count = fixture rows and
   stand-in file hash unchanged -> `PASS publish-dry-run`. RED first (unit not linked), then GREEN.
   `PublishClick`: `SaveChanges`; `InputQuery` for the connection (masked: `PasswordChar` via the same
   `#31`-prefix trick as the plugin's `MaskedPrompt`, or a small TForm with a TEdit PasswordChar '*'); reject ''
   and strings with `"`; open with `OpenSourceConnection`; `RunPublish(Apply=False)`; show counts +
   `FormatPublishDiff(..., 30)` in a MessageDlg ending `Publish these changes to <Database>?` (Database value only);
   on Yes: before-publish backup exactly as the CLI does (call a shared routine: if TT-PUBLISH put it in CLI.Repo,
   move it into FbPublish.pas as `WriteBeforePublishBackup(pRepoPath, pTarget, pTables): string` in a
   prerequisite commit -- that one file edit is granted), then `RunPublish(Apply=True)`, status line per spec 5.
   Exception -> MessageDlg with the message, status `publish failed`. No `--delete-missing` in the UI (U2).
3. **Builds:** both editor builds (`build\_build_field_repo_local.bat` DevEx, `_build_field_repo_std_local.bat`),
   `run_fieldrepo_editor.ps1` green for both.
4. **IDE row:** `RegisterRow('field-repository-07-publish', 'Publish to Firebird...', True, InvokePublish)`;
   `InvokePublish` = ResolveContext, masked connection prompt (copy of InvokeRefreshSchema's checks), then
   `RunDryThenApply('repo publish-fb', FieldRepoCommandLine(Exe, 'publish-fb', Project, '--connection "' +
   Connection + '"'), '', '--apply')`. The dry-run confirm text from RunDryThenApply says "Write these files
   now?" -- add an optional prompt parameter or a sibling helper so this row asks `Publish to Firebird now?`.
   Extend `run_v152_TTIDE_menu.ps1`-style seam check only if the existing seam covers command lines (it does:
   `FieldRepoCommandLine`); add one case for `publish-fb`. BPL builds (Debug, IDE closed rule from
   `C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md` does not apply -- no options page; normal plugin build recipe).
5. **Registry:** ide-menu surface `drag-lint > Field Repository > Publish to Firebird...` with steps (open project
   -> choose the row -> enter connection -> read the dry-run summary -> Yes publishes; restart the Micronite
   server); `featuregen verify --id field-repository --by ENGINE`.
6. **Owner test page lines** (REPORT, for the controller's page): scratch-copy steps from the TT-PUBLISH plan, then
   the editor button and the IDE row against the SCRATCH database only.

## Acceptance

Self test `PASS publish-dry-run` in both builds; BPL builds; blast-radius output in REPORT; registry verified;
lint on changed units = 0 on changed lines.
