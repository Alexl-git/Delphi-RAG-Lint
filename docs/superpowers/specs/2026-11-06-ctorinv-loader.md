# Constructor inversion on Loader (E-CTORINV-LOADER), wave 146, lane r4

Status: first phase built behind `--ctor-wide` (OFF by default). On Loader: 14 of 14 planned, 14 of 14 applied and compiled, 0 cycles cut; see "Measured result".

## The question

`cycles --plan` / `--fix` refuses all 14 Loader sites (12 `TdmX`, `TFolderProcessor`, `TFolderWorker`) with
`ctor-inversion-surface`. Earlier reports gave causes from reading the first refusal only. This spec classifies
each site by what actually blocked it, measured on a scratch copy of `C:\Projects\Loader2019\Loader2025.dproj` by
lifting one blocker at a time and re-running the plan.

The headless build of the copy needs three edits nobody had recorded (the original project does not build under
msbuild here either): `Custom_Styles` removed (`Windows11_Modern_Light.vsf` is not installed), the unit scope names widened
(`System.Win`, `Bde`, ...), `C:\Projects\spring4d\Source` on the include path. `Win32\Debug\{DOC,DCU,EXE}` must exist.
Then the untouched copy builds: 834795 lines, 0 errors, about 60 s.

## Classification, measured

| Site | Blocker seen first (1.44 text) | Every blocker, in the order they surfaced |
|---|---|---|
| 12 `TdmX` (`FDM_X` in `Loader2025.FolderProcessor`) | `FDM_X.GFLDRID` "is not a read of a member" | one: a store to a public field through the slot. `Configure`, `LoadData` already pull; the constructor signature (`TDataModule.Create(AOwner)`) already reads from the library; the spaced `TdmOPERAT  .Create(nil); FDM_OPERAT  .Configure(..)` already rewrites |
| `TFolderProcessor` | `Loader2019.Main.pas:108` field `FolderProcessor` | one, a false refusal: line 108 is `, Loader2025.FolderProcessor` in `uses`; the field of the same name (line 398) is dead. The earlier reports read it as "field not readable via base" |
| `TFolderWorker` | "method `Execute` already carries directives (override)" | five. (1) False: `Execute` is pulled only because `FDBatchMove1.Execute` (`Main:2062`) is unresolved and matches by name; (2) `FWorkers.Add(TFolderWorker.Create(..))`, the construction as an argument; (3) `FWorkers[I].Finished`, a read of an inherited member of an element, and `FWorkers.OwnsObjects := False`; (4) false: `FWorkers` in a multi-line `{ }` comment (`Main:2188`) counted as a use; (5) `var FW: TFolderWorker:= FWorkers[Ix]` (`Main:2194`) and `W.Finished` (`Main:1672`, an inherited member with no read fact on an unresolved ref) |

So the row's "field typed TdmX not readable via base" was wrong for all 12 (reads pass; it is one store), and
"override" was an accident of name matching. No site was blocked by the hub.

## What the hub does (fabcyc row 18 is right, and it is a different question)

The 15 interface `uses` edges of this cycle are exactly these sites: `Main -> FolderProcessor`, `Main -> FolderWorker`,
`FolderWorker -> FolderProcessor`, `FolderProcessor -> 12 uX`. Cutting them ends the INTERFACE coupling.
The cycle lives on in the implementation edges: every `uX` reads the global `frmLoader2019_Main` (published fields of a
form the hub creates), and `Main` constructs and reads every `dmX`. Lifting sites cannot end that. So three counts are
kept apart, always: site planned, site applied and compiled, cycle actually cut.

## Options

A. **Widen the base-class whitelist, behind a switch.** Same recipe as 1.44 (`TXBase` in a leaf, `New<TX>Ptr`,
   `FX: TXBase`); only the admitted shapes grow. Soundness argued per shape below, proved by real writes with the dcc gate.

B. **One hand-written shared ancestor** (`TFolderDMBase` with `Configure`, `LoadData`, `GFLDRID`), the 12 modules
   deriving from it. The best final code: the 12 are identical in shape. Not mechanical: the tool would have to prove 12
   signatures equal and merge them, and it removes a duplication nobody asked to remove. Good for the owner by hand.

C. **`I<Class>Surface` interface instead of a base class** (fabcyc row 6). Leaves the ancestor of each data module
   alone, so the form designer sees no new class. Costs: `GFLDRID` is a field and needs a new property with a setter, a holder must never `Free` through the interface
   (`TComponent` refcounting no-ops, `Free` needs a cast back), every consumer line is rewritten. More edits for the same edges.

D. **Attack the hub** (fabcyc row 18): a `global hand-over` for `dmX` and an interface of 64 getters over the form:
   1671 refs across 77 units. The only route to actually cutting the cycle; XL, and a design smell as a mechanical
   rewrite. Not this phase.

## Chosen: A, as flag `--ctor-wide` on `cycles --plan` / `--fix`

