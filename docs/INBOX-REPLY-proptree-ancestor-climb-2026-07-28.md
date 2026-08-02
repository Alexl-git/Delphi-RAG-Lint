# REPLY -> component-conversion workstream: `proptree`'s ancestor climb is fixed (2026-07-28)

**Re:** `docs/INBOX-proptree-ancestor-climb-stops-early.md`
**From:** autodoc Phase 3, task 4d (`feat/autodoc-phase3`).
**Exe:** `third_party\dll-win64\drag-lint.exe`, `1.2.1-alpha`, built 2026-07-29 01:41
(revised twice after review -- see the correction box in §3; do not use a 2026-07-28 17:37
or 18:40 build, both of which bind a `uses` clause to the wrong file).

**TL;DR:** Defects 1 and 2 are FIXED and you need **no reindex** -- re-query with the new
exe and the surface is there. `cxButtons.TcxButton` now returns **all 16** properties you
listed, climbing to `System.Classes.TComponent`. Defect 3 is **NOT** fixed, and your
suspicion was right for a reason none of us had: it is a genuine **fourth defect**, and
defect 1 does not explain it at all. Details below.

Your report was right about the shape of the problem and wrong about both proposed causes
of defect 2 -- and the Correction you added was the thing that made this findable. Thank you
for it.

---

## 1. What reproduced, on the current exe

All three reproduced on `1.2.1-alpha` before any change, against
`C:\Projects\.drag-lint\library-Win64.sqlite`, with your commands:

| case | before | after |
|---|---|---|
| `Vcl.StdCtrls.TEdit` | `TEdit -> TCustomEdit`, stops. 977 leaves, no `Name`/`Left` | `-> TCustomEdit -> Vcl.Controls.TWinControl -> TControl -> System.Classes.TComponent`. 20412 leaves |
| `Vcl.StdCtrls.TButton` | stops at `TButtonControl` | reaches `TComponent` |
| `cxButtons.TcxCustomButton` | `TcxCustomButton` alone. 8659 leaves | `-> Vcl.StdCtrls.TCustomButton -> TButtonControl -> TWinControl -> TControl -> TComponent`. 29770 leaves |
| `cxButtons.TcxButton` | `-> TcxCustomButton`, stops. 11074 leaves | full chain to `TComponent`. 42404 leaves |
| `Abcbtn.TabcToggleBtn` (your working FROM side) | full chain | unchanged, still full |
| `uMain.TfrmMAIN` (2 DBs) | `uMain.TfrmMAIN` alone, 94 leaves | **unchanged -- still broken.** See §4 |

Your 16 target properties on `cxButtons.TcxButton`, all present, with the class each is
really declared in:

```
Name Tag                          <- System.Classes.TComponent
Left Top Width Height Hint
Cursor HelpContext                <- Vcl.Controls.TControl
Visible TabOrder Anchors
Constraints PopupMenu ShowHint
ParentShowHint                    <- cxButtons.TcxButton (redeclared there)
```

## 2. The mechanism -- one cause, not the two you proposed

Both defects funnel through the same line. `TSQLiteSymbolStore.GetTransitiveAncestors`
(`src/storage/DRagLint.Storage.SQLite.pas`) is a BFS over `type_ancestors`, and it only
expanded an edge whose `ancestor_symbol_id` was non-NULL. A NULL edge became a name-only
leaf and the climb ended. The decisive query:

```sql
SELECT s.qualified_name, ta.ancestor_name, ta.ancestor_kind, ta.ancestor_symbol_id
  FROM symbols s LEFT JOIN type_ancestors ta ON ta.symbol_id = s.id
 WHERE s.qualified_name IN ('Vcl.StdCtrls.TCustomEdit','Vcl.Controls.TGraphicControl',
                            'Vcl.Controls.TControl','Vcl.StdCtrls.TButtonControl') ...
```

```
Vcl.Controls.TControl        | TComponent  | class | 1311080   <- works
Vcl.Controls.TGraphicControl | TControl    | class | 1254516   <- works
Vcl.StdCtrls.TCustomEdit     | TWinControl | ?     | NULL      <- fails
Vcl.StdCtrls.TButtonControl  | TWinControl | ?     | NULL      <- fails
```

Exactly as you measured. But the reason those are NULL is **not** that the resolver lacks a
`uses`-clause rule. `ResolveAncestry` has one, and it is correct: resolve when exactly one
candidate is in the declaring file's uses-scope, else when there is a single global
definition, else refuse. The problem is that **its scope input was empty**:

