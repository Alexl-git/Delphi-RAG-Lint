# RESUME -- DataCopy INBOX defect round (2026-08-06)

Read this first. Source report (UNTRACKED, do not lose it):
`docs/INBOX-datacopy-2026-08-06-manifest-db-never-created-and-doc-lint-defects.md`
-- it carries 9 numbered defects, and I annotated two of them in place with VERIFIED root causes.

Predecessor doc: `docs/lint/RESUME-datacopy-hardening-2026-08-06.md` (section D work, all shipped).

---

## Status

`main` is **in sync with origin**. Released **v1.2.2-alpha** (tag pushed, GitHub release published):
https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.2.2-alpha

Battery **222/222** green (222 runners, 0 fail).

### >>> THE EXACT NEXT ACTION

**Step 2a is COMMITTED AND PUSHED** (`4ce699e`), battery **222/222**. `main` is in sync with origin.
Nothing is pending on disk except `FEATURES.txt`, which is the user's and predates this work.

**Start here: #7 -- constructor `Called from:` misattribution.** The plan is written out below and
the fix is a one-line guard in `DRagLint.Doc.Facts.pas`.

**Blocked and needing the user's answer first: #3** (`document` vs `doc-drift` on `<param>`).

---

## What shipped this round (all pushed)

| # | Defect | Commit |
|---|--------|--------|
| -- | ghost-check silently reverted a just-saved file (DATA LOSS) | `6036261` |
| 6,7 | empty-case-with-comment FP; write-only-local on loop counter/bound | `0def08e` |
| 5a | for-loop zero-trip modelling (29 FPs) | `9913ea5` |
| 9a,9c,5c,1a,2,4 | roll-up, scanned list, dedup, unbuilt-DB notice, prune-by-default, prose `<returns>` | `542dace` |
| 6 | nested/local routine bodies never walked -> refs missing | `4ce699e` |

---

## STEP 2a -- nested-routine refs (DONE, committed + pushed as `4ce699e`)

**Root cause.** In Pascal a nested/local routine lives in the DECLARATION part, before `begin`, so
it is a sibling of `declVars` and NOT a child of the `body` field. `Walk`'s `defProc` branch walked
only `ChildByField('body')`, so nested routine bodies were never entered and every call inside one
was invisible to the reference index.

**Fix** (`DRagLint.Parser.Delphi13.pas`, in the `defProc` branch after the body walk): also walk
named children whose NodeType is `defProc`, at `RoutineDepth > 0` so they still emit no SYMBOL of
their own -- only their references.

**Verified on the reporter's own corpus** (`C:\Projects\.drag-lint\DataCopy.sqlite`, rebuilt with
`drag-lint index --all --only DataCopy --jobs 0`):

- `SamePathFolder` refs 0 -> 1; `find-callers` now shows `CollidesWithFromPath`
- `unused-public-symbol` no longer flags it
- `IsValidFileNameChar` (a TRUE positive per the reporter) is STILL flagged -- rule not disabled

**Deliberately NOT included, do not "finish" these without deciding:**

- Nested routines are still not emitted as SYMBOLS. They are not unit-level API, and emitting them
  would change what `unused-public-symbol` and the dead-code rules treat as a declaration.
- `LoopsBackIntoScan` still has 0 refs -- it is called as `if not LoopsBackIntoScan then`, a BARE
  parameterless call in expression position, which is not an `exprCall` node. That is a SEPARATE
  gap (bare-identifier calls in expressions), not part of #6.

---

## NOT DONE -- ordered backlog

### #7 -- constructor `Called from:` misattributed across types (NEXT, plan ready)

`document --apply` writes `Called from:` lists naming routines that cannot possibly call the
constructor (proof is structural: `uZeissRoutines`'s implementation uses `uFileUtils`, so
`uFileUtils` cannot use `uZeissRoutines`).

