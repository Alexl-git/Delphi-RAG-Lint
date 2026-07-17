# ConvRulesEditor -- independent FROM/TO platform selection (design)

**Date:** 2026-07-17
**Status:** approved (brainstorm) -- ready for implementation plan
**Component:** `src/tools/convrules-editor/` (ConvRulesEditor.exe)
**Scope:** feature (A) of a two-part request. Feature (B) -- text-value
castability with conversion rules -- is a SEPARATE later spec (see Out of Scope).

## Problem

The editor's FROM and TO class pickers are wired to hard-coded database sets in
`ConvRulesEditor.dpr`:

- `FromDbs` = `[library-Win32, library-Win64, ProjectDb]` (union)
- `ToDbs`   = `[library-Win64, ProjectDb]` (target hard-coded to Win64)

But a real conversion's FROM and TO can be on DIFFERENT platforms (e.g. migrating
a Win32 app to Win64, or comparing types across platforms). The target platform
is currently baked in; there is no way to say "FROM is this platform, TO is that."

## Goals

- Let the user pick the FROM platform and the TO platform INDEPENDENTLY.
- FROM and TO **type** pickers draw from the selected platform's LIBRARY index
  (`library-Win32.sqlite` / `library-Win64.sqlite`) -- the source/target
  component types live in the platform libraries.
- Changeable interactively (dropdowns) and settable at launch (CLI args).
- Preserve today's behavior exactly when no selection is made.

## Non-goals

- Per-side PROJECT database selection (both sides keep the single shared project
  DB for the From-Unit "Fill From-classes" feature; the TYPE pickers are
  library-driven). Confirmed with the user.
- INI/config persistence of the last selection (YAGNI for now; CLI + defaults
  cover it; trivial to add later).
- Any change to text-value castability / conversion rules (that is feature B).

## Design

### 1. Platform model & DB resolution

A small enum, one value per side:

    TConvPlatform = (cpWin32, cpWin64, cpBoth);

`cpBoth` = the union of both platform libraries. It stays available on the FROM
side because some legacy source components resolve in only ONE platform's library
(e.g. Orpheus `TOvcTable` is indexed under Win64 only) -- the union is the current
FROM safety net.

A pure helper maps a platform to its library DB set:

    function LibDbsFor(APlatform: TConvPlatform): TArray<string>;
    // cpWin32 -> [library-Win32.sqlite]
    // cpWin64 -> [library-Win64.sqlite]
    // cpBoth  -> [library-Win32.sqlite, library-Win64.sqlite]

The library directory (`C:\Projects\.drag-lint\`) stays a constant base as today.
The PLATFORM selection controls only the LIBRARY part of each side's DB set; the
shared `ProjectDb` stays always-on and additive (it is what preserves today's
behavior and keeps project-declared component types visible). Wiring:

- FROM type picker (`FCbFrom`)  <- `LibDbsFor(FromPlatform)` + ProjectDb
- TO type picker   (`FCbTo`)    <- `LibDbsFor(ToPlatform)` + ProjectDb
- From-Unit picker (`FCbUnit`) + "Fill From-classes" <- ProjectDb (UNCHANGED)
- Engine default (proptree / scaffold / validate) <- union of
  `LibDbsFor(FromPlatform)` + `LibDbsFor(ToPlatform)` + ProjectDb (must resolve
  both sides' types + project-declared types).

Rationale for keeping ProjectDb additive: the user's "the FROM and TO types are
both from the platform libraries" clarification means the tool must NOT grow a
per-side PROJECT-DB picker (the platform library is the selectable type source) --
it does NOT mean removing the existing shared ProjectDb, which project-declared
component classes still resolve against and which the back-compat lock depends on.

### 2. Selection: CLI args + UI dropdowns

Two combo boxes at the top of the window -- "From platform" and "To platform",
each offering `Win32 / Win64 / Both`. Seeded at launch from optional CLI args,
else defaults that reproduce today's behavior:

- `--from-platform <win32|win64|both>`  default = **Both** (today's FROM union)
- `--to-platform   <win32|win64|both>`  default = **Win64** (today's TO target)

CLI parsing lives in `ConvRulesEditor.dpr` (which already computes the DB
globals). Values are case-insensitive; an unknown/absent value falls back to the
default. Nothing else about launch changes.

No INI persistence in this pass (see Non-goals).

### 3. Live re-scoping + one engine change

The form owns `FFromPlatform` / `FToPlatform`. On a platform dropdown change:

1. recompute that side's DB set via `LibDbsFor`;
2. clear the side's class cache (`FFromClasses` or `FToClasses`) and its combo
   Items;
3. reload it via `TEngineAdapter.ListDescendantsOf(<ancestor>, <newDbs>, ...)`
   (FROM ancestor = `TComponent`, TO ancestor = `TControl`, as today);
4. update the engine's default DB set to the new union (both sides + ProjectDb)
   so proptree/validate resolve against the current platforms;
5. show a status-bar message.

One required engine change: `TEngineAdapter` currently receives its default DB
list only in the constructor. Add:

    procedure SetDbs(const ADbs: TArray<string>);

so the union can be updated when either platform changes. The `FCbUnit` /
ProjectDb path is untouched.

### 4. Testing

- **Pure unit tests** (`tests/ConvRulesModelTests.dpr`): `LibDbsFor` mapping --
  `cpWin32`->[Win32], `cpWin64`->[Win64], `cpBoth`->[Win32,Win64] (order + set).
- **Data-layer, headless** (the existing `TestPickerDatasource` pattern -- build a
  real `TEngineAdapter`, drive the exact spawn+parse path the pickers use):
  - FROM with a Win64-only DB set lists `TOvcTable`; FROM with a Win32-only DB set
    does NOT -- proving platform selection actually re-scopes (a discriminating
    check, same helper both directions).
  - Default (no CLI): FROM=Both / TO=Win64 reproduces today's class lists exactly
    -- a back-compat lock.
  - Tests SKIP (not fail) when the library DBs are absent (lean-machine safe), per
    the existing convention.
- **Live UI** (dropdown change -> picker reload): headless-unverifiable, as with
  the rest of the UI; noted for a human click-through.

## Back-compat

With no CLI args, FROM defaults to Both and TO to Win64 -- byte-identical to the
current hard-coded `FromDbs`/`ToDbs`. Nothing breaks for the existing workflow.

## Files touched

- `ConvRulesEditor.dpr` -- parse `--from-platform` / `--to-platform`; compute
  initial platforms; keep the library-dir constants; set the DB globals from
  `LibDbsFor`.
- `ConvRules.MainForm.pas` -- two platform combo boxes; `FFromPlatform` /
  `FToPlatform`; `LibDbsFor`; on-change re-scope; call `FEngine.SetDbs`.
- `ConvRules.Engine.pas` -- add `TEngineAdapter.SetDbs`.
- `tests/ConvRulesModelTests.dpr` -- `LibDbsFor` unit tests + platform re-scope
  data-layer asserts.

## Out of scope -- feature (B), a later spec

Text-value castability: the compatibility test for converting DFM/PAS text is
"can we obtain the TO value from the FROM value's text representation?" For
enum-like types whose type NAMES differ (e.g. `TXAlign` vs `TYZAlign`) but whose
text values map, we need value-level conversion rules (a value->value mapping) and
a DSL construct to express + apply them. The symbol model already has
`skEnumValue`, so enum members are indexable -- feasibility looks good. This is a
separate brainstorm + spec after (A) lands.
