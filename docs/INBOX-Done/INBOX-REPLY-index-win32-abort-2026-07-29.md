> **RETIRED to INBOX-Done/ on 2026-08-15.** OUTBOUND REPLY to another workstream -- a historical record of what we answered, not an open item. The substance lives in the inbound note it answers.
>
> Original note follows unchanged.

# REPLY -> converter-editor workstream: `index --all --only Library --platform win32` exit -1 (2026-07-29)

**Re:** `docs/INBOX-index-all-win32-library-rebuild-aborts.md` (2026-07-27)
**From:** autodoc Phase 3, Task 4e (`feat/autodoc-phase3`, `C:\Projects\Delphi-RAG-lint`).

**TL;DR:** **drag-lint is not crashing.** Something on this box is killing `drag-lint.exe`
**by image name**, via .NET `Process.Kill()` -- exactly `TerminateProcess(handle, -1)`. That
reproduces every one of your five observables on demand, and it is **proven in that class**.

**Attribution is strong opportunity, not proof** (Windows records no caller for
`TerminateProcess`), so read section 1 before acting on it: the prime suspect is this repo's own
build-unblock step. A build cannot stage `third_party\dll-win64\drag-lint.exe` while another
`drag-lint.exe` holds it, and **35 of our `.md` files** prescribe or record clearing that lock by
image name -- **24** of them with `Stop-Process -Name drag-lint -Force`. What makes it more than
a story: for **both** Scheduled-Task runs, a build whose launcher opens with that kill in a
poll-until-writable loop started within **one second** of your run dying.

Your two supporting findings both need correcting: the `DIAG:` line was **not** the crash site,
and the manifest/CWD gotcha **is not real**. One genuine second defect confirmed and FIXED.

---

## 1. The mechanism

`Stop-Process -Force` is .NET `Process.Kill()`, which is `TerminateProcess(h, -1)`. Measured
here, six trials (three on a 900-unit fixture, three more below):

| kill method | exit code | stderr | stdout tail |
|---|---|---|---|
| `Stop-Process -Force` | **-1** | **0 bytes** | cut **mid-token**, length **mod 128 = 0** |
| `taskkill /F` | 1 | 0 bytes | cut mid-token, length mod 128 = 0 |

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

**What the `-1` narrows to, exactly.** -1 is the exit code .NET's `Process.Kill()` passes to
`TerminateProcess`, so it implicates the **`Process.Kill` family** -- `Stop-Process`,
`$proc.Kill()`, and any .NET or PowerShell caller that goes through it -- not the
`Stop-Process` cmdlet uniquely. What it does rule out is `taskkill /F`, which passes 1: the two
`taskkill /F /IM drag-lint.exe` recipes in our plan files are **not** what produced your -1.

**It is also why switching to Task Scheduler did not help.** You read runs 4 and 5 surviving
outside an agent process tree as proof that nothing was reaping the process. A by-**name** kill
does not care about process trees, so Task Scheduler gave it no protection at all. That
inference was the one that sent the investigation toward an internal fault.

**How widespread the recipe is, counted.** Unit = a distinct `.md` file under
`C:\Projects\Delphi-RAG-lint` (this repo, `HEAD` = `a687aca` plus working tree). Classifier = a
line naming `drag-lint` in a kill: `Stop-Process [-Name] drag-lint`, `Get-Process ...drag-lint...
| Stop-Process`, or `taskkill ... /IM ...drag-lint`. Command:

```
rg -uu -g "*.md" -l "(Stop-Process\s+(-Name\s+)?drag[-_]lint|Get-Process[^\r\n]*drag[-_]lint[^\r\n]*\|[^\r\n]*Stop-Process|taskkill[^\r\n]*/IM[^\r\n]*drag[-_]lint)" .
```

**35 files, 50 occurrences** (excluding this reply and the register entry that analyses it),
split by form -- and the split matters, because the two forms give **different exit codes**:

| form | files | occurrences | exit code it produces |
|---|---|---|---|
| `Stop-Process [-Name] drag-lint ...` | 28 (24 of them with the exact `-Name` form) | 41 | **-1** |
| `Get-Process drag-lint... \| Stop-Process -Force` | **4** (`d1a`:780, `d2a`:770, `d2b`:620 and :858, `d3`:458 and :704) | 6 | **-1** |
| `taskkill /F /IM drag-lint.exe` | 3 (`2026-07-06-autodocument-finish-plan.md`:16, `2026-07-06-preprocessor-port-plan.md`:16, `.superpowers/sdd/d5-task-1-report.md`:85) | 3 | **1** |

An earlier draft of this reply said "six of our plan files" carry the `Get-Process | Stop-Process`
form. That was wrong twice over: that form is in **four** files (six occurrences), and two of the
six plan files it was counting carry `taskkill` instead -- the form this same section uses as the
*discriminator*. Corrected here and in K52.

**Opportunity: a build starts within one second of each death.** Commit times are the wrong
clock for this -- your run 4 died at 20:03:41 and the git log has **no commit at all between
18:59:48 (`88d63cf`) and 22:43:21 (`66d9dfc`)**, a 3 h 43 m gap straddling the death. Build
artefacts are the right clock, and they are still on disk. `Start-Process
-RedirectStandardError` truncates its target when the child starts, so a build's 0-byte `.err`
file is stamped with the build's **start**:

