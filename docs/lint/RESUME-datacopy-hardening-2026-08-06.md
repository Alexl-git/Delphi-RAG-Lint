# RESUME -- DataCopy hardening + drag-lint autofix fixes (2026-08-05/06)

Read this first. Predecessor: `docs/lint/RESUME-autofix-and-hover-2026-08-05.md`.

---

## Status at handoff

### DataCopy (`C:\Projects\DataCopy`, Mercurial) -- branch `datacopy-hardening-2026-08-05`, revs 18-33

`default` is untouched at rev 17. `hg update default` discards the whole branch;
`hg diff -r 17 -r 33` is the complete change. Every revision was gated on BOTH `DataCopy.dproj` and
`SortTest.dproj` building clean (exit 0) and on files staying 7-bit ASCII + CRLF.

Full detail lives in the repo itself:
- `C:\Projects\DataCopy\CODE-REVIEW-2026-08-05.md` -- round 1 findings
- `C:\Projects\DataCopy\CODE-REVIEW-ROUND2-2026-08-06.md` -- round 2 + corrections
- `C:\Projects\DataCopy\CODE-REVIEW-ROUND3-2026-08-06.md` -- round 3, regressions, rejected findings
- `C:\Projects\DataCopy\TEST-INSTRUCTIONS-2026-08-06.txt` -- **for the human tester**

**Headline:** the pipeline no longer destroys instrument source files on failure. A source is deleted
only after the output was written and closed successfully AND every configured backup was verified
present with a matching size. That guarantee did not exist at rev 17, in any form.

**Lint findings 1456 -> 275** (with the library DBs attached; `used-unit-not-resolvable` 409 -> 1).

