> # RETIRED 2026-08-16 (session 23) -- the rebuild ALREADY SUCCEEDED; this note is stale.
>
> The session-23 plan listed this under "genuinely blocked -- root cause unknown,
> launch the rebuild unattended and harvest". Both halves are wrong.
>
> **The Win32 library index is complete and healthy.** Verified independently:
> `C:\Projects\.drag-lint\library-Win32.sqlite`, schema v21, **7,427 files /
> 2,243,080 symbols / 3,326,130 refs / 543,706 call edges**, 2.14 GB. Every file
> carries a `parsed_at` inside 2026-08-12 14:34 -> 16:44 -- one from-scratch pass
> that finished in **2h10m**. Not a fragment, not truncated. The Win64 sibling
> (6,993 files) is comparable; Win32's higher file count is expected, since
> Win32-only third-party sources are on that path. `SourceD3` rows: 0, so the
> exclude held.
>
> **Root cause was found on 2026-07-29** and is recorded in
> `INBOX-Done\INBOX-REPLY-index-win32-abort-2026-07-29.md` (registered K52): an
> EXTERNAL `Stop-Process -Name drag-lint -Force` from the build-unblock loops,
> i.e. `TerminateProcess(h, -1)`. The evidence is the exit code itself -- exactly
> -1, which is what `Kill()` produces; `taskkill` gives 1 and an access violation
> gives 0xC0000005 -- plus 0-byte stderr, no WER event, and build launchers
> carrying that kill starting within 1 second of both scheduled-task deaths.
>
> The "crashed mid-DIAG-line" clue was disproved: all three surviving logs were
> exact multiples of **128 bytes**, a `TTextBuf` boundary artifact, since fixed by
> a per-file flush. The manifest/CWD theory was also disproved -- configs merge
> rather than compete.
>
> Hypotheses refuted with evidence: pathological unit / parser crash (three
> different stop points; the suspect directory indexes alone at exit 0), OOM
> (Win64 exe, working set flat 175 -> 328 MB on a 36 GB box), disk or SQLite limit
> (151 GB free, and a 2.3 GB DB has since been built), permissions (same paths
> succeeded).
>
> **Do not launch an 11-hour harvest run.** That estimate predates the 4.6x perf
> work in `a0a906e` / `043d402`; the real cost is ~2h10m. If a confirmation run is
> ever wanted, the section is named `Library` and the rule is simply: never kill
> drag-lint by image name while it is indexing.
# INBOX (engine): `index --all --only Library --platform win32` aborts mid-run, exit -1

- Date: 2026-07-27
- Reporter: converter-editor workstream (worktree `C:\Projects\Delphi-RAG-lint-converter`)
- Exe under test: `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, reports
  `drag-lint 1.2.1-alpha`
- Impact: `C:\Projects\.drag-lint\library-Win32.sqlite` cannot be rebuilt. It is currently a
  **9.5 MB fragment** of a ~1.9 GB index. It still answers queries and silently misses almost
  everything, which is worse than failing loudly. `library-Win64.sqlite` (1.87 GB, schema v18)
  is healthy and unaffected.

## Symptom

The process dies **mid-line while writing its own stdout**, with exit code **-1**, no stderr
output at all (the redirected stderr file is 0 bytes), and no Windows application-error event.
It is not a clean error path: the last log line is cut off in the middle of a token.

## Five runs, three launch methods, all failed

| # | Launched via | Started | Ended | Ran for | DB reached | Last line written |
|---|---|---|---|---|---|---|
| 1 | agent Bash tool | 2026-07-27 | -- | ~2 min | -- | cut mid-line |
| 2 | agent PowerShell, `timeout: 600000` | 18:21:57 | 18:31:14 | 9.3 min | ~116 MB | cut mid-line |
| 3 | `Start-Process -PassThru` (no `-Wait`) | 18:33:13 | 18:34:13 | 1 min | -- | cut mid-line |
| 4 | **Windows Scheduled Task** | 18:56:06 | 20:03:41 | **67 min** | ~108 MB | `...\dxPSContainerLnk.pas -> 15` (cut mid-number) |
| 5 | **Windows Scheduled Task** | 23:59:00 | 23:59:46 | **46 s** | 9.5 MB | `    DIAG: C:\Progr` (cut mid-path) |

Runs 4 and 5 ran under Task Scheduler -- no agent process tree, no tool timeout, nothing an
agent harness could reap. **The agent-timeout theory that was recorded earlier is therefore
wrong.** So is the obvious alternative: `C:` has **151 GB free**, so this is not a full disk.

## The sharpest clue (run 5)

Run 5 died 46 seconds in, immediately after this pair of lines:

```
  C:\Program Files (x86)\Raize\CS5\Source\Delphi\Indy\CSIdVers.inc -> 0 symbols, 0 refs, 1 errors
    DIAG: C:\Progr==== run ended 07/27/26 23:59:46.69 exit=-1 ====
```

It crashed **while emitting the `DIAG:` detail line for a file that had just reported a parse
error** (`1 errors`). Run 4's last line was also a truncated write, on
`C:\Program Files (x86)\DevExpress\VCL\ExpressPrinting System\Sources\dxPSContainerLnk.pas`.

Suggested first look: the diagnostic/DIAG emission path for a file with parse errors, and
whatever buffer or string it formats the path into.

## Reproducing

```
cd C:\Projects\Delphi-RAG-lint\third_party\dll-win64
drag-lint.exe index --all --only Library --platform win32 >> run.log 2>> run.err.log
```

Notes for whoever picks this up:

- The command form is **valid** -- `... --dry-run` prints a correct one-section plan, from
  `C:\Projects` and from `C:\Windows\System32` alike. Invocation and CWD are not the cause.
- Ignore the `ERROR: unknown command: index,--all,--only,Library,--platform,win32` usage dump
  that appears in one of the older logs. The comma-joining is only how the dispatcher formats
  the arg list in its error text; it is not evidence of mis-passed arguments.
- **Log in APPEND mode (`>>`).** Something in `index --all` truncates its own redirected stdout
  on the way out, which destroyed the evidence on runs 1-3 and is why it took five runs to see
  where it stops.
- This is a DESTRUCTIVE from-scratch rebuild. Every failed run leaves a smaller partial DB than
  the last. A pre-v18 backup that predates ABC5/Orpheus exists at `library-Win32.sqlite.bak`
  (1.93 GB, 2026-07-20) if a rollback is ever wanted.

## Manifest gotcha found while diagnosing (may be a separate bug)

Which config file wins depends on the current directory:

- CWD = `C:\Projects` -> `C:\Projects\.drag-lint.json` (settings-only; **no `indexes` section**,
  so **no `exclude`**), RootDir `C:\Projects`.
- any other CWD -> `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.json`, which is
  the one carrying the `Library` section's
  `"exclude": ["SourceD3","Delphi5","Delphi7","BuildD3",...]`, RootDir = the exe's own directory.

So a library rebuild launched from `C:\Projects` silently loses the `SourceD3` exclude and
re-imports ABC5's 34 Delphi-3-era duplicate units. Either the search order should be documented,
or the two files should be reconciled.

## Not blocking the converter workstream

The converter editor draws on `library-Win64.sqlite`, which is intact. Nothing in the rule-book
curation work needs the Win32 library index.
