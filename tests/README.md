# The drag-lint test battery

## What "the battery" is

**Every file named `run_*.ps1` anywhere under `tests/`, found recursively.**

That is the whole definition. It is enumerated dynamically by
[`tests/run_battery.ps1`](run_battery.ps1); there is no list to keep in sync.

```
pwsh -File tests\run_battery.ps1                    # the battery (default: everything, serial)
pwsh -File tests\run_battery.ps1 -List              # enumerate only, run nothing
pwsh -File tests\run_battery.ps1 -Include autodoc   # a subset, for a fast inner loop
pwsh -File tests\run_battery.ps1 -TimeoutSec 300    # per-runner budget (default 300s)
pwsh -File tests\run_battery.ps1 -Jobs 8            # run concurrently (default 1 = serial)
```

The driver prints the denominator it enumerated **before** it runs anything, plus a
per-suite breakdown, so a shrinking battery is visible instead of silent. It exits 0
only when every enumerated runner passed.

### `-Jobs N` and the serial quarantine

**The default is 1, and the serial path is byte-for-byte the loop the driver has
always used.** It stays the reference every green claim in this repo is measured
against; `-Jobs` is opt-in until it has earned more.

A runner that cannot share a machine opts out by carrying `# dl:serial: <reason>`
in its first 60 lines. The marker lives in the RUNNER, not in a list in the
driver, because "I cannot run concurrently" is a property of the runner -- a
driver-side list would drift the first time someone added one.
`tests\autotest\run_battery_jobs_guard.ps1` fails if an `lsp_proxy` runner loses
its marker, or if the quarantine empties because the regex stopped matching.

Today the quarantine is exactly the three LSP proxy guards, which are documented
to have interfered with **each other while strictly serialised**.

**It is NOT "the runners that write the shared staged exe".** The note that asked
for `-Jobs` said eight runners write
`third_party\dll-win64\drag-lint.exe` and named them. Measured 2026-08-30: **zero
do.** Every one was a mention of `build_draglint_win64.bat` in a block comment or
a `Write-Host` advice string, or a `Copy-Item` pulling the tree-sitter DLLs *out*
of `dll-win64` into the runner's own scratch dir. The guard asserts that premise,
so if a runner ever does start staging the engine, it goes red rather than the
battery going quietly flaky.

When comparing a parallel run to a serial one, **compare the pass/fail SET, not
the count.** A parallel run that reports the same number while a *different*
runner failed is not equivalence.

### The count is not written down here, on purpose

**Run `pwsh -File tests\run_battery.ps1 -List` when you want the number.** The driver's
printed denominator is the only statement of the count that cannot go stale, and this
file deliberately does not compete with it. The constraint this document replaced failed
*because* it hardcoded "31 tests"; a different hardcoded number is the same defect
wearing a new value.

If you are tempted to quote one anyway, note that the honest answer depends on the
working tree. A clean checkout of this branch enumerates **178** runners; a tree that also
has the two deliberately-untracked prior-session regression runners
(`tests/autotest/run_hover_callsite.ps1`, `run_typeat_generic_member.ps1`) enumerates
**180**. Both are correct. That is exactly why the driver reports what it found rather
than checking against a literal.

Full run: roughly **10 minutes** wall clock on the build box.

### Which failures are tolerated

**None, with one time-boxed exception.** Until task **T3i** lands, the two
`tests/callresolve` runners (`run_ambiguous_calls`, `run_calledfrom_resolved`) are
expected to fail: they are deferred-defect **E1**, `member-access` refs counted as
unresolved call sites, pre-existing since `9d7e641` (2026-07-10). Any other non-pass
blocks the commit. **After T3i, the whole battery must pass** -- delete this paragraph
then.

## Why this file exists

Through six consecutive tasks of Auto-Document Phase 3, every "full battery green"
report covered only `tests/autodoc` + `tests/autotest` -- roughly **two thirds** of the
runners that existed. The rest were never run. Nine runners were red when the whole set
was finally executed on 2026-07-27, and only ONE of them was caused by that phase. The rest had been
red since **2026-07-01** (`lintconfig`, a deliberate config-semantics change the test
never followed), **2026-07-06** (three `refactor` runners, a `uses` clause the `-U` lists
never followed), **2026-07-08** (`ergonomics`, a new rule firing on an old fixture) and
**2026-07-10** (two `callresolve` runners). Nobody was cutting corners -- the battery
simply had no written definition, so an unstated one quietly became the definition.

Two rules follow, and they are the point of this document:

1. **The default is everything.** `-Include` and `-Exclude` exist for a fast inner loop
   while you are iterating; a task does not get to *report* on a narrowed run. Both raise
   a banner -- `SUBSET RUN` / `EXCLUSIONS APPLIED` in the header, and
   `*** NARROWED RUN -- this is NOT the full battery ***` in the summary, because a
   report usually quotes the summary. If you see either, say so.
   `-Exclude` is the more dangerous of the two: `-Include` collapses the denominator to
   something obviously small, while `-Exclude` drops a handful from an otherwise-full run
   and leaves a count that still *looks* right.
2. **Exclusions are documented or they do not exist.** The only default exclusion is
   `tests/run_battery.ps1` itself (it matches `run_*.ps1` and would recurse forever).
   Anything else added to `$DefaultExclusions` needs a one-line reason next to it, and a
   caller-supplied `-Exclude` needs its reason in whatever report quotes the run.
