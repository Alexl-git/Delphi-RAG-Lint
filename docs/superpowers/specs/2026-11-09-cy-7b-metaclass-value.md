# 150-CY-7b -- metaclass passed as a VALUE across a cycle edge (design note, lane 150 CY2)

Status: IMPLEMENTED in 150 by lane CY1 (5120c2ab6), option 1, all in CyclePlan.pas (PlanMetaclassValue / MetaclassSteps).
Deviation from 'Where the code goes': no new TCutRecipe value and no CycleEdge.pas change -- the steps are encoded as
crRoutineInversion with ClassTypeName = TX (IsMetaclassInversion), so R1's leaf / uses / RegisterDecl / --fix paths apply
unchanged and the renderer names the recipe 'metaclass hand-over'. Known gap: cycles --fix summary and --format json
still name the recipe 'routine-call inversion' / 'routine-inversion'. The guard now asserts the acceptance (m2/m3) plus
k2 (init-order) and pc1.
History (CY2):
Fixture + guard that pin today's (safe) behaviour: tests\fixtures\cyclefix\metaclassvalue,
tests\autotest\run_cyclefix_metaclass_value_dcc.ps1.

## Shape
Unit A (consumer) passes a class TX declared in unit B as a VALUE: `RegisterClass(TX)`,
`Application.CreateForm(TX, V)`, `Register(TX)`. TX cannot move to a leaf (its bodies need the cycle).
The edge A -> B carries only that value (CycleEdge surface: ClassNames=[TX], HasClassRefArg, no
members, no construction / class method / cast / decl). Census (149 CYA): Loader 0, dlcli 1, lab 1.

## Today (1.49 base, fixture metaclassvalue)
`mvapp -> mvjob` is refused by the base-class route: "`TMvJob` is used here as something other than a
parameter type (a field, variable, cast or type argument)" (CyclePlan.pas:3292). Safe (no plan, --fix
refuses, files untouched) but the wording misdescribes a metaclass argument (handed over to CY1).

## Options
1. R1-shaped hand-over: leaf declares `var TXClass: <metaclass>`; B's initialization assigns
   `TXClass := TX;`; A's value uses become `TXClass`. Reuses R1's leaf, init-order check
   (InitOrderWhy), unit-leaves-program check (LeavesProgramReason / RegisterDecl).
2. Base-class route extension: TX gets a library-only base, A passes the base's metaclass. Wrong:
   the registered class would change identity (RegisterClass / CreateForm need TX itself).
3. Refuse with a precise reason (today, better wording).

Chosen: (1), with (3) as the refusal for every unprovable case.

## Option 1 -- the decisions
- Metaclass type of the variable = the FORMAL parameter's type at the value's argument position
  (library or project routine, read from the callee's signature: `RegisterClass(AClass: TPersistentClass)`
  -> TPersistentClass, `CreateForm(InstanceClass: TComponentClass; var Reference)` -> TComponentClass).
  Its declaring unit goes into the leaf's uses (SigTypes machinery). Not resolvable (no library, overloads
  that differ at that position, an untyped / open-array parameter) -> refuse `signature-unknown`.
  A formal metaclass declared IN the cycle -> refuse `signature-in-cycle` (the 150 row's "cycle-declared
  metaclass of a base class + virtual-constructor proof" is a later extension, not 150).
- Assignment `TXClass := TX;` in B's initialization section (created when absent), as R1's pointer.
- Init order: every rewritten use must run after B's initialization: refuse `init-order` when the use is in
  A's initialization section or in a routine A's initialization names (InitOrderWhy, as R1); the .dpr main
  block and anything called from a form / event runs after all initializations.
- B must stay linked: LeavesProgramReason -> RegisterDecl (as R1, A2).
- A value use that is not a call argument (`C := TX`, `[TX]`, `TX.ClassName` already is class-method) ->
  refuse `class-ref` with "passes the class `TX` as a value outside a call argument".

## Where the code goes
- CycleEdge.pas (CY2): `PlanMetaclassHandOver(pSource, pLibrary, pSurface, out pRefusal): TRecipeSteps`
  (new TCutRecipe value crMetaclassHandOver; Edits = the A-line rewrites + B's initialization assignment).
- CyclePlan.pas (CY1): PlanInversion / EvaluateEdge route an edge whose surface is value-only to it (before
  the base-class route), the leaf + uses + RegisterDecl handling shared with R1, the renderer block, the
  --fix applier (Edits are generic TRecipeEdit), RecipeRank.
- Acceptance: run_cyclefix_metaclass_value_dcc.ps1 flips m1-m3 from "refused" to "planned + --apply builds +
  stdout byte-identical + no cycle"; k-controls: the use in A's initialization -> init-order refusal.

## Reversible assumptions
- The variable is named `<TX without T>Class` (`TMvJob` -> `MvJobClass`), suffix 2..99 on a clash, as R1.
- One variable per class, shared by every value use of TX in A.