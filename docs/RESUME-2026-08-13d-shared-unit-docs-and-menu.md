# RESUME -- 2026-08-13 (session 16)

Supersedes `RESUME-2026-08-13c-shared-unit-docs-and-menu.md`.

Plan: `docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md`.
**Tasks 1-4 are DONE.** Task 7 (LoopZero) is BLOCKED on a defect found by running
it. Tasks 5-6 (IDE menu) are untouched and unblocked.

## Status

`main` = **`7eaff08`**, **10 commits unpushed**. Battery **269/269**.
Pushing still needs `git config http.postBuffer 524288000` + `http.version HTTP/1.1`.

`C:\Projects\YADF` is on branch `autodoc-phaseC` at **`b7a1368`** (the marker
commit), working tree clean apart from a pre-existing `YADFOT.res` and untracked
reports. Indexes match source.

### Measured, current

| Project | findings | `doc-drift` |
|---|---|---|
| YADF | 8 | 0 |
| YADFOT | 51 | 18 |
| YADFSetup | 45 | 21 |

Autofixable rules present: `doc-drift` and `local-var-casing` ONLY. Everything
else in the mix (`try-except-swallowed` 16 on YADFOT, `object-leak`,
`used-before-assignment`, `unused-public-symbol`, `unit-too-large`) needs triage.

## Shipped this session

* **`e6d0b8b` Task 3** -- `dl:shared` marker, reader, `shared-unit` CLI. The tree
  held a first cut that did not compile (`--in`/`--apply` read from fields nothing
  set; `if DoApply and NewText <> ''` precedence; assignment to a `for..in`
  variable; an `AddProject` that duplicated the line prefix). Replaced. The reader
  is a comment/string state scanner, not a line split -- that is what makes
  `dl:shared` in a literal not a marker and a marker on line 2 of a `{ }` block a
  marker. Test 5 -> 26 checks.
* **`57b0be4` Task 4** -- shared blocks are the UNION across projects. Checker
  forgives; writer merges. Test 20/20.
* **`7eaff08`** -- two defects found on the first real-code run (below).
* **`b22beb5`, `c523fb1`** -- Task 4 re-measurement and the Step-1-vs-Step-3
  contradiction, recorded before implementing.
* **YADF `b7a1368`** -- the eight shared units marked. Membership taken from
  `YADF.dpr` / `YADFOT.dpk` / `YADFSetup.dpr`, not guessed.

## THE BLOCKER -- read before touching Task 7

**Running LoopZero on YADFOT made things worse, and was reverted.** Marking alone
is a clean win with no writes (YADFOT 64 -> 51, YADFSetup 58 -> 45, YADF
unchanged). The moment `document --project YADFOT --apply` runs, **YADF goes
8 -> 18**.

Cause: `Used in units:` is an inbound fact, and under YADFOT it renders

```
Used in units: dxXMLWriter, FireDAC.Comp.QBE, Spring.Data.ExpressionParser,
               System.Bindings.Evaluator, System.JSON, XPTestedUnitParser, ...
```

where YADF renders four real units. Those names arrive through the facts
builder's **NAME-BASED extra-store fan-out** -- the bucket with no uses-scope
filter, every hit marked `unverified`. And the label renders through `JoinEsc`,
not `JoinRefs`, so it carries **no `' ?'` marker at all**: the uncertainty guard
is vacuous for it.

So the label was EXCLUDED from the shared-unit feature (`7eaff08`) rather than
let library noise become permanent in shared source. That leaves it on the byte
compare, which is exactly the residual churn: -7 YADFOT for +10 YADF.

**CORRECTS A RECORDED BELIEF.** The junk facts (`dxRibbon`,
`TestCachedUpdates.dpr`) written off in `RESUME-2026-08-13c` as "stale TEXT from
the union-DB era, which the per-project split already prevents from recurring"
are **not stale text -- they regenerate**. That is why Task 4's `certain` guard
looked like "insurance against nothing": it was guarding the wrong label.

### Two ways forward, owner's call

1. **Fix the pollution upstream (RECOMMENDED)** -- stop the name-based
   extra-store fan-out from feeding `Used in units:` on a project-scoped run.
   Fixes the facts for every project, not just shared units, and retires the
   whole "junk facts" class. `DRagLint.Doc.Facts.pas` ~1660-1705 is the fan-out;
   note the comment there admitting it has no uses-scope filter and that
   "section 7's noise can still arrive from an EXTRA store".
2. **Filter by the marker's project list** -- preserve only entries naming a
   project listed in `dl:shared`. Cheaper, but makes the project list
   load-bearing, which the plan explicitly said it was not.

Do NOT run LoopZero on YADFOT or YADFSetup until one of these lands.

## Traps this session paid for

* **A fixture that ends its block with `Pure` cannot catch a slice overrun**,
  because `Pure` IS a label. `MergeInboundFacts` parsed whole `Remarks` instead of
  the block body and wrote a swallowed `AUTO_END` into `YADF.Tokens.pas`; 20/20
  green throughout. Any parser test needs a fixture where the construct under
  test is LAST.
* **`JoinRefs` emits `' ?'` only on a MIXED list.** Absence of the marker proves
  nothing, so a "is this entry certain" test read off stored text is sound in one
  direction only.
* **`lint-all --db <db>` scopes to ownRoots**, so a scratch fixture whose units
  live outside the project folder reports a silent zero. Declare
  `_D-RAG\drag-lint-project.json` with `ownRoots`.
* **doc-drift reads the doc from the STORE**, so a `document --apply` not followed
  by a reindex makes every drift assertion pass vacuously
  ("no doc-comment on: X").
* **The engine writes `(loaded defaults from ...)` to stderr.** Merging streams
  in a test interleaves it into `--json` output and fails every read assertion
  while the engine is answering correctly.
* Battery is ~14 min -- background it.
* Line 1 of all eight YADF shared units is the `{` of a header comment. The
  markers correctly landed on the `unit` line (15/28/32/68).

## Not done

1. **The blocker above** -- decide 1 or 2, then Task 7.
2. **Tasks 5-6**, the two IDE menu items. Unblocked, need a LIVE IDE check, build
   BPLs with RAD Studio CLOSED, both platforms.
3. **`TSharedUnit.IsShared` reads the file on every call** -- no cache. Invisible
   at YADF scale, but it is one file read per documented decl in a marked unit.
4. **Item D, the type-blind pair** -- `concat-in-loop` 15 on DataCopy. Separate plan.
5. `C:\Projects\DelphiAST` still holds collateral damage from `aeeeee6` (2
   modified sources + 2 `.pas.bak`). Separate repo, never asked for.
