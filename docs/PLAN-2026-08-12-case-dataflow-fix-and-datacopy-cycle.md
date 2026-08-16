# PLAN -- fix the `case` dataflow defect, then drive DataCopy to zero

Written 2026-08-12 for execution in a fresh session. Owner ruling: the `case`
defect is URGENT and comes BEFORE pushing any project to zero, because marking a
false positive as "reviewed and accepted" records something untrue about the
code, permanently, with a hash attached.

`main` = `d21e7d3`, 9 unpushed. Battery 259 runners, green.

## Correct the record before anything else

**YADF is at 149 findings, NOT 0.** The `0` seen in the previous session came
from `lint-all --project`, which reports `0 finding(s) ... 0 file(s) scanned` on
a correctly-indexed project. That is a defect, not an achievement. The same
project via `lint-all --db` reports 149 findings over 8 files.

    drag-lint lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite --quiet   # 149, works
    drag-lint lint-all --project C:\Projects\YADF\YADF.dproj    --quiet   # 0, broken

Nothing in YADF has been fixed or marked. Its only change is commit `0c5b546`,
which checkpointed pre-existing autodoc output.

## Task 0 (BLOCKING) -- `lint-all --project` scans 0 files

**Promoted ahead of the `case` fix because LoopZero cannot run without it.** Step
4 of the cycle is `lint-all --project <file.dproj>`, and that command currently
reports `0 finding(s) ... 0 file(s) scanned` on a correctly indexed project. Five
LoopZero runs are queued (Tasks 4-5), each measuring twice a round, so every one
of them would route around a broken command -- or worse, read `0 files scanned` as
a zero. That already happened once and cost a session.

    drag-lint lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite --quiet   # 149, correct
    drag-lint lint-all --project C:\Projects\YADF\YADF.dproj    --quiet   # 0, broken

**Do NOT chase a missing-member theory -- it was checked and there is none.**
`YADF.dpr` is complete (8 units: Tokens, Options, Groups, Guard, LineScan, Layout,
Debug, YadfMain). The index holds exactly 18 files: those 8 + `YADF.dpr`, plus
DelphiAST's 9 pulled in transitively as compile closure and correctly excluded
from the owned count. Nothing else is in there. The four stray `.pas` in
`C:\Projects\YADF` (`YADF.OptionsFrame`, `YADFOT.Options`, `YADFOT.Wizard`,
`uYADFSetupMain`) belong to the sibling projects, which have their own DBs in the
same `_D-RAG` folder.

So `--project` RESOLVES its members correctly and then scans none of them. **The
bug is in the scan step, not in membership resolution.** The 8/9/10 spread is
benign: 8 lintable units, 9 files in the index (+ the .dpr), and the "10 source
file(s)" the message reports.

Add a regression test: a fixture project whose `lint-all --project` count equals
its `lint-all --db` count. Neither number may be 0 -- a test that passes when both
are 0 is exactly the test that would have missed this.

Logged in `stats/draglint-gaps.log`.

## Task 1 (URGENT) -- the `case` else-arm is never emitted into the CFG

**File:** `src/analysis/DRagLint.Analysis.Cfg.pas`, the `if K = 'case'` block at
**lines 639-657**.

Lines 648-655 walk the `caseCase` children and emit a block per branch body.
Line 656 then does:

    Cfg.Blocks[ACur].AddSucc(JoinIdx); { else / no-match fall-through }

The `else` BODY is never emitted. Consequences: assignments inside `case..else`
are invisible, and the CFG carries a path that assigns nothing.

**The correct shape is already in the same file**, in the `if` handler at lines
628-635: fetch the else node, emit it as its own block, join it, and add the
direct `ACur -> JoinIdx` edge ONLY when there is no else.

