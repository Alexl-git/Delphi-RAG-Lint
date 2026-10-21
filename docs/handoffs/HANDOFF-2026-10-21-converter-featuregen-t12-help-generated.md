# HANDOFF 2026-10-21 -- converter: featuregen Task 12 (P7) built on a branch, awaiting review + deploy "go"

Session: converter (DL account). Resumed `HANDOFF-2026-10-20-converter-merged-featuregen-t12-next.md`.
ENGINE (delphi-rag-lint-db / delphi-rag-lint-20) released v1.33.0-alpha and opened the build slot.

## Status

Branch `feat/featuregen-t12-cli-help` in worktree `C:\Projects\Delphi-RAG-lint-wt\fg-t12`, off main b0bad3cf,
7 commits, tree clean, NOT pushed, NOT merged, NOTHING deployed to `third_party\dll-win64` (main tree).

* 5fe9531b checks B/C compare registry with the DISPATCH table (not --help); controls
  `Check.DispatchVerbUnregisteredFails`, `Check.HelpOnlyVerbIsNotCompared`; golden SeededFull message text updated.
* b6183df1 + b07dadae + c18bf3b2 `FeatureGen.HelpText.pas` generates `src\cli\DRagLint.CLI.HelpText.pas`
  (`WriteVerbReference`; literals over 800 chars are split, dcc line limit 1023).
* 97fedb3d registry change (owner-approved design): each public cli surface carries `helpOrder` + `help`
  (its VERBATIM --help block, original spacing). `featuregen import-help --blocks [--dry-run]` seeds them
  (100 blocks over 99 entries; the entry whose id = verb owns the block, feature entries that merely run the verb get none).
  Schema, `SurfaceOrder`, `SurfaceRules`, Model (`TSurface.Help/HelpOrder`) extended.
* 57a7d992 `PrintHelp` calls `WriteVerbReference` (the 380 hand lines removed; its 7 comment lines kept in a
  comment block above the call). docs-sync guard F0 now reads PrintHelp + the generated unit.
* 40e456bf unit added to drag-lint.dpr/.dproj.

Evidence: rebuilt `--help` (private build in the worktree) is BYTE-IDENTICAL to the 1.33.0 one (419 lines, 0 diffs),
so no surface hash moves and no prose is lost. Frozen fixture `src\tools\featuregen\tests\fixtures\help-verb-reference-1.33.0.txt`
(327 lines) pinned by `Help.FrozenBannerPreserved`. featuregen tests 202/0; guards PASS: docs-sync, feature-registry,
encoding (docs-sync needed `rules\` copied beside the worktree exes; environmental). `featuregen check --level full` PASS.

## Owner's decisions (this session)

* Registry holds usage/flags/pitfalls; prose may later move from `help` into the leaf wiki page body entry by entry;
  hand text vs generated text is separated by the existing `dl:registry` marker blocks. `--help` must stay AI-usable:
  traps (`^` lines) stay inline; nothing may be lost (guarded by the frozen-fixture test).

## Resume point -- first actions

1. `ListAgents`; tell ENGINE the branch is ready for review (it touches `src\cli\DRagLint.CLI.pas` + new unit + dpr/dproj).
2. Still owed on the branch: lint (`drag-lint lint` + `lint-all` with `--enable magic-literal,multiple-statements-per-line,commented-out-code`)
   of `FeatureGen.HelpText.pas`, `FeatureGen.HelpImport.pas` (SeedHelpBlocks), generated unit; featuregen has NO index
   (no .dproj) -> gap logged in `stats\draglint-gaps.log`; consider `register-project` or report as out-of-scope.
   A test for `SeedHelpBlocks` (claim order, shared usage line gets no block) is missing.
3. Docs: registry entry/wiki page for the new `help`/`helpOrder` fields and `import-help --blocks` (featuregen --help,
   `docs\wiki\featuregen.md`, spec section P7), `featuregen verify` for the entry we own; CLAUDE.md Feature-registry block mention.
4. Deploy: building to `dll-win64` (main) needs the owner's explicit "go"; then re-pin the converter (pin sha changes) or keep 1.33.0 and say so.
5. Merge to main announce to ENGINE/other sessions; commit with pathspec; never `git add -A`.

## Not done / owed (carried)

* Owner: `git branch -D` of feat/converter-apply-fields, feat/converter-model-batch, fix/converter-testkit, integrate/converter-e18 + remove worktrees (autonomy hook blocks it).
* Uncommitted in MAIN tree: `docs\CONVERTER-BACKLOG.md`, `docs\handoffs\RESUME.md` (+ this handoff).
* Then backlog A4 #migrate (owner decisions D0-D9). Standing list `docs\CONVERTER-BACKLOG.md`.

## Gotchas

* Worktree is not indexed; featuregen is not indexed (no .dproj): drag-lint-first hook blocks Grep -- call any drag-lint verb, retry.
* Private engine build only: `msbuild ... drag-lint.dproj` from `fg-t12\src\cli` (wrapper `%TEMP%\fgcli_build.bat`); do NOT run
  `build_draglint_win64.bat` for main. The worktree has its own `third_party\dll-win64` copy (+ `rules\`).
* Write/Edit emit LF: .NET `ReadAllText/WriteAllText(..., ASCII)` with `` `r`n `` keeps CRLF; `python3` hangs on this box.
* A usage line claimed by a verb-named entry; `import-help --blocks` is idempotent (clears old help first).
* Surface hash covers the verb's --help block: any non-identical --help text marks verified entries stale.
