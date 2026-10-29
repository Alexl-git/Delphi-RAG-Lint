# cycle-lab -- the circular-uses demo, extended with the cases drag-lint cannot fix alone

Base: `circular-demo` (4-unit interface cycle, routine-call cycle, member-access cycle; all three
are fixed mechanically). Added: ten small Lab* cases from the refusal list in
`docs/superpowers/plans/2026-10-25-cycles-fix-refusal-recipes.md` section 3, plus `illegal\`
(a project that does not compile: F2047). Original `circular-demo` is untouched.

Engine: shipped 1.36.0-alpha (gaps-stage2 build), run from `engine\`. `run-lab.sh` replays everything
into `out\`. Baseline program output: `baseline-run.txt` (identical after the DL fixes: `after-run.txt`).

## Cases, expected drag-lint behaviour, expected manual step (all observed)

| Case (units) | Shape | `cycles --fix` | Manual step |
|---|---|---|---|
| Demo group (DemoLogger..DemoSession) | globals + enums across 4 units | auto (Part A): 3 `*.Untangle` leaf units | none; Part B left (legal impl-only cycle) |
| DemoUIConnect/GagePort, DemoBlueprint/ControlPlan | member access / routine call | auto | none |
| LabInit (Consumer/Sink) | routine called from an `initialization` section | auto Part A (impl-only cycle left); Part B refuses `init-order` | optional: leave it (legal) |
| LabExc (Host/Widget) | `as` cast + `except on EInvalidCast` | auto Part A (impl-only left) | optional; Part B would change the exception class (`exception-semantics`) |
| LabVar (Host/Widget) | `var` parameter of the other unit's class | refused `blocked-symbol` (class used as `TX.Create`) | move the class pair into one unit, or stop naming the class in an interface |
| LabCtor (Owner/Child) | owner creates child, child casts owner | refused `blocked-symbol` (`TLabCtorChild.` construction) | child holds `TObject`/interface; or merge units |
| LabRc (Host/Widget) | `TInterfacedObject` descendant | refused `blocked-symbol` (+`signature-in-cycle`) | merge, or hand over an interface (`ref-counted`) |
| LabCls (Registry/Widget) | `class of` type in a signature | refused `blocked-symbol` (classref cannot move) | declare the metaclass in a leaf unit that both use |
| LabDir (A/B) | interface `uses` entry inside `{$IFDEF}`, entry unused | refused `directive` | delete the guarded entry (unused) |
| LabGuard (A/B) | same, entry used by a class field type | refused `directive` / class bodies | restructure by hand; both branches must stay consistent |
| LabInc (A/B) | `uses {$I file.inc}` | NOT DETECTED: index parse error on LabIncA, no cycle line | none seen by DL; known blind spot (`uses-in-include`) |
| `illegal\` IllOrders/IllCustomers | interface loop, F2047 | `cycles --f2047` names both edges and symbols; `--fix` dry run says "mechanical" but `--apply` rolls back (compile-error F2047) | merge the two classes into one unit (forward `TIllOrder = class;`) |

## Recorded results (this run)
Index 32 files. 10 groups before; 7 after DL's five auto fixes (see `out\09-cycles-after.txt`);
the build is 0 errors and the program output is byte-identical. `uses-fix` found nothing more to move.
Remaining interface-coupled: LabVar, LabDir, LabGuard, LabCtor, LabRc, LabCls (+ LabInc unseen).
Haiku run (playbook text only): see `REPORT.md`.

Folder note: this copy holds the sources BEFORE any fix. To replay, copy it to a scratch folder, put a
drag-lint engine in `engine\`, and run `bash run-lab.sh`. `results\` keeps the key outputs
(paths shortened to the scratch location of the run).
