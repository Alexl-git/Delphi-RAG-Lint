# HANDOFF 2026-10-21 -- converter: featuregen item F (registry review) mostly done; waits on ENGINE

## Status (main, local, NOT pushed; head 3d2b8ff2)
* Task 12 leftovers done: deployed --help verb reference byte-identical to fixture; units lint-clean; SeedHelpBlocks tests; docs (cca1190d, d4db0d38).
* New featuregen feature (11038bd7): entry fields `access` (cli-only | repo-tooling | standalone-app) + `accessReviewed {date, by}`, verb `review-access --id a,b --access X --by TEAM`, audit gap `no-access` (shipped/experimental entry with no ide-menu/ide-context/ide-about/tool-window surface). Wiki: docs/wiki/featuregen.md.
* Item F review: CONVERTER 12 entries done (intro, questions, own pages docs/wiki/glyph-vacuum.md + convrules-editor.md, 5 CLI entries verified, 10 access stamps). CHARTS (charts-07) done b98fa957 + access stamps (committed in 3d2b8ff2). ENGINE (delphi-rag-lint-20) committed 3b6b4a3b (153 intro+verify, 45 access stamps). Reports: docs/registry-review-2026-10-21/report-*.md (mine: report-CONVERTER-1.md).
* Registry guard PASS on 3d2b8ff2; `build --site --check` leaves=165.
* Owner rulings: shared help ids = one page per feature, group id only as see-also (SOMEHELPIDn placeholders only if needed); regenerate+republish user-facing pages after ENGINE's stale sweep, keeping only intro + bottom-line prose of old hand-written pages.

## OPEN (resume here)
1. ENGINE REGRESSION (sent to ENGINE): 3b6b4a3b changed features/entries/query-kind-all.json (usage now `query --kind <k> --all`, help[] one line) so the generated --help loses ~10 lines (query --name/--qname, --case-sensitive, --exact, match_kind, --quiet, --text block). Also check ask.json help[]. Failing featuregen tests: Help.FrozenBannerPreserved (316 vs 326), Audit.SurfaceChangedAfterVerify (verify hash). Wait for ENGINE's fix, then: `featuregen build --all`, run `src\tools\featuregen\tests\FeatureGenTests.exe` (expect 212 pass / 0 fail), guards, commit with pathspec.
   src\cli\DRagLint.CLI.HelpText.pas: I restored it to HEAD (good); a `build --all` regenerates it from the entries - do NOT commit a version shorter than the fixture src\tools\featuregen\tests\fixtures\help-verb-reference-1.33.0.txt (327 lines).
2. ENGINE will add ~22 ide-menu surfaces after the IDE menu branch merges + one more rebuild; it will tell us before. After THAT commit: regenerate/commit help/dl and tell www-51 (it then runs `build --site --check`, asks the owner to publish).
3. The "regenerate and republish user-facing pages" job (after ENGINE finishes): diff each hand-written wiki page vs generated text, keep intro + bottom line, drop the rest, regenerate. Not started.
4. CHARTS `compare` entry deliberately has no access stamp (needs an IDE menu item; plugin has none): stays as a visible no-access gap.
5. Re-pin decision (stay on 1.33.0-alpha-20261020-205554 pin or re-pin) and docs-sync F0 (deployed exe older than source PrintHelp: needs engine rebuild+deploy, owner go) are ENGINE's.
6. GUI entries convrules-convert-progress / reindex-project / qualify-fix / work-list / editor are NOT verified (no live editor check); verify after running the drivers on a staged pin copy. Then backlog A4 #migrate (owner decisions D0-D9) in docs/CONVERTER-BACKLOG.md.
7. Owner owes: git push, `git branch -D` of merged branches, remove worktree C:\Projects\Delphi-RAG-lint-wt\fg-t12.

## Gotchas
* ENGINE asked: no `featuregen build` / commit of features\entries while its batch runs - ask first.
* PowerShell: `@(@('a','b'))` flattens to chars (caused 1-char placeholder questions, fixed 9c85ba78); `[IO.File]` uses the process cwd, give full paths. python3 hangs here.
* drag-lint-first hook blocks Grep/shell grep on Delphi sources: call any drag-lint verb (e.g. resolve-dbs --in src/cli/DRagLint.CLI.HelpText.pas) then retry.
* featuregen update --set with JSON containing spaces gets split by PowerShell (charts-07 hit it): edit entry files directly in canonical layout, then `featuregen normalise`.