Open question to settle first: what node type / field holds a case's else arm in
tree-sitter-delphi13? The `if` handler uses `ANode.ChildByField('else')`. Check
whether `case` exposes the same field or a distinct node type (e.g. `caseElse`).
Dump a parse tree rather than guessing -- `drag-lint check-ast <file>` or the
`dumptree` helper under `scratchpad\`.

**Careful:** a `case` WITH an else is exhaustive, so after the fix the direct
`ACur -> JoinIdx` edge must be dropped in that case, or `function-result-not-set`
will keep firing.

Reproducer (real, tracked): `C:\Projects\YADF\YADF.Options.pas:593-601`

    function EncodingOf(const E: TYadfEncoding): TEncoding;
    begin
      case E of
        encUTF8BOM : Result:= TEncoding.UTF8;
        encUTF16BOM: Result:= TEncoding.Unicode;
        else
          Result:= TEncoding.ANSI;
      end;
    end;

Expected after fix: no `function-result-not-set` finding.

## Task 2 (URGENT) -- reads in the case SELECTOR are not counted

`write-only-local` claims `CurLineLast` is "assigned but never read" at
`YADF.Layout.pas:3325`, but it IS read at line 3512: `case CurLineLast of`.
(Assigned 3489, 3520, 3541, 3781; read only at 3512.)

**This one is NOT diagnosed.** Lines 641-646 of the `case` handler do appear to
add the selector as a block item, so the naive explanation is wrong. Do NOT
patch on the hypothesis. Write the mock fixture first (Task 3), confirm the
failure reproduces in isolation, and only then find the mechanism. Candidates
worth checking: whether `write-only-local` consults the CFG at all, whether
`AddItem` on the selector marks it as a read or only as a visited node, and
whether the `Break` at line 645 stops before the selector when child ordering
differs.

## Task 3 -- mock fixtures, not a full YADF run

The owner explicitly approved mock tests; a whole-YADF run is not needed to
prove either fix.

Existing harness to model on: `tests/flowengine/FlowEngineTests.dpr` +
`run_flowengine_tests.ps1`, and the fixture style under `tests/fixtures`.

Minimum cases:
1. `case..else` where every arm assigns `Result` -> no `function-result-not-set`.
2. `case` with NO else, where a fall-through path leaves `Result` unset -> the
   finding MUST still fire. This is the regression guard; a lazy fix that simply
   deletes the fall-through edge would break it.
3. A local read only in a case selector -> no `write-only-local`.
4. A local genuinely never read -> `write-only-local` MUST still fire.

Cases 2 and 4 matter as much as 1 and 3: the risk here is silencing a real rule.

Then re-measure YADF (expect below 149) and record the new number.

## Task 3b -- THE STANDARD: everything we own is scanned, and every finding lands

Owner ruling, 2026-08-12, and it governs every project from here on:

> If it is not third-party and it is part of our project, it has to be scanned
> and analyzed, and then FIXED IN THE LINTER, FIXED IN THE SOURCE, or ALLOWED.
> Nothing else counts as done.

Two halves, and the first is the one that gets skipped:

**(a) Scan everything we own.** Not "everything the default command happened to
scan". A project index is the compile closure of ONE project file, so code we own
that no `.dproj` in the scan pulls in is invisible -- it does not appear as a
finding, and it does not appear as a zero either. Before declaring any repo at
zero, enumerate the owned source on disk and prove every file is covered by some
project's index.

**YADF is THREE projects, not one.** `YADF.dproj`'s closure is 8 units. Also
owned, and NOT in it:

| File | Owning project |
|---|---|
| `YADF.OptionsFrame.pas` (68 KB) | not in YADF.dpr's closure -- resolve where it belongs |
| `YADFOT.Options.pas`, `YADFOT.Wizard.pas` | `YADFOT.dproj` |
| `uYADFSetupMain.pas` | `YADFSetup.dproj` |

DBs already exist beside them: `_D-RAG\YADFOT.sqlite`, `_D-RAG\YADFSetup.sqlite`
(both dated 2026-08-12 07:41 -- reindex before trusting). `YADF.OptionsFrame.pas`
needs its owner established first; if no project compiles it, say so rather than
quietly leaving ~68 KB unmeasured.

**DataCopy is TWO projects:** `DataCopy.dproj` and `SortTest.dproj`.

Task 4 executes this for the YADF family; Task 5 for DataCopy.

**(b) Every finding resolves, in this order of preference:**

1. **Fix the rule** when the finding is wrong. Highest value -- one fix deletes
   findings across every project at once, and it is the only outcome that also
   improves the tool. The `case` defect in Tasks 1-2 is the model.
2. **Fix the source** when the finding is right and the change is worth making.
3. **Allow** (`drag-lint allow`) when the finding is right but the code should
   stand as written, or it is a false positive we cannot practically fix.
   Accountable, per-line, self-invalidating -- and a deliberate LAST resort.

Never allow something in class 1. Marking a false positive as reviewed records
something untrue about the code, permanently, with a hash attached, in every
project that carries the same pattern.

**Definition of done for a repo:**

* every owned file is inside some project's index (half (a) above, demonstrated,
  not assumed);
* `lint-all` reports 0 findings at EVERY severity -- info and hint included (YADF's
  149 are 146 info + 3 hint, so an error-only or warning-only zero is not zero);
* `review-marker-stale` and `review-marker-unused` are also 0, otherwise the
  marker corpus itself is the remaining debt;
* the allow corpus is reviewable in one command -- `grep -rn "dl:ok" <repo>` --
  and every entry is defensible.

## Task 4 -- LoopZero, three times, on the YADF family

The cycle is now a SKILL: `~/.claude/skills/loopzero/SKILL.md`, invoked as
**LoopZero &lt;project&gt;**. It is one project per run -- reindex, autodoc, reindex,
lint-all, triage -- with a convergence guard on autodoc, an explicit termination
rule, and the done criteria. Read it; do not re-derive the cycle here.

**Three runs. YADF.dproj is NOT already done.** Its 149 findings have had no
triage at all; the `case` fix in Tasks 1-2 will dent that number, not clear it.

* **4.1 -- resolve `YADF.OptionsFrame.pas` (68 KB) FIRST.** It is not in
  `YADF.dpr`'s uses clause. Check `YADFOT.dproj` and `YADFSetup.dproj`. If NO
  project compiles it, that is the finding: report it. Do not leave 68 KB
  unmeasured, and do not invent a project to hold it.
* **4.2 -- LoopZero YADF.dproj.** Baseline 149 (146 info + 3 hint) as of
  2026-08-12, minus whatever Tasks 1-2 remove. **Strongest safety net in the whole
  plan:** `C:\Projects\YADF\Test\run_tests.ps1` -- 22 scripts, 84 golden files, 53
  cases, 32 snippets. Source fixes here are verifiable against OUTPUT, not merely
  "it compiles". It fails fast if the exe is stale, so rebuild first. Be bolder
  here than anywhere else.
* **4.3 -- LoopZero YADFOT.dproj.** Design-time BPL (IDE wizard). **Build with the
  IDE CLOSED**; consult `C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md` before
  touching anything wizard-shaped -- those traps compile clean and fail only in a
  live IDE. DB `_D-RAG\YADFOT.sqlite` dates from 2026-08-12 07:41; reindex first.
* **4.4 -- LoopZero YADFSetup.dproj.** No golden coverage -- compile-verified only,
  so prefer `allow` over risky source edits. DB `_D-RAG\YADFSetup.sqlite`, same
  stale timestamp; reindex first.
* **4.5 -- confirm nothing is left.** Run `lint-all --db` against each of the
  three DBs (they are three, one per project, not one).

**What "the DB says 0" does and does not mean.** The default `--db` run is
ownership-filtered and CAN reach 0. Adding `--lint-third-party` will report
roughly 22,600 more findings from vendored **DelphiAST**, pulled into YADF's index
as part of the compile closure. That is CORRECT and is not a regression -- vendored
upstream code is not ours to restyle. Do not chase it, and do not be alarmed by it
six weeks from now.

YADF is git, branch `autodoc-phaseC`, clean at `0c5b546`.

## Task 5 -- LoopZero, twice, on DataCopy

**DataCopy is TWO projects:** `DataCopy.dproj` and `SortTest.dproj`. Mercurial,
branch `default`. Repo `C:\Projects\DataCopy`. It was dirty at last inspection
(5 modified, 5 untracked) -- commit that as the starting point, labelled
pre-existing, before the loop touches anything.

Baseline from the previous session: **493 findings** (doc-drift 192,
used-unit-not-resolvable 99, commented-out-code 55).

* **5.1 -- LoopZero DataCopy.dproj**
* **5.2 -- LoopZero SortTest.dproj**

**Sample doc-drift (192) and used-unit-not-resolvable (99) BEFORE fixing
anything.** Together they are 59% of the total, and that shape -- one huge
category -- has been majority-false every time it has been checked. Fixing those
two rules could delete most of the 493 without touching DataCopy's source at all,
and it would carry over to every other project. This is the single highest-value
move in the plan after the `case` fix.

Note: DataCopy exes built by msbuild cannot run (EurekaLog options are
IDE-injected), so "it builds" is the verification ceiling for some changes there.

## Task 6 -- backlog uncovered on the way

* **`field-name-prefix` advertises `fixable: true`** in `rules --json`, but
  `lint --fix --fix-rule field-name-prefix` answers "no fixable findings". One of
  the two is lying. Until resolved, treat the catalogue's fixable flag as unproven.
* **`field-name-prefix` false positive:** flags 2 of the 7 public fields on
  `TGroup` (`YADF.Groups.pas:39-46`) with no coherent policy. `F` is the
  convention for private backing fields, not public data members of a
  record-like class.
* **`empty-except` / `empty-case-branch` are comment-sensitive**, so writing any
  marker silences them as a side effect. One `allow` can clear two messages, which
  bends the "only this one message" rule. Pre-existing and measured; see
  `COMMENT_SENSITIVE` in `DRagLint.CLI.pas`.
* **VS Code `allow`** is a DISTANT item and is engine work, not protocol work:
  nothing under `src/lsp/` honours markers at all. See
  `docs/INBOX-vscode-allow-codeaction-and-lsp-marker-filtering.md`. Prior art on
  branch `salvage/lsp-codeaction-agent`.
* **Share the marker hash with YADF** to VERIFY and warn, never to refresh. See
  `docs/INBOX-yadf-share-review-marker-hash.md`.

## Notes carried forward

* Run the battery with `pwsh`, never `powershell.exe`.
* The Write tool emits LF; `.pas`/`.dpr`/`.ps1`/`.md` here are strict 7-bit ASCII
  + CRLF. `run_encoding_guard.ps1` catches it -- it caught this session's new
  test script. Byte-check after every write.
* Stage INBOX notes explicitly; `git add -A docs` sweeps ~50 untracked ones.
* Kill the episodic-memory `sync-cli.js` PARENTS at session start. In this
  session two were live and had committed straight to `main`; their work is
  preserved on `salvage/lsp-codeaction-agent`.
* Do NOT `git reset --hard` to unwind commits while unrelated edits are live in
  the working tree -- it discarded uncommitted FEATURES.txt and PLAN-doc edits
  this session, unrecoverably. Use `--mixed`, or stash first.
