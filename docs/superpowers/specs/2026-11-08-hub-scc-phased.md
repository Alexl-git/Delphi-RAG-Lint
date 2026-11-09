# Hub-shaped SCC (fabcyc case 18), phased -- wave 148, lane HS

Date 2026-11-08. Branch lane/148-HS (base lane/147-int 1e426a40f). Engine for every number below:
C:\TEMP\claude\lanes\148\HS\engine\drag-lint.exe = 1.46.0-alpha, on a COPY of
C:\Projects\Loader2019\_D-RAG\Loader2025.sqlite (35 MB, taken 17:44, before the re-parse window);
library C:\Projects\.drag-lint\library-Win32.sqlite read-only. Queries: `sql --db <copy>` (recursive CTEs over
unit_uses / refs / symbols / ref_receivers), `cycles --edges --format json`, `cycles --causes --format json`.
Earlier evidence: lanes\143\fabcyc\REPORT.md row 18, lanes\146\r4\REPORT.md + spec 2026-11-06-ctorinv-loader.md,
lanes\148\CY\REPORT.md (timing) -- all verified against the copy, not trusted.

## 1. The problem, measured

One group, 78 units, 239 uses edges inside it: 224 implementation, 15 interface.

| unit | out (impl/intf) | in (impl/intf) | role |
|---|---|---|---|
| Loader2019.Main | 77 (75/2) | 76 (76/0) | THE hub: creates every data module / form, read by every one |
| uFolderCheck | 1 (-> Main) | 74 | second hub-in; `dmFolderCheck` global read by 74 units |
| Loader2025.FolderProcessor | 13 (1/12) | 2 | source of 12 of the 15 interface edges |
| every other unit | 2 | 2 | spoke: `uses Main, uFolderCheck` in the implementation |

**Articulation (new, decisive):** removing Loader2019.Main leaves 0 cyclic units among the other 77 (their 86
mutual edges are acyclic). Cutting ONLY the 77 hub->spoke edges breaks the group; cutting ONLY the 76 spoke->hub
edges breaks it too (recursive-CTE reachability, both directions: 0 nodes reach themselves). uFolderCheck is NOT
needed for any cycle (without Main it is a leaf-ish hub-in). Every cycle of the group passes through Main, in
both directions. The group is a star, not a tangle.

**Weights** (refs crossing a uses edge, consumer -> declaring unit): spoke->hub 1886 (per spoke 0..139);
hub->spoke 574 (1..84). 35 of the 239 edges carry 0 refs (34 `uses uFolderCheck`, 1 `uses Loader2019.Main`):
dead uses, removable by the existing unused-unit rule, but cycle-neutral on their own.

**spoke->hub surface** (what 75 units take from the hub): ONE global, `frmLoader2019_Main`, 1665 reads,
0 writes, 1 bare read (passed as a value), 0 `with` (grep over Loader2019\*.pas: 0 sites), 1821 member
accesses through it, 22 distinct member names:

| group | members (refs / units) |
|---|---|
| 13 DFM components | edtCurrent TcxTextEdit 322/63, prbRecords TcxProgressBar 269/75, IBD TFDConnection 228/75, lstSource TcxListBox 201/75, cxlDone TcxLabel 75/75, cxlTotal 64/63, lstDest 63/63, memFolderCount TFDTable 45/1 (+ memFolderCountRecords 21, memFolderCountTable 11), prbFolders 7/2, cxlFoldersDone 2, cxlFoldersTotal 1, lblTimeElapsed 1 |
| 4 plain public fields | NRECS integer 68/62 (+ `NRecs` 1), FBatchActive Boolean 65/63, StartTime TDateTime 1, MAXFOLDERCOUNT integer 1 |
| 2 methods | LogError(const pError; pFolder: Int64 = 0; ...) 300/74, ShouldUpdateUI: Boolean 63/63 |
| 1 inherited | Invalidate (TControl) 12/6 |

plus 10 free routines of the hub unit: 221 calls (VerifyFields 75/75, StrZ 48/8, Set1ByteArrayDML 48/8,
DateTimeToSQLTimeStamp 43/18, 6 others 1-2). 9 of the 10 bodies touch no hub member; VerifyFields does (2 refs).

