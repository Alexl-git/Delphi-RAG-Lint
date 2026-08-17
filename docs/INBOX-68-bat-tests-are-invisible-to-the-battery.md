# INBOX -- 68 `.bat` tests under `tests\` are invisible to the battery, and 43 point at a retired exe

**Found:** 2026-08-16 (session 24), while fixing `resolve-uses`. Its ONLY
existing coverage was one of these files, which is why a user-visible defect in
a verb `docs\AI-USAGE.md` recommends survived indefinitely.

**Class:** coverage gap. Not a defect in the engine -- a defect in what we
believe about the engine.

## Measured

```
total .bat under tests\                               68
  ... referencing third_party\dll\drag-lint.exe       43
  ... referencing dll-win64                            0
  ... referencing neither                             25
```

`tests\run_battery.ps1` collects **`run_*.ps1`, recursively**. None of these 68
are collected. They are not skipped, not reported, not counted -- they are not
seen at all, so nothing anywhere says they did not run.

The retired path still exists and still runs:

```
third_party\dll\drag-lint.exe        2026-08-13  26.2 MB   (Win32)
third_party\dll-win64\drag-lint.exe  2026-08-16  30.5 MB   (Win64, current)
```

Both report `1.3.0-alpha`, so **the version string cannot tell them apart** --
a run against the stale one looks like a run against the current one. And
`C:\Projects\CLAUDE.md` retired the Win32 exe for a reason: it OOMs on the large
indexes.

## Why this is worse than "some old tests rotted"

Three compounding properties, and the third is the one that bites:

1. **They look like coverage.** 68 named integration tests spanning schema,
   MCP, LSP, hover, rename, refactor, lint rules, workspace config. A reader
   counting test files gets a number that has nothing to do with what is
   verified.
2. **They are silent.** A skipped-and-reported test is a known gap. These
   produce no line at all.
3. **A real defect actually hid behind one.** `T_resolve_uses.bat` covers
   `resolve-uses` INCLUDING its "already in uses" detection -- and it passes,
   because it puts both units in ONE database, which is precisely the
   configuration in which the multi-DB bug cannot appear. The file's existence
   is what made `resolve-uses` look tested. See
   `INBOX-find-unit-silently-uses-only-the-last-db.md`.

## What this note is NOT claiming

**Not measured:** whether these 68 currently pass, fail, or error. Nobody ran
them. Some are certainly obsolete (they reference `v016`-`v021` doctest
vintages, and several test IDE forms that need a live IDE). The claim here is
only that **their status is unknown and nothing reports that**, which is the
same failure mode as a green suite that asserts nothing.

Do not "fix" this by pointing them at the Win64 exe and running them -- that
would convert an unknown into a large pile of unattributed red with no triage
budget attached.

## Suggested shape, cheapest first

1. **Make the gap visible before closing it.** Have `run_battery.ps1` COUNT the
   `.bat` files it is not running and print one line
   (`68 legacy .bat test(s) under tests\ are NOT run by this battery`). One
   line, no behaviour change, and the number stops being invisible. This is the
   part worth doing immediately.
2. **Triage in batches, by subsystem**, converting what still describes current
   behaviour into `run_*.ps1` and DELETING what does not. A deleted obsolete
   test is a better outcome than a retained one that never runs.
3. Anything needing a live IDE stays out of the battery by nature -- but should
   say so in its own header rather than by being unreachable.

## The general lesson, worth stating once

A test harness that DISCOVERS tests by filename pattern silently defines
"coverage" as "files matching the pattern". Everything else becomes invisible
without any error being raised anywhere. The same property is what makes
`.gitignore`d rule directories and `Grep`'s hidden-directory skip bite in this
repo -- see the existing memory entries on both.
