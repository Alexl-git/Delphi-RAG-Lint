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

1. **Prefix-rule group atomicity.** Skipping is per-edit, so for the three prefix rules an applied
   declaration edit with a skipped use-site can leave uncompilable code. The new guard makes partial
   application MORE likely, not less. Needs a design decision.
2. **The index never prunes vanished files** -- filed in
   `docs/INBOX-lint-scope-stale-files-and-project-members.md`. After the user moved 10 units, lint
   still reported ~249 findings against paths that no longer existed.
3. **`lint-all --project` is accepted but does not scope the finding set.** Same INBOX note. This is
   what ORM3 actually needs: it is multi-folder (CLIENT / SERVER / OBJECT / COMMON), so a folder-scoped
   index unions client and server. **Per-project INDEXING already works** -- `index --project` resolves
   the search paths and follows the unit closure across folders (verified by dry-run on
   `CLIENT\Micronite2027.dproj`: 21 scan folders including COMMON and COMMON\OBJECTS). ORM3 could be
   split into per-`.dproj` sections; the tradeoff is that a per-project scan also pulls in resolved
   library roots (Spring4D etc.) and would want an exclude for those.
4. **`doc-drift` / `missing-doc` resolve decls by `(file, line)` with NO name check**
   (`DocRules.pas:348`) -- the same latent shape as the naming bug, with a different blast radius
   (wrong doc comment attached rather than corrupted tokens). Verified they do NOT emit
   `tekReplaceInLine`, so they were never exposed to the corruption itself.
5. **`lint-all --json` prints a banner to stdout** -- `docs/INBOX-lint-all-json-stdout-banner.md`. The
   JSON will not parse without stripping it.
6. `TTextEditApplier` rewrites a file and writes a `.bak` even when every edit for it was skipped.
7. **The v19 reindex still owes a `--force-reparse` pass** -- the runs so far SKIP unchanged files, so
   the B1 unit-level-`var` extractor has not reached them.
8. Shellshock bisect (`docs/INBOX-parse-error-shellshock-units.md`) -- 3 units parse to 0 symbols; the
   `{$I+}` hypothesis is DISPROVED in the doc.
9. Answer the other group's finding 2.5 (bare `TEdit` resolving FMX-first; they proposed
   `--prefer-namespace Vcl`).
10. **Push -- 16 commits on `main`, none pushed.**

---

## Gotchas that will bite a cold start

1. **Run the drag-lint battery with `pwsh`.** Under Windows PowerShell every `$proc.ExitCode` is null
   and all tests falsely FAIL while the per-runner logs show clean passes.
2. **A reindex HOLDS `drag-lint.exe`, so a rebuild cannot overwrite it. Sequence them.** A concurrent
   session killing those processes to unblock itself is what aborted the first v19 attempt at 7/9.
3. **Never rebuild the exe mid-battery** (the BPL is fine -- different artifact).
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