**The user has moved 10 retired units** out of the project root into `Backup-20260805\`. Both projects
still build clean with them absent -- empirical proof they were dead. The root is now 14 live units.

### drag-lint (`c:\Projects\Delphi-RAG-lint`, git `main`) -- 16 commits UNPUSHED, head `6e66279`

Battery **217/217 PASS** with the fresh exe staged to `third_party\dll-win64`.

Three defects of the same family were found and fixed -- **a fixer that writes without verifying its
target**:
- `41cb000` `unused-local` deleted live variables and whole `var` blocks (72 lines destroyed in a
  measured case). Replaced with an AST-driven builder grouped PER FILE, not per finding.
- `3fbb0b8` naming autofix applied STALE store coordinates to a changed file, writing `GlyActive` onto
  `then`/`else` keywords with exit code 0. Guard + regression test proven red-then-green.
- `ddfc4f1` root cause (`ResolveSymbolAt` line-only fallback) plus the verification hoisted into
  `TTextEditApplier` (`ExpectText`), and a stale `Col` past end-of-line now rejected instead of
  silently appending.

All nine manifest sections are at schema v19; a tenth (`DataCopy`) was added in `6e66279`.

---

## TODO -- what is left, in priority order

### A. Before the merge to MAIN (DataCopy)

1. **Record the file moves in Mercurial.** 19 tracked files show as `!` (missing) because they were
   moved to `Backup-20260805\`. A merge with those outstanding will be messy. Deliberately NOT done --
   it is a structural decision:
   - `hg remove --after` marks them removed and leaves the archive untracked (history at rev 17 still
     has the content -- nothing is lost, repo stays lean); OR
   - `hg addremove --similarity 100` records them as renames into the archive folder (content stays
     tracked under the new path).
2. **Rebuild and send `TEST-INSTRUCTIONS-2026-08-06.txt` to the tester.** Nothing in revs 18-33 has
   ever run. The document is written for a tester, not a developer, and asks two questions we cannot
   answer ourselves (see below).
3. **After the test passes** -> merge the branch to `default`, final build.

### B. Questions only the tester/user can answer

- **Is the CSV tag-grouping feature needed?** It is DORMANT -- `TagList` is never populated, so every
  row lands in one output file regardless of tags. Section D of the test instructions asks for a
  deliberate test. Decide: finish it (and size `COLidx` to `TagList.Count` first) or delete it.
- **What is in the INCOMPLETE stranded Zeiss groups?** The startup sweep refuses to guess at a group
  missing a member and reports them. Section C2.
- **Do restored Zeiss groups need their original sequence number?** Restored files may carry a
  different number than the instrument produced. Section C3.

### C. DataCopy -- known outstanding, NOT fixed

- **No test harness exists.** `SortTest.dproj` is a VCL app (it checks folder filename sort order), not
  DUnitX. NOTHING in revs 18-33 is covered by an automated test -- the compile is the only gate. Given
  how much changed on a data path, **this is the highest-value follow-up in this document.**
- `BackupFile` returns True without copying when `IgnoreFilesWith` matches and `BackupIgnored` is
  False, so the group is transferred and deleted with no backup at all -- the one path where the
  delete-after-verified-backup rule has nothing to verify. (medium/medium)
- `LastSavedNum` only reaches the INI via a UI save, so a restart during unattended running resets the
  counter to whatever a human last saved.
- Alerts are double-logged (module path logs, caller logs the same message again).
- `.orphan-*` / `.TXD` / `.mm1.done` leftovers are never cleaned automatically -- deliberate (nothing
  is thrown away without a human), but it wants an operator retention policy.
- `Application.HandleException(Application)` in several places passes `Application` instead of `E`, so
  EurekaLog gets no exception context.
- Main-thread `Sleep` retry loops and synchronous network I/O still freeze the UI (up to ~7.5s per
  locked file). Correct fix is moving the batch to a worker thread -- large, deliberately deferred.

### D. drag-lint -- cleanup still owed

**Session 2026-08-06 (post-handoff) closed D2, D3, D4, D5 and D6.** All five are implemented,
built (Win64, staged to `third_party\dll-win64`) and covered by tests. Battery denominator moved
217 -> 219 (two new runners). **NOT COMMITTED** -- the working tree carries all of it.

1. **Prefix-rule group atomicity.** Skipping is per-edit, so for the three prefix rules an applied
   declaration edit with a skipped use-site can leave uncompilable code. The new guard makes partial
   application MORE likely, not less. Needs a design decision. **STILL OPEN -- the top remaining item.**
2. ~~**The index never prunes vanished files.**~~ **DONE** -- `ISymbolStore.PruneMissingFiles` +
   an opt-in `--prune` on every `index` form. The dependent rows needed no hand-written sweep:
   every file-owned table already declares `ON DELETE CASCADE` from `files(id)` and `Migrate` sets
   `PRAGMA foreign_keys = ON`. `string_literals` IS deleted explicitly first -- its FTS5 shadow
   tables sync via `AFTER DELETE` triggers, which SQLite does not fire for FK-cascaded rows unless
   `recursive_triggers` is on. Test `tests\autotest\run_index_prune.ps1` (12 checks); the
   load-bearing one indexes two folders into one DB and proves a targeted prune does not touch the
   other folder. Full write-up in the INBOX note.
3. ~~**`lint-all --project` does not scope the finding set.**~~ **DONE** -- scopes to the project's
   compile closure + sibling `.dfm` + the `.dpr`/`.dproj`. BOTH passes are scoped: filtering the
   file list alone only narrows the per-file rules, and every project-wide rule reads the whole
   store. An unresolvable `--project` now exits 2 rather than reporting a clean project.
   Test `tests\autotest\run_lint_project_scope.ps1` (12 checks, 22 findings -> 11 when scoped).
   **The ORM3 note above still stands as a separate question** -- per-project sections would still
   pull in resolved library roots and want an exclude; lint-side filtering just lowers the urgency.
4. ~~**`doc-drift` / `missing-doc` resolve decls by `(file, line)`.**~~ **DONE** -- `TLintFinding`
   gained `SymbolName`; `RunMissingDoc` records it and `FixEditsForMissingDoc` requires line AND
   name to agree, resolving nothing when they do not. Deliberately NOT done by parsing the message
   (the codebase has a stated policy against it) nor by checking the column against the file --
   `StartCol` can point at the `procedure` keyword rather than the identifier, per
   `NamingFix.ResolveSymbolAt`'s own note.
5. ~~**`lint-all --json` prints a banner to stdout.**~~ **DONE** -- one predicate
   (`IsMachineReadableOutput`) + one writer (`EmitStatusLine`) above `FinalizeAndOutput`, which
   every prose site now routes through. Test: `run_pipeline_tests.ps1` section 6 (16/16).
6. ~~`TTextEditApplier` rewrites a file and writes a `.bak` even when every edit was skipped.~~
   **DONE** -- and it was worse than clutter: the write path re-serializes through a `TStringList`
   and forces CRLF, so a fully-skipped file was being MODIFIED. Now counted per file; no applied
   edit means no backup, no rewrite, not counted as touched. An out-of-range `tekInsertInLine`
   was also being dropped silently and is now reported as skipped. 4 new `TextEditTests` cases,
   proven red against HEAD before going green.
7. **The v19 reindex still owes a `--force-reparse` pass** -- the runs so far SKIP unchanged files, so
   the B1 unit-level-`var` extractor has not reached them. **STILL OPEN.**
8. Shellshock bisect (`docs/INBOX-parse-error-shellshock-units.md`) -- 3 units parse to 0 symbols; the
   `{$I+}` hypothesis is DISPROVED in the doc. **STILL OPEN.**
9. Answer the other group's finding 2.5 (bare `TEdit` resolving FMX-first; they proposed
   `--prefer-namespace Vcl`). **STILL OPEN.**
10. **Push -- `main` is 17 commits ahead of origin, none pushed, PLUS this session's uncommitted work.**
    **STILL OPEN.**

---

## Gotchas that will bite a cold start

1. **Run the drag-lint battery with `pwsh`.** Under Windows PowerShell every `$proc.ExitCode` is null
   and all tests falsely FAIL while the per-runner logs show clean passes.
2. **A reindex HOLDS `drag-lint.exe`, so a rebuild cannot overwrite it. Sequence them.** A concurrent
   session killing those processes to unblock itself is what aborted the first v19 attempt at 7/9.
3. **Never rebuild the exe mid-battery** (the BPL is fine -- different artifact).
   **Nor EDIT `src\*.pas` mid-battery** -- broader than the old rule and learned the hard way on
   2026-08-06. Some runners COMPILE from source rather than using the staged exe
   (`run_coherence.ps1` builds `CoherenceHarness.dpr` against `src\`), so an edit landing between
   two of its statements fails a runner that has nothing wrong with it. It passed on re-run with
   no change. A battery result taken while the tree was being edited is not a result.
3a. **Write repo files with CRLF.** The `Write` tool emits lone LF, and
   `tests\autotest\run_encoding_guard.ps1` fails the whole battery for it (it caught both new
   runners this session). Normalize after creating any file, `.ps1` included -- `.gitattributes`
   declares `eol=crlf` for `.ps1 .pas .dpr .dpk .dfm .inc .rules .bat .cmd`.
4. **Reindex immediately before ANY store-backed `--fix`.** A stale index used to corrupt source
   silently with exit code 0; there is a guard now, but it SKIPS rather than fixing, so a stale index
   still means "nothing happens" instead of "work done".
5. **Delphi builds:** the `delphi-build` recipe -- a 3-line wrapper `.bat` (rsvars -> cd -> msbuild)
   run from PowerShell `Start-Process -Wait` with output to a log. NOT the MCP build tool (no rsvars),
   NOT `cmd.exe /c` from the Bash tool (hangs).
6. **`.pas` / `.dfm` / `.dpr` are strict 7-bit ASCII + CRLF.** Verified after every agent edit this
   session; keep doing it. `DataCopy.dpr`'s BOM was stripped in rev 31.
7. **Do not delete DataCopy's commented-out code** (61 lint findings). Those commented
   `CodeSite.Send` lines are deliberate diagnostic scaffolding.
8. **Verify every agent finding before acting on it.** Three separate confident HIGH-severity claims
   were rejected this session on inspection -- most notably a "double-free on every DPP transfer" that
   rested on `TStreamReader`'s third constructor parameter being ownership. It is `DetectBOM`. Acting
   on it would have leaked the stream or disabled BOM detection.