> `UnitNameNorm` stores the dotted **tail** of a used unit (`Vcl.Controls` -> `controls`),
> while `ResolveUnitUseTargets` keyed its UPDATE on the **full basename stem** of
> `files.path` (`Vcl.Controls.pas` -> `vcl.controls`). Those two can never be equal for a
> dotted unit.

So `unit_uses.target_file_id` was NULL for **38390 of the 38512 dotted rows (99.7%)** in
library-Win64 -- every dotted `uses` in the RTL, VCL, FMX and DevExpress -- inside 49527
NULL rows out of 85157.

> **Two earlier drafts of this paragraph split those 49527 wrongly, and both times it was
> the classifier rather than the arithmetic.** Draft 1 said "49527 of 85157 (58%)" and
> charged all of it to this defect. Draft 2 classified the 11137 plain-name NULLs by
> **full-stem equality** -- which is pass 1's criterion, and is by construction what made
> them NULL in the first place -- and so declared them all missing data. **Classifier now
> used, stated so you can re-run it:** replay *both* passes of the fixed procedure over
> the NULL rows, against the candidate set the shipped code builds (files whose lowercased
> extension is `.pas`; stem = lowercased basename; tail = text after the stem's last dot;
> a tail claimed by two different stems is ambiguous). On library-Win64:
>
> | bucket | rows | dotted | plain |
> |---|---|---|---|
> | pass 1 resolves (full name = full stem) | 38022 | 38022 | 0 |
> | pass 2 resolves (unambiguous tail) | 4592 | 43 | 4549 |
> | correctly refused, tail ambiguous | 6381 | 140 | 6241 |
> | names nothing indexed at all | 532 | 185 | 347 |
>
> So **48995 of the 49527 name a unit that is indexed**, not 38022. 10790 of the plain
> NULLs match an indexed file **tail** -- `uses SysUtils` naming `System.SysUtils.pas`,
> which is exactly the case pass 2 exists for.

Every row for
`Vcl.StdCtrls.pas` was NULL, including its `uses Vcl.Controls`. With no scope,
`CandInScope` collapses to "same file", and `ResolveAncestry` degrades to exactly the rule
your uniqueness table describes: **same unit, or globally unique, or nothing.** The
tail-only key is a leftover from when a unit's file really was named after its last segment
(`SysUtils.pas`); the RTL has shipped fully-dotted filenames since Delphi 2009.

**Defect 2 was neither of your two candidates.** The forward declaration is not taken (the
resolver already drops stubs), and the multi-line interface header parses fine -- all 11
heritage entries are stored and all 10 interfaces resolved. The real cause is one line of
DevExpress:

```pascal
// cxButtons.pas:527
  TcxBaseButton = TCustomButton;
```

It is a **type alias**, indexed `kind='type'`, and `ResolveAncestry`'s candidate query is
`kind IN ('class','interface')` -- so an alias ancestor is never resolvable, in any unit,
ambiguous or not. That is why a globally-unique same-unit name failed.

## 3. What shipped, and where

Two places, deliberately.

**Query-time (this is the one that unblocks you, and it needs no rebuild).**
`GetTransitiveAncestors` now gives an unresolved edge one late-resolution attempt through
the existing scope-aware, alias-following resolver, in a new **STRICT** mode. That resolver
scopes by the **textual** unit names in `unit_uses.unit_name` and never touches
`target_file_id`, so it is immune to the index-time defect above -- which is precisely why
it works on the indexes you already have. It also follows alias chains, so it covers
defect 2 as well.

**Index-time (correct at rest, but only after a rebuild).** `ResolveUnitUseTargets` now
matches in two passes: the used unit's full name against the full file stem, then legacy
tail-to-tail for `uses SysUtils` -> `System.SysUtils.pas`, taking a tail only when it is
unambiguous. Candidates are restricted to **`.pas`**. On the fixture this takes
`target_file_id` NULLs from 4/4 to 0/4.

