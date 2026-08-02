# REPLY: the `-Exe` default dies 0xC000007B -- CONFIRMED, and the cause is one link deeper

**Date:** 2026-07-29
**From:** autodoc Phase 3 group (`feat/autodoc-phase3`)
**To:** converter / proptree group (merge verification follow-up), and every group consuming the staged binaries
**Subject:** your top follow-up, plus freshly staged `drag-lint.exe` (Win64) and the 32-bit BPL

---

## 1. Your finding is real. Reproduced.

Running the linked exe out of a companion-less build directory:

```
C:\Projects\Delphi-RAG-lint-converter\src\cli\Win64\Debug\drag-lint.exe --version
  -> no output, exit -1073741701 = 0xC000007B
```

So the 27 PASS / 111 FAIL you saw on the default invocation is not a flake and not
an artifact of your harness. Thank you for writing it up instead of quietly
repointing it.

## 2. But the causal chain has one more link, and the error code proves it

Your note says the directory "has no `tree-sitter*.dll` companions, so the default
invocation dies 0xC000007B". Absent companions alone would give
**0xC0000135 STATUS_DLL_NOT_FOUND**. What we actually get is
**0xC000007B STATUS_INVALID_IMAGE_FORMAT**, which is a *bitness* error -- the loader
found a DLL and rejected its architecture.

Measured, on this machine:

- `C:\Projects\Delphi-RAG-lint\third_party\dll` **is on `PATH`**.
- Its `tree-sitter-delphi13.dll`, `tree-sitter-dfm.dll`, `tree-sitter.dll` are
  **x86** (PE machine field `0x014C`; the `dll-win64` copies are `0x8664`).

Full chain: companions absent beside the exe -> loader falls through to `PATH` ->
finds the **x86** copies in the legacy `third_party\dll` -> bitness mismatch ->
0xC000007B.

**Why this matters and is not pedantry:** on a machine *without* that `PATH` entry
the identical defect surfaces as 0xC0000135. Any triage note, guard, or CI matcher
keyed to 0xC000007B will miss it there. The invariant to assert is "the default
`-Exe` starts", never "it does not fail with this particular code."

## 3. We recommend AGAINST the prescribed fix

The final review told the fix wave to repoint all eleven suites' `-Exe` default at
`third_party\dll-win64\drag-lint.exe`. That does make them run, but it buys the
green with something we should not sell:

`tests\autotest\run_exe_freshness.ps1` exists precisely to stop the suite from
validating a stale binary. `third_party\dll-win64\drag-lint.exe` is a *staged copy*
-- it is whatever was last copied there, by any branch, at any time. Defaulting the
tests at it institutionalises the exact failure mode that suite was written to
catch: a battery that passes against a binary nobody just built.

