# The drag-lint test battery

## What "the battery" is

**Every file named `run_*.ps1` anywhere under `tests/`, found recursively.**

That is the whole definition. It is enumerated dynamically by
[`tests/run_battery.ps1`](run_battery.ps1); there is no list to keep in sync.

```
pwsh -File tests\run_battery.ps1                    # the battery (default: everything)
pwsh -File tests\run_battery.ps1 -List              # enumerate only, run nothing
pwsh -File tests\run_battery.ps1 -Include autodoc   # a subset, for a fast inner loop
pwsh -File tests\run_battery.ps1 -TimeoutSec 300    # per-runner budget (default 180s)
```

The driver prints the denominator it enumerated **before** it runs anything, plus a
per-suite breakdown, so a shrinking battery is visible instead of silent. It exits 0
only when every enumerated runner passed.

As of 2026-07-27 that is **180 runners**:

| Suite | Runners | | Suite | Runners |
| --- | --: | --- | --- | --: |
| `autodoc` | 45 | | `lint-store` | 1 |
| `autofix` | 10 | | `lintconfig` | 1 |
| `autotest` | 67 | | `preprocess` | 13 |
| `baseline` | 1 | | `projectchecks` | 1 |
| `callresolve` | 12 | | `refactor` | 9 |
| `ergonomics` | 3 | | `rules-catalog` | 2 |
| `flowengine` | 1 | | `sarif` | 1 |
| `heritage` | 6 | | `searchparse` | 1 |
| `lint` | 1 | | `textindex` | 1 |
| `lint-project` | 4 | | | |

Full run: roughly **10 minutes** wall clock on the build box.

## Why this file exists

Through six consecutive tasks of Auto-Document Phase 3, every "full battery green"
report covered only `tests/autodoc` (45) + `tests/autotest` (67) = **112** of the 180.
The other 68 were never run. One of them, `tests/autofix/run_missing_doc_fix.ps1`, had
been red since the day the doc emitter changed; three more had been red for weeks; one
had been red since 2026-07-01. Nobody was cutting corners -- the battery simply had no
written definition, so an unstated one quietly became the definition.

Two rules follow, and they are the point of this document:

1. **The default is everything.** `-Include` exists for a fast inner loop while you are
   iterating; a task does not get to *report* on a subset. If you ran a subset, say so
   -- the driver prints `SUBSET RUN -- this is NOT the full battery` for you.
2. **Exclusions are documented or they do not exist.** The only default exclusion is
   `tests/run_battery.ps1` itself (it matches `run_*.ps1` and would recurse forever).
   Anything else added to `$DefaultExclusions` needs a one-line reason next to it.

## What is *not* a runner

`.ps1` files under `tests/` that are **not** named `run_*` are helpers or scratch, and
are never executed by the driver:

| File | What it is |
| --- | --- |
| `tests/autotest/_manifest_common.ps1` | dot-sourced prologue (`Check`, exe path) for the manifest runners |
| `tests/lint-store/enclosing-attribution/verify.ps1` | one-off verification helper |
| `tests/preprocess/lib/oracle.ps1` | oracle-corpus helper library |
| `tests/textindex/fts5_spike.ps1` | design spike |
| `tests/textindex/schema_v10.ps1` | design spike |

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
- **Win64 is the target.** Per the v0.86 policy (user ruling 2026-07-05, see
  `src/delphi-plugin/DragLint.Plugin.ExeResolver.pas`), the IDE BPL is the only 32-bit
  artifact and every process the plugin spawns defaults to the Win64 CLI.
  `third_party/dll-win32/drag-lint.exe` is a frozen fallback, last built 2026-07-05 --
  do not point a runner at it.