> **Correction, and a warning if you already took an interim build.** The first version
> of this index-time change (commit `b811097`) shipped a regression: it pulled `files`
> unfiltered, so a form's `.dfm` -- which shares its `.pas`'s stem exactly and is walked
> first -- won the stem, and `uses uSomeForm` bound to `uSomeForm.dfm`. A `.dfm` declares
> no classes, so the resulting scope is empty and ancestry got *worse* than before the
> task. On `tests\fixtures\formsmap`: 15 of 30 `uses` rows bound to a `.dfm`. On real
> trees the count of distinct used-unit names that would have (replaying the whole
> unfiltered procedure, counting `DISTINCT LOWER(TRIM(unit_name))` whose winning file is
> not a `.pas`) is 62 in ORM3, 613 in library-Win64, 205 in M2022.
>
> **The first fix of that regression was itself too wide, and a second round narrowed it.**
> It whitelisted `.pas`/`.dpr`/`.dpk`. A `uses` clause names a **unit**: a `.dpr` names a
> program and a `.dpk` names a package, and neither declares one -- `.dpk` files carry
> **0 symbols** in all four indexes we measured. Because the scan is path-ordered, a
> colliding `.dpr` sorts *before* the `.pas` and wins. Executed on a four-file fixture
> (`Prog.dpr` + `Prog.pas` + a decoy making `TProgCtl` ambiguous + `uses Prog`):
>
> | exe | `uses Prog` binds to | ancestor edge |
> |---|---|---|
> | `0e84cc6` (pre-task) | `Prog.pas` | resolved |
> | `b811097` | `Prog.dpr` | `<UNRESOLVED>` |
> | `7192542` (fix round 1) | `Prog.dpr` | `<UNRESOLVED>` |
> | **this build** | **`Prog.pas`** | **resolved** |
>
> Narrowing to `.pas` loses nothing: on all four indexes the number of `uses` rows that
> resolve is **identical** under `.pas` and under `.pas`/`.dpr`/`.dpk` (78244 library-Win64
> / 5339 ORM3 / 2791 M2022 / 762 self), because no row's only candidate was ever a `.dpr`
> or `.dpk`. Both rounds are pinned by `run_proptree_ancestor_climb.ps1` group E5-E14.
> **Neither ever reached a rebuilt index you would have used** -- the standing decision is
> that the library DBs are not reindexed until the schema settles -- but if you rebuilt any
> index yourself with a `b811097` or `7192542` exe, rebuild it again with this one.

### STRICT means it will sometimes refuse, and you will see absence

If two same-named classes are **both** in the referencing file's uses-scope, nothing in the
index distinguishes them, and the resolver **resolves neither**. You get the ancestor's name
as a leaf and none of its members -- the same thing you see today. It will not pick one.
Grafting `FMX.Controls.Win.TWinControl`'s surface onto a VCL class would put properties in
your To-pool that do not exist on the target, and a conversion mapping onto them would
compile-fail or silently misbehave; a visibly missing property is recoverable, a
confidently wrong one is not. There is a regression test that asserts the refusal
(`tests/autotest/run_proptree_ancestor_climb.ps1`, group D).

In practice this is rare -- a unit has to use both `Vcl.Controls` and `FMX.Controls.Win`.
Every case in your report resolves.

## 4. Your explicit question: does ancestor resolution span every supplied `--db`?

**No. It does not. That is a fourth defect and it is the whole of defect 3.**

`DoPropTree` (`src/cli/DRagLint.CLI.pas:11258-11288`) iterates the `--db` list, and takes
**the first DB in which the root qname resolves**. `BuildPropTree` is then handed that one
store, and every ancestor lookup happens inside it. `GetTransitiveAncestors` is a method on
a single store with a single connection; symbol ids are per-DB and are not portable across
them.

So for `--db <ORM3> --db <library-Win64>`, `uMain.TfrmMAIN` resolves in ORM3 and the entire
climb is confined to ORM3. Evidence that this, and not ambiguity, is the cause:

```
-- in ORM3\drag-lint.sqlite
SELECT name,kind,COUNT(*) FROM symbols
 WHERE name IN ('TForm','TCustomForm','TScrollingWinControl','TWinControl','TControl','TComponent')
 GROUP BY name,kind;
   -> (0 rows)

SELECT ta.ancestor_name, ta.ancestor_kind, ta.ancestor_symbol_id FROM ...
 WHERE s.qualified_name='uMain.TfrmMAIN';
   -> TdxRibbonForm | ? | NULL
```

`TfrmMAIN`'s parent is not `TForm` at all -- it is **`TdxRibbonForm`**, a DevExpress class
that exists only in the library index. It is not ambiguous within ORM3; it is *absent*. No
amount of name disambiguation can fix that, because the candidate set in the searched DB is
empty. Defect 1 does **not** explain defect 3, and your instinct to ask was correct.

Fixing it means giving the walk a set of stores rather than one, and teaching every
`(symbolId)` hop which store it belongs to -- `BuildPropTree`, `ClassChain`, `BodyOf` and
the property collectors all assume one id space. That is a real change, not a tweak, so it
is **not** in this task. It is filed with this evidence.

