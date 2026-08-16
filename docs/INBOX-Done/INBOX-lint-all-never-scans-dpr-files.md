> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (8d911f9): the lint-all file loop now admits .dpr as well as .pas. Verified -- a bare except inside SweepProg.dpr is reported and the two-file fixture says "2 file(s) scanned" (was 1).

# `lint-all` never scans a `.dpr`, so a program-only project measures as 0

Found 2026-08-13 while closing the YADF/DataCopy coverage gap.

## Reproducer

    drag-lint index --all --only YADF-GuardTest      -> files=8 symbols=1022
    drag-lint lint-all --project ...\Test\GuardTest.dproj
        0 finding(s) -- 0 file(s) scanned

    drag-lint lint-all --project ...\Test\OptionsTest.dproj
        0 finding(s) -- 0 file(s) scanned

Both indexed fine. Both scanned nothing. **That is not a zero** -- it is the same
"0 files scanned" shape that Task 0 existed to eliminate, arriving by a different
route.

## Two causes, stacked

**1. The scan filter is `.pas` only.** `DoLintAll` enumerates the store with

    if SameText(ExtractFileExt(PasPath), '.pas') and TFile.Exists(PasPath)

so a `.dpr` is never a candidate. `GuardTest.dpr` (9.8 KB) and `OptionsTest.dpr`
(6.2 KB) are entire console test programs -- `Check()` helpers, assertions, real
control flow -- living wholly in the program file. None of it can ever be
measured.

This affects every program-file-heavy project, not just these two. It also means
the `.dpr` half of any `program` unit (its `uses`, its main block, its
initialisation logic) is unmeasured everywhere.

**2. Ownership defaults to the project file's folder.** `GuardTest.dproj` sits in
`C:\Projects\YADF\Test\` while the units it compiles are in the parent
`C:\Projects\YADF\`. The default own-root is the .dproj's folder, so those units
are classified third-party and skipped -- correctly, in this case, since
`YADF.dproj` already owns them. But it leaves `Test\` owning only the `.dpr`,
which cause 1 then drops. The two defects compose into a silent zero.

This second half is a KNOWN trap ("a .dproj in a subdirectory silently scopes
lint to almost nothing" -- drag-lint's own project scanned 3 files of 97 until
`ownRoots` was declared). What is new is that it can now produce a clean-looking
`0 findings` instead of an obviously-too-small count.

## Why it matters

A test project is exactly where a silent zero is most costly: the code that
checks the product goes unchecked, and the report says everything is fine.

## Fix sketch

* Include `.dpr` (and `.dpk`) in the scan filter. Most per-file rules are
  file-kind agnostic; a program file is Delphi source like any other. Watch for
  rules that assume a `unit` header before enabling this broadly -- run the
  fixture suite over a `.dpr` before trusting it.
* Consider making `lint-all` report `0 file(s) scanned` as a WARNING (or a
  non-zero exit) rather than a success line. Every instance of it found so far
  has been a defect, never a genuinely clean project.

## Current honest status of the three projects added to the manifest today

| Project | files scanned | findings |
|---|---|---|
| `YADF-GuardTest` | 0 | **unmeasured**, not zero |
| `YADF-OptionsTest` | 0 | **unmeasured**, not zero |
| `DataCopy-Tests` | 3 | 77 |
