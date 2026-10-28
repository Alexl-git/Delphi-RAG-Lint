# Delphi-RAG-lint -- project instructions

Index / DB / gap rules are in the global `~/.claude/CLAUDE.md` (drag-lint block). The
incidents and measurements behind every rule below: `docs\AI-USAGE.md` "Rule history".
Handoffs: `docs\handoffs\RESUME.md` (index, newest first) -- never in a CLAUDE.md.

## Docs in sync (highest priority in this repo)

`--help`, `README.md` and `docs\AI-USAGE.md` are part of the product: a CLI-surface change
is not finished until all three match the code.

| Surface | Must satisfy |
|---|---|
| `--help` | every verb the CLI accepts is listed; every flag a verb accepts is on that verb's line |
| `README.md` | rule counts match `drag-lint rules --json`; no whole feature missing from the verb list |
| `docs\AI-USAGE.md` | verb list covers the real surface; no DB path that no longer exists |

Guard: `tests\autotest\run_docs_sync_guard.ps1` (in the battery) fails on drift. Update the
banner and the docs in the SAME change. If the guard is wrong, fix it deliberately -- never
weaken it to get green.

## Feature registry (every shipped change, however small)

Spec: `docs\superpowers\specs\2026-10-19-featuregen-design.md` (the 2026-10-05 PowerShell design,
`docs\superpowers\specs\2026-10-05-feature-registry-design.md`, is superseded); page
`docs\wiki\featuregen.md`. The registry, its checks and every generated page belong to
`featuregen.exe` (`src\tools\featuregen`; build it with `build\_build_featuregen_local.bat`;
the PowerShell scripts that did this are retired). `featuregen` below means
`src\tools\featuregen\featuregen.exe` (not on PATH; run it from the repo root, e.g.
`.\src\tools\featuregen\featuregen.exe --help`, which lists every verb). The gates
(`tools\featuregen-gate.ps1`, `run_feature_registry_guard.ps1`) rebuild the exe themselves when
it is missing or older than its sources.
1. `featuregen add --id .. --title .. --group .. --owner .. --summary .. --intro ..
   --wiki-page .. --surface "<type>:<...> ;; <type>:<...>"`; surfaces carry the FULL menu path
   (`ide-menu:<top> > Submenu > Caption`), every level. Moving a menu item:
   `featuregen blast-radius --menu-path "<node>"`, then `featuregen move-menu --from .. --to ..`,
   in the plugin's commit.