**Diagnosed.** `DRagLint.Doc.Facts.pas` (~line 878 onward) gathers `Called from:` from TWO buckets:
1. `FindResolvedCallers(ASym.Id)` -- grounded in `call_edges`. Correct.
2. `FindUnresolvedNameCallers(LastSeg)` -- name-matching refs with NO `call_edges` row.

For a constructor `LastSeg` is `Create`, so bucket 2 sweeps in EVERY unresolved `Create` call in the
index (`TStringList.Create`, `TIniFile.Create`, ...). It is already marked `' ?'` by design, but for
a name that common the marker does not rescue it -- it pollutes essentially every constructor's
tooltip, which is what humans read in Help Insight.

**Planned fix (principled, no hardcoded name list):** before running bucket 2, if
`Length(AStore.FindSymbolsByExactName(LastSeg)) > 1` then SKIP bucket 2 -- when the index holds more
than one symbol with that short name, a bare-name match cannot identify THIS one. Covers
Create/Destroy/Execute/Clear/Add automatically and leaves genuinely unique names working.
Both store methods already exist (`FindSymbolsByExactName` at Interfaces.pas:78,
`FindUnresolvedNameCallers` at :417).

Test it the same way as `run_nested_routine_refs.ps1`: assert the noise is gone AND that a
uniquely-named routine still gets its unverified caller.

### #3 -- `document` and `doc-drift` disagree about `<param>` (NEEDS A USER DECISION)

22 findings. `document --apply`'s batch mode is facts-only by design ("an empty tag is never
written, `<param>` never gets a skeleton"), and `doc-drift` reports the resulting absence as drift.
The two halves can never converge. **The user has NOT chosen yet.** Options:
- (a) a `--params` flag on `document` emitting `<param name="X"></param>` skeletons -- reporter's
  preference and mine: an empty stub is a visible to-do in the tooltip;
- (b) `doc-drift` suppresses `no <param> tag` on decls carrying a managed `<!-- drag-lint:auto -->`
  block -- hides the gap.
ASK BEFORE IMPLEMENTING -- it changes what generated docs look like in every project.

### #5b -- `except` handler ending in `exit` still merged with the normal path

`uFileUtils.pas` `srcsize` (and the DPPRoutines double-free pair at 302-303) are ONE bug: the
handler exits, so it cannot coexist with the normal path. I fixed one wrong CFG edge in
`DRagLint.Analysis.Cfg.pas` (a diverting handler was still wired to the follow block -- `EmitStmt`
returns -1 for exit/raise/break/continue meaning "does not fall through"). It did NOT clear the
symptom, so there is a SECOND merge route still to find. Note the `finally` branch's equivalent edge
is deliberate (a finally always runs) -- do not "fix" that one.

### #1b -- the IDE reindex ignores the manifest

It writes `<projectRoot>\drag-lint.sqlite` by convention instead of resolving the manifest section
that CONTAINS the path. Consequence: docs get generated from one DB and linted against another, and
the manifest's `exclude` patterns never apply to the DB the IDE actually uses. #1a (resolve-dbs now
NAMES an unbuilt manifest DB on stderr) shipped; this half did not.

### #8 -- harvest swallows an unrelated preceding comment

Already filed as `docs/INBOX-harvest-swallows-preceding-banner-comment.md`; fresh reproduction in
the new report's section 8.

### Smaller / mine to clean up

- **New noise I introduced:** `lcount` at `uFileUtils.pas:1045` -- previously invisible because the
  loop bound was never read; my bound-as-read fix exposed it. Check whether `exit(False)` inside an
  if-chain is being modelled as a divert.
- **#9b** cosmetic: report file carries a UTF-8 BOM, and `writeln-in-source` uses a real em dash
  while every other message uses `--`. That one character makes the report non-ASCII.
- **DataCopy source work never started** (from the earlier list): rename `FName1/2/3/FNameOut`;
  add try-finally to the unprotected findings; run autodoc across the project and fix doc-drift.
  DataCopy is on hg branch `datacopy-hardening-2026-08-05` rev 33 awaiting a human tester.

