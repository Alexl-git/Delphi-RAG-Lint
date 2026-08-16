# RESUME -- 2026-08-14 (session 19)

Supersedes `RESUME-2026-08-14-session18-anchor-and-rule-fixes.md`.

## Status

Branch **`session18-q0-orphan-anchor`**, **not pushed**. `main` untouched at
`17e3fb1`. Tracked `src/ tests/ rules/ editors/` clean at the last commit;
`docs/INBOX-*.md` and `docs/probe-*.pas` are intentionally UNTRACKED -- do NOT
`git add docs`.

Session 18 ended at 8 commits. This session added 4 more (see the table), plus
one batch pending at the time of writing -- check `git log` rather than trusting
this count.

| commit | what |
|---|---|
| `91c3e55` | the OWED cap-parity guard, non-vacuous at last |
| `602ae0b` | dangling-else `if/else` is an `exprIf`, and `EmitStmt` had no arm |
| `587546e` | LSP fatal wrote its only diagnostic INTO the JSON-RPC stream |
| `ebec205` | the doc writer honoured `ownRoots` but ignored `exclude_paths` |
| `84be4c9` | four scanners reading comment prose as code + two node-shape bugs |

Tracked tree is CLEAN at `84be4c9`. Untracked and expected: `docs/INBOX-*.md`,
`docs/probe-*.pas`, `docs/RESUME-*.md`, `lint-report-*.txt`, `tools/lsp-diag/`.

**Battery: 279 pass / 0 fail / 0 timeout out of 279 executed (of 280 found), on
the committed state `84be4c9`.** Fully green -- the earlier `run_exe_freshness`
failures during the session were correct (source newer than the exe) and cleared
once the final build was deployed before committing. All nine new/extended
runners are in that count.

One honest limit inside the green: `run_lint_project_db_resolution.ps1`'s new
case 4 is **NON-DISCRIMINATING** on the existing fixture -- both indexes return 5
findings for `UnitA.pas`, because the rules that fire there are syntactic and
never ask the store. The test SAYS SO in a `[NOTE]` rather than presenting a
green assertion that cannot fail. So the `ResolveConsumerDbs` membership fix is
REASONED (it matches what `resolve-dbs --in` already did) but NOT PROVEN by a
test. To make it real, `UnitA` needs a finding from a store-backed per-file rule.

## Counts

| project | session-18 end | now |
|---|---|---|
| drag-lint own source | 1607, 0 err | **1581, 0 err**, 253 warn, 2 hint |
| YADF | 6 | **6** |
| YADFOT | 8 | **6** |
| YADFSetup | 10 | **10** |
| `object-leak` (YADF/OT/Setup) | 3 / 7 / 7 | **1 / 1 / 1** (one shared finding) |
| prose-derived `Calls:` entries, own corpus | 150 | **0** |

