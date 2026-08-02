---
title: "Forms-CSV v4: Interface-Method-Mediated Form Navigation"
date: 2026-07-05
status: draft
author: Claude
---

# Forms-CSV v4: Interface-Method-Mediated Form Navigation

## Summary

The v3 forms-csv navigation algorithm handles form→form launches and direct-routine-mediated launches (e.g., `frmGap` shown via `OpenGap` routine). It fails for interface-method-mediated launches — forms called through service/interface methods. This spec enhances the algorithm to traverse interface→implementation→caller chains, unblocking paths like `frmMAIN → frmCP2 → [iPlanList.Edit] → Z14slctFrm`.

## Problem Statement

### Current Limitation

The v3 `BuildEdges` → `FindNearestFormCaller` algorithm walks form-launch call-sites upward through the call graph to find the nearest form-class ancestor, attributing launches with a `(via <routine>)` caption. The walk uses `refs.name_text = :routine` (a bare-name search) and assumes the nearest form caller is reachable.

This fails for **interface-method launches**:

```
frmCP2.PlanButtonClick
  └─> iPlanList.Edit          ← Interface method (not a form)
       └─> Z14slctFrm.ShowModal ← Target form
```

When `FindNearestFormCaller` searches for callers of `Edit` (the interface method), it:
1. Finds ALL `Edit` calls across the codebase (ambiguous — 50+ methods named Edit).
2. Doesn't traverse the interface→implementation mapping.
3. Dead-ends when the implementation's enclosing class has no form ancestor in *its* call path.

**Result:** Z14slctFrm shows `(no path from MAIN)` even though a valid path exists through frmCP2.

### Evidence

- **Working case (v3):** `frmGap` via `OpenGap` routine — the bare-name search finds `OpenGap` uniquely, walk succeeds.
- **Broken case (v3):** `Z14slctFrm` via `iPLANLIST.Edit` — the bare-name `Edit` search is ambiguous and interface indirection breaks the walk.

## Proposed Solution

### Design Principle

When a form-launch site's **call target is an interface method** (not a form-class method), resolve the interface → all implementations, then walk upward from each implementation to find callers that are forms or form-adjacent. This "fans out" the walk to include all possible call paths through the interface.

### Algorithm (v4)

```
EnhancedFindNearestFormCaller(
  LaunchCall: TCrossRefRecord,  ← The form-launch call site
  TargetForm: string            ← The form being launched
  MaxHops: integer = 3          ← Hop limit to prevent infinite walks
): TFormNavPath
  
  EnclosingRoutine := LaunchCall.enclosing_symbol_id → routine name
  EnclosingClass := routine's enclosing class
  
  IF EnclosingClass.IsForm THEN
    RETURN FormPath(EnclosingClass, TargetForm, via: EnclosingRoutine)  ← Direct form call
  END
  
  ← EnclosingClass is NOT a form; walk upward via callers
  ← But if EnclosingClass is also an interface, resolve to implementations first
  
  IF EnclosingClass.IsInterface THEN
    ← Query: find all classes implementing EnclosingClass
    Implementations := FindImplementations(EnclosingClass)
  ELSE
    ← If it's a normal (non-form) class, just walk its callers
    Implementations := [EnclosingClass]
  END
  
  ← Walk callers of each implementation up to MaxHops hops
  FOR EACH Implementation IN Implementations DO
    FormCaller := WalkCallersUntilForm(Implementation, MaxHops)
    IF FormCaller.IsFound THEN
      ← Construct path: FormCaller → [hops] → Implementation → EnclosingRoutine → TargetForm
      RETURN FormPath(FormCaller, TargetForm, via: HopCaption(EnclosingRoutine, Implementation))
    END
  END
  
  ← No form caller found within MaxHops
  RETURN NoPathFound(TargetForm)

WalkCallersUntilForm(
  StartSymbol: string,     ← Class or routine name
  HopsRemaining: integer
): TFormCallerOrNone
  
  WHILE HopsRemaining > 0 DO
    Callers := QueryIndex("refs WHERE called_symbol = StartSymbol").enclosing_symbol_id
    
    FOR EACH Caller IN Callers DO
      CallerClass := Caller.enclosing_class
      IF CallerClass.IsForm THEN
        RETURN (Found: Caller, Class: CallerClass)
      ELSE
        ← Recursive hop: walk this non-form caller's callers
        Result := WalkCallersUntilForm(Caller, HopsRemaining - 1)
        IF Result.IsFound THEN
          RETURN Result
        END
      END
    END
    
    BREAK  ← No caller found at this hop
  END
  
  RETURN NotFound
```

### Key Design Choices

#### 1. **Hop Limit (MaxHops = 3)**
   - Walk **up to 3 layers** of callers before giving up.
   - Rationale: most service-method calls are 1–2 hops from a form (method → form method → form click handler). 3 is a safe upper bound that prevents deep ambiguous walks but catches real paths.
   - Tunable post-ship if evidence suggests a different limit.

#### 2. **Interface Resolution**
   - When the direct caller's enclosing class is an interface, resolve to **all implementing classes**.
   - If an interface method has multiple implementations, walk each implementation's callers separately.
   - Rationale: ensures we don't miss a valid path just because the interface has multiple implementations.

#### 3. **Tie-Breaking: Multiple Forms**
   - If multiple form callers are reachable, pick the **first found** (by index query order, typically symbol-ID order).
   - Rationale: typically there's only one form caller; multiple callers are ambiguous but rare. A deterministic rule (first) is better than silence.
   - Future: if evidence shows ambiguous multi-form paths are common, add a comment in the CSV noting the ambiguity.

