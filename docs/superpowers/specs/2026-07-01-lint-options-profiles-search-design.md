# Lint Options tab -- full-config named profiles + rule search -- Design

Status: approved (2026-07-01). Builds on v0.69 D1b (the "Lint Options" IDE dock
tab, merged to `main` at `d4cac28` + post-merge fixes through `4ea595d`). Ships
in the same upcoming release as D1b (VERSION bump is a release-time step).

## Goal

Two additions to the existing `TLintOptionsFrame` dock tab
(`src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`):

1. **Full-config named profiles** -- save the current tab settings under a name,
   and load a saved profile back, so the user can keep several complete
   configurations and switch between them. A profile captures the COMPLETE
   config (enable/disable + severity + thresholds + naming), not just
   enable/disable as today.
2. **Rule search** -- a search box that live-filters the rule list to entries
   whose id or title contains the typed text, so a user drowning in one rule's
   messages can find that rule's checkbox in a couple of keystrokes.

Non-goals (YAGNI): profile delete/rename UI (hand-edit the JSON); a "discard
unsaved changes?" prompt when switching profiles; regex/fuzzy search.

## Part A -- Config engine: profiles hold a full config

### Schema
`drag-lint-lint.json` `profiles.<name>` gains the same keys as the top level:
`disabled[]`, `enabled[]`, `severity{}`, `thresholds{}`, `naming{}`. Today a
profile only holds `disabled`/`enabled` (merged via `MergeListsFrom`).

### `TLintConfig.Load(APath, AProfile)` (DRagLint.Lint.Config.pas)
Today: parse top-level (disabled/enabled/severity/thresholds/naming), then if
`AProfile` is set + present, `MergeListsFrom(profileObj)` (disabled/enabled only,
APPEND).

New: a profile OVERRIDES the base per top-level key it defines (snapshot
semantics):
- The current per-key parsing (disabled/enabled/severity/thresholds/naming from a
  `TJSONObject`) is factored into a private helper, e.g.
  `procedure ApplyConfigObject(const AObj: TJSONObject; AReplaceLists: Boolean)`.
- `Load` calls it once for the top-level root, then -- if `AProfile` is set and
  `profiles.<AProfile>` exists -- calls it AGAIN for the profile object with
  `AReplaceLists = True`.
- REPLACE semantics per key the profile defines: `disabled`/`enabled` lists are
  REPLACED (the profile's on/off is a complete decision, not additive); a
  `severity`/`thresholds` key present in the profile REPLACES the base map; a
  `naming` block present in the profile REPLACES the base naming block. Keys the
  profile OMITS fall back to the base value. Because the tab writes complete
  profiles, a profile fully determines the config; hand-edited partial profiles
  inherit the base for anything they leave out.
- IMPORTANT preserved subtlety: `short_identifier_check` stays a JSON STRING
  ("true"/"false") in a profile's `naming` block, same as top level.

### CLI
`drag-lint lint --profile <name>` (CLI.pas already wires `TLintConfig.Load(Path,
AArgs.Profile)`) now applies the profile's FULL settings. No new flag, no help
change beyond wording. Base config (no `--profile`) is unchanged. Existing
disabled/enabled-only profiles keep working (their missing keys inherit base).

## Part B -- `TLintConfigWriter` new methods (DRagLint.Lint.ConfigWriter.pas)

Pure `System.JSON`, console-testable; reuse the merge-preserving write path.

- `class function ListProfileNames(const APath: string): TArray<string>;`
  Return the keys under `profiles` (empty array if the file/section is absent).
- `class procedure SaveToProfile(const APath, AName: string; const ACfg: TLintConfig);`
  Serialize `ACfg`'s owned keys (disabled/enabled/severity/thresholds/naming --
  the same object `ToJson` builds) and set it as `profiles.<AName>` in the
  existing file, MERGE-PRESERVING the base top-level keys AND any other profiles
  (extend the existing `SaveToFile` merge logic: parse existing root or start
  fresh, ensure a `profiles` object, set/replace the one named member, write
  ANSI/CRLF/no-BOM).
- Loading a profile for display reuses `TLintConfig.Load(APath, AName)` (Part A)
  -- no new reader needed; add a thin `LoadProfileOrBase(APath, AName)` wrapper
  only if it reads cleaner (`AName=''` -> base).

## Part C -- Tab UI (TLintOptionsFrame top panel)

State fields to add: `FProfile: string` (active profile name; `''` = base),
`FSearch: string` (current filter text), and store the active config as a field
(e.g. `FCfg: TLintConfig`) so both a profile switch and a search keystroke can
re-render without re-running the CLI.

### Profile combo (editable)
- A `TComboBox` (`Style = csDropDown` -- editable) labeled `Profile:`, filled
  with `(base)` followed by `ListProfileNames`.
- Selecting an existing dropdown entry -> set `FProfile` (`''` for `(base)`),
  reload the active config (`TLintConfig.Load(cfgPath, FProfile)`), re-render.