Autodoc on our own source CONVERGES ("1029 public decl(s), nothing to
document") and `third_party\delphi-tree-sitter` stays clean under a real run.

## What the owner asked for, and where it landed

> "VS Code still has problem starting our drag-lint"

Two real defects, both fixed in `587546e`, and the load-bearing one was the
CLIENT:

* **The engine was healthy the whole time** -- a stock `initialize` handshake
  returns exit 0, 32 FTS5 probes and the full capability set from every candidate
  CWD. The symptom was `vscode-languageclient`'s CIRCUIT BREAKER, latched by this
  session's own engine redeploys: `dragLint.serverPath` deliberately points at the
  same deployed binary the Delphi IDE loads, so a rebuild overwrites the file the
  running server is executing from, and 5 crashes in 3 minutes is the stock
  give-up policy. The extension contributed NO commands, so the only recovery was
  *Developer: Reload Window*.
  -> `dragLint.restartServer` now exists (registered unconditionally and BEFORE
  the exe check, building a FRESH client rather than calling `restart()`, because
  the latched state lives in the client object). Budget raised to 10/3min, and the
  give-up message now names the redeploy and offers the command.
* **A fatal on the `lsp` path wrote its ONLY diagnostic to stdout**, i.e. straight
  into the JSON-RPC transport -- so the crash destroyed its own evidence. Now
  `ErrOutput`, plus a `drag-lint-fatal.log` breadcrumb beside the exe. The
  invariant existed only as a COMMENT and was violated ~60 lines below it, so it
  is now a test.

**If the client still misbehaves, run the command first** -- and note the
extension is loaded from `editors\vscode\drag-lint`, so a *Reload Window* is
needed once for the new `package.json`/`extension.js` to take effect at all.

## The through-line of this session: a text scan cannot tell code from comment

**Four instances, all fixed, all the same bug wearing different clothes.** Worth
knowing because a fifth is likely and this is now the first thing to suspect:

1. `review-marker-unused` reported "marker no longer matches any finding" on a
   line inside the unit's own braced header and on a `///` line quoting the
   grammar -- and advised DELETING documentation. Fixed with
   `TReviewMarkers.MarkerBearingLines`.
2. `Calls:` harvested ENGLISH WORDS. `CollectCallIdents` reset its brace depth on
   EVERY LINE, so a block comment opened earlier was invisible; the scan matches
   "Identifier(" and prose does too -- `the defect (2026-08-14)` yields `defect`.
   150 corpus-wide -> 0.
3. `CollectRaiseClass` had the identical bug and is the SHARPER edge: prose
   reading "we raise EFoo" produced a **fabricated `<exception cref>`** for a
   class that is never raised. Not covered by the original note.
4. `undeclared-identifier` regex-scanned the raw file with NO stripping at all --
   `Fixture`, `This`, `MUST`, `FIELD` reported as undeclared identifiers. Fixed
   with `MaskCommentsAndStrings` (blanks comments and strings to spaces, keeping
   length and line breaks so offsets stay valid).

The original state machine and the argument for it live in
`DRagLint.Lint.SharedUnit`'s header. **Read it before writing a fifth scanner.**

## Second through-line: KEYWORDS ARE NAMED NODES

Three instances this session, in tree-sitter-delphi13:

* `exprIf` -- the dangling else. `EmitStmt` had arms for `if`/`ifElse` but the
  grammar types `if A then if B then S1 else S2` as `statement(exprIf(...))`,
  so the WHOLE nested construct became one opaque CFG item and every dataflow
  rule saw it as indivisible.
* `kAt` -- `@Buf[0]` is `exprUnary(kAt, exprSubscript)`, so `LeftmostBaseVar`
  descending via `NamedChild(0)` landed on the OPERATOR and returned -1. An
  address-of handed to a filling API was counted as a READ of the buffer.
* The `case` arm in `DRagLint.Analysis.Cfg` records the same trap in prose,
  having paid for it twice.

`tools\dumpnode` answers this in one command and **is already built** at
`src\cli\Win64\Debug\dumpnode.exe` -- do not guess a node shape, and do not
rebuild the tool.

## Gotchas paid for THIS session

* **`lint <file>` is a SILENT SUBSET of `lint-all`.** It prints `0 finding(s)` on
  a file `lint-all` warns about, because whole-index rules (`doc-drift`,
  `unused-public-symbol`, `review-marker-unused`) need the store-wide walk. It
  cost two tests that went green for the wrong reason. Filed:
  `INBOX-lint-single-file-silently-omits-lint-all-rules.md`.
* **A closing brace inside a braced comment ends it early.** Cost two builds in
  one hour, in comments explaining the comment-scanning fixes. Name the
  delimiters in prose; `DRagLint.Lint.SharedUnit`'s header says so and was right.
* **Take the LAST match when anchoring a test on a routine header.** Every
  routine is named twice (interface + implementation); `-First 1` puts every
  anchor in the interface section and attributes every finding to the last
  routine. One test passed entirely for this reason.
* **Every new guard needs a POSITIVE control.** Three separate tests this session
  would have passed with the rule disabled. Assert that the thing you expect to
  still fire, still fires.
* `Select-String -SimpleMatch` treats `^` as a literal -- silently matches nothing.
* The battery takes **~15 min**; never rebuild while it runs. It auto-enumerates
  `run_*.ps1`, so a new runner needs no registration.
* `run_exe_freshness` correctly fails whenever source is newer than the exe --
  expect it after any source edit, and rebuild before believing a battery result.

## NEXT -- in order

0. **`overwrite-before-read` (56 on our own source) -- the strongest case left in
   the whole INBOX, and the one to start with.**
   `INBOX-group-E-dataflow-rules-are-majority-false.md` section 1, re-measured
   this session and unchanged. The rule does not merely produce noise: **its
   ADVICE IS WRONG.** It flags the nil-init immediately before a `try`, and
   deleting that store leaves an uninitialised variable to be tested or freed on
   the exception path -- following the finding converts correct code into a crash.
   Fix shape is narrow and syntactic: do not report a store when the next
   statement is a `try` whose `except`/`finally` reads or frees the variable, and
   cover the multi-init case (five nil-inits before one shared `try`) the same way
   `object-leak`'s Cause A had to. The guard fixture MUST include a genuine dead
   store that still fires -- the cheap fix for every rule in this family is to
   stop reporting near a `try`.

1. **Full battery for the wrong-index fix.** `ResolveConsumerDbs` now applies
   `OrderDbsByMembership` for a named target file (a bare `lint <file>` used to
   open the manifest's FIRST section rather than the index holding the file --
   every store-backed per-file rule and index-dependent autofix silently answered
   from a foreign project). `run_lint_project_db_resolution.ps1` gained case 4.
   Verified by targeted suites only if the log says so -- confirm.
2. **Audit the OTHER store-backed fix paths for the stale-position guard.**
   `INBOX-naming-autofix-corrupts-source-on-stale-index.md` is CLOSED (the guard
   exists at `Refactor.Rename.pas:374`, the note's "Not fixed" was stale) but its
   closing suggestion was never done: `doc-drift` and `missing-doc` resolve
   declarations by (file, line) and are equally exposed to writing at a stale
   position.
3. **`object-leak` Cause C.** Down to ONE finding shared by three projects
   (`YADF.Groups.pas:174`), and it is neither of the two causes in the note: `Cur`
   is a CURSOR into a tree, each `TGroup.Create(..., Cur)` links the new node under
   the current one, and `Result := Root` hands the whole tree to the caller.
   Needs escape-through-constructor-argument analysis. Deliberately deferred --
   one `info` finding is not worth that machinery yet, and every cheap heuristic
   silences genuine leaks.
4. **`bare-except` anchors one line below the `except`**, so a hand-written
   `dl:ok` at the obvious place never matches and is then itself reported unused.
   `INBOX-bare-except-anchor-defeats-a-hand-written-marker.md`. Fixing the anchor
   invalidates every recorded `@hash` for that rule corpus-wide -- take the churn
   once, and check whether sibling rules anchor off their own construct too.
5. **~100 INBOX notes remain untriaged.** Two were closed this session by
   MEASUREMENT rather than code (naming-autofix, object-leak spread), which is the
   cheapest kind of progress available: several notes are stale and a re-measure
   closes them. Do that pass before writing any new code.

## Notes filed this session

`INBOX-documenter-ignores-exclude-paths-and-writes-vendored-code.md` (fixed),
`INBOX-lint-single-file-silently-omits-lint-all-rules.md`,
`INBOX-bare-except-anchor-defeats-a-hand-written-marker.md`,
`INBOX-used-before-assignment-array-local-never-counted-as-defined.md` (its first
version was WRONG and says so -- element-wise assignment was never broken, and
DataCopy's 3 findings are correlated conditions, not an array bug).

Probes kept: `docs\probe-used-before-assignment-dangling-else.pas` (13 variants),
`docs\probe-used-before-assignment-array.pas` (5 cases).
