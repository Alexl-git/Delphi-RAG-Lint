> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED: guarded by tests/autotest/run_index_scope_eviction.ps1, green in the full battery.
>
> Original note follows unchanged.

# INBOX: files excluded by `.gitignore` are never EVICTED once indexed (B5 has no repair path)

- **Filed:** 2026-08-09, during nested-CALL resolution work
- **Class:** `wrong` (the index answers, but from files it was told to ignore)
- **Corpus:** `C:\Projects\YADF` / `C:\Projects\YADF\YADF.sqlite`
- **Related:** PLAN-autodoc-phaseC-2026-08-09 B5 (".private indexed", recorded as
  FIXED -- "honour `.gitignore` by DEFAULT"), and B6, which needed exactly this
  kind of repair migration for its own already-in-the-wild corpora.

## What happens

`.private/` **is** in `C:\Projects\YADF\.gitignore`. The ignore engine **works** on
discovery. But `C:\Projects\YADF\YADF.sqlite` still carries 5 `.private` files, and
they survive a full reindex of the same root:

```
C:\Projects\YADF\.private\bug2_cases.pas
C:\Projects\YADF\.private\uStyles_proprietary.pas
C:\Projects\YADF\.private\issue-1-d10.2.3\YADF.dpr
C:\Projects\YADF\.private\issue-1-d10.2.3\YADF.Layout.pas
C:\Projects\YADF\.private\issue-1-d10.2.3\YadfMain.pas
```

Decisive pair of runs, both with the same exe:

| run | command | `.private` files in the DB |
|---|---|---|
| existing DB | `index C:\Projects\YADF --db C:\Projects\YADF\YADF.sqlite --force-reparse` | **5** |
| fresh DB | `index C:\Projects\YADF --db <new>.sqlite` | **0** |

So B5 stops ignored files being **added**; nothing ever **removes** ones that are
already there. `--prune` does not help and says so -- it removes *vanished* files,
and these still exist on disk (`--prune: no vanished files to remove.`).

## Why it is not cosmetic

The archived copy is a *different version of the same unit*, so it contributes a
second, stale set of symbols under the same qualified names:

```
YADF.Layout.ReflowLineBreaks  id 21181  file 22 (.private\issue-1-d10.2.3\)  lines 1174-1528
YADF.Layout.ReflowLineBreaks  id 24879  file  7 (the live YADF.Layout.pas)   lines 1920-2294
```

In the archived copy those helpers are unit-level; in the live one they are nested.
That single stale file accounts for **157 of the 321** call refs that still look
unresolved on this corpus after nested-call resolution landed -- i.e. most of the
apparent remainder is an artefact of a file that should not be indexed at all.
It is also what made the "463 unresolved refs name a nested routine" figure read
far larger than the 142 that were actually resolvable (see the plan's corrected
measurement).

Same DB, same mechanism, worth checking together: it also holds 104 files under
`C:\Projects\DelphiAST\` (228 files total vs 124 on a fresh index of the YADF
root). Multi-root DBs are legitimate, so that may be intentional -- but the
eviction question is the same one.

## Expected vs actual

- **Expected:** an index pass over a root drops rows for files that the CURRENT
  ignore rules exclude -- the same way B6 shipped a repair migration rather than
  only fixing new writes.
- **Actual:** they are kept forever, and only a delete-the-DB-and-start-over fixes
  it. Nobody knows to do that, because the tool reports success.

## Reproduce

```powershell
$exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
& $exe index C:\Projects\YADF --db C:\Projects\YADF\YADF.sqlite --force-reparse --quiet
python -c "import sqlite3; c=sqlite3.connect(r'C:\Projects\YADF\YADF.sqlite'); print(c.execute(\"SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE '%\\.private\\%'\").fetchone()[0])"
# -> 5 ; the same index into a NEW db prints 0
```

## 2026-08-13: still open, and it has now cost a whole repair path

Re-measured on the CURRENT per-project layout (`C:\Projects\YADF\_D-RAG\YADF.sqlite`).
The `.private` case is gone, but the same mechanism now holds **DelphiAST**, which
left YADF's compile closure on 2026-08-12 when DelphiAST was moved onto the IDE
Library path:

| measurement | value |
|---|---|
| files the DB reports | **18** |
| files `index --all --only YADF --force-reparse` actually parses | **9** (YADF's own) |
| DelphiAST mentions in that reparse log | **0** |

So 9 rows are ghosts: never re-parsed, never evicted, frozen at whatever revision
was current when they were last indexed. How far out of date:

```
store : DelphiAST.SimpleParserEx.TmwSimplePasParEx.PushNames  start_line 564, impl 905..908
disk  : that file is 779 lines long; PushNames is on line 414
```

`impl_start_line` 905 is past EOF. **`--force-reparse` does not fix this** -- it
re-parses files, and nothing ever revisits a file the scan no longer reaches.
Only `--rebuild` (or deleting the DB) clears it, which is exactly the follow-on
`INBOX-document-project-ignores-ownroots-and-writes-into-third-party.md` recorded
as owed and nobody ran.

**What it cost.** These ghost rows are what made `lint-all --project YADF.dproj
--fix --apply` print `22 skipped (stale index)` identically across three
reindexes: the repair path planned edits at ghost coordinates, `AnchorIsValid`
correctly refused every one, and no command could ever clear them. The repair
path has since been scoped to the reported findings, so it no longer plans
against ghosts -- but that fixed the CONSUMER, not this defect. Any store-wide
walk still sees them.

## Suggested fix

At the end of an index pass over a root, evict `files` rows under that root whose
path the ignore engine now excludes (cascades already remove their symbols/refs).
Report the count, the way `--prune` reports vanished files, so a corpus that had
been quietly wrong announces itself once.