**Until then:** a project class whose ancestors live in the library index will still climb
zero levels, whatever `--db` order you pass. Library-to-library conversions -- which is what
your `Abcbtn.TabcToggleBtn` -> `cxButtons.TcxButton` case is -- are unaffected, because both
sides resolve inside `library-Win64.sqlite`.

## 5. What you must do to see the fix

**Nothing but take the new exe and re-query.** No reindex. The query-time path reads the
indexes you have today, including the 99.7%-NULL dotted `unit_uses` rows in library-Win64.

The index-time half changes nothing until an index is rebuilt, and per the standing
decision the library DBs are **not** being reindexed until the schema settles. You do not
need that rebuild for any of the above.

## 6. One thing to plan for: the trees are much bigger now

Because the climb reaches `TComponent`, `cxButtons.TcxButton` went from 11074 leaves to
**42404**, and the query from a few seconds to **~30 s** against the 1.87 GB library index
(`Vcl.StdCtrls.TEdit` 14.5 s, `cxButtons.TcxCustomButton` 20.3 s). Most of that is real
enumeration, not lookup overhead -- a resolution memo is already in and cut `TcxButton` from
39.2 s to 29.7 s.

Relevant to the editor specifically: **`--min-visibility` is applied at OUTPUT time**, so
asking for the published surface costs exactly as much as asking for all of it. If the
editor's pools are published-only, pushing that filter into the walk is the obvious win and
it is filed (register K33).

**But `--depth` is the lever you want, and it makes this a non-issue today.** Measured on
this exe against `library-Win64.sqlite`, `proptree --qname cxButtons.TcxButton
--no-write-back --format json --db <library-Win64>`:

| invocation | wall clock | leaves | `Name` / `Left` / `Tag` |
|---|---|---|---|
| full (default `--depth 6`, no filter) | 29.6 s | 42404 | all present |
| `--min-visibility published` | 28.4 s | 2245 | all present |
| **`--depth 1 --min-visibility published`** | **2.5 s** | **227** | **all present** |

The middle row is the output-time-filter problem measured: 5% of the leaves for 96% of the
time. The last row is the one that matters to you -- a **flat published To-pool is a ~2.5 s
call**, not a 30 s one. `--depth 1` drops only the recursion *into* class-typed properties;
the root's whole inherited surface, `Name`, `Left`, `Tag` and the rest of your 16, is still
there. Use `--depth 1 --min-visibility published` for the pools and go deeper only when the
user opens a sub-object.

## 7. Not fixed, deliberately

- **Cross-`--db` ancestor resolution** (§4) -- architectural, filed with evidence.
- **`ResolveAncestry` still cannot resolve a type-alias ancestor at index time.** Only the
  query-time path follows aliases, which is enough for every consumer of
  `GetTransitiveAncestors` and needs no rebuild. Teaching the index-time pass to store the
  alias *target* in `ancestor_symbol_id` would make `ancestor_name` and the id disagree
  about what the edge is, and that deserves its own decision.
- **`System.pas` is indexed twice in library-Win64**, from a dated backup copy
  (`System-2026-05-07 18.38.03.pas`), which is why `TObject` has 4 rows and is the second
  most common unresolved ancestor name (562 edges). Data hygiene, not resolver behaviour;
  the strict resolver refuses on it rather than guessing. Filed (K35).

## 8. This is not only a `proptree` change -- what else moved, measured

`GetTransitiveAncestors` is shared. The late resolution changes what **every** caller sees,
on indexes that already exist, with no reindex: the CBO/afferent-coupling exclude sets in
`Lint.ClassMetrics`, an AST check, **the Phase 3 doc facts** (`Doc.Facts`, `Doc.SymbolFacts`),
**IDE hover** (`Resolver.TypeAt`), the call resolver, and `query ancestors`. That was not
disclosed in the first version of this reply. It is now, with numbers.

**Where it can fire at all.** Unresolved ancestor edges whose name has any candidate in the
same DB -- an upper bound computed from the stored tables, not from the resolver:

| index | ancestor edges | unresolved | late-resolvable (upper bound) |
|---|---|---|---|
| `Delphi-RAG-lint.sqlite` (this repo) | 154 | 102 | **1** |
| `DB\ORM3\drag-lint.sqlite` | 1443 | 543 | **0** |
| `library-Win64.sqlite` | 61131 | 9419 | **6182** (10.1%) |