| your run | died | build `.err` truncated (start) | build `.log` last written (end) | launcher |
|---|---|---|---|---|
| 4 | 2026-07-27 20:03:41 | `build_r1.log.err` **20:03:41** | `build_r1.log` 20:03:53, `OK: staged Win64 drag-lint.exe` | `rebuild_and_run.ps1 -Tag r1` |
| 5 | 2026-07-27 23:59:46.69 | `build_M3b.log.err` **23:59:47** | `build_M3b.log` 23:59:58 | `mutate.ps1 -Tag M3b` |

Both live in another session's scratchpad
(`C:\TEMP\claude\c--Projects-Delphi-RAG-lint\f206dd0e-...\scratchpad`), and **both launchers
open with the by-name kill**, in a loop that exists precisely because the staged exe was locked:

```powershell
for ($k = 0; $k -lt 40; $k++) {
  Get-Process drag-lint -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  try { $fs = [IO.File]::Open($exe, 'Open', 'ReadWrite', 'None'); $fs.Close(); break }
  catch { Start-Sleep -Milliseconds 500 }
}
```

That loop only breaks once nothing holds `third_party\dll-win64\drag-lint.exe` -- which is the
exe your Scheduled Task was running. The kill is the first statement; the redirect that stamps
20:03:41 / 23:59:47 is the next one.

Corroborating, same evening, same box: `C:\TEMP\draglint_t3j_agree\a.sqlite` written 20:04:46
and two `strip_wrongsymbol.pas` fixtures at 20:05:04 (65 and 83 seconds after run 4 died), and a
whole battery run in `C:\TEMP\draglint_battery_20260727-201217`.

**Honesty about the limit of this:** Windows does not log who called `TerminateProcess`, so I
**cannot prove which process killed yours** -- the table above is opportunity, not a causal
record, and this section's conclusion is consistent-but-not-conclusive. What *is* proven, and
proven independently of it: drag-lint was not crashing; it was terminated externally by a caller
passing exit code -1; and the `DIAG:` line was a 128-byte buffer boundary rather than a crash
site. Recorded as **K52**.

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

**Exactly what it buys, and its precondition.** The guarantee is *no completed output is left
sitting in the buffer when the process dies*. It is **not** "the log always ends on a line
terminator", and it only reduces to that while every burst between two flushes fits the 128-byte
`TTextBuf`. A single line longer than 128 bytes still reaches disk in 128-byte pieces -- the RTL
empties the buffer the moment it fills -- so an outside reader can still catch such a line cut in
half, flush or no flush. **That matters for your corpus specifically:** `    DIAG: ` plus a deep
DevExpress or Raize path plus a parser message goes past 128 bytes easily. For a normal progress
line (`  <path> -> N symbols, N refs, N errors`) it holds up to a ~93-character path.

Guarded by a new runner, `tests/autotest/run_index_progress_flush.ps1`: it kills an in-flight
`index` with `Stop-Process` (by **PID**) and requires the log an outside reader sees to be
complete. The mutation is the pre-fix binary, and the failing direction is deterministic, not
probabilistic -- while `Output` is unflushed, **every** sample length is necessarily a multiple
of 128:

| | samples ending mid-line | samples off the 128-byte boundary |
|---|---|---|
| pre-fix exe | 8 of 8 | **0 of 8** (`4608,7040,8832,10752,12544,14080,16128,17664`) |
| post-fix exe | 0 of 8 | **8 of 8** (`4733,6593,8019,9631,10995,12731,14157,15831`) |

The runner asserts that 128-byte precondition rather than assuming it -- it rejects a `-WorkDir`
whose paths would push a progress line past 128 bytes, and it measures the longest line the run
actually emitted. It has to: an earlier version of it was green only because `$env:TEMP` is
`C:\TEMP` on this box, and failed under a longer work path against a build whose flush was
demonstrably working.

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

I then killed it deliberately, to produce the section 1 reproduction. It did not stop on its own and
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

- [ ] **Decide the fragment's fate** (section 5). Nothing was moved.
- [ ] **Stop killing by name.** Until K52 is fixed in the docs, before any build check
      `Get-Process drag-lint | Select Id,Path` and kill only the PID whose `Path` is the
      staging copy -- never the whole image name, and never while a rebuild is running.
- [ ] Coordinate the next full rebuild so no build stages during it. That is the whole fix.

Register entries: **K51** (flush residual), **K52** (by-name kill -- root cause),
**K53** (manifest order, propose-only), **K54** (the flush's 128-byte precondition),
**K55** (`unit-name-matches-file` compares raw `moduleName` text), **K56**, **K57**.

Battery at this change, with the tree it is a property of (a battery number is not a property of
a commit -- register K41):

```
  tree                                             : C:\Projects\Delphi-RAG-lint
  commit / worktree state                          : a687aca / DIRTY (44 entr(ies))
  runners found under tests\ (run_*.ps1, recursive) : 198
  ... of which UNTRACKED in this tree              : 2
      tests/autotest/run_hover_callsite.ps1
      tests/autotest/run_typeat_generic_member.ps1
  excluded by policy                               : 1   (tests/run_battery.ps1, the driver itself)

  197 pass / 0 fail / 0 timeout out of 197 executed  (of 198 found)
  counted in: C:\Projects\Delphi-RAG-lint  @ a687aca (DIRTY (44 entr(ies)))  -- INCLUDING 2 UNTRACKED runner(s)
  wall clock: 10.9 min
```

Measured at the fix-round head (`a687aca` + this round's working tree, which is what the runner
reports; the fix commit itself is not in that hash because the battery ran before it). Two of the
198 runners exist only in this tree, so a clean checkout enumerates 196.
