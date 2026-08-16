> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16. Both halves: build_draglint_win64.bat now stages rules\*.scm/*.json into BOTH src\cli\Win64\Debug\rules and third_party\dll-win64\rules (verified -- a deliberately drifted deployed file was restored by the build), and run_battery.ps1 K41 was upgraded from PRESENCE to CONTENT, hashing rules\ against both deploy dirs and naming every drifted file (verified in both directions: drift detected and named, clean state reports "matches rules\ by content: yes"). Release/Win32 corpora are deliberately NOT staged -- decide separately whether to sync or delete them.

# Editing `rules\*.scm` changes nothing until you hand-copy it to three other directories

Filed 2026-08-16 (session 21), hit while fixing
`INBOX-bare-except-anchor-defeats-a-hand-written-marker.md`.

Class: **wrong** (build/deploy), and it is in the **silent no-op** family --
the edit succeeds, the build succeeds, the tests pass, and the change is simply
not in effect.

## What happened

`rules\bare-except.scm` was edited and verified directly:

```
drag-lint lint <fixture> --rules-dir rules      -> new behaviour, correct
```

Then the test suite was run and **passed**, i.e. reported the OLD behaviour as
still correct. Nothing had gone wrong with the fix; the suite was reading a
different copy of the file.

## Root cause

There are **four** copies of the rule corpus on disk and no automated sync:

| directory | who reads it | files |
|---|---|---|
| `rules\` | **source of truth**; only when `--rules-dir` is passed explicitly | 114 |
| `third_party\dll-win64\rules\` | the staged exe, i.e. the battery's default `-Exe` | 113 |
| `src\cli\Win64\Debug\rules\` | the freshly linked exe, which ~51 suites resolve | 114 |
| `src\cli\Win64\Release\rules\` | Release builds | 111, **35 files behind** |
| `third_party\dll\rules\` | the old Win32 exe | 28, **104 files behind** |

`TRuleCatalog.BuildCatalog('', '')` "reads the default `<exe-dir>\rules`" (its
own comment in `DRagLint.CLI.pas`), so **the exe's own directory wins** and the
repo's `rules\` is not consulted at all unless asked for by flag.

`build\build_draglint_win64.bat` stages `drag-lint.exe` and the tree-sitter DLLs
into both exe directories. It does **not** stage `rules\`. Nothing else does
either -- `grep -l rules build\*.bat` returns only the unrelated ConvRules
editor scripts.

The Win32 and Release copies being 104 and 35 files behind is the same defect
already having happened and gone unnoticed.

**`.gitignore` already says which one is source.** `third_party/*/rules/`
(line 63) and `Win64/` (line 14) are ignored, so `rules\` is the ONLY tracked
corpus and the other three are declared build outputs -- build outputs that
nothing builds. Staging them is completing a decision the repo has already
recorded, not a new judgement call.

## HALF OF THIS IS ALREADY KNOWN -- and the existing check is the near miss

`tests\run_battery.ps1:258-286` (**register K41**) already states the diagnosis
in as many words: *"That directory is GITIGNORED and nothing stages it, so a
fresh checkout has none and those runners fail without ever saying why."* It
prints a loud red precondition banner naming the exact `Copy-Item` fix, and then
continues anyway on the reasonable grounds that a battery which refuses to start
hides more than it saves.

**But it tests PRESENCE, not CONTENT:**

```powershell
(-not (Test-Path -LiteralPath $p)) -or
(@(Get-ChildItem ... -Filter '*.scm' ...).Count -eq 0)
```

A directory with 113 stale `.scm` files passes that check, and prints
`rule catalogue beside the exe : present`. That is precisely the state this note
was filed from: the banner said present, the battery ran, and it measured the
OLD rule. So the gap is not "nobody noticed" -- it is that the existing guard
stops one step short, at *is there a corpus* rather than *is it THE corpus*.

`build\pack-lint-release.ps1:38-41` does stage `rules\` into the release
staging dir, so shipped artifacts are fine. Only the two development exe
directories are unserved, which is why this bites development and not users.

Some suites work around it per-run -- `tests\lint\run_lint_tests.ps1:40-43`,
`tests\lint-store\run_store_tests.ps1:49-52` and
`tests\autotest\run_report_encoding.ps1:81-82` each copy `rules\*` into their own
temp bin first, which is why THOSE suites correctly caught the rule change while
others silently did not. That inconsistency is itself worth collapsing into one
mechanism.

## Why it is worse than a stale file

The failure is **silently green in the wrong direction**. A rule edit that
loosens a rule is inert, so the suite keeps passing and the author concludes the
rule was already correct. Worse, the reverse: a suite that passes against a
STALE rule corpus is not testing the rules in the tree, and `run_exe_freshness`
does not close this -- it checks exe existence and mtime-vs-newest-source, and
never looks at `rules\` at all (its own comment says it does not look for the
tree-sitter DLLs beside the exe either, and this is the same blind spot one
directory over).

## Fix -- pick one, but the guard is the part that matters

1. **Stage `rules\` in `build_draglint_win64.bat`**, next to the existing
   tree-sitter `copy /Y`, into BOTH `src\cli\Win64\Debug\` and
   `third_party\dll-win64\`. Cheapest, matches how the DLLs are already handled.
2. **Resolve the rules dir from the repo, not the exe dir** -- removes the
   duplication entirely, but changes behaviour for a shipped//installed exe that
   has no repo beside it, so it needs a fallback and is the bigger change.

Either way, **upgrade K41 from presence to content**: hash `rules\*.scm` +
`*.json` against each live deploy directory and report drift with the same red
banner it already prints. That is a few lines inside a check that exists, and it
is the single highest-value part of this note -- fix (1) without it just moves
the day the corpora diverge again.

`tests\autotest\run_exe_freshness.ps1` is the other candidate home ("is the
artifact you are testing the artifact you built" -- the same question about a
sibling input), but K41 already owns this and already runs first, before any
suite can be misled.

Decide separately whether `src\cli\Win64\Release\rules` and
`third_party\dll\rules` should be synced or **deleted**. Two corpora that are 35
and 104 files behind are not deploy targets anyone is maintaining, and deleting
them is a smaller promise than keeping them correct.
