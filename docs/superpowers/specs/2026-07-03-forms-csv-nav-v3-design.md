# forms-csv Navigation v3 -- Interleaved Click Path (Design)

Date: 2026-07-03
Status: approved (user, in-session)
Owner: drag-lint forms-csv (`src/forms/DRagLint.FormsMap.pas`)

## Problem

The Navigation column shows the root form plus button captions only:

    frmMAIN -> 'Job List' -> 'Open Folder' -> 'Exit to Control Plan 2' -> 'Plan'

A tester cannot tell WHICH form they are on at each step. The BFS in `NavPath`
already knows the landing form class of every hop (`TFormEdge.ToClass`); it just
never renders it.

## Decisions (user-approved)

1. **Format: interleaved arrows.** After each caption, append the FormName of the
   form that the click lands on:

       frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4
              -> 'Exit to Control Plan 2' -> frmControlPlan2 -> 'Plan' -> Z14slctFrm

   The user noted the format may be expanded later (e.g. tester sentences), so the
   renderer must be swappable (see Architecture).
2. **Column: enrich Navigation in place.** Called From stays as the list of ALL
   immediate callers (different information: multiple entry points).
3. **Trailing target included** -- the path ends with the row's own FormName so it
   reads as a complete, self-contained sentence.

## Behaviour spec

- Ordinary hop: `-> 'Caption' -> <LandingFormName>`.
- Synthetic captions keep their existing unquoted style, also followed by the
  landing form: `frmMain -> (via OpenGap) -> frmGap`.
- Landing name = `AClassToNode[E.ToClass].FormName`; fall back to the class name
  if the node lookup fails (defensive; edges only target inventory nodes today).
- Root form row: Navigation stays blank. Unreachable rows stay `(no path from MAIN)`.
- Called From column: byte-identical to v2 output.
- CSV provenance header: `FORMS_CSV_ALGORITHM` bumps `'2' -> '3'`.

## Architecture

Refactor `NavPath` (FormsMap.pas:765) minimally:

- `THop = record Caption: string; LandingName: string; end`
- BFS accumulates `Hops: TArray<THop>` per queue entry instead of a pre-rendered
  string. Extending uses array concatenation (`Cur.Hops + [NewHop]`), which
  allocates a fresh array per enqueue -- no aliasing between branches.
- New `function RenderPath(const ARootName: string; const AHops: TArray<THop>): string`
  is the ONLY place that turns hops into text. A future format change (tester
  sentences, localisation) touches this one function, not the BFS.
- Scale: ~55 forms/project, BFS unchanged O(V*E); per-entry array copy is O(depth).

## Testing (TDD)

Update `tests/autotest/run_formsmap.ps1` FIRST (checks fail against current exe):

- `frmList` nav: `frmMain -> 'Lists' -> frmList`
- `frmEdit` nav: `frmMain -> 'Lists' -> frmList -> 'Edit Item' -> frmEdit`
- `frmChild` nav: `frmMain -> 'Lists' -> frmList -> 'Open Child' -> frmChild`
- `frmReports` nav: `frmMain -> 'Reports' -> frmReports`
- keep-the-gap: `frmMain -> \(via ` still matches and ends `-> frmGap`
- NEW check: an intermediate FormName appears between two captions (frmEdit row
  contains `frmList ->` between 'Lists' and 'Edit Item').
- Root-blank and `(no path from MAIN)` checks unchanged.

Real-data smoke: regenerate the Micronite2027 CSV against the full ORM3 DB;
Z14SLCT row must contain `frmControlPlan2 -> 'Plan' -> Z14slctFrm`.

## Release

- `VERSION = '0.84.0-alpha'` (feature bump), CHANGELOG entry.
- Rebuild Win32 + Win64, stage to `third_party/dll-win32|64/`.
- No schema change; no index impact.

## Out of scope

- Tester-sentence format (future; enabled cheaply by RenderPath).
- IDE plugin passing the manifest/full DB instead of the per-project DB to
  forms-csv (separate enhancement, discussed 2026-07-03).
- Called From changes.
