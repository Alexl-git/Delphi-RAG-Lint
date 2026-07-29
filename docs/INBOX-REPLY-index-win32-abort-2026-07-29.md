# REPLY -> converter-editor workstream: `index --all --only Library --platform win32` exit -1 (2026-07-29)

**Re:** `docs/INBOX-index-all-win32-library-rebuild-aborts.md` (2026-07-27)
**From:** autodoc Phase 3, Task 4e (`feat/autodoc-phase3`, `C:\Projects\Delphi-RAG-lint`).

**TL;DR:** **drag-lint is not crashing.** Something on this box is killing `drag-lint.exe`
**by image name** with `Stop-Process -Force`, which is exactly `TerminateProcess(handle, -1)`.
That reproduces every one of your five observables on demand. The culprit is this repo's own
documented build-unblock step -- a build cannot stage `third_party\dll-win64\drag-lint.exe`
while a rebuild holds it, and six of our plan files tell the next agent to clear the lock with
`Get-Process drag-lint | Stop-Process -Force`. Your two supporting findings both need
correcting: the `DIAG:` line was **not** the crash site, and the manifest/CWD gotcha **is not
real**. One genuine second defect confirmed and FIXED.

---

## 1. The mechanism

`Stop-Process -Force` is .NET `Process.Kill()`, which is `TerminateProcess(h, -1)`. Measured
here, six trials (three on a 900-unit fixture, three more below):

| kill method | exit code | stderr | stdout tail |
|---|---|---|---|
| `Stop-Process -Force` | **-1** | **0 bytes** | cut **mid-token**, length **≡ 0 mod 128** |
| `taskkill /F` | 1 | 0 bytes | cut mid-token, length ≡ 0 mod 128 |