---

## Gotchas that will bite a cold start

1. **Battery needs `pwsh`.** Under Windows PowerShell every `$proc.ExitCode` is null and all tests
   falsely FAIL.
2. **Do not EDIT `src\*.pas` mid-battery**, not just "do not rebuild": some runners COMPILE from
   source (`run_coherence.ps1` builds a harness against `src\`), so an edit landing mid-run fails a
   runner that is fine. A battery result taken while the tree was being edited is not a result.
3. **The agent `Write` tool emits lone LF** and `run_encoding_guard.ps1` fails the whole battery for
   it. Normalize any new repo file to CRLF -- `.ps1` included.
4. **Build:** `build\build_draglint_win64.bat` via PowerShell `Start-Process -Wait` with output
   redirected to a log; it also STAGES to `third_party\dll-win64`. Not the MCP build tool, not
   `cmd.exe /c` from the Bash tool.
5. **A `}` inside a `{ }` Pascal comment closes it early.** Cost one broken build when a comment
   contained a brace-dollar directive example.
6. **The tree-sitter grammar exposes `for`/`to`/`downto`/`do` as NAMED children**, so "the first
   named child that is neither start nor body" is the `for` KEYWORD, not the bound. Skip `k`-prefixed
   token types.
7. **Verify a REPORTER's diagnosis, not just an agent's.** The 29 `used-before-assignment` FPs were
   reported as "indexed stores treated as reads" -- wrong, and implementing the ask would have fixed
   nothing. Worse, my first repro appeared to CONFIRM it, because `Writeln(X)` treats call arguments
   as possible DEFS rather than reads, so the control variable was never actually read. A repro that
   confirms a hypothesis deserves the same scrutiny as one that refutes it.

---

## Drafted commit message for the uncommitted step 2a

```
fix(index): walk nested routine bodies so their calls reach the reference index

`unused-public-symbol` reported uFileUtils.SamePathFolder as dead public API.
It is the FROM-vs-TO folder collision guard and it IS called -- but its only
call site sits inside CollidesWithFromPath, a local function declared inside a
method, and there was no ref row for it AT ALL.

In Pascal a nested routine lives in the DECLARATION part, before `begin`, so it
is a sibling of declVars and NOT a child of the `body` field. Walk's defProc
branch descended only into `body`, so nested routine bodies were never entered
and every call made inside one was invisible to the reference index. Isolated
against one DB: DirNotFound (called from the outer body) 5 refs,
CollidesWithFromPath (ditto) 4, SamePathFolder (called inside a nested routine)
0, LoopsBackIntoScan (declared AND called inside nested routines) 0 refs and 0
symbols.

Blast radius was wider than one rule -- find-callers, impact and the call graph
under-reported for any unit using local functions, an idiomatic Delphi pattern
and commonest in exactly the large routines people most want a call graph for.
The FACTS walker does descend, which is why a generated `Calls:` block named a
symbol that find-callers then denied.

Nested routines are walked at RoutineDepth > 0, so they still emit no SYMBOL of
their own: they are not unit-level API, and emitting them would change what
unused-public-symbol and the dead-code rules treat as a declaration. Only their
references are collected, which is what the reference-derived rules were missing.

Verified on the reporter's corpus: SamePathFolder refs 0 -> 1, find-callers
resolves the nested call site, unused-public-symbol no longer flags it, and
IsValidFileNameChar (a true positive) is still reported.

Test: run_nested_routine_refs.ps1 (6 checks, both directions).

Still open, same family: `if not LoopsBackIntoScan then` is a BARE parameterless
call in expression position, not an exprCall node, so it is still unrecorded.

Refs docs/INBOX-datacopy-2026-08-06-manifest-db-never-created-and-doc-lint-defects.md (6)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
```