Index fact found on the way (resolver, NOT a cycles item): all 1821 member accesses through the global are
UNRESOLVED (`refs.symbol_id IS NULL`, `member_accesses` 0 rows for the class) although TfrmLoader2019_Main
declares 259 fields + 39 methods in the same unit. Member access through a global typed variable of a
same-unit class is not resolved. fabcyc's "64 fields / 662 accesses" was a different count of the same
thing; by name it is 22 / 1821. Phase 5 below.

**hub->spoke surface** (what the hub takes from each spoke): `TdmX`/`TfrmX` class read (76 constructions),
`dmX` var write (75), var reads (181), method calls (143, `LoadData` on most), plus FolderWorker properties
(51/3 members) and uFolderCheck fields (39/4). 77 distinct surfaces, one per spoke.

**What the engine does today on this group:** plain `cycles` 0 s. `cycles --causes --format json` 223 s --
its `fix{}` block runs the planner: `available:false, part:a, reason: ctor-inversion-surface (Loader2025.FolderWorker.pas:216 TFolderProcessor ...)`.
`cycles --plan --ctor-wide` 381 s (CY, same copy: BuildPlan 69 s, RenderPlan 305 s = RenderPartB planning
Part B over the 78-unit group); every spoke->hub edge prints "not mechanical: `frmLoader2019_Main` (var): it
needs `TfrmLoader2019_Main` (class), which cannot move: its method bodies use ...". The planner tries to MOVE
the hub class (Part A) or invert the 77 constructions (--ctor-wide: 14 sites applied, 0 cycles cut, lane
146 r4). Neither route can finish: the first is impossible, the second is 77 surfaces wide. Nothing times
out; it gives up at Part A and spends 5 minutes rendering a refusal.

## 2. Why "impossible" was the wrong word

fabcyc row 18 and the r4 spec are right that a BASE CLASS cannot carry DFM-streamed published fields (the
designer re-creates them in the form class; streaming fills the wrong one). That route stays closed.

They dismissed the INTERFACE route as "64 getters, 1671 rewritten refs = a different program". Measured:
22 names, and an interface with PROPERTIES keeps every consumer line textually identical except the
receiver identifier: `frmLoader2019_Main.edtCurrent.Text := S` becomes `MainHub.edtCurrent.Text := S`.
No component moves, no DFM edit, the form class gains `, IMainHub` in its heritage plus one getter per
property (and a setter for the 4 writable plain fields). This is the planner's existing R2
`I<Class>Surface` recipe (CycleEdge TMemberSurface / TMemberPlan) applied to a GLOBAL INSTANCE of a class
instead of a constructed one -- a new way of OBTAINING the surface, not a new way of using it.

Soundness of the hand-over (all checkable at the compile gate + by the `cycles` prediction):
* `TComponent` implements IInterface without reference counting (`_AddRef`/`_Release` return -1 when no
  VCLComObject): `var MainHub: IMainHub` holds no count; the owner (Application) frees the form as today.
* `MainHub := Self` in `AfterConstruction` runs BEFORE `Application.CreateForm` assigns `frmLoader2019_Main`
  (the Reference is set after the constructor returns): availability is a superset of today's.
  `MainHub := nil` in `BeforeDestruction`: today the global is never nilled; strictly safer.
* No GUID needed for `MainHub := Self` (only for `as` / Supports). An interface method may be satisfied by an
  inherited public method (`Invalidate`); the gate proves it.
* Property types are library types (cx*, FireDAC, System): the surface unit uses library units only -- no
  project edge, so it is a leaf by construction.
* Writes to plain fields -> `read GetX write SetX`; writes to a component FIELD itself
  (`frmLoader2019_Main.edtCurrent := nil`) -> refuse `member-write` (0 measured). A write to the global
  (`frmLoader2019_Main := ...`) -> refuse (0 measured). `with frmLoader2019_Main do` -> existing `with-member`
  refusal (0 measured). A bare use (passed as TForm / Owner / `Assigned()`) -> phase 4 (`AsForm: TForm`),
  refused until then (1 measured). A member name not declared in the class or its library ancestors ->
  refuse `member-unsupported` (0 measured: 21 in the class, Invalidate in TControl).

