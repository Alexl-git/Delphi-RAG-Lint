# extract-interface and lazy-init (E-REFACTOR-5, E-REFACTOR-6 first phase)

Lane g3, wave 146. Both are NEW verbs; nothing existing changes behaviour. The backlog's DROP advice was overruled by
the owner for this row. The branch is for owner review.

## The shared gate: a build on a scratch copy, then the real gate

`ApplyGated` (the compile gate of narrow-param and friends) writes the rewrite into the real tree, builds, and rolls back
on failure. Three options for the "scratch copy" the row asks for:

| option | for | against |
|---|---|---|
| A. `ApplyGated` only | exists, proved | a broken rewrite touches the real tree (and a running IDE sees it) for a whole build |
| B. Scratch only, then write | real tree never holds an unbuilt rewrite | a unit reached by an ABSOLUTE search path builds from the original in the copy, so the rewrite would go unproved |
| C. Scratch, THEN `ApplyGated` | both: a rewrite that does not compile never reaches the tree, and the tree is still built | one more build |

**Chosen: C** (`DRagLint.Refactor.ScratchGate`). The mirror holds the project's folder and every folder holding an
indexed file, source and resource extensions only, laid out under their common ancestor so relative paths in the `.dproj`
and `.dpr` still resolve. Output folders are forced into the scratch on the msbuild line, so a project with an absolute
`DCC_ExeOutput` cannot overwrite its real exe. A failed scratch build is classified by building the copy WITHOUT the
rewrite: `scratch-compile-error` (the rewrite is at fault) or `scratch-unusable` (the mirror cannot build the project at
all, for instance an unindexed folder). Files on two drives: `scratch-unavailable`. All three leave the real tree alone
and exit 1.

Assumption the owner can reverse: scratch failures refuse; there is no flag to skip them.

## E-REFACTOR-5: `extract-interface`

**What "the members used" means.** A member of the class counts when a reference from outside the class resolves to it
(call edge or symbol), or names it through a receiver typed as the class or a descendant. A reference inside the class
does not count, nor an implicit-Self one in a descendant: neither is a consumer. `--members a,b` replaces the computed set.

Options for the output:

| option | for | against |
|---|---|---|
| A. Print the interface only | no risk | the owner still does the edit; no proof it compiles |
| B. Add the interface and the heritage entry; consumers stay on the class | purely additive, the build proves it | no consumer gets decoupled yet |
| C. B + retype consumers (parameters, fields) to the interface | the actual decoupling | refcount semantics: a class instance passed as an interface parameter can be FREED when the parameter goes out of scope. dcc catches nothing |

**Chosen: B.** C is a later phase and needs a lifetime proof (who owns the instance) that the index does not hold.

Behaviour:
- `IFoo` goes in the same type block, immediately before `TFoo` and its doc comment: every type a member's signature names is
  in scope there. The class's own name in a signature gets a forward `TFoo = class;` unless one exists.
- Method headers are copied from the source. Kept directives: `overload`, calling conventions and hints. Dropped:
  `virtual`, `override`, `abstract`, `dynamic`, `reintroduce`, `final`, `inline`, `static`, `message`.
- A property goes through only with method accessors (private ones are legal implementers); they join the interface.
- The GUID is a name-based hash of unit, interface and members: the plan shows the very bytes `--apply` writes.
- Left out, each named, and the run carries on, because the class keeps them: `field`, `not-public`, `class-member`
  (class methods, constructors, destructors, operators), `generic-method`, `class-scope-name` (the signature names something
  declared inside the class), `field-backed-property`, `property-specifier`, `no-such-member`.
- Refused whole: `include-file`, `stale-file`, `outside-roots`, `generic-class`, `nested-class`, `class-helper`,
  `ifdef-in-class`, `type-on-same-line`, `name-taken`, `no-iinterface`, `unresolved-ancestor`, `no-used-members`.

`no-iinterface`: a class whose chain has no `IInterface` implementation cannot take an interface. `--reparent-interfaced`
(opt-in, direct parent `TObject` only) makes it `TInterfacedObject`. Existing code keeps working, because `Create` / `Free`
behave the same until someone holds an interface reference. Never done by default.