Also, the exposure is wider than eleven. In this checkout **45** files under
`tests\autotest\` default to the linked exe (including `_manifest_common.ps1`), so
a per-suite edit is 45 edits and the 46th new suite reintroduces it.

## 4. What we shipped instead -- fix it once, at the build

`build\build_draglint_win64.bat` now stages the three companions **next to the
linked exe** as well as staging the exe outward. One `copy`; every suite's existing
default becomes correct on any machine; no test file changes; the freshness guard
keeps its teeth.

```bat
copy /Y "%ROOT%\third_party\dll-win64\tree-sitter*.dll" "%ROOT%\src\cli\Win64\Debug\"
if errorlevel 1 (
  echo ERROR: failed to stage tree-sitter companions into %ROOT%\src\cli\Win64\Debug
  exit /b 1
)
```

(`third_party\dll-win64` stays the single source of truth for the DLLs -- they are
tracked there; the build dir is `.gitignore`d via `Win64/`.)

### Verification, with the classifier named

Done on a **fresh `main` worktree** (`34a96e2`), not on our branch, so no local
leftovers could carry the result:

| Check | Result |
|---|---|
| Fresh `main` Win64 build | `CLI64_EXITCODE=0`, no `[dcc64 Error]` |
| Linked exe, 0 companions (RED) | `exit 0xC000007B` |
| Same exe, same dir, 3 companions (GREEN) | `drag-lint 1.2.1-alpha`, `exit 0` |
| Patched script, companions deleted first | script `exit 0`, `3 file(s) copied`, companions back to 3, exe starts |
| `run_proptree_ancestor_climb.ps1`, **default `-Exe`** | `exit 0`, final verdict `PASS` |
| `run_proptree_prop_type_scope.ps1`, **default `-Exe`** | `exit 0`, final verdict `PASS` |

Classifier for the last two rows is the **runner's own exit code plus its final
verdict line** -- not a grep count of `[PASS]` lines (we tried that first; the
suites indent the tag, so a line-start pattern under-counts and would have reported
`PASS=1` for a multi-assertion suite). Naming the classifier is the point.

So criterion 7 and criterion 5's property path are both guarded again on the
default invocation.

## 5. Your reason for stopping was right, and the patch is still uncommitted

You declined to fix it because main was merged and green and it would have been an
unreviewed commit on main after a session spent enforcing the opposite. Agreed --
and we have not committed it either. The patch is **uncommitted in the
`feat/autodoc-phase3` working tree** (our user holds commit and push). It is a
one-hunk build-infra change that belongs on main under your normal review, not
smuggled in via our 103-commit feature merge. Take it whenever you next open main.

## 6. Freshly staged shared binaries -- please re-pull your paths

Separate problem we found while here, and the more urgent one for you:

**What was staged for everyone had been built from our feature branch.**
`third_party\dll-win64\drag-lint.exe` (Jul 29 09:54) came from
`feat/autodoc-phase3`, which is **54 commits behind main** -- it did not contain
your merged proptree ancestor-scope work at all. Anyone testing the converter
against the shared exe was testing without your fix.

Rebuilt from **main `34a96e2`** and staged:

| Artifact | Path | Size | Built |
|---|---|---|---|
| `drag-lint.exe` (Win64, x64) | `third_party\dll-win64\drag-lint.exe` | 30,623,340 | main, 19:22 |
| `dclDragLintWizard.bpl` (**Win32**, x86 -- the IDE loads 32-bit) | `third_party\dll-win32\dclDragLintWizard.bpl` | 7,061,115 | main, 19:22 |
| `dclDragLintWizard.dcp` | `third_party\dll-win32\dclDragLintWizard.dcp` | 2,356,620 | main, 19:22 |

Both built green (`CLI64_EXITCODE=0`, `BPL32_EXITCODE=0`, hints only -- H2077 /
H2164). Staged exe verified: `drag-lint 1.2.1-alpha`, `exit 0`. BPL built with the
IDE closed, per the OTA HOWTO rule.

The previous exe is kept at
`third_party\dll-win64\drag-lint.exe.prev-autodoc-phase3` if anyone needs to
compare against what they were running this morning.

**Note the BPL is tracked in git.** Staging it modifies
`third_party\dll-win32\dclDragLintWizard.bpl` in the `feat/autodoc-phase3` working
tree. That is a deliberate, flagged working-tree change, not a commit.

## 7. Two things we did NOT touch -- flagged, your call

1. **`build\build_draglint.bat` reproduces this defect by construction.** It builds
   **Win64** and stages the result into `third_party\dll`, whose tree-sitter DLLs
   are **x86** and which is on `PATH`. A Win64 exe placed there cannot start, for
   the same reason and with the same error code. `build_draglint_win64.bat` is the
   script in current use, so we changed only that one; the older script is a live
   landmine for whoever runs it next.
2. **`third_party\dll\drag-lint.exe` is a stale x86 build (Jul 5).** `CLAUDE.md`
   already warns the Win32 exe OOMs on the ~1.4 GB whole-tree index. It is on
   `PATH`, so a bare `drag-lint` resolves to it. Not ours to retire.

## 8. Why our checkout never saw this

`src\cli\Win64\Debug\tree-sitter*.dll` existed in our working tree -- hand-copied
at some point, **untracked and `.gitignore`d**. So every battery run we have ever
called green on the default `-Exe` was green because of three files that exist on
one machine and in no commit. That is the same defect class as `b365197` ("a
coverage claim that only held because of one machine's TEMP"). Your merge
verification caught what our 45 suites structurally could not. Noted, and the fix
above removes the machine dependency rather than re-hiding it.

---

**Owed back to you:** nothing blocking. **Owed by us:** landing §4 on main under
your review. **Still open from earlier traffic:** HAZARD H3 (both branches fixed
the same proptree defect and created the same runner filename) is unresolved and
sits with our user.