2. Write/update the wiki page named in `wikiPage` (yours; the registry links to it).
3. `featuregen normalise`, then `featuregen build --all`; commit the regenerated `docs\wiki`
   pages, README / AI-USAGE blocks, `features\generated\` (manifest.json, cli-reference.md,
   site-pages.json) and the website set `WWW\help\dl\` WITH the feature.
4. `tests\autotest\run_feature_registry_guard.ps1` -- names what is missing.
5. Never hand-edit `Home.md`, `Features.md`, `Feature-Index.md`, `Quick-Help.md`, a
   `dl:registry` block or anything under `WWW\help\dl\`; edit the entry or `features\templates\`
   and regenerate. Groups and teams are data (`--new-group` / `--new-team`).
6. A commit that adds or changes a feature updates ITS OWN entry (usage, flags,
   steps, questions, wiki page) and runs `featuregen verify --id <its id> --by <TEAM>`. Never
   verify another team's entry; report it to its owner instead.
`status: internal` = accepted-but-unadvertised verbs; docs-sync's `$UndocumentedOnPurpose`
stays a separate list (owner 2026-10-05).

## A project index is only as complete as its `.dproj` / `.dpr`

The index is the compile closure; a unit that is used but not listed is silently NOT
indexed, so query / find-callers / lint-all answer SHORT, never visibly wrong. After every
full reindex, and before trusting a `lint-all`:
```
drag-lint reconcile-project <App.dproj> --json          (read-only: no --db)
drag-lint lint --project <App.dproj> --rule unit-not-in-dpr
```
Report before `--apply` (it edits the project file). Fix the `.dproj`/`.dpr`, reindex
incrementally, and check `files=` grew. Procedure: `docs\PLAN-project-completeness-sweep.md`.

Summary-line fields: `files=` = every row in the DB (a stock); `walked=` = paths this run
admitted; `attempted=` counts attempts before the parse (can exceed `files=`);
`up-to-date=` is not the log's `SKIP` lines; `committed=` = attempted files whose rows landed
(`attempted - committed` = rolled-back files). **`files > walked` = a once-widened DB: run
`index --project <X.dproj> --db <db> --rebuild`** -- the periodic rebuild is the remedy, there
is no eviction verb (owner 2026-09-16). Incremental already handles a refactored unit (full
re-emit by `file_id`) and a unit dropped from the `.dproj` under a scope root (evicted).

## Two version constants

* `DRAGLINT_VERSION` -- product version; bump freely.
* `DRAGLINT_EXTRACTOR_VERSION` -- part of the indexer fingerprint; a bump re-parses EVERY DB
  (hours). Bump ONLY when extraction changes: parser/grammar, emitted symbols / refs / uses /
  call edges, or which preprocessor branches parse -- never for lint rules, output, docs,
  the plugin or the LSP. Guard `tests\autotest\run_extractor_version_guard.ps1`; a missed
  real bump leaves silently stale parses.

## Encoding

`.pas`, `.dpr`, `.dfm`, `.bat`, `.ps1`: 7-bit ASCII, CRLF, no BOM. Write/Edit emit LF --
normalise, or `run_encoding_guard.ps1` fails.

## Shared working tree (other teams' uncommitted work lives here)

* Never `git checkout -- <paths>`; never a bare `git stash`. Back out with
  `git stash push -m "agent:<task> -- <why>" -- <path> ...` (flags BEFORE `--`).
* Resolve every stash you made before reporting: pop it, drop it and say why, or name the
  exact `stash@{n}` + message. Finish with `git stash list`.
* Commit with a pathspec: `git commit -m "<msg>" -- <path> ...`. Never `commit -a`,
  `add -A`, or a commit without a pathspec. Announce a merge to main to the other sessions.

## Two controllers, and the whole-branch lint sweep

* Before dispatching against an SDD ledger you did not create this session, run
  `ListAgents`; if a live session names this repo/branch, message it and wait. Record in the
  ledger who owns the branch.
* The final whole-branch review lints the FULL diff (`<merge-base>..HEAD`), not per-task
  hunks, and sweeps stale markers:
  ```
  drag-lint lint-all --db <db> --enable multiple-statements-per-line,magic-literal,commented-out-code
  one drag-lint lint <unit> --db <db> --enable ... per changed unit   (review-marker-stale AND review-marker-unused included; lint takes ONE path)
  ```
  Run `review-marker-stale` and `review-marker-unused` (a marker that suppresses nothing) WITH the rules the branch's `dl:ok` markers suppress (an OFF rule
  makes every marker for it read stale). Re-check every `dl:ok` the branch adds; remove one
  whose finding no longer fires.

## Building

`delphi-build` skill. CLI: `build\build_draglint_win64.bat` -- Win64 Debug, stages the
tree-sitter companions, syncs `rules\` to both exe dirs, deploys to `third_party\dll-win64\`.
Run the engine as `.\drag-lint.exe` or by full path, never by bare name.

**dll-win64 exe locked** ("being used by another process"): never kill by name or bare-copy over it.
Stop it remotely -- `drag-lint ide-release --seconds 900` (the IDE plugin stops respawning) then
`drag-lint shutdown --all --wait 30` (running engines stand down) -- or let
`build\stage-engine.ps1 -FreshExe <new> -Target <deployed>` do hold + kill-by-image + retry; the
build bat and `pack-lint-release.ps1` stage through it. Wiki: `docs\wiki\ide-release.md`.
