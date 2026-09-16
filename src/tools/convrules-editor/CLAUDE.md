# convrules-editor -- converter stream instructions

## THE ENGINE UNDER THIS EDITOR IS PINNED. CHECK IT BEFORE YOU WORK.

The rule editor shells out to `drag-lint.exe` for six verbs (`proptree`,
`query descendants`, `query find`, `query --name`, `convert-scaffold`,
`convert-validate` -- all in `ConvRules.Engine.pas`). The **engine stream builds
that exe from the same working tree we develop in.**

On 2026-09-14 the deployed engine was rebuilt at **12:55 and again at 14:02
during one converter session**. Verification done at 12:55 was, by 14:02, a
statement about bytes that no longer existed at that path. Nothing announced it;
the file simply changed.

So: **the editor runs against a pinned snapshot, and the first thing any session
here does is check whether that pin has fallen behind.**

### Run this at session start, and again before any GUI or engine-touching work

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-engine-drift.ps1
```

| exit | meaning | what to do |
|---|---|---|
| 0 | pin matches the deployed engine, no new INBOX notes | carry on |
| 1 | **action needed** -- engine drifted, or new/open notes addressed to us | read the listed notes, then decide whether to re-pin |
| 2 | **cannot answer** -- pin or engine missing/unreadable | fix that first; never read a 2 as "fine" |

**Match on the exit code, not on the text.** Exit 2 exists precisely so a
misconfigured check cannot pass silently.

The script is read-only and keeps no "last checked" state, so running it can
never itself become the thing that drifts. Its baseline is always the pin's own
manifest.

### >>> THE TRAP: the version STRING is not a drift signal

Both the 12:55 and the 14:02 builds reported `drag-lint 1.11.0-alpha`. Only the
SHA256 and the build timestamp moved. **Never conclude "same engine" from a
matching version.** The check compares bytes for this reason; so should you.

### Where the pin lives, and how the editor finds it

`third_party\engine-pinned\<version>-<yyyyMMdd-HHmmss>\`, holding
`drag-lint.exe`, its tree-sitter DLLs, `drag-lint.json`, the full `rules\` tree
(111 files) and `ENGINE-PIN.json` -- the manifest recording version, build stamp,
SHA256 and what was verified at pin time.

`ConvRulesEditor.exe` is copied in beside it, and
`ResolveDragLintExe` (`ConvRulesEditor.dpr:48-50`) prefers a `drag-lint.exe`
sitting next to `ParamStr(0)`. **Launch the editor FROM the pin directory and it
uses the pinned engine with no code change.** Launch it from anywhere else and it
falls through to `third_party\dll-win64\` -- the live, rebuilt-without-warning
one.

The snapshot is gitignored (`third_party/engine-pinned/`); the rule and the check
that govern it are tracked. `*.exe` alone was not enough -- it would have hidden
the binaries and still committed 111 rule files.

### Re-pinning

Copy the `dll-win64` tree to a new `<version>-<stamp>\` folder, write a fresh
`ENGINE-PIN.json`, and **verify the new pin RUNS before trusting it**: `info`
must report the *pinned* paths for its tree-sitter DLLs, `rules` must report a
non-zero count, and one real query must answer. A pin that exists but cannot
answer is worse than no pin -- it is an authoritative-looking baseline for an
engine that was never checked.

Re-pin when the engine change is *settled*, not mid-sweep. A pin taken halfway
through a breaking change buys nothing.

## Standing state with the engine stream (as of 2026-09-14)

* **`resolved_defaults` was never built** (zero occurrences in `src\`). Do not
  start anything that consumes `convert-apply` findings until it ships -- that
  array is the ~2,156-item informational flood. The editor calls no
  `convert-apply` today, so nothing current is affected.
* **The `--db` strictness sweep is in flight** in the shared tree. It costs us
  nothing by construction: our DB set is three hardcoded paths that all exist,
  and `DbArgsFor` (`ConvRules.Engine.pas:544`) filters empty entries so an unset
  `GEditorProjectDb` never reaches a command line. The only exposure is a typo in
  `--project-db`, which already fails today on the strict `query --name`.
* **The stdout -> stderr move for engine errors is a non-event here.**
  `RunCapture` sets `SI.hStdError := WritePipe` (`ConvRules.Engine.pas:580`) --
  both streams already land in one pipe, and we gate on the exit code.
* **`query descendants` exit-1-on-success is fixed** in the pinned engine
  (verified: 6,324 names -> exit 0; unknown ancestor -> exit 1). The `Code = 2`
  workaround at `ConvRules.Engine.pas:756` stays *correct* either way; removing
  it is optional cleanup, not a fix.

## Replying to the engine stream

Notes arrive as `docs\INBOX-*engine-to-converter*.md`; ours go back as
`docs\INBOX-REPLY-*.md`. The drift check lists both, newest first. **Re-verify an
inherited claim against the tree before repeating it** -- the 2026-09-14 ledger
found five items that read as open in the correspondence and were already done,
and one that read as answered and was not.