3. **Never quote a runner count as a contract.** Read the driver's printed denominator.
   See "The count is not written down here, on purpose" above.

## What is *not* a runner

`.ps1` files under `tests/` that are **not** named `run_*` are helpers or scratch, and
are never executed by the driver:

| File | What it is |
| --- | --- |
| `tests/autotest/_manifest_common.ps1` | dot-sourced prologue (`Check`, exe path) for the manifest runners |
| `tests/lint-store/enclosing-attribution/verify.ps1` | standalone probe for `refs.enclosing_symbol_id` attribution (v0.82 T1) |
| `tests/preprocess/lib/oracle.ps1` | helper that shells out to the Node preprocessor oracle; dot-sourced by the preprocess runners (Node is a **test-only** dependency -- the shipped exe never calls it) |
| `tests/textindex/fts5_spike.ps1` | design spike -- probes `--selftest-fts5` |
| `tests/textindex/schema_v10.ps1` | design spike -- probes `--selftest-schema` for the v10 string tables |

Miscounting `_manifest_common.ps1` as a runner is what produced three separate
runner-count disagreements during Phase 3. It is a helper.

`tests/*.bat` (`run_v0*_doctests.bat`, `run_phase1_e2e.bat`) and `tests/fixtures/T*.bat`
are older batch harnesses, not part of the PowerShell battery.

## Gotchas a new runner should respect

- **Capture stdout and stderr separately.** The engine writes
  `(loaded defaults from ...)` and `FTS5 probe: ...` to **stderr**. Folding them in
  with `2>&1` and then testing the first character of the result (`StartsWith('[')`,
  `Select-Object -Last 1`) is order-dependent: measured at ~4 failures in 40 runs.
  Use `2>$null` for any assertion about stdout's shape; keep `2>&1` only where the
  assertion is a substring match on stderr content (`WARN`, `SKIP`, size-guard).
- **Run from a neutral CWD** (`Push-Location C:\TEMP`) unless the test is about config
  discovery. From inside the repo the walk-up finds `C:\Projects\.drag-lint.json` and
  the engine emits that stderr preamble.
- **Don't pin a version literal.** `run_smoke.ps1` reads the expected version from
  `src/cli/DRagLint.CLI.pas`'s `VERSION` const; a hardcoded copy went stale twice.
- **Don't assert a total finding count** to prove one rule was disabled -- a later,
  unrelated rule firing on the fixture breaks it. Assert the rule-specific effect.
- **Bare `dcc64` runners must list the whole uses-closure in `-U`.** `src/core`'s
  `DRagLint.Core.Interfaces` uses `DRagLint.Preprocess.Types`, so `src/preprocess`
  is mandatory; omitting it is `F2613`, not a code defect.
- **Never invoke the engine by BARE NAME. `cd <dir>` then `drag-lint ...` runs a
  DIFFERENT BINARY.** `NoDefaultCurrentDirectoryInExePath=1` is set on this machine,
  so cmd does not search the current directory; the bare name resolves off PATH to
  `third_party\dll\drag-lint.exe` -- the frozen **Win32** build of 2026-07-05. It
  starts, it lints, and it answers with two-month-old rules: measured 2026-08-17 on
  ORM3 it reported **33,626 findings against the current build's 14,764**, with ~20
  `.scm` rules silently at zero. Nothing errors. Use `.\drag-lint.exe` or an absolute
  path; every suite here already takes `-Exe` and resolves it, which is why the
  battery never saw this. PowerShell is not affected (it requires `.\` anyway) --
  this bites `cmd /c` one-liners and anything copied out of a doc's "Reproducing"
  block.
- **For a LONG run, redirect through `cmd.exe` -- PowerShell holds native stderr
  until the process exits.** This is a harness rule, not an engine defect, and it was
  mis-attributed to the engine for two sessions
  (`INBOX-index-runs-are-not-resumable`). The engine already flushes: stdout once per
  file (`src/core/DRagLint.Core.Indexer.pas`, guarded by
  `run_index_progress_flush.ps1`) and every `resolve:` line
  (`DRagLint.Storage.SQLite.pas` `ResolveLog`). Measured on one 52 s index, sizes
  polled every second:

  ```
  cmd.exe    > 2>   out.log 128 -> 765 -> 2230 bytes within 4 s; err.log grew from t=1 s
  PowerShell > 2>   out.log 0 until an 8192-byte block
                    err.log 0 BYTES FOR THE ENTIRE RUN, 4462 at exit
  ```

  So `drag-lint ... > out.txt 2> err.txt` typed at a **PowerShell** prompt makes a
  healthy multi-hour index indistinguishable from a hung one -- which is how a
  working whole-DB resolve came to be filed as a hang. Use
  `cmd /c "... > out.txt 2> err.txt"` or `Start-Process -RedirectStandardError`, and
  poll the file. Short suites are unaffected and need no change.
- **Win64 is the target.** Per the v0.86 policy (user ruling 2026-07-05, see
  `src/delphi-plugin/DragLint.Plugin.ExeResolver.pas`), the IDE BPL is the only 32-bit
  artifact and every process the plugin spawns defaults to the Win64 CLI.
  `third_party/dll-win32/drag-lint.exe` is a frozen fallback, last built 2026-07-05 --
  do not point a runner at it.