- The combo's TEXT is the SAVE TARGET.

### Save button (existing, retargeted)
On Save, the target is the combo's current text:
- `(base)` or empty -> write the base top-level config via `SaveToFile` (today's
  behavior).
- an existing or new name -> `SaveToProfile(cfgPath, name, cfg)`; then refresh
  the combo's item list (add the name if new) and keep it selected/`FProfile`.
The current control state is read into a `TLintConfig` exactly as Save does today
(the Part-C build-config-from-controls logic is unchanged; only the destination
differs).

### Search box
- A `TEdit` labeled `Search:` in the top panel; `OnChange` sets `FSearch` and
  re-renders.
- Filter predicate: a rule is shown iff `FSearch` is empty OR (case-insensitive)
  the rule's `id` OR `title` contains `FSearch`.
- `RenderCatalog` gains a filter step: skip non-matching rules; skip a category
  box entirely if none of its rules match; the vertical stack re-flows so there
  are no large gaps (the existing two-pass measure/place already computes group
  heights -- it operates on the filtered set).
- Re-render reads the CACHED catalog JSON (`FCatalogJSON`) -- no CLI re-call.
  Clearing the box restores the full list.

### Interplay
Both "profile switched" and "search changed" funnel through a single re-render
that uses `FCfg` (config -> control initial state) and `FSearch` (visible
subset). Switching a profile loads that profile's config (unsaved edits to the
current view are discarded -- acceptable; no prompt).

## Testing

- **ConfigWriter (console, extend T63 or a new T65):** write a base config with a
  `profiles` block; `ListProfileNames` returns the names; `SaveToProfile`
  round-trips a full config under a name while preserving the base and a second
  profile; re-read raw JSON and assert the profile has disabled/thresholds/naming
  and the base + other profile survived.
- **Config full-profile apply (console):** write a base + a profile that overrides
  `thresholds`/`naming`/`disabled`; `TLintConfig.Load(path, name)` yields the
  profile's values (override), and omitted keys fall back to base. Include the
  `short_identifier_check` string-survives case.
- **Frame:** compile-smoke (T64 already covers the unit compiling) + the human
  in-IDE gate (below). The UI (combo behavior, live filter) is not unit-testable.
- Keep the existing harness green (lint, lintconfig, T63/T64).

## Build & deploy (hard-won constraints from D1b -- do NOT relearn these)

- The IDE on this machine is **32-bit** (`bds.exe` in `Program Files (x86)`); it
  loads the **Win32** BPL registered at `third_party\dll-win32\dclDragLintWizard.bpl`.
  Build the plugin **Win32** (`src\delphi-plugin\_bpl_build.bat` now does
  `Platform=Win32`), which the `.dproj` Base group outputs straight to
  `dll-win32`. A Win64 BPL is useless to this IDE. `DCC_UsePackage` now lives in
  the Base group so a command-line Win32 build links `vclsmp` (TSpinEdit).
- RAD Studio must be **CLOSED** to overwrite the loaded BPL (BPL lock). To verify
  a build without closing the IDE, build to a scratch `DCC_BplOutput` override,
  then copy into `dll-win32` once the IDE is closed.
- New embedded dock content must be a code-built **`TForm` + `inherited
  CreateNew`** (like `TDragLintStructureForm`), NOT a `TFrame` (a `.dfm`-less
  `TFrame` raises `EResNotFound`). The frame is already converted.
- Resolve the engine via the Win64-preferring pattern (`ResolveExe` already
  prefers `..\dll-win64\drag-lint.exe`, like `DLExe64`) -- the `dll-win32` exe can
  be stale and predate `rules`.
- `TDictionary` inserts use `AddOrSetValue`, never `Dict[key] := value` (SetItem
  raises "Item not found" on a missing key).
- Encoding: every touched `.pas`/`.dpr` stays strict 7-bit ASCII, CRLF, no BOM;
  no bare `}`/nested `{` in `{ }` comments; DocInsight `///` on new public surface.
- Human gate (user): open RAD Studio, switch/save/load a couple of profiles,
  confirm `drag-lint lint --profile <name>` reflects a profile's threshold/naming
  change; type in the search box and confirm the list filters live.

## Files touched

| File | Change |
|------|--------|
| `src/lint/DRagLint.Lint.Config.pas` | factor `ApplyConfigObject`; full-profile override in `Load` |
| `src/lint/DRagLint.Lint.ConfigWriter.pas` | `ListProfileNames`, `SaveToProfile` (+ optional `LoadProfileOrBase`) |
| `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` | profile combo + retargeted Save + search filter + `FProfile`/`FSearch`/`FCfg` |
| `tests/fixtures/T65_profiles_roundtrip.*` (or extend T63) | console tests for the two config-layer behaviors |
| `CHANGELOG.md` | entry under the in-progress release |