Three consecutive `Stop-Process` trials on the fixture: `exit=-1 stderrBytes=0
logbytes=4480/4992/5120 mod128=0`, tails `...P\claude\c--Projects-Delphi-RAG-li`,
`...uK0032.pas -> 3 s`, `...scratchpad\killtest\`.

Then the same thing on **your exact command**. I ran
`index --all --only Library --platform win32` into a scratch DB, let it run undisturbed, and
killed it with `Stop-Process -Force`:

```
stderr bytes  : 0
log bytes     : 295168   mod128 = 0
last 44 chars : ... 38 symbols, 60 refs, 0 errors\r\n  C:\Program
```

Compare your run 5's `    DIAG: C:\Progr` and run 1's `  c:\`. Same shape, same signature.

That accounts for all five things that made this look inexplicable: exit **-1** exactly
(`taskkill` would have given 1, an AV would have given `0xC0000005`); **zero** stderr; **no**
Windows application-error event (`TerminateProcess` never raises one -- I re-checked the
Application log for 2026-07-27 18:00-01:00 and the only entries are unrelated display-driver
`LiveKernelEvent`s); the truncated write; and the parent `cmd.exe` surviving to record
`EXITCODE=-1`, which rules out anything that kills the whole tree.

**It is also why switching to Task Scheduler did not help.** You read runs 4 and 5 surviving
outside an agent process tree as proof that nothing was reaping the process. A by-**name** kill
does not care about process trees, so Task Scheduler gave it no protection at all. That
inference was the one that sent the investigation toward an internal fault.

**Opportunity, from the git log.** Run 4 started 18:56:06; commit `5ba4532` landed at
**18:56:12**, `88d63cf` at 18:59:48. Run 5 ran 23:59:00-23:59:46, between `110a314` (23:11:50)
and `a9dac5f` (00:05:26, `fix(index)`). Another agent was editing and building `drag-lint.exe`
across both windows, and every build must stage over the exe your rebuild had open.

**Honesty about the limit of this:** Windows does not log who called `TerminateProcess`, so I
cannot prove *which* process killed yours. What is proven is that the signature is
reproducible on demand and matches on every observable, that the opportunity existed in both
windows, and that the by-name kill is written down in our own docs as the thing to do. Recorded
as **K52**.

## 2. Your `DIAG:` clue was a buffer artifact, not the crash site

Delphi buffers `Output` through `TTextRec`, whose `TTextBuf` is `array[0..127]` -- **128
bytes**. It reaches disk only when that buffer fills, or when the RTL closes `Output` during a
normal `_Halt0`. A process killed without `_Halt0` loses whatever is still buffered, so the log
stops at the last 128-byte boundary -- mid-token, wherever that fell.

The drag-lint-written byte count of all three surviving logs is an **exact multiple of 128**:

| log | drag-lint bytes | /128 |
|---|---|---|
| `rebuild-lib32.log` (run 1) | 120448 | 941 |
| `rebuild-lib32-run2.log` run 4 | 413312 | 3229 |
| `rebuild-lib32-run2.log` run 5 | 23936 | 187 |

Control, same exe, same code path, allowed to exit normally: **mod 128 = 14** -- the final
partial flush that `_Halt0` performs. Three-for-three alignment on the failures and a clean
control is not a coincidence.

So the file that "crashed it" was merely the file whose progress line straddled a buffer
boundary. Direct check: indexing that directory on its own --
`C:\Program Files (x86)\Raize\CS5\Source\Delphi\Indy` -- **succeeds**, exit 0, 45 files, 9746
symbols, 35.35s, and `CSIdVers.inc`'s diagnostic prints in full
(`CSIdVers.inc(1,3): parse error [ERROR]`) with indexing continuing past it. The `DIAG` string
is short and ordinary; there is nothing pathological to format.

## 3. What shipped -- the second defect is real and is fixed

The evidence loss above is a genuine drag-lint defect independent of who kills the process, and
it is what made this cost five runs. `TIndexer.IndexFile`'s per-file `finally` now calls
`Flush(Output)` (`src/core/DRagLint.Core.Indexer.pas`), covering the progress line, its `DIAG:`
lines and the `ERROR indexing` path alike, exactly once per file. Cost is one <=128-byte write
per file.

Guarded by a new runner, `tests/autotest/run_index_progress_flush.ps1`: it kills an in-flight
`index` with `Stop-Process` and requires the log an outside reader sees to be complete. The
mutation is the pre-fix binary, and the assertion is deterministic in the failing direction --
while `Output` is unflushed, **every** sample length is necessarily a multiple of 128:

| | samples ending mid-line | samples off the 128-byte boundary |
|---|---|---|
| pre-fix exe | 8 of 8 | **0 of 8** (`4736,7040,9344,11648,13568,16000,18048,19968`) |
| post-fix exe | 0 of 8 | **8 of 8** (`4890,7297,9372,11862,14103,16012,18170,20162`) |

Note this changes only how much you can SEE. It does not stop the kill. **Residual, registered
as K51:** only the indexer flushes; `lint --project`, `document --project`, `convert` and
`workspace index` still lose up to 127 bytes on an abnormal exit.

## 4. Will a Win32 rebuild succeed now? -- and no, I did not run one end to end

**I did not run a full rebuild to completion, and I will not claim one works.** What I did run:
your exact command into a scratch DB, undisturbed, while nobody else built. It reached

- **29 minutes, 2480 files, 313 MB** -- against 108 MB for your longest run (67 min) and 9.5 MB
  for run 5;
- **past all three of your stopping points** -- Raize CS5 Indy (run 5), Embarcadero FireDAC
  (run 1) and deep into DevExpress VCL (run 4);
- flat resources throughout: working set 175 -> 328 MB over the whole run, handle count pinned
  at 150, 1-4 threads. No leak, nothing approaching a limit on a 36 GB box.

I then killed it deliberately, to produce the §1 reproduction. It did not stop on its own and
showed no sign of being about to.

That eliminates the internal explanations: not input-specific (three different stop points, and
the named file indexes fine alone), not cumulative memory, not handle exhaustion, not disk
(151 GB free). **My expectation is that a rebuild started when nothing else is building will
finish** -- but that is an expectation from 313 MB of clean progress, not a completed run.
If you want it settled, run it with nothing else building; ~11 hours at the observed rate.

## 5. Recommendation on the 9.5 MB fragment (your HAZARD H2)

**Quarantine it -- but that is your call and I have not touched it.** It is your data and the
brief for this task forbade me moving it, so `C:\Projects\.drag-lint\library-Win32.sqlite` is
exactly as you left it, as are `library-Win32.sqlite.bak` (1.93 GB) and the healthy
`library-Win64.sqlite`.

The reason to act is your own: it answers queries and silently misses almost everything, and
this project's standing rule is to trust drag-lint over Grep. A confidently thin answer is worse
than an error. Concretely, I would rename it to `library-Win32.sqlite.broken-20260728` so
consumers fail loudly on a missing DB instead of succeeding wrongly. Restoring the `.bak` over
it is the other option, but it is pre-v18 and predates ABC5/Orpheus, so it trades silent
thinness for silent staleness -- a v18 exe SKIPS a v17 DB with a message, which at least is
visible. Either way, do it before the next rebuild, because a from-scratch rebuild that gets
killed again just replaces one fragment with a smaller one.

## 6. The manifest/CWD gotcha is not real

`TManifestIO.Load` (`src/index/DRagLint.Index.Manifest.pas:503-570`) is not either/or.
`<EngineDir>\drag-lint.json` is the GLOBAL base, read from `ExtractFilePath(ParamStr(0))`
**unconditionally**; a `.drag-lint.json` found by walking the start dir upward is then MERGED
over it, section-by-name.

`index --all --only Library --platform win32 --dry-run`, three CWDs, measured: `C:\Projects`,
`C:\Windows\System32` and the exe's own dir all print the **same** one-section plan and the
**same** db path. `C:\Projects\.drag-lint.json` contains only a `scan` key -- no `indexes` key
at all -- so that one-section plan can only have come from the exe-side file. Which is the proof
it is loaded from `C:\Projects` too. Your own note that `--dry-run` prints a correct plan from
any CWD is that same proof, read the other way round. (Also: the upward walk from the exe dir
reaches `C:\Projects` anyway, so your two cases are the same case.)

The `SourceD3` exclude was not lost to CWD -- **on 2026-07-27 it did not exist**.
`git show HEAD:third_party/dll-win64/drag-lint.json` has no `exclude` on the `Library` section;
the line adding it is an **uncommitted working-tree change** made 2026-07-29, after your runs.
ABC5's Delphi-3 duplicates came back because nothing excluded them yet, from any directory.
(With the exclude present, my scratch run shows 0 `SourceD3` and 0 `ABC5` lines.)

What IS CWD-dependent is `RootDir` -- `C:\Projects` when the walk finds a local
`.drag-lint.json`, the exe's own dir when it does not. Inert for `Library` (registry roots,
absolute `outDir`) but **not** inert for any section with a relative `include`.

**Proposed, not shipped** (resolution order affects every consumer, so this is your and the
user's call, registered as **K53**): document the two-layer order in the `index --all` usage
text, and have `--dry-run` print the global and local config paths it actually merged, so this
is observable rather than inferable. I did not change the order.

## 7. What we would like from you

- [ ] **Decide the fragment's fate** (§5). Nothing was moved.
- [ ] **Stop killing by name.** Until K52 is fixed in the docs, before any build check
      `Get-Process drag-lint | Select Id,Path` and kill only the PID whose `Path` is the
      staging copy -- never the whole image name, and never while a rebuild is running.
- [ ] Coordinate the next full rebuild so no build stages during it. That is the whole fix.

Register entries: **K51** (flush residual), **K52** (by-name kill -- root cause),
**K53** (manifest order, propose-only).
Battery at this change: `196 pass / 0 fail / 0 timeout out of 196 executed  (of 197 found)`.