Assumption the owner can reverse: all overloads of a used name go in, since the interface should not make a caller's
overload resolution differ between the class and the interface.

## E-REFACTOR-6 first phase: `lazy-init`

Moving work out of a section changes WHEN it runs; a compiler proves nothing about that. Options:

| option | for | against |
|---|---|---|
| A. Global-to-getter rewrite: `G` becomes `function G` with lazy creation, every reader rewritten | the real payoff | cross-unit, thread safety, finalization order, side effects moved. XL |
| B. Delete the section and make callers call `EnsureX` | simple text | one missed caller is a nil crash at run time; no build catches it |
| C. Extract: the section's body moves VERBATIM into a run-once routine, and the section just calls it. Order and effects are unchanged. Plus a plan naming what a phase 2 needs | behaviour-preserving, proved by build and by run; every later step becomes a one-line change | by itself nothing starts later yet |

**Chosen: C as phase 1.** Phase 2 (owner's decision, not built): for a candidate the plan marks, drop the section's call and
call `EnsureX` from a getter or the application's start.

The plan (default): per section the statements with the heavy ones marked (the `heavy-initialization` rule's evidence), and
per global the section writes: where it is declared, its readers inside and outside the unit, and `lazy_candidate`
(declared in the implementation section and read by no other unit, so a phase 2 rewrite stays in one file). `--all` lists
every section the rule reports; `--apply` takes one `--unit`.

Refusals: `no-section` (none, or the old `begin ... end.` form), `empty-section`, `include-file`, `stale-file`, `outside-roots`,
`ifdef-around-section`, `unbalanced-ifdef`, `include-in-section`, `name-taken` (also the fixed point: a second run finds the
routine exists).

Assumption the owner can reverse: the run-once guard is a plain Boolean, because the only caller in phase 1 is the section,
on one thread. Phase 2 must decide thread safety before adding a second caller.

## Not done, on purpose

- The IDE plugin wiring of either verb.
- Retyping consumers (extract-interface phase 2), moving the work (lazy-init phase 2).
- A lint rule pointing at either verb.

## Phase 2 consumer retype: why `--reparent-interfaced` cannot prove one (wave 148 RN, 2026-11-08)

Row: "`--reparent-interfaced` opt-in retypes one consumer (lifetime proof)". Not built; 149 row. The analysis:

- `--reparent-interfaced` makes the class a `TInterfacedObject`: reference-counted. Every instance in the program today
  is created into a CLASS-typed location (no interface type exists before the verb runs), so its count is 0.
- Retyping ONE consumer `p: TFoo` to `p: IFoo` (by value or `const`) makes each caller convert an object reference to an
  interface. The compiler holds the result in a hidden temporary: `_AddRef` (count 1), call, temporary finalized,
  `_Release` (count 0), destructor. The caller's `TFoo` variable now dangles. dcc reports nothing, a build gate proves
  nothing, and a run shows it only when the freed memory is reused. That is the "lifetime proof the index does not hold":
  with a reference-counted base it cannot hold for any caller that passes a class reference, which is every caller.
- So for a `TInterfacedObject` reparent the honest proof is "never"; a guarded retype would refuse 100 percent of the time.

Options for a 149 phase:

| option | proof | cost |
|---|---|---|
| A. Retype only when the class's `IInterface` does NOT count references: chain reaches `TComponent` (no `VCLComObject`) or `TNoRefCountObject`; refuse `lifetime-refcounted` otherwise | `_AddRef`/`_Release` return -1, so no interface reference can free the instance; uses checked as narrow-param checks members (every use is an interface member, nil test; `is`/cast/store refused) | M: reuse NarrowParam's body scan + ExtractInterface's member set |
| B. `--reparent-interfaced=norefcount`: reparent to `TNoRefCountObject` instead of `TInterfacedObject`, then A applies | as A | S on top of A |
| C. Whole-program ownership proof for a counted class: every `TFoo.Create` lands in an interface-typed location and nothing calls `Free` | needs every construction site and every free; cross-unit rewrite | XL |

Default proposed (owner can reverse): A + B, opt-in flag `--retype-consumer <Routine>.<param>`, one consumer per run,
through the scratch gate and the compile gate. Owner question filed in lanes\148\OWNER-QUESTIONS.md.