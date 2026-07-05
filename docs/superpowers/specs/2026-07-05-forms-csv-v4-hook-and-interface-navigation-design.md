# forms-csv v4: interface-dispatch + hook-registration navigation (Design)

Date: 2026-07-05
Status: approved (user, in-session)
Scope: `src/forms/DRagLint.FormsMap.pas` navigation edge-building. Bumps
`FORMS_CSV_ALGORITHM` to `'4'`. No index-schema change.

## Problem

forms-csv reports a family of plan-editor forms as `(no path from MAIN)` even
though a user can reach them: `frmControlPlan2` has a **Plan** button (with a
slider that selects which plan to edit); clicking it calls `APlan.EditForm`,
and each plan type opens its own editor form. In the CSV these show up as dead
or orphaned:

```
52,Z14SLCT,Z14slctFrm,275,(no path from MAIN),,DEAD FORM - no callers found
53,z19Slct,Z19slctFrm,515,(no path from MAIN),uPlanEditForms.ShowPlanEditor,
```

`frmControlPlan2` itself IS reachable from MAIN (existing CSV):
`frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4 ->
'Exit to Control Plan 2' -> frmControlPlan2`. The break is entirely in the
last hop, `frmControlPlan2 -> <plan editor>`.

## Root cause: three layered factors (all real, all required)

Traced against the live ORM3 index 2026-07-05.

### Layer 0 -- database scope (the dominant factor)

