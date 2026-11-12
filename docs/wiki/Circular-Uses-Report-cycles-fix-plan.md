# Circular Uses Report (cycles + fix plan)

Finds `uses` cycles among indexed units and, on request, proposes a followable
refactoring plan to break them. Reach for it when the compiler is fighting
circular references, or a project's dependency graph feels tangled.

This works because of the thorough index of the Delphi platform library (RTL, VCL and the rest) and of your
project: every unit, `uses` edge, symbol and reference is already in a local SQLite database, so the engine knows
which symbol ties a cycle together and who uses it. The work runs locally and needs no AI and no internet:
`cycles`, `--plan` and `--fix` make no network call and no model call. The only programs they start are your own
Delphi compiler build (`msbuild`, to prove the edit) and this same engine re-indexing the project. A model can
follow the `--plan` playbook (measured below), but that is optional.

## Step by step
1. Index the project once (and again after every edit outside this tool):
   `drag-lint index --project <X.dproj> --db <db>`
2. See the groups: `drag-lint cycles --db <db> --causes`. An interface-coupled group is Part A, an
   implementation-only one is Part B.
3. Dry run, no source file written (it does build the project first):
   `drag-lint cycles --fix --project <X.dproj> --db <db> [--unit <stem>]`. Exit 0 = the engine can do it, 1 = refused with a named kind (see
   [Refusal kinds](#refusal-kinds)).
4. Apply: the same command plus `--apply` (every touched file is first backed up as `<file>.BCK<n>`; a compile
   error rolls everything back; after a rollback rebuild the project). Then run `drag-lint cycles --db <db>`: it
   prints what the plan predicted, and the next group is the next run.
5. A refused group: `drag-lint cycles --db <db> --plan > cycle-plan.md` prints the by-hand playbook.
## Running it from the CLI
```
drag-lint cycles --db <file.sqlite> [--edges] [--causes] [--hub] [--plan [--hub-surface [--apply]] [--project <X.dproj>]] [--f2047 [--unit <stem>]] [--format json|text]
```
`--edges` and `--causes` add detail to the cycle report; `--hub` tells a star from a
tangle: per group the hub units (a unit whose removal leaves the rest acyclic), the uses
edges and reference weights on each side, whether cutting one side alone breaks the group,
what the spokes take from the hub (globals with the member names read through them,
routines), what the hub takes from the spokes, and the dead `uses` inside the group
(read-only, no planner; JSON adds `hubs[]` and `zero_ref_edges` per group); `--plan --hub-surface` plans recipe R3 for such a star with one hub read through one global: a new leaf unit `<Hub>.Hub` holding an interface with one property per field and one method per method the spokes read through the global, the hub class implementing it with an AfterConstruction / BeforeDestruction hand-over, and a receiver-only rewrite in each spoke (`frmMain.edtX` becomes `MainHub.edtX`); `Inc` / `Dec` of an integer field becomes an assignment; `Assigned(<global>)` becomes `Assigned(MainHub)` and any other bare use of the global (passed as a value, compared with nil, cast) becomes `MainHubAsForm`, a nil-safe function in `<Hub>.Hub` over the interface's `AsForm` property, typed with the hub class's one library class ancestor (`TForm`, `TdxRibbonForm`, `TComponent`; phase P4, 1.49); `with <global> do` (with-member), a write to the global or a designer field, `FreeAndNil` / `CreateForm` / `@` of the global or another var-parameter use, or an ancestor's member the platform library does not declare, refuses only that spoke; a free routine of the hub that a spoke still calls goes through an R1 pointer in `<Hub>.Hub` (`<Name>Ptr`, assigned in the hub's initialization; a call from the spoke's initialization keeps that spoke's edge); the dry run is the normal playbook with R3 and the `--hub` block in place of Part A for a hub-shaped group (a group R3 refuses gets one note line and the planner's plan), and `--causes --format json --hub-surface` gives R3's `fix` object (`part: r3`) for such a group without running the planner; OFF by default, `--apply` writes one group (`.BCK<n>` backups) and runs no compile gate yet (build after it); `--plan` produces the
refactoring playbook; `--f2047` narrows the report to the interface-only cycles
the compiler rejects with F2047 (`--unit <stem>` limits it to one unit's cycle);
`--format` selects `json` or `text` output. `--fix` makes the edits
for you -- see [Fix it mechanically](#fix-it-mechanically-cycles---fix) below.

## What `--plan` gives you
A mechanical procedure, written so that a reader with no project context can
follow it literally:

* **What moves where** -- each symbol that ties the cycle together, with its kind
  and the recipe for that kind. Enums, records, constants and variables move
  unchanged into a new leaf unit `<Declaring>.Untangle` (or into an existing one that is still a leaf) (exact line ranges, doc
  comment included). A class whose method bodies use the cycle is not moved: a
  base class with just the members its consumers use is extracted instead, and
  the playbook says why. Every consuming unit is listed with its section and
  first-use line.
* **Uses decisions** -- per unit: keep the old partner, move it from the
  interface to the implementation uses, or remove it.
* **The new units' full text**, and the rule for their uses clause.
* **Every edit** (units, `.dpr`, `.dproj`) as current text + new text, bottom-up.
* **DONE** and a **checklist** ending in the re-index command and the exact
  output `cycles` must print afterwards, plus what to do for each compile error.

An interface-coupled cycle becomes a legal implementation-only one (Part A). The
optional Part B names the edge that can be cut next; re-running `--plan` after
Part A prints it as the same kind of steps. When no edge can be cut mechanically
(it carries a routine, or a class whose bodies use the cycle), the playbook says
so and gives the standard remedy instead of guessing.

## Worked example, and whether a model can follow it

[Circular Dependency Report](Circular-Dependency-Report) walks through a real
four-unit cycle. The full, unabridged playbook for it is
`circular-demo/CYCLE-REPORT.md` in the repository -- that is the file to hand to
a model. Its followability is measured: Haiku at its lowest effort, given only
that report and a fresh copy of the project ("Break the cycle."), produced a
tree that compiled with 0 errors, printed the predicted `cycles` output, and
touched only the named files (4 of 4 criteria; re-run on engine 1.19.0-alpha).
The examples are regenerated from the engine and checked for drift by the test
battery, so they always show what the current `--plan` prints.

## Fix it mechanically: `cycles --fix`

`--plan` tells you what to edit; `--fix` makes the edits for you, one circular group per run,
and proves them with the compiler.

```
drag-lint cycles --fix --project <X.dproj> --db <file.sqlite> [--cycle <n> | --unit <stem>]
                 [--part a|b|all] [--apply] [--no-backup] [--no-reindex] [--no-compile]
                 [--shadow-out <dir>] [--rsvars <rsvars.bat>]
                 [--platform win32|win64] [--library-db <lib.sqlite>] [--rules-dir <dir>]
                 [--format json|text]
```

**Which group.** `--cycle <n>` (the number `drag-lint cycles` prints) or `--unit <stem>` (the
group that unit belongs to). Without either, the run walks the groups in order, prints each
refused one with its first refusal, and plans the first mechanical one; the text output then
ends with one line naming every group it never reached:

```
Not planned: cycle(s) 2, 3 -- this run plans one group; add --cycle <n> to plan another
```

**Dry run (the default).** Plans the group, checks the plan against the files on disk, stages
the result in a shadow tree (`C:\TEMP\draglint_cyclefix_<pid>\`, or `--shadow-out <dir>`) and
prints the verdict. No source file of the project is written -- but the dry run **builds the
project by default** (the baseline gate), and that build writes what any build writes (dcu,
exe). `--no-compile` skips it. Exit 0 mechanical, 1 refused, 2 error (bad flags, no such group).

**Builds.** Every build is `msbuild /p:Config=Debug` of the project for `--platform` (default:
the project's active platform from its `.dproj`, else `win32` -- a Delphi 7 `.dpr` or a
Delphi 2007..XE `.dproj` names none; the IDE passes its active platform). The Release configuration is never built.

**Scratch.** The default shadow tree and the gate's `C:\TEMP\draglint_cyclefix_<pid>_build\`
(build logs, `reindex.log`, `all-iteration-<n>.json`) are **deleted at exit** -- the text dry run
says so on its line: `Shadow tree: <dir> (deleted at exit; --shadow-out keeps it)`. A run whose
output **cites a file in there** (a build log after an msbuild failure or timeout, `reindex.log`,
`all-iteration-<n>.json`, ...) **keeps** them, so the cited file still exists, and names each kept
dir on stderr: `drag-lint: note: cycles --fix exited 1; its scratch is kept for the files it cites: <dir>`.
A message cites a scratch file only when it exists. An ordinary refusal cites none and keeps
nothing. A `--shadow-out` dir is never deleted. In the JSON, `shadow_kept` says whether `shadow`
still exists after the run.

**Apply.** `--apply` runs the same plan, then:
1. the baseline build must pass (else `dirty-baseline`, nothing written) -- except a baseline whose ONLY error is an `F2047 Circular unit reference` on a unit of the Part A group being fixed (owner ruling 2026-10-25): the plan is made anyway, `baseline.status` is `f2047-in-group`, and the build after the edit is the only proof;
2. every file it touches is backed up as `<file>.BCK<n>` (the lowest free n) plus a
   `recovery.txt`, unless `--no-backup`;
3. the edits are written and the project is built in place; one bounded repair (R4: a cast
   through the plan's ancestor, a missing leaf unit in `uses`, a re-emitted pointer type) is
   tried on a compile error, otherwise every file is rolled back. The rollback restores the
   sources byte for byte but not the DCUs the failed build wrote: **rebuild the project after a
   rollback** before you trust its output;
4. the project is re-indexed (unless `--no-reindex`) and `cycles` re-run: the output must
   equal the plan's prediction.

Exit codes with `--apply`: **0** written and verified (or written with `--no-reindex`);
**1** refused, rolled back after a compile error or build timeout, or written but not
verified; **2** error -- a write or build failed part-way (rolled back, project not changed,
or the rollback failure is named), or bad flags. `--apply --no-compile` is refused with
exit 2: an apply always builds.

**Parts.** An interface-coupled group is Part A (it becomes a legal implementation-only
group); an implementation-only one is Part B (one edge is cut). `--part a|b` asks for one;
`--part all` applies Part A and then Part B in one run, re-planning on the re-indexed project
after each iteration -- so it **needs `--apply` and refuses `--no-reindex`**.

**Recipes.** Part A moves globals into a `<Declaring>.Untangle` leaf, as `--plan` describes.
Part B cuts one edge: **R1** routine-call inversion (each routine on the edge whose signature
types all live outside the cycle is called through a procedural variable declared in a leaf and
assigned in the declaring unit's initialization section -- one `initialization` edit for all of
them; since plan B3 an edge may carry several routines, and globals on the same edge that can move,
or a plain type a signature names (enum, record, alias), move into the same `<Declaring>.Untangle`
leaf first); **R2** member hand-over
(an edge that is only `is` / `as` against one class plus reads of its members: the class
implements an `I<Class>Surface` interface declared in its leaf, and the consumer uses
`Supports` / `as`).

**JSON.** `--format json` prints one `cycle-fix/1` document: `mode`, `cycles[]` (per group:
`n`, `units`, `part`, `verdict`, `recipe`, `edge`, `refusals[]`, `moves`, `uses`, `new_units`,
`edits`, `compile`, `baseline`, `repairs`, `written`, `backups`, `reindex`, `predicted`,
`actual`, `verified`), `shadow`, `shadow_kept`, `baseline`, `ok`, `exit_code`. An error that
ends the run before any group is planned (bad flags, a `--library-db` that does not open) is
the document `{schema, error, ok: false, exit_code: 2}`. Separately,
`cycles --format json --causes [--project <X.dproj>]` adds a `fix` object to every group of
the report -- `available`, `part`, `dry_run` and `apply` (the exact commands; `--project` names
the project in them, else `<your.dproj>`), `edges[]`, `reason`, and for a Part A group whose
Part B would cut an edge afterwards, `followup {from,to,recipe}`.

### Refusal kinds

A refused group prints `Verdict: refused` and one `  - <kind>: <reason>` line per refusal.
The engine never guesses; every kind it can give:

* **Run and gate:** `dirty-baseline` (the project does not build before any edit),
  `no-compiler` (rsvars.bat missing; name it with `--rsvars <rsvars.bat>` for a Studio the registry /
  BDS does not name, or use `--no-compile` for a dry run), `compile-error` (the
  project does not build after the edit; rolled back), `build-timeout` (a build exceeded the `--build-timeout <s>` you set; rolled back), `cancelled` (the engine was asked to stand down -- IDE Cancel or `drag-lint shutdown --db <db>`; rolled back, exit 1), `build-error` (the build itself failed to run; rolled back, exit 2),
  `write-failed` (a write failed part-way; rolled back, exit 2), `stale-file` (a file changed
  after it was indexed: a dry run or `--apply --no-reindex` refuses -- reindex and retry;
  `--apply` re-indexes once, re-plans and reports `reindex_before`, and refuses only a file
  still stale after that), `anchor-mismatch` (a line the plan edits is not
  what the planner saw), `non-ascii-text` (an inserted line holds a character the ANSI code page of the file cannot hold, in a comment or an identifier -- inside a string literal it is written as a numeric code, `'a'#20013'b'`, instead; a NEW unit holding such text is written UTF-8 with a BOM instead), `outside-roots` (the plan would edit a file outside the project's own
  roots).
* **Plan:** `base-class` (a class whose bodies use the cycle would need a base class
  extracted -- a manual step; the base class stands in for the class at a const / value
  parameter, a private `TArray<TX>` field, and -- plan B4 -- a local, a plain field `F: TX`, a
  `TList<TX>` / `TObjectList<TX>` field and a property read through a method accessor, each only
  when every use is on a closed whitelist; the refusal names the first site that is not. Plan B4-f:
  an IMPLEMENTATION edge that no other recipe cuts is tried with the base class too (ranked after
  R2), and there `X is TX` and `(X as TX).M` -- M pulled into the base, never assigned -- switch to
  the base class as well; a hard cast `TX(X)` stays refused, the refusal naming its line),
  `ctor-inversion-surface` (since 1.44: the consumer constructs the class and the constructor inversion does not cover
  the site, see below; the reason names the line), `blocked-symbol` (a declaration the move needs cannot move: a
  routine, a class whose method bodies use the cycle, an unrecognised declaration block -- an
  indented `type` / `var` / `const` header and the same-line form `var GX: T = v;` are recognised),
  `directive` (a conditional compiler directive inside an edited region; `{$REGION}`,
  `{$ENDREGION}`, `{$WARN}`, `{$HINTS}` and `{$MESSAGE}` inside a uses clause are kept byte for
  byte; since 1.47 a single-branch `{$IFDEF X} ... {$ENDIF}` region whose entries are all removed goes whole, guard included -- an `{$ELSE}` branch, a nested or second directive, or an entry of the region that stays still refuses), `unresolved-edge` (the index could not resolve what one unit of the group uses from
  another; an INTERFACE uses entry the interface uses for nothing is moved to the
  implementation uses, or removed when nothing uses it, and the refusal stays only when a
  lexical hit names an identifier and line), `edge-still-used` (after
  an R1 / R2 cut the consumer still uses the declaring unit for another name, so the uses
  entry -- and the edge -- would stay), `coupling-remains` (since 1.43: the moved declarations of two units need each other and cannot share one new unit, see below, or the plan's own prediction still shows the interface coupling; before 1.43 such a plan printed `mechanical`; since 1.47 also a line that moves and names another unit of the cycle qualified, as `DUnit.Foo(2)` in a method body that moves with its class, which the compile gate used to catch), `manual-edit` (the default for any edit the planner
  cannot make mechanically), `declaration-in-include` (since 1.50: a symbol the cut would move is declared in an
  include file of the declaring unit, `{$I}` at any depth) and `reference-in-include` (since 1.50: a line an R1 / R2 /
  hand-over cut would redirect sits in an include file of the consuming unit) -- drag-lint never edits an include,
  which other units may share; the reason names the symbol, the include and its line, the `{$I}` site in the unit,
  and the remedy: move the declaration (or the code) into the unit itself and run `cycles --plan` again (the lint
  rule `cycle-edge-in-include` reports such an edge). Before 1.50 such a use was invisible to the planner: it printed
  "could not resolve the symbol" and could plan to REMOVE a uses entry the include still needs. An include-borne use
  now counts as a use of the unit that includes it, so its uses entry is always kept; `Why it cycles` names it as
  `` `IncDeclB.pas:12`; declared in `IncDeclA` through `IncDeclTypes.inc:2` (`{$I}` at `IncDeclA.pas:8`) ``.
  Pinned by `run_cyclefix_include_aware.ps1` (positive control: the same fixtures with the include inlined plan
  mechanically and pass the compile gate).
* **R1 (routine-call inversion):** `not-a-routine`, `signature-in-cycle`,
  `overloaded-routine`, `signature-unknown`, `qualified-ref` (a name qualified by the declaring unit that the plan can neither redirect nor move: another routine of that unit, or the inverted routine in a shape it cannot rewrite, such as `@Unit.Foo`; `Unit.Foo(2)` of the inverted routine itself becomes `FooPtr(2)`, a comment or a string is not a use, and a global moves and is rewritten, see below), `name-shadowed` (since 1.44: a line to rewrite also holds `Foo` bound to something else, a nested routine, a method or a parameter, as in `Foo(1); Unit.Foo(2);`, or `Unit` there is a local of the consumer; the rewrite works on the text of the line, so it would call the pointer instead; on separate lines the plan is sound and goes ahead), `routine-not-called` (`@F`, a parameterless function as an argument, an argument on a line of its own; a routine passed as a whole argument is redirected, see below),
  `init-order` (the consumer's initialization section runs the call and, since 1.50, the program's uses order does not prove that the declaring unit initializes first -- see "Init order proved from the program" below; the reason says which condition failed), `finalization-order` (since 1.43: the consumer's finalization section runs the call, and the declaring unit, finalized first after the cut, has statements in its finalization section or a variable of a type the compiler may finalize), `unsupported-directive`, `duplicate-identifier` (the leaf already declares the
  pointer type or variable differently and every suffix up to 99 is taken; an identical declaration is
  reused, a different one gets the lowest free suffix; since 1.44 also when the consumer, the declaring unit or a class member already declares `FooPtr`, which would win over the pointer). `unit-leaves-program` is NOT a refusal
  any more (since 1.34.1): when the declaring unit is used only by the consumer and the
  program's `.dpr` does not list it, the plan adds the unit to the `.dpr` uses (and a
  `DCCReference` to the `.dproj` when absent), because after the cut the linker would drop it,
  its initialization would never assign the pointer and the call would be a nil call at run time.
* **R2 (member hand-over):** `member-write` (a plain write `F := v` is carried by a read/write
  property with a one-line setter; `Inc` / `Dec(F)`, `F` passed to a var / out parameter and a
  write into a record-typed member are refused), `construction`, `class-method` (an instance
  method the consumer calls inside `with ... as TX do` is carried as an interface method, its
  signature copied verbatim and dispatch to an override unchanged; a class method or a method
  taken as a pointer is refused), `overloaded-routine`, `signature-in-cycle`, `class-ref`,
  `type-decl` (a declaration of the class type other than a routine local `V: TX;` alone on
  its line -- since 1.42 such a local is retyped to the interface when every use of it is
  `V := X as TX`, `V := nil`, `Assigned(V)`, a compare with nil or `V.M` with M a member the
  interface carries; a field, a parameter, a global, an inline `var`, `A, B: TX` and any other
  use of the local, `V.Free` or `FreeAndNil(V)` included, still refuse), `other-ref`, `multiple-classes` (since 1.42 an edge through several
  classes is cut with one interface per class, see below; since 1.49 a class the edge only hard-casts, `TX(X).M`, counts as one too), `member-unsupported` (an inherited
  member that no ancestor declared in the class's own unit declares, or one that is `strict private`
  there -- since 1.42 a member of a same-unit ancestor is carried like an own one, its getter reading
  it by name, and an ancestor that already declares `Get<M>` / `Set<M>` refuses `duplicate-identifier`;
  a member of a library ancestor named inside a `with` body is carried too, see below --, a `default` array property or a write to an indexed property; a plain indexed property
  is carried for reading, its index list verbatim), `duplicate-identifier` (the class has a `Get<M>`
  that is not exactly `function Get<M>: <T>;` read by the property -- that one is reused -- or the
  leaf declares `I<Class>Surface` differently with every suffix taken; an identical interface is
  reused, a different one gets the lowest free suffix), `no-iinterface`, `ref-counted`, `receiver-unknown`, `cast-unseen`
  (no IInterface ancestor outside the cycle; the walk continues past one declared inside it),
  `exception-semantics` (since 1.47 only when the name of the helper below is taken: a consumer that handles EInvalidCast and casts with an unguarded `as` gets `function As<Surface>(const pX: TObject): I<Surface>` before the routine that casts -- nil for nil, else the interface, else `raise EInvalidCast.CreateRes(@SInvalidCast)`, the class and message the failed class cast raised; every `X as TX` of that consumer goes through it; since 1.49 an `as` whose receiver's static type is unknown -- `GetOwner as TX` -- goes through the same helper instead of refusing `receiver-unknown`, handler or not; a hard cast `TX(X).M` under an EInvalidCast handler becomes `(X as I).M` and the plan states that behaviour change), `ancestry-unknown`, `with-member`, `unresolved-qualified-type`,
  `type-unresolved`, `leaf-uses-cycle`.

### Four shapes that are cut since 1.43

* **Two units whose moved types need each other (the F2047 shape, `cycle-lab\illegal`).** One new
  unit per source would use the other in its interface, which is F2047 again. They share ONE new unit,
  `<First>.Untangle`, in one `type` block: a class or interface used before its place gets a forward
  declaration (`TIllOrder = class;`); an ancestor, a record held by value and every other type comes
  complete first. Both old `uses` entries are removed. Only plain types without bodies merge, in new
  units: a const or variable in the set, a class with method bodies, a generic class, an existing leaf or
  a by-value loop refuses `coupling-remains`.
* **`finalization` is not `initialization`.** `init-order` used to count the finalization section:
  a routine named there runs long after the pointer is assigned. It can still run too late, for another
  reason: the declaring unit keeps using the consumer, so it is finalized FIRST. The call is planned only
  when that cannot be seen (no statement in the declaring unit's finalization section, and every variable
  of a type known to need no finalization: an ordinal, a float, a pointer, a class, a plain procedural
  type); otherwise `finalization-order`. The check reads the declaring unit only, not what the routine
  calls.
* **`Unit.GVar`.** A qualified name is no reference in the index. A global of the declaring unit that the
  consumer names qualified now moves with the edge, and every code occurrence of `<Unit>.<Name>` of a moved
  declaration, in the source and in every unit that uses it (Part A and Part B), becomes
  `<Unit>.Untangle.<Name>`. Strings and comments stay. A `Unit.Y` that does not move keeps the uses entry (in an interface declaration that means `coupling-remains`, before any build; since 1.44 this includes a subrange bound, `array[0..Unit.cMax]`, whose `..` used to hide the name, so the entry was removed and the build failed with `E2242`),
  and on an R1 edge a qualified routine other than the inverted one still refuses `qualified-ref`; `Unit.Foo(2)` of the inverted routine goes through the pointer.
* **A routine passed as an argument (`AddItem(x, Foo)`).** The pointer is passed instead: a procedural
  type or a method reference with the same parameters takes it, under the same order checks as a call.
  It holds for a procedure, and for a function with a required parameter. A parameterless function as an
  argument is its RESULT, so that stays refused.

### Init order proved from the program (since 1.50)

A routine-call inversion (R1) moves the call behind a pointer that the declaring unit assigns as the
first statement of its initialization. When the consumer's own initialization makes the call, the
pointer is still nil there unless the declaring unit initializes FIRST. Since 1.50 the planner proves
that from the program instead of refusing outright. Delphi initializes units in a depth-first
post-order from the .dpr uses list (interface uses, then implementation uses, a unit already being
visited is skipped -- the order `init-order-hazard` uses; pinned by `run_cyclefix_initorder_proof_dcc.ps1`
on six compiled programs). The call is planned when ALL hold, for every program of the index that
reaches both units:

| Condition | Refusal text when it fails (kind stays `init-order`) |
|---|---|
| After the cut the consumer still reaches the declaring unit through other units | "after the cut `B` still uses `A` and `A` no longer reaches `B`, so `A` initializes first whatever the .dpr order: the variable is nil there" -- always the case in a TWO-unit cycle, never provable |
| The declaring unit comes first, with the uses as they stand and with the cut made | "in `X.dpr` `A` (position m) initializes before `B` (position n): list `A` before `<entry>` in the .dpr, or cut another edge" |
| No uses entry of the .dpr, either unit or a unit on the path sits in a conditional region or comes from an include | "the order depends on a conditional uses entry (`file:line`)" |
| The index holds a program (a package has no initialization order) | "no program in this index: a package has no initialization order to prove" |
| The edge is weighed on the graph predicted after Part A | the old reason + "; re-checked against the program order once Part A is applied" (Part A moves uses entries, which changes the order; re-run `--plan` after it) |

A proved plan prints, in the step that edits the declaring unit, `init order: `B` initializes before `A`
in `X.dpr` (position n before m; `A` reaches `B` through `C`). This holds for this uses order; the lint
rule `init-order-hazard` reports it if a later uses change reverses it.`, and `--causes --format json`
carries the same text as `fix.edges[].init_order`. The proof holds for one uses order: a later edit of the
.dpr or of a uses clause can reverse it, and `init-order-hazard` (which since 1.50 also follows a variable
declared in a used unit, the pointer's leaf, and assigned in the declaring unit's initialization) reports
the nil read then.

### Never automatic, and why (since 1.50)

Some base-class refusals are final: no later engine will cut them, because the cut would retype code
outside the cycle. The reason is now part of the refusal:

| Site | Reason printed |
|---|---|
| a `var` / `out` parameter of the class | the compiler requires the actual and the formal `var` parameter to be of the identical type (E2033), so every caller's variable would have to be retyped |
| a function result of the class | every caller's expression would change type; that is retyping the callers, not a cut |
| the class as a generic type argument (`TList<TX>`) | `TList<TX>` and `TList<TXBase>` are different types (E2010) |
| a class descending from `TInterfacedObject` (appended to any other reason) | an interface reference would count the object and free it when the reference goes out of scope while plain object references still hold it |

Merge the two units, or change the signature by hand, when such a cycle must go.

### Constructor inversion (since 1.44)

A class whose bodies use the cycle cannot move, and a consumer that constructs it used to refuse `blocked-symbol`
(`TX.` is the class itself). Now the constructor goes through a pointer, in the R1 shape, next to the base class:

```pascal
// the leaf
TXBase = class(TAnc) ... end;               // the members the consumer uses; methods `virtual; abstract;`
TNewTXPtr = function(<ctor params>): TXBase;
var NewTXPtr: TNewTXPtr;

// TX's unit
function NewTX(<ctor params>): TXBase; begin Result := TX.Create(<names>); end;
initialization
  NewTXPtr := NewTX;

// the consumer: `FX: TX;` becomes `FX: TXBase;`, `FX := TX.Create(a);` becomes `FX := NewTXPtr(a);`
```

Same constructor, same arguments, same owner, one indirection. The parameter list is verbatim, default values
included; an inherited constructor (`TDataModule.Create(AOwner)`) is read from the platform library. The consumer loses
its `uses` of TX's unit, so for an edge this usually ends the cycle rather than only its interface coupling.

Only this closed set is planned, every other site refuses `ctor-inversion-surface` and names the line (on an implementation edge the kind stays R2's `construction`, and the reason adds `through a base class: refused: ctor-inversion-surface -- ...`):

* the call is `S := TX.<ctor>[(args)]` as a whole statement, S a field or local of type TX that switches to the base class;
* every other use of S is on the base class whitelist: a member read, a call of a method pulled into the base,
  `Free`, `FreeAndNil(S)`, `Assigned(S)`, a nil test, a store to or from another such slot;
* one constructor per class, not overloaded, every parameter type a plain name that is a System built-in or
  lives in a unit outside the cycle that the interface of TX's unit already uses;
* the program lists TX's unit (nothing else may use it after the cut, and its initialization assigns the pointer);
* the consumer's initialization section neither holds the call nor names the routine that makes it, its finalization
  does not hold it (`init-order`'s check of R1).

Stays refused on purpose: a temporary (`TX.Create(nil).Show`, `with TX.Create do`), `Result := TX.Create`, a global or
a property of the class type, the slot passed as an argument, a property written through it, `TX.ClassMethod`
(`blocked-symbol` as before), a class reference as a value (`Application.CreateForm(TX, V)`), an `override` the base
class would have to carry, `var` / `out` of type TX. T is always the base class: a library ancestor would need no new
class when it covers every use, but the base class is sound in every case the whitelist admits.

### The wider whitelist: `--ctor-wide` (off by default)

`cycles --plan --ctor-wide` and `cycles --fix --ctor-wide` also plan these, each a shape that keeps the program's behaviour:

* a store to a field pulled into the base class (`S.F := x`: the same memory; a public field stays public in the base);
* `L.Add(TX.Create(..))`, `L[i].M` with M inherited (not declared by TX) and `L.OwnsObjects` on a list field that switches;
* an `override` stays in the class and is not pulled: the base inherits the same virtual, a call through it reaches the class's body;
* a dotted unit name in `uses` or a multi-line comment that spells a slot's name is no use of the slot.

With the flag a field in the published section, or an unlabelled one, is refused when the consumer would pull it: a `.dfm` streams into it. A library property written through the slot, a temporary, `L.Extract` and `L.First` stay refused.

A lifted site is not a cut cycle. On a hub-shaped group (N units read the hub form's global, the hub creates them all) the interface `uses` edges go and the implementation cycle stays, so count sites planned, sites applied and compiled, and cycles cut separately. A data module gets a new ancestor without a `.dfm`: it loads at run time (the guard runs it); opening it in the form designer is not proved. Design and measurements: `docs\superpowers\specs\2026-11-06-ctorinv-loader.md`.

### A library member through a `with` body or a cast (R2, since 1.43)

The same carrying applies to `(X as TClass).M` and `TClass(X).M` with M a library member; there a library method
refuses `class-method`, and any other member that cannot be carried `member-unsupported`.

After the rewrite a `with X as TClass do` body sees the interface, not the class, so a bare name the class
inherited from a library ancestor would silently bind to something else. A public or published, non-indexed
field or property of a library ancestor therefore goes on the interface as well: its getter reads it by name, a
plain write adds a setter, and an accessor name the chain already declares takes the suffix `Surface`
(`TPersistent.GetOwner` -> `GetOwnerSurface`). A name private to its library unit is invisible to the consumer
and is ignored. The same goes for a public or published field or property of a project class of the chain that the edge
itself does not list (the index binds a bare name to the innermost `with` only). A `with` head may span several lines. These still refuse `with-member`, on purpose:

* **A library method** (`Free`, `Show`). `Free` through an interface leaves a temporary to release on a freed
  object; rewrite that line by hand.
* **A protected library member.** The consumer sees it only if it descends from its class; carrying it could
  itself change what the name binds to.
* **An indexed property**, a type that is not a plain name, or a library source the index no longer finds
  (visibility unknown).

### An edge through several classes (R2, since 1.42)

When the consumer tests or casts against more than one class of the used unit, each class that is an
`is` / `as` operand gets its own interface `I<Class>Surface` in the same leaf, with its own GUID, its own
getters and setters, and every use site is retyped to its own interface; a consumer line naming two classes
is rewritten for both. The output is deterministic: classes are taken in name order and the GUID derives from
leaf + interface name.

* **All or nothing.** Every R2 check runs per class. The first class refused refuses the whole edge, under
  that class's own refusal kind, and the reason names the class (`class `TZed`: no ancestor ...`). No
  interface of the other classes is planned, so nothing is half-applied.
* **A member two classes can reach** is carried by each: `TA` and `TB` sharing a same-unit ancestor's member
  each get a getter, and a member of `TA` is also on the interface of a descendant `TB` of `TA` when both are on
  the edge, even if only `TA`'s uses read it. `X is TA` stays true for a `TB`, because `TB` inherits `TA`'s
  interface. A `Get<M>` that already exists on the ancestor therefore refuses `duplicate-identifier` on the
  descendant; split the edge by hand if that hits you.
* **An existing leaf** is settled per interface: an identical declaration is reused, a different one takes the
  lowest suffix free in the leaf and on the edge, and the others are not affected.
* **Overlapping `with` bodies** (nested, or one `with X as TA, Y as TB do`, since 1.43): each class checks every bare
  name of its whole body, so a name either class declares is carried by that class or the edge is refused, and
  the nesting order, unchanged by the rewrite, decides between two carriers as it did between the classes.
  Measured on 1.43.0-alpha (un_cyclefix_r2_multiclass_dcc.ps1, 153 checks): the nested form, the comma form and a head spread over two lines each plan exit 0 with two interfaces, the followed copy builds and prints byte-identical output; a library method such as Free bare inside the overlapping bodies refuses with-member (not multiple-classes) and nothing is planned.
* **Still refused:** `other-ref` on the edge's line for an `as` operand that is an interface, or an `is` / `as` operand that is an alias, which the planner
  could not move out either (the refusal names the line); the `with-member` shapes above. Read the edge's line: the verdict of the whole cycle is often `coupling-remains`, because the other direction would have to move a class with bodies. `X is <interface>` is not one of these shapes: it does not compile (`E2015`, for a class or an interface on the left), so only `as` reaches the planner; an interface or alias that can move goes to the leaf and the plan is mechanical.
* `--plan`, `tools\follow-cycle-plan.ps1` and `--fix --apply` apply the same bytes; guard
  `tests\autotest\run_cyclefix_r2_multiclass_dcc.ps1`.

### What the fix handles when names or call shapes already exist

These cases used to refuse and are now applied (lane CYC-C), or are predicted the same way by `--plan` (CYC-B):

* **Names already in the leaf (routine-call inversion).** If the leaf unit already declares the pointer
  names, identical `T<Routine>Ptr` / `<Routine>Ptr` text is reused and nothing is inserted; different text gets
  the lowest free `<Routine>Ptr2`, `Ptr3` ... instead of `duplicate-identifier`. For an interface extraction
  an identical `I<Class>Surface` is reused and a different one takes the lowest free suffix; an existing
  `Get<M>` is reused only when it is exactly `function Get<M>: <T>;` and the property reads through it
  (any other still refuses).
* **Call shapes.** `B.Foo(...)` (the inverted routine qualified by its unit) and `X := Foo` (an assigned value)
  are redirected to the pointer under the same initialization-order check. `@Foo`, `@B.Foo` and any other
  `B.X` still refuse.
* **Overloads.** An overloaded routine is bound when the overload the index bound admits the argument count of
  every call, no other overload admits any, and none has a default parameter; otherwise `overloaded-routine` stays.
* **Source layout.** An indented `type` / `var` / `const` header (indented less than its declarations) and the
  same-line forms `var GX: T = v;` / `type TR = record` are recognised. A final `end.` followed by a block comment is
  still the final `end.`; a class heritage spread over several lines is read up to its closing `)`. An unbalanced
  heritage still refuses `manual-edit`.
* **Plan agrees with fix.** A routine edge whose signature names a type that Part A already moves is predicted as
  cut by routine-call inversion (not `signature-in-cycle`) when Part B is re-run,.

Still manual: type declarations and type casts of the moved name, an edge that names several classes but neither tests nor casts any of them (`multiple-classes`; with an `is` / `as` operand or a hard cast `TX(X).M` several classes are cut, see above), unsupported
members, unresolved types, non-ASCII text in a comment or an identifier (in a string literal it becomes a `#code`).
### What stays manual

A refused group is yours: `--plan` still prints the playbook and the standard remedy for it,
and `tools\follow-cycle-plan.ps1` applies a playbook's edits literally when you have decided
to follow it by hand. Moving a class whose method bodies use the cycle, and any cut the
refusals above name, stay human decisions.

### Per-file finding

`lint <file> --db <db> --format json` reports `circular-uses` on every unit of a cycle, at the
first intra-cycle `uses` entry of that file (implementation section preferred), with
`"fix_hint": "cycles --fix --project \"<X.dproj>\" --db \"<db>\" --unit <stem>"`; `lint-all`
keeps one finding per cycle and no hint.

## The extended example: what DL does, what it reports, what you do

`docs\examples\cycle-lab` extends `circular-demo` with the shapes `cycles --fix` refuses, one small
unit pair each, plus `illegal\` (a project the compiler rejects). Replay it with `run-lab.sh`.
Measured on 1.36.0-alpha; the playbook text alone was handed to Haiku.

| Layer | What happens | Cases |
|---|---|---|
| DL fixes (compile-gated, `cycles --fix --apply`) | Part A leaf units; the build and the program output stay identical | the four circular-demo groups, LabInit, LabExc |
| DL reports, you cut by hand | `Verdict: refused` with the kind and line, or `Nothing can be moved mechanically` + a MANUAL list | LabVar, LabRc, LabCls (`blocked-symbol`), LabDir, LabGuard (`directive`) |
| DL fixes since 1.44 | constructor inversion: the owner calls a pointer, the base class carries what it uses; the cycle is gone, the build and the output stay identical | LabCtor, LabCtorStr |
| DL fixes since 1.43 | `--fix --apply` puts both classes into one new unit behind a forward declaration; the F2047 is gone and the project builds | `illegal\` |
| DL does not see it | `uses {$I file.inc}`: parse error at index time, no cycle line | LabInc |

Haiku (playbook only, no shell): the build stayed green and the output identical, but of the six
refused groups only LabDir (delete the unused guarded entry), LabCls (class and metaclass merged into
one new unit) and `illegal\` (both classes merged into one unit, forward `TIllOrder = class;`) ended
without a cycle. For LabVar, LabGuard, LabCtor and LabRc it moved one class into a `*.Untangle` unit
that still uses its partner in the interface: the cycle only changed name. Rule for the manual step:
a cut counts only when `cycles` stops printing "has interface coupling" for the pair, not when the
project compiles.
## Reaching it in the IDE
* drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...
* drag-lint > Uses & Dependencies > Fix Circular Uses Mechanically (dry run)... -- a dry
  run only (the engine picks the group; no `--apply` from a menu click). Save first: the
  engine plans and compiles from the files on disk.
* The drag-lint tool window (View > Tool Windows), Uses & Deps tab, section *This project -- Circular uses
  (cycles --fix)*: one row per group, Dry run / Apply buttons. Apply asks first (Yes / No,
  default No), like the Structure tree.
* drag-lint Structure window, Diagnostics tree, right-click a `circular-uses` finding:
  *Fix this cycle (dry run)...* and *Apply cycle fix...* (a dry run, your confirmation, then
  `--apply`).

Every IDE-started run passes the IDE's active platform as `--platform`. There is no time limit: `--build-timeout <s>` sets one per build (default 0 = none). Instead the run shows its progress: while it waits on a build, a re-index or a child run, the status strip reads e.g. *cycles --fix: baseline build 45 s* (the engine heartbeat), and on the command line stderr says `cycles --fix: <step> -- started`, then every 10 s `cycles --fix: <step> -- <n> s (no time limit; Cancel, or drag-lint shutdown --db "<db>", stops it)`; stdout keeps only the result. Cancel on the status strip asks the engine to stand down: it kills the build, rolls back, exits 1 *cancelled -- rolled back*; only an engine still running after 90 s is killed. `--part all` forwards the request.

## What it needs
Required. You must have indexed the project before running this -- cycle
detection reads unit-to-unit `uses` edges from the index, not from disk.

## Example
Illustrative only, against a project database that has already been indexed:
```
drag-lint cycles --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --plan --format text
```
This would report any `uses` cycles involving, say, the unit that declares
`TfrmMain`, plus a suggested order of moves to break them.