## 3. Options

| | route | work | measured outcome |
|---|---|---|---|
| A | cut hub->spoke: constructor inversion + base class per spoke + var hand-over + `LoadData` pulls (r4 `--ctor-wide` extended) | 77 surfaces, each M | r4: 14/14 sites applied + compiled, 0 cycles cut; needs 63 more surfaces; XL |
| B | cut spoke->hub: ONE hub-surface interface + 9 routine moves (R1 exists) | 1 surface (22 props/methods) + R1 x 9 + VerifyFields through the surface | breaks the whole group (section 1 articulation); every site a receiver-only rewrite; L, phaseable |
| C | both | A + B | not needed: B alone breaks it |
| D | report only (hub, cut side, surface, weights) | S | the first phase of B anyway; useful on every hub-shaped project |

**Chosen: B, delivered as D first.** Reversible assumptions the owner can overturn: (1) the interface is
named `I<FormClass>Hub` in a new unit `<HubUnit>.Hub.pas` next to the hub unit; (2) the global that replaces
`frmLoader2019_Main` in the spokes is `MainHub` (`<stem>Hub`); (3) component fields are read-only
properties, plain public fields read/write; (4) the hub unit keeps its global `frmLoader2019_Main` (the .dpr
`Application.CreateForm` still needs it; nothing else is deleted); (5) hub route only when the group has
EXACTLY one articulation hub and the spoke->hub surface is one or few globals (threshold: a flag,
default <= 3 globals); more hubs = report, no plan.

## 4. Phases

Each phase ships on its own, has a guard with a positive control, and changes no default until P6.