The forms-csv that produced the report ran against the per-project CLIENT db
`C:\Projects\DB\ORM3\CLIENT\Micronite2027.sqlite`, which indexes only
`CLIENT\`. The launch sites live in `COMMON\OBJECTS\uPLANLIST.PAS`
(`TANSIZ14Plan.EditForm` at line 2529 does `TZ14slctFrm.Create(Self)`), which
that db does NOT contain (`query --name EditForm` -> 0 matches; the class
bodies are absent). No navigation algorithm can bridge a launch site that is
not in the index. The full-tree db `C:\Projects\DB\ORM3\drag-lint.sqlite` DOES
contain them (`EditForm` resolves to 19 `TxxxPlan.EditForm` methods +
`iPLANLIST.ImcPLANLIST.EditForm`).

This ties to the known backlog item "IDE menu passes the per-project db =
enhancement candidate." v4 is only meaningful against a COMMON-inclusive db.

### Layer 1 -- interface-method dispatch (fixes the Z14-class, the majority)

The Plan button is a **polymorphic dispatch hub**. The slider selects a plan
instance; the button calls `APlan.EditForm` where `APlan` is an *interface*
reference (`iPLANLIST`). `EditForm` has **19 concrete implementations** --
`TANSIZ14Plan.EditForm`, `TSB100Plan.EditForm`, `TEWorksPlan.EditForm`, ...
each of which launches a different editor form. The launch (`TZ14slctFrm.Create`)
lives in the *concrete class* body; the call site (`frmControlPlan2`) references
the *interface* method. The existing `FindNearestFormCaller` walks
`refs WHERE name_text = 'EditForm'` and does not bridge
interface-method <-> implementing-class-method, so the walk from the concrete
body up to the calling form is severed. Bridging this one interface method
resolves the whole 19-form family in one shot.

### Layer 2 -- procedure-variable hook (fixes the Z19 sub-case)

A few plan types route through a runtime-assigned function-pointer hook rather
than a direct create. `TANSIZ19Plan.EditForm` calls `PlanEditFormHook()` (a
proc-variable field on `uPLANLIST`), and `uPlanEditForms.pas:123` registers
`uPLANLIST.PlanEditFormHook := ShowPlanEditor;` (a standalone function that does
`TZ19slctFrm.Create`). There is NO static call edge from `EditForm` to
`ShowPlanEditor` -- the link exists only at the `:=` registration line. Static
call-graph fan-in can never follow a proc-variable indirection; the binding
must be recovered from the registration site.

(`Z14` is deliberately NOT hooked -- `uPLANLIST.PAS:1024` comment: its
`EditForm` "still drives this form inline"; so Z14 is Layer-1-only, Z19 is
Layer-1 + Layer-2.)

## Design

### D0. Database scope (guidance + guardrail, not an algorithm change)

- Document that forms-csv must run against a db whose scan root includes the
  form-launch bodies. For ORM3, that is the full-tree db, not CLIENT-only.
- Guardrail: when the resolved root form's editor-dispatch method
  (`EditForm`-class interface method) has zero indexed implementations, emit a
  one-line note to stderr: "forms-csv: <N> interface dispatch(es) unresolved --
  db may not include COMMON; run against the full-tree index." So a scope
  problem announces itself instead of silently printing "(no path)".
- The IDE-menu-passes-full-db change stays a separate plugin backlog item
  (invocation, not FormsMap algorithm). Referenced here, delivered elsewhere.

### D1. Interface-method fan-in bridge (the core of v4)

**Backward-chain, fully index-queryable -- NO text-scan needed** (confirmed
against the live ORM3 index 2026-07-05). `FindNearestFormCaller` already walks
`refs WHERE name_text = M` by method name. The bridge adds interface awareness
to that walk:

When the walk is looking for callers of a method `M` defined on a concrete class
`C` and finds none directly, ALSO look for callers of `M` reached through an
interface `C` implements. The chain, all from existing tables:

1. Launch body found inside concrete `C.M` (e.g. `TANSIZ14Plan.EditForm` does
   `TZ14slctFrm.Create`). The launch ref is already enclosing-attributed to
   `EditForm` via `enclosing_symbol_id` (v0.82).
2. `C`'s heritage from `type_ancestors` (VERIFIED present): `TANSIZ14Plan` ->
   `[TmcPLANLIST (class, ord 0), IANSIZ14Plan (interface, ord 1)]`.
3. Find `call` refs where `name_text = M` (`EditForm`): each carries its
   `enclosing_symbol_id`. At `ControlPlan2.pas:1451` `APlan.EditForm`, the ref
   is `EditForm | enclosing = btnSelFinalPlanClick` -- a FORM method with a DFM
   button binding. (VERIFIED: `dump-refs` shows `EditForm|1451|...|btnSelFinalPlanClick`.)
4. Resolve that enclosing form method -> its owning form (`frmControlPlan2`) ->
   MAIN via the normal edge graph, and its DFM caption via `CaptionForHandler`.

- **Matching is by method NAME across the interface family**, not by resolving
  the exact receiver type. The `refs` row for `EditForm` records only the bare
  method name + line + enclosing symbol; it does NOT record that `APlan`'s type
  is `iPLANLIST` (see the receiver-type gap in D5). Name-based matching is
  CORRECT here: every `TxxxPlan.EditForm` is reachable via the same Plan button,
  so attributing all of them to `frmControlPlan2 -> 'Plan'` is the true nav.
- `type_ancestors` lists the per-plan interface (`IANSIZ14Plan`) while call
  sites use the base interface (`ImcPLANLIST.EditForm`); since matching is by
  method name (`EditForm`), the specific interface identity is not required --
  any indexed `EditForm` call site whose enclosing symbol is a navigable form is
  a valid caller. (If false positives arise from an unrelated `EditForm`, D5's
  receiver-type index would disambiguate; not needed for v4 correctness here.)
- Bound the fan-in with the existing `AVisited` set (already present) so the
  1->many interface dispatch cannot loop or explode; each concrete
  implementation resolves independently to its own editor form.
- Result: every `TxxxPlan.EditForm` that directly launches an editor form
  (the ~18 direct-create plan classes incl. Z14) attributes its edge to
  `frmControlPlan2` with the `'Plan'` caption.

### D2. Hook-registration synthetic edges (Layer 2, on top of D1)

**Detection is a TEXT-SCAN of the source, NOT a refs query** (confirmed against
the live index 2026-07-05). At the registration line
`uPLANLIST.PlanEditFormHook := ShowPlanEditor;` (uPlanEditForms.pas:123, inside
an `initialization` block), the ONLY ref the parser emits is `uPLANLIST` (the
unit) -- there is NO ref for the hook field `PlanEditFormHook` and NO ref for
the RHS routine `ShowPlanEditor`. So the registration is invisible to any
`refs`-based query (`find-callers ShowPlanEditor` returns 0; the function is
`[impl-only]`). This is WHY the current algorithm cannot see the hook.

Text-scan pre-pass (mirrors the existing `IsLaunchLine`/`FindEnclosingImpl`
source-line scanning already in `BuildEdges`): for each already-known
form-launching routine `R` (routines whose body constructs a form -- we compute
these during the normal launch-site pass), scan `.pas` sources for an assignment
line of shape `<HookField> := R` (optionally unit-qualified: `Unit.HookField := R`).
Record `R -> HookField` (`ShowPlanEditor -> PlanEditFormHook`). Only routines
already identified as form-launchers are candidates, which bounds the scan and
avoids matching ordinary assignments.

(D5 proposes indexing proc-variable assignments so this scan becomes a clean
`refs` query in a later milestone; v4 uses the text-scan.)

When the D1 fan-in dead-ends on a handler routine `R` (a form-launching routine
with no direct callers -- because its only reference is the registration), look
up `R` in the hook map: if `R` is registered to hook field `H`, continue the
fan-in from `H`'s INVOCATION sites (`PlanEditFormHook()` inside
`TANSIZ19Plan.EditForm`) -- which then rejoins the D1 interface bridge back to
`frmControlPlan2`.

- Detection is the text-scan above; no schema change in v4.
- Only ONE hook hop is bridged in v4 (see Out of scope).

### D3. Hop caption (name the UI trigger, not the mechanism)

When the fan-in lands on a form `F` (`frmControlPlan2`) whose method `Mcall`
invokes the dispatch/hook, reuse the existing `CaptionForHandler(F, Mcall)` to
recover the DFM event-binding caption -- yielding the button/slider label so the
path reads:

```
... -> frmControlPlan2 -> 'Plan' -> Z19slctFrm
```

Fall back to `(via EditForm)` / `(via <hook> hook)` only when no DFM caption
resolves (mirrors the existing `if Cap = '' then Cap := '(via ' + Rout + ')'`
convention). This is the same caption path normal form edges already use,
applied at the dispatch-invoking form -- near-zero new machinery.

### D5. Indexer enhancements to eliminate/reduce text-scans (future, not v4)

v4 makes Layer 1 fully index-driven but Layer 2 (hook detection) falls back to a
text-scan because the current index does not capture two source facts we can
plainly see. Adding them would let navigation -- and any other consumer -- query
clean relationships instead of scanning `.pas` bytes. These are proposed as a
SEPARATE indexer milestone (schema-bumping), not part of v4:

1. **Receiver type on `call` refs (`receiver_type_symbol_id`).** Today a `call`
   ref records only the bare method name + line + enclosing symbol (VERIFIED:
   `refs` columns are `symbol_id, file_id, kind, name_text, start/end line/col,
   enclosing_symbol_id`). At `APlan.EditForm` the index knows `EditForm` is
   called and that `APlan` is on the same line, but NOT that `APlan`'s declared
   type is the interface `iPLANLIST`. If the parser resolved the receiver's
   declared type (from the local/param/field declaration in scope) and stamped
   its symbol id on the call ref, polymorphic dispatch would resolve exactly:
   "who calls `iPLANLIST.EditForm`" becomes a precise query, no name-only
   matching, no false-positive risk from unrelated `EditForm` methods. This is
   the single highest-value addition -- it turns interface/virtual dispatch from
   a heuristic into indexed data and benefits find-callers, impact, and graphing
   too.

2. **Proc-variable assignment refs (`kind='proc-assign'`).** At
   `PlanEditFormHook := ShowPlanEditor` the parser currently emits only a ref to
   the unit. Emitting a ref that links the LHS hook field to the RHS routine
   (an "address-of-routine assignment") would replace D2's text-scan with a
   `refs` query and generalize to every callback/hook registration in the code
   base (EnsureJobListHook, PlanEditFormHook, and any future ones), not just the
   ones forms-csv happens to scan for.

3. **Interface-implementation method edges (`impl_of`).** `type_ancestors`
   already links a class to its interfaces; a per-METHOD link ("`TANSIZ14Plan.
   EditForm` implements `IANSIZ14Plan.EditForm`") would let consumers walk
   interface->all-implementations and implementation->interface directly, rather
   than matching by method name. Complements #1: #1 resolves the call's target
   interface, #3 expands that interface to its concrete bodies.

Rationale (user, 2026-07-05): we can SEE in the source that a specific interface
object's specific method is called, so the physical incarnations are a bounded,
resolvable set -- and tracing backward from a form we already reach the calling
method and object. Where the index doesn't yet record that, we should add it, so
polymorphic navigation stops depending on text search. v4 ships the navigation
win now (Layer 1 via existing data + Layer 2 via a bounded scan); this indexer
milestone removes the scan and sharpens dispatch resolution afterward.

## Out of scope (documented future todos)

- **Multi-hook / multi-hop chains.** v4 bridges ONE interface-dispatch hop and
  ONE proc-variable hook hop. If more than one proc-variable indirection sits
  between MAIN and a form, it stays "(no path)". The `AVisited` set makes this
  safe (no loop), just unresolved. Add a MISSING-FEATURES / backlog note.
- **IDE menu -> full-tree db.** The plugin invocation change that makes the
  forms-csv menu pass a COMMON-inclusive db (Layer 0) is a separate plugin
  backlog item.
- **Slider-driven plan-type enumeration.** v4 attributes ALL 19 editor forms to
  the single `frmControlPlan2 -> 'Plan'` hop. It does NOT try to distinguish
  which slider position selects which plan type (that mapping is runtime data).
  Every plan editor gets the same `'Plan'` caption, which is correct: the button
  is the reachable UI affordance.

## Testing

- **Fixture (formsmap):** add a hook + interface-dispatch pattern mirroring the
  real one: an interface `IThingPlan` with method `EditThing`; two concrete
  classes -- `TDirectPlan.EditThing` that does `TfrmDirect.Create` (Layer-1
  path) and `THookPlan.EditThing` that calls `ThingHook()` where
  `ThingHook := ShowThing` and `ShowThing` does `TfrmHooked.Create` (Layer-2
  path); a root-reachable form `frmRoot` whose button-click method calls
  `APlan.EditThing` through the interface. Assert:
  - `frmRoot -> 'ButtonCap' -> frmDirect` (D1 + D3 caption)
  - `frmRoot -> 'ButtonCap' -> frmHooked` (D1 + D2 + D3)
  - a `(via ...)` fallback variant where the button has no DFM caption.
- **Real-DB smoke:** run forms-csv against the full ORM3 db; assert that
  `Z19slctFrm` and `Z14slctFrm` (and the broader `TxxxPlan.EditForm` family)
  render a `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>` path instead
  of "(no path from MAIN)". Also assert the D0 stderr note fires when run
  against the CLIENT-only db.
- Existing 14 formsmap assertions must stay green (v4 is additive; forms with
  plain edges are unaffected).

## Files

- `src/forms/DRagLint.FormsMap.pas` -- `FindNearestFormCaller` (D1 bridge),
  `BuildEdges` pre-pass (D2 hook map), `ProcessSite` (D2 dead-end -> hook
  continuation), caption reuse (D3), `FORMS_CSV_ALGORITHM` -> `'4'`, D0 stderr
  guardrail note.
- `tests/autotest/run_formsmap.ps1` + `tests/fixtures/formsmap/` -- new
  interface + hook fixtures and assertions.

## After this milestone

- **Indexer milestone (D5):** receiver-type on call refs + proc-assign refs +
  interface-impl method edges -- removes Layer 2's text-scan and makes
  polymorphic dispatch precise. Its own brainstorm -> spec -> plan (schema bump).
- Backlog: IDE forms-csv menu -> full-tree db (Layer 0 delivery); multi-hop hook
  chains; slider->plan-type mapping (if ever wanted).
