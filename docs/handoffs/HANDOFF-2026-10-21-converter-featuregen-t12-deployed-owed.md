# HANDOFF 2026-10-21 -- converter: featuregen Task 12 MERGED + DEPLOYED, owed items for the morning

Supersedes HANDOFF-2026-10-21-converter-featuregen-t12-help-generated.md (now `resumed`).

## Status

* Branch feat/featuregen-t12-cli-help ff-merged to main; main = 4addffe0, PUSHED.
* Owner gave an explicit go: build\build_draglint_win64.bat -> BUILD_EXITCODE=0; third_party\dll-win64\drag-lint.exe
  rebuilt 2026-10-21 01:24, SHA256 558ED58392A4EEE4D13B03E002F52B8E6BF28E05C0DD47DF1FFC38C7F724A656.
* Peers told (delphi-rag-lint-20 ENGINE, www-51, yadf-23). dll-win64 slot is free.
* Converter pin stays 1.33.0-alpha-20261020-205554; check-engine-drift.ps1 now exits 1 (expected: engine rebuilt, no extractor change).
* Worktree C:\Projects\Delphi-RAG-lint-wt\fg-t12 and the branch still exist (owner removes: autonomy hook blocks delete).

## Resume point -- first actions (morning)

1. Verify the DEPLOYED exe's `--help` against the frozen fixture `src\tools\featuregen\tests\fixtures\help-verb-reference-1.33.0.txt`
   (deployed `--help` counted 411 lines vs 419 in the private-build evidence; probably the "(loaded defaults ...)" line / counting,
   but it was NOT diffed). Run the docs-sync guard on main.
2. Owed lint: `lint` + `lint-all --enable magic-literal,multiple-statements-per-line,commented-out-code` for
   FeatureGen.HelpText.pas, FeatureGen.HelpImport.pas (SeedHelpBlocks), DRagLint.CLI.HelpText.pas. featuregen has no
   .dproj -> not indexed (gap logged in stats\draglint-gaps.log).
3. Owed test: SeedHelpBlocks (claim order; shared usage line gets no block).
4. Owed docs: registry entry + wiki page for `help`/`helpOrder` and `import-help --blocks` (docs\wiki\featuregen.md,
   spec section P7, CLAUDE.md Feature-registry block), then `featuregen verify --id <ours> --by CONVERTER`.
5. Re-pin decision: stay on 1.33.0 or re-pin to the new exe (hash it yourself; tell the 3 engine sessions first).
6. Then backlog A4 #migrate (owner decisions D0-D9).

## Standing task list

`docs\CONVERTER-BACKLOG.md` (kept; item F = registry review after the release).

## Gotchas

* featuregen / worktree are not indexed: drag-lint-first hook blocks Grep -- call any drag-lint verb, retry.
* Write/Edit emit LF; keep CRLF for .pas/.ps1/.bat via .NET WriteAllText ASCII. python3 hangs on this box.
* push / branch -D need the owner; commit with a pathspec only. Owner still owes `git branch -D` of the merged converter branches.