| phase | what | files | wave | bump |
|---|---|---|---|---|
| P1 | `cycles --hub` read-only report (text + `--format json`): per group the articulation hubs (units whose removal leaves the rest acyclic), per hub in/out edges (impl/intf), ref weights per side, zero-ref edges, the spoke->hub surface by name (globals + member names + routines), hub->spoke kinds, the lighter side, and whether cutting one side alone breaks the group; `--hub` on a group with no single hub says so. 0 s class (graph + counting SQL; never runs the planner). | NEW DRagLint.Report.CycleHub.pas; CLI.pas: 1 flag line + 1 call in DoCycles text/json loop; HelpText, README, AI-USAGE, entry circular-uses-report-cycles-fix-plan.json + wiki page; guard run_cycles_hub.ps1 (fixture: hub + 3 spokes; control: a 2-unit mutual cycle = "no single hub") | 148 (no CY file; CLI.pas DoCycles region is not CY's; merge after CY) | no |
| P2 | recipe R3 "hub surface": `cycles --plan/--fix --hub-surface` (OFF): emit `<Hub>.Hub.pas` (interface with properties/methods typed from the class declaration + library ancestors), edit the hub class (heritage, getters/setters, AfterConstruction/BeforeDestruction hand-over), rewrite receivers in the spokes, uses edits, prediction; refusals of section 2. Planned ONLY when P1 finds exactly one hub; lab fixture (hub form-like class with a global + 3 spokes) through the compile gate; dry run on the Loader copy = the acceptance number (76 edges planned). | CyclePlan.pas, CycleEdge.pas, CLI.CycleFix.pas (CY's files -- after CY), HelpText/docs/entry, guard run_cyclefix_hubsurface_dcc | 149 | no |
| P3 | the 9 hub free routines by the existing R1 move into the same new leaf (today the group is refused as a whole at Part A, so R1 never runs on them); VerifyFields: body rewritten `frmLoader2019_Main.` -> `MainHub.` then moved, or kept in the hub and put on the interface (choose by the gate). One plan with P2. | CyclePlan.pas, guard extension | 149 | no |
| P4 | bare uses of the global (`AsForm: TForm` property on the interface; `Assigned(MainHub)`); `with` blocks: still refused (restructuring) | CycleEdge.pas | 149 or 150 | no |
| P5 | resolver: resolve member access through a global typed variable of a same-unit (then any) class -- 1821/1821 unresolved today; gives `member_accesses` rows for the hub, lets P2 type the surface from facts instead of names, and fixes hover/usages on `frmX.Member`. `NEXT-BUMP` (resolver constant; a reader the resolve pass depends on). | CallResolver.pas (+ whatever the member-access writer is) | 150 (after the 149 re-parse window) | YES (resolver) |
| P2b | Part B rendering speed (CY 149-CY-PERF, folded here because the hub group is the case): on Loader RenderPartB is 219 of 261 s (84 percent, CY's final profile; 305 of 381 s in the earlier run) -- PlanImplCycle evaluates every implementation edge of the 78-unit group. With P1's hub analysis available, RenderPartB (a) skips the Part B pass for a group whose hubs P1 found and prints the hub block instead, behind the same `--hub-surface` switch, and (b) independent of the switch, profiles per edge (DRAGLINT_CYCLE_TIMING=1 inside RenderPartB) before any algorithmic change; acceptance: `--plan` on the Loader copy under 60 s with the switch, byte-identical plan text without it. | CyclePlan.pas (RenderPartB, PlanImplCycle; CY's file), guard run_cycles_plan_hub_speed (fixture, timing budget) | 149 (with P2) | no |
| P6 | defaults: `--plan` prints the P1 hub block for a hub-shaped group and plans R3 instead of Part A; `--causes --format json` skips the planner when R3 applies (223 s -> seconds); `--fix` picks R3 when it is the lighter side. Flag becomes `--no-hub-surface`. | CyclePlan.pas, CLI.pas, docs | 150, after the owner has applied P2 on Loader once | no |

Not in any phase: option A beyond r4 (kept as `--ctor-wide`), a base class for DFM fields, deleting the
hub's global, uFolderCheck (not on any cycle once Main is cut; its 34 dead `uses` are the unused-unit rule).

## 5. P1 contract (built in this lane if time allows; otherwise the 149 row)

`drag-lint cycles --db <db> --hub [--format json]`, read-only, no library, no project needed.
Text per group (after the group line `cycles` prints today):
```
      hub <stem>: in <n> (<impl> impl, <intf> intf) refs <w>; out <n> (<impl> impl, <intf> intf) refs <w>;
          cutting the in-side alone breaks the group: yes|no; the out-side alone: yes|no
        spoke->hub surface: <k> symbols -- var <name> (<refs> reads in <units> units; <m> member names: <name> <refs>, ...), procedure <name> (<calls> in <units>), ...
        hub->spoke surface: <c> classes constructed, <w> vars written, <r> var reads, <m> method calls in <u> units
        lighter side: spoke->hub (1 global + 10 routines) | hub->spoke (...)
        zero-ref edges inside the group: <z>
      hubs: none (no single unit whose removal leaves the group acyclic)
```
JSON: the existing group object gains `"hubs":[{unit, in:{edges,intf,refs,breaks_alone}, out:{...},
spoke_to_hub:[{kind,name,refs,units,members:[{name,refs,units}]}], hub_to_spoke:{construction,var_write,
var_read,method_call,units}, lighter_side, zero_ref_edges}]`. Member names are counted by `refs.name_text`
of refs whose receiver (ref_receivers) is a read of the global -- the fact that is there today (P5 makes it
resolved). Guard: fixture with a hub unit H (global `GH: TH`, class with 2 fields + 1 method) and spokes S1-S3
(`uses H` in the implementation, `GH.F1`, `GH.M`), H constructs each `TSx` -> exactly one hub `h`, in 3 / out
3, breaks_alone both yes, surface var GH with 3 member names; control: units P <-> Q mutual (no hub) ->
"hubs: none"; negative control: the flag absent prints no hub line. 

## 6. Owner questions (defaults taken)

* Name of the interface/global (`IMainHub` / `MainHub`): default as above, a `--hub-name` flag can follow.
* Threshold for "hub-shaped" (one articulation unit, <= 3 globals): default; reversible in P2.
* P5 is the only bump; it is independent of P1-P4 (names carry P2) and can wait for a planned re-parse.