#### 4. **Caption Format**
   - Single-hop: `(via RoutineName)`  ← existing v3 format, e.g., `(via OpenGap)`
   - Multi-hop interface case: `(via iPlanList.Edit from Implementation.Method)`  ← shows the interface method and the form-adjacent caller
   - Rationale: users need to understand the path, especially when it crosses an interface boundary.

#### 5. **No Change to v3 Direct Cases**
   - Direct form→form launches and direct-routine launches remain unchanged.
   - The enhancement only activates when the initial walk fails to find a direct form caller.
   - Rationale: preserves v3 behavior and test cases; new code path is orthogonal.

## Implementation Plan

### Phase 1: Index Enhancement (if needed)
- Verify `refs.enclosing_symbol_id` and `type_ancestors` are up-to-date and queryable.
- Add a test query: `SELECT * FROM refs WHERE called_symbol = 'Edit' AND enclosing_symbol_id LIKE '%.iPlanList%'` — should resolve to implementations of iPlanList.
- **Status:** v0.82 added `enclosing_symbol_id`; v0.86 keeps schema v13. No reindex required if the data is already there. Spot-check that interface implementations are correctly attributed.

### Phase 2: Algorithm Implementation
- Extend `FindNearestFormCaller` (FormsMap.pas:692) with interface-resolution logic.
- Add helpers:
  - `FindImplementations(InterfaceName: string): TStringList` — query `type_ancestors` to find classes implementing the interface.
  - `WalkCallersUntilForm(StartSymbol: string; MaxHops: integer): TFormCaller` — recursive upward walk.
- Preserve v3 behavior: if the new walk finds nothing, fall back to the old bare-name walk (or return NoPath).

### Phase 3: Testing
- **Fixture:** `iPlanList.Edit` and implementations (`TPlanList.Edit`).
- **Forms:** Z14slctFrm, Z19slctFrm (both launched via `iPlanList.Edit`).
- **Test case:** forms-csv should show Z14/Z19 with a valid path like `frmMAIN → frmCP2 → (via iPlanList.Edit from TPlanList.Edit) → Z14slctFrm`.
- **Regression:** existing v3 cases (`frmGap`, other direct and routine-mediated launches) should remain unchanged.

## Edge Cases & Mitigations

| Case | Behavior | Mitigation |
|---|---|---|
| Interface has 0 implementations | WalkCallersUntilForm returns NotFound, fallback to v3 walk | Rare in practice (unused interfaces); OK to show NoPath |
| Interface has 50+ implementations | Query returns many rows, walk explodes | Limit interface-resolution to <= 10 implementations, then pick the first 10 by symbol-ID; acceptable since implementations are usually few |
| Ambiguous method name (50 Edit methods, not all interface) | Bare-name walk from v3 fallback picks arbitrarily | OK — v4 removes this ambiguity by resolving the interface first; only fallback if type_ancestors is missing |
| Recursive call loop (A calls B, B calls A) | WalkCallersUntilForm infinite loop | Maintain a visited set (seen_symbol_ids) during recursion; exit if already visited |
| MaxHops=3, but real path is 5 hops | Form unreachable, shows NoPath | Acceptable tradeoff; if evidence shows >3 hops is common, increase MaxHops post-ship |

## Test Cases

### Test 1: Direct Interface Method (v4 activation)
**Input:** Z14slctFrm launched via `iPLANLIST.Edit`  
**Expected output:**
```
Z14SLCT,Z14slctFrm,275,frmMAIN → frmCP2 → (via iPlanList.Edit) → Z14slctFrm,(no longer dead)
```
**Assertion:** `NavigationPath.Contains("frmCP2")` AND `NavigationPath.Contains("iPlanList.Edit")`

### Test 2: Regression — Direct Routine (v3 unchanged)
**Input:** frmGap launched via `OpenGap` routine  
**Expected output:**
```
frmGap,400,frmMAIN → frmGap,OpenGap,(description)
```
**Assertion:** path unchanged from v3

### Test 3: Regression — Form-to-Form (v3 unchanged)
**Input:** Any form launched via `Form.Create` / `ShowModal` in another form  
**Expected output:** Identical to v3 CSV output

### Test 4: No Callers (v3 unchanged)
**Input:** Unreferenced form  
**Expected output:** `(no path from MAIN)` (unchanged)

## Success Criteria

1. **Z14/Z19 forms appear with valid paths** instead of `(no path from MAIN)`.
2. **All v3 test cases pass** (regression: direct, routine-mediated, form→form unchanged).
3. **Ambiguous bare-name walks are reduced** — the interface-specific walk is more precise than generic `name_text=Edit`.
4. **No performance regression** — the new walk is bounded by MaxHops=3 and only activates on initial-walk failure, so it's O(n) where n is callers of the interface method (typically small).
5. **CSV output is readable** — the `(via ...)` caption clearly shows the interface method and path.

## Future Enhancements

- **Configurable MaxHops:** if users report paths beyond 3 hops, add a config option.
- **Ambiguity reporting:** if an interface method has multiple callers from different forms, list all in a comment or a separate "ambiguous paths" section.
- **Type-aware walk:** currently walks by bare routine name; could filter by type_ancestors to disambiguate callers of common names (e.g., only `Edit` on TPlanList, not Edit on other classes).

## References

- v3 algorithm: `src/forms/DRagLint.FormsMap.pas` § `BuildEdges`, `ProcessSite`, `FindNearestFormCaller`
- Index schema: `src/storage/DRagLint.Storage.Schema.pas` § `type_ancestors`, `refs.enclosing_symbol_id` (v0.82+)
- Example data: `C:\Projects\DB\ORM3\CLIENT\Micronite2027.sqlite` — query Z14slctFrm, iPLANLIST.Edit, implementations
