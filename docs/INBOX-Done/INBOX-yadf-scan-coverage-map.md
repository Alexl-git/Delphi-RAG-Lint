> **RETIRED to INBOX-Done/ on 2026-08-15.** SUPERSEDED by the per-project index layout: coverage is now answered by 'drag-lint resolve-dbs --project <x.dproj>' and lint-all's own skipped-root reporting, not by a hand-maintained map.
>
> Original note follows unchanged.

# YADF scan coverage -- what is owned, what is fixture data, what is uncovered

Written 2026-08-12 while executing Task 3b(a) of
`PLAN-2026-08-12-case-dataflow-fix-and-datacopy-cycle.md`: *prove* every owned
file is inside some project's index before claiming any zero.

The plan assumed YADF was three projects. It is **five**, plus a large body of
files that must NEVER be linted. Both halves of that matter: the first is
missing coverage, the second would be noise if "scan everything" were applied
literally.

## 1. `YADF.OptionsFrame.pas` is NOT an orphan -- question closed

Task 4.1 asked who compiles it, and warned against inventing an owner. Two
projects already do:

    YADFSetup.dpr:6        YADF.OptionsFrame in 'YADF.OptionsFrame.pas' {YadfOptionsFrame: TFrame}
    YADFSetup.dproj:104    <DCCReference Include="YADF.OptionsFrame.pas">
    YADFOT.dproj:131       <DCCReference Include="YADF.OptionsFrame.pas">

So indexing `YADFOT.dproj` and `YADFSetup.dproj` covers it. Nothing to invent,
nothing to report as unowned. (66 KB, not 68.)

## 2. Two owned projects are in NO index and NO manifest section

    C:\Projects\YADF\Test\GuardTest.dproj     -> Test\GuardTest.dpr    (9.8 KB)
    C:\Projects\YADF\Test\OptionsTest.dproj   -> Test\OptionsTest.dpr  (6.2 KB)

Both are real console test programs for YADF's own units (`YADF.Guard`,
`YADF.Options`), written in the house style. They compile the product units via
`..\`, so those units are already covered by `YADF.dproj`'s index -- the
uncovered part is the two `.dpr` files themselves, i.e. the test code.

This is precisely the failure mode Task 3b(a) describes: code we own that no
scanned project pulls in yields neither a finding nor a zero. It is simply
absent, and absence reads as success.

## 3. One genuine orphan

    C:\Projects\YADF\Test\uMainForm.pas       (2.4 KB)

Referenced by no `.dpr`/`.dproj`/`.dpk` anywhere in the tree. It looks like a
stray copy of `Demo\Parser\uMainForm.pas`. Reporting rather than adopting it,
per the plan's instruction not to invent a project to hold unowned code.

## 4. Most `.pas` files under `C:\Projects\YADF` are FIXTURE DATA, not code

This is the part a naive "scan everything we own" would get badly wrong. YADF is
a source formatter, so its test corpus is Delphi source by definition:

| Location | Count | What it is |
|---|---|---|
| `Test\Cases\*.pas` | 53 | formatter INPUT fixtures -- some deliberately malformed (`broken_unit.pas`) |
| `Test\Snippets\*.pas` | 30 | more formatter input |
| `Result\*.pas` | 32 | formatter OUTPUT -- the golden files the suite compares against |
| `Demo\**` | 11 | DelphiAST's own demo/sample code (vendored) |
| `.private\**` | 4 | issue-repro copies + a proprietary sample |

None of it should ever be linted. Linting a formatter's corpus measures the
fixtures, not the product, and `broken_unit.pas` exists specifically to be
invalid. `Result\YADF.dpr` in particular is **formatter output of `YADF.dpr`**,
not a project -- it is a stale copy (missing `YADF.LineScan` and `YADF.Guard`)
and must not be mistaken for a fifth program to index.

## The honest coverage statement for YADF

| Project | Owned source | Indexed? |
|---|---|---|
| `YADF.dproj` | 8 units + `.dpr` | YES -- 149 findings as of 2026-08-12 |
| `YADFOT.dproj` | `YADFOT.Options`, `YADFOT.Wizard`, `YADF.OptionsFrame` (+ shared) | DB exists, dated 07:41 -- reindex before trusting |
| `YADFSetup.dproj` | `uYADFSetupMain`, `YADF.OptionsFrame` (+ shared) | DB exists, dated 07:41 -- reindex before trusting |
| `Test\GuardTest.dproj` | `Test\GuardTest.dpr` | **NO -- not in the manifest** |
| `Test\OptionsTest.dproj` | `Test\OptionsTest.dpr` | **NO -- not in the manifest** |
| -- | `Test\uMainForm.pas` | **NO -- no project compiles it** |
| -- | 130 fixture/sample/output files | deliberately out of scope, see above |

## Recommended action

1. Add `YADF-GuardTest` and `YADF-OptionsTest` sections to
   `third_party\dll-win64\drag-lint.json` pointing at the two `.dproj` files.
2. Declare the fixture directories in each YADF project's
   `_D-RAG\drag-lint-project.json` (`ownRoots`) or in `exclude_paths`, so the
   exclusion is a recorded decision rather than an accident of the compile
   closure. Today they are out of scope only because no project compiles them --
   which is true but fragile, and says nothing to the next reader.
3. Decide `Test\uMainForm.pas`: delete it or give it an owner.