Why: it lifts the sites at the smallest change of the recipe; B and D stay open afterwards (B can replace the 12 bases
by hand at any time); default behaviour does not move, so every existing guard reads the same.

The whitelist the flag adds, each with why it cannot change what the program does:

1. **A store to a field pulled into the base class** (`FDM_X.GFLDRID := id`). The field moves up, it is the same memory
   in the same object. A public field stays public in the base class (1.44 always emits `protected`).
2. **A dotted unit name in a uses clause** beside a slot of the same name: not a use of the slot.
3. **An `override` stays in the class, unpulled.** The base class inherits the same virtual from the same parent, so
   a call through the base class dispatches to the class's body. No hoist is needed, simpler than fabcyc case 10.
   Only a bare `override`; `override; overload` and the like keep refusing. A protected virtual called from outside fails the
   gate; it cannot compile into something else.
4. **`L.Add(TX.Create(..))`** with L a list field that switches: T is the base class on both sides.
5. **`L[i].M` and `S.M`**, M not declared by the class itself and not stored to: the base class inherits it from the same parent, same object, same member. A name the base class
   does not have fails the gate. `W.Finished` and `FWorkers[I].Finished` on Loader.
6. **`L.OwnsObjects`**: names no element type. **`var S: TX := L[i]`** as a whole statement: S is a slot that switches (`Main:2194`).
7. **A name in a multi-line comment** is not a use (`CodeOf` instead of `CodePart`, as B11 did for rewriting).
7a. **The `.dproj` line of a new leaf** goes after the close of a `<DCCReference>` with children, self-closed.

The flag also adds one refusal the 1.44 path does not make:

8. **A pulled field in the published section is refused.** A `.dfm` streams into it, `FieldAddress` looks on the class
   and the compiler cannot see it break. The 12 `TdmX` publish about 15 fields each; none of those is used through the slot,
   so none is pulled.

Stays refused with the flag: a library property written through the slot, a temporary, `L.Extract`, `L.First`, as the guard shows.

Consequence for the ancestor of a data module: `TdmX = class(TdmXBase)`, `TdmXBase = class(TDataModule)`, no `.dfm` of its own.
At run time `InitInheritedComponent` walks the chain and takes no resource for the base: proved by the guard, whose
`OnCreate` set in the `.dfm` prints the same bytes after the apply.

## Assumptions the owner can reverse

* **The flag stays OFF.** Promoting items 1, 2, 4-7 to the default is a later decision; item 2 and item 7 are false refusals
  that could be fixed for everybody. I kept them behind the flag because the brief says no default behaviour changes.
* **The form designer on a data module with a new base class is unproved: live proof owed.** I expect the IDE to want the ancestor
  known at design time. If it refuses to open `uPPSET.dfm`, option C or B is the answer for data modules, and the `TdmX`
  lift should stay out of the owner's tree. This is the one reason I would not apply it to the real Loader today.
* **`ClassParent` of `TdmX` changes**, and a 13-file `*.Untangle.pas` leaf per class is what the recipe emits. 14 new
  units in a project for no cut cycle is a real cost; the owner may prefer B for the 12.
* The run-time proof on Loader itself is not possible here (BDE + the Firebird data). Loader gets the compile gate; the
  behaviour proof is the fixture's byte-compare.

## Not in this phase

Fabcyc case 7 (metaclass values), `TX.ClassMethod`, `Application.CreateForm(TX, V)`, any hub edge, the `.dsk` and the IDE.

## Measured result

Real write on a scratch copy of the project (`cycles --fix --apply --ctor-wide --platform win32 --cycle 1`, the dcc gate, then
an independent `msbuild /t:Rebuild`), 2026-11-06 21:39, engine built from this branch, library = a copy of library-Win32:

| Count | of 14 | Note |
|---|---|---|
| site planned | 14 | 0 of 14 without the flag, same engine, same tree |
| site applied and compiled | 14 | 31 files written, 14 new leaves; gate ok, rebuild 835702 lines 0 errors, `Verified: the re-indexed cycles output matches the prediction` |
| cycle actually cut | 0 | still 1 group |

What the 14 did buy, measured: the group goes from 78 units to 76 (`Loader2025.FolderProcessor` and `Loader2025.FolderWorker` leave it),
and `cycles --f2047` reports no interface-only cycle. The other 76 stay on the hub's implementation edges, as fabcyc row 18 said.

Honest limits: Loader was compiled, not run (BDE and its data); the run-time proof is the fixture, byte-identical stdout through the
`.dfm`. The form designer on `TdmXBase` is not tried (live proof owed). The copy's `.dproj` had the three build edits at the top.

Found on the way, kept out of the default per the brief: the `.dproj` line for a new leaf landed INSIDE a multi-line `<DCCReference>` (any form or data
module unit), which left an unparsable project: the gate caught it and rolled back. Behind the flag the line closes itself and goes after the element.
`--unit` does not accept a dotted unit (`--part all` iterates by `--unit`, so it fails on Loader's first dotted stem): not fixed here, reported.
