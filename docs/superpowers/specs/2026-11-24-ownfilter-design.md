# OWNFILTER -- third-party findings in a project lint-all (1.54)

Owner ruling: a project `lint-all` drops findings located in third-party / vendored code; definition from library
roots, vendored path markers and project config; never hide the owner's shared units (COMMON beside the project);
text and `--json` say how many were skipped and why; a switch shows them.

## What existed
* `DRagLint.Project.OwnRoots` (`ownRoots` / `excludeRoots` in `_D-RAG\drag-lint-project.json`), used by lint-all,
  document, exceptions-sync, cycle-fix, reconcile, refactorings. `--lint-third-party` switches it off in lint-all.
* `exclude_paths` in `drag-lint-lint.json`. Scan filter + finding filter for both.
* Defects against the ruling: (1) with nothing declared, EVERYTHING outside the project folder was hidden, COMMON
  included; (2) a vendored folder inside the project was linted as own; (3) `--json` said nothing at all;
  (4) the number of findings dropped was never counted. `SharedScope` judges peers of a shared unit, not ownership: unused here.

## Decisions
1. `DRagLint.Lint.OwnFilter` sits ON TOwnRoots; TOwnRoots itself is unchanged. Reporting may be wide, writing must be
   narrow: `TOwnRoots.IsOurs` stays the write scope, and a lint-all `--fix` run keeps to it.
2. Order: explicit exclusion (exclude_paths, excludeRoots) > explicit ownership (own_paths) > inferred (vendored folder
   name, inside roots too) > declared ownRoots > library path > OWN. No signal = own.
3. Vendored names: third_party, third-party, thirdparty, 3rdparty, 3rd_party, 3rd-party, vendored. NOT vendor, lib,
   external, components (owner folders may be called that). Config: `vendored_folders` (`-name` removes one).
4. Library scope: the manifest Library "include" folders (declared, unconditional) and the IDE library paths (inferred:
   a unit the project file lists stays own; a root holding the project is no signal).
   The closure indexer already keeps registry-library units out, so the registry arm matters for widened / folder DBs.
5. Skipped files are still not scanned (cost, and own / vendored clone pairs). The finding count is therefore the
   project-wide findings the run computed and would have reported; the text says so.
6. `--json` is a bare array and stderr must stay empty on success, so the summary is one trailing row
   `third-party-skipped`, only when something was skipped; not a catalogued rule, not in exit code / baseline.
7. Single file (`lint <file>`, LSP, editor): always reported. `lint <dir>` keeps its own closure scope. `lint-project` unchanged.
8. Unanchored index: no filter, as before (the existing NOTE).

## Behaviour changes
* Undeclared project: files outside the project folder are now linted unless marked. `run_ownroots_default_note.ps1`
  A0/A4/A5 and the fixture of `run_lint_own_roots.ps1` part 5 changed for that reason.
* A vendored-named folder inside declared ownRoots is now skipped.

## Owner questions
1. Undeclared + unmarked + off every library path (e.g. C:\Projects\tzdb beside a project): reported now. Right?
2. Is `vendor` to be a built-in name? (conservative: no)
3. Is one extra `--json` row acceptable, or should it need a flag?
4. Should a scan count per-file findings in skipped files too (slower: the skipped files are parsed)? (conservative: no)
5. A LISTED unit under an IDE library path is kept (COMMON may be there). Right for vendored units listed in the .dpr?
