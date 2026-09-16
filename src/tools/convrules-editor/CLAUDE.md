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

* **`resolved_defaults` HAS SHIPPED (corrected 2026-09-16).** This entry said it
  "was never built (zero occurrences in `src\`)" and told the next session not to
  start anything consuming `convert-apply` findings until it landed. It landed as
  `7f5ce20`: a real run on VARINSP prints `ResolvedDefaults: 8 property value(s)
  carried from their declared defaults (--format json lists each)`. The advice was
  correct when written and became a brake on work that was already unblocked.

* **`convert-apply` needs the unit to be INDEXED, and says something else when it
  is not (2026-09-16).** It reports `could not locate .dfm object block for "<x>:
  <Type>"` -- an assertion about the .dfm's content that is FALSE. Measured: a
  261-byte fixture with the block at depth 1 fails; index that folder and the
  identical run converts. VARINSP produced 20 of these and converted 0 of 20;
  indexed into its own DB it converts **20 of 20, 60 edits**. Do not go looking in
  the .dfm -- check the `--db` set first. Filed as
  `docs\INBOX-2026-09-16-converter-to-engine-dfm-block-needs-indexed-unit.md`.

* **The class cast is still not realized, and the .dfm half DROPS the image.**
  `#link OptionsImage.Glyph <- Picture : AssignGraphic` is skipped on the `.pas`
  side, and the re-emit reports `dropped Picture.Data` -- so twenty buttons lose
  their glyphs silently. `--castlib` executes **enum blocks only** (its own help
  says so); `TCastDef.PasTemplate` is parsed at
  `src\report\DRagLint.Convert.CastLib.pas:375` and read nowhere in `src\`. This
  is engine item 6, `realize-class-casts`, 3-5 d, planned in
  `PLAN-SESSION-95-OPEN-NOTES.md`. It is the ONLY remaining gap in the
  conversion; everything else lands.
* **The `--db` strictness sweep has LANDED, and the "costs us nothing" reading of
  it was WRONG (corrected 2026-09-15).** The claim recorded here was that our DB
  set is three hardcoded paths that all exist, so strictness could not touch us.
  That measured EXISTENCE. The strictness is about **SCHEMA**: a read verb now
  refuses an index at an older schema, and on 2026-09-15 the ORM3
  `Micronite2027.sqlite` sat at v21 against an engine wanting v22.

  It cost 12 test failures (`picker.*`, `platform.rescope.*`, `proptree.bareclass.*`)
  and would have blocked a GUI session at the first class pick. **A stale DB is a
  file that exists perfectly.**

  Two properties worth knowing before you debug this shape again:

  * **One stale `--db` fails the WHOLE query.** The error is `exit 2` with
    "Nothing was answered", even though the other DBs in the list are healthy and
    could answer. So a single stale index takes down every editor query, and the
    message names the stale DB -- read it, do not assume the engine broke.
  * **The migration is nearly free when the sources have not changed.** The fix
    was `index --project Micronite2027.dproj --db <db>`: **2.0 s, 624 files, all
    624 "up-to-date"** -- a schema migration, NOT a re-parse. Do not budget hours
    for this or route around it; just run it.

  `DbArgsFor` (`ConvRules.Engine.pas:544`) filtering empty entries is still true
  and still irrelevant to this. Note also that `--project-db ''` does NOT disable
  the project DB: `ConvRulesEditor.dpr:205-206` re-defaults an empty value to the
  hardcoded `ProjectDb`.
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