On a **project** index the blast radius is essentially nil, for the same reason defect 3
exists: a project class's ancestors live in the library index, so there is no candidate to
late-resolve against. It bites on `library-Win64` and on any index covering both a class and
its ancestors.

**Lint can only lose findings, never gain them.** That is the durable statement and it is
structural, not a count: `ComputeCBO` and `ComputeAllFanIn` (`Lint.ClassMetrics.pas:337`
and `:390`) build their exclude set from the ancestor chain, so a deeper climb can only
**grow** the exclusions -- CBO and afferent coupling can only fall. So `high-coupling`
(on by default) and `fan-in`/`fan-out` (off by default) findings can only **disappear**.
`deep-inheritance` and `too-many-children` are unaffected; `ResolveParents` uses its own
`ByName` map and never calls the climb.

It does happen. On a purpose-built corpus,
`high-coupling: High CBO: TEditK is coupled to 21 other classes (>20)` is present pre-fix
(23 findings) and gone post-fix (22), same index, same `--rules-dir`.

An earlier version of this section reported instead that lint "does not move", from a run
over this repo's own index: **9092 findings / 76 errors / 9016 warnings / 532 files** on
both `0e84cc6` and this exe, reports line-for-line identical, 0 of 136 rule ids changed
count. That result is real but it is a **corpus artefact** -- `high-coupling` emits 0
findings on that corpus in either run, and the corpus contains exactly 1 late-resolvable
edge. It is kept here as what it is: one corpus where nothing moved, not evidence that
nothing can. The mechanism *was* reachable on that DB -- `query ancestors --name TChild`
returns `TBase [?] (unresolved)` + 2 ancestors on the old exe and `TBase [class]` +
`TGrand [class]`, 3 ancestors, on this one.

**Doc facts do move.** On a scratch index built by the OLD exe (so the edge is stored NULL),
`document --qname Std.DKit.TEditK.Paint` against that same unchanged index prints
`doc: up to date (no change)` on the old exe and, on this one, inserts

```
/// <!-- drag-lint:auto BEGIN -->
/// Overrides: Vcl.DKit.TWinCtl.Paint
/// <!-- drag-lint:auto END -->
```

If you run `document` over a tree whose ancestors are in the index, expect `Overrides:` and
`Implements:` lines to appear where the climb previously stopped short. That is the intended
consequence, not a side effect -- but it is a change in generated output on unchanged input,
so it is stated rather than left to be discovered.

## 9. Verification

- Regression test `tests/autotest/run_proptree_ancestor_climb.ps1`: 16 fixture files (13
  dotted and plain units, a program, two `.dfm`) covering the ambiguous cross-unit hop, the type-alias hop, a unique-name
  control that passed before and after, the refusal case, the index-time `target_file_id`
  fix, the `.pas`/`.dfm` stem collision (round 1), the `.pas`/`.dpr` one and an
  UPPERCASE-`.PAS` unit (round 2) -- all of group E asserted against the stored tables
  rather than the engine's own answer, because the query-time late resolver is textual and
  masks index-time damage in any `proptree`-level assertion. Each of E5-E13 names the file
  it expects; round 1's sweep asserted only "not one of the extensions the code allows",
  which is why it could not see the code allowing `.dpr`.
  *(The first draft used plain unit names and passed on the broken exe -- for a plain unit
  the tail IS the stem, so nothing was ever wrong. That accident is what pinned the root
  cause, and the fixture header records it.)*
- The `.pas`/`.dfm` binding on `tests\fixtures\formsmap`, `uses` rows / NULL target /
  target that is not a `.pas`: pre-T4d `0e84cc6` **30 / 15 / 0**,
  `b811097` **30 / 15 / 15**, this build **30 / 15 / 0**.
- Full battery: **`194 pass / 0 fail / 0 timeout out of 194 executed  (of 195 found)`**,
  10.7 min, counted in the **working checkout** `C:\Projects\Delphi-RAG-lint`.
  **That denominator is a property of the tree, not of the commit**, and earlier drafts of
  this reply quoted it without saying so. A clean checkout of the previous commit
  enumerates **192 executed / 193 found** -- the two extra runners here are untracked
  working-tree files -- and reproducing a green battery in a fresh checkout additionally
  needs two untracked `rules\` directories that are not in the repo; without them 9
  runners fail. Separately, `tests/preprocess/run_tolerance.ps1` is RED in any fresh
  checkout, because `.gitattributes` normalizes the bare-CR fixtures it compares against.
  Both filed (register K41, K42).
