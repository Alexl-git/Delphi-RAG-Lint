# Batch G -- IDE splash + About box with on-demand live self-info (design)

**Date:** 2026-07-09
**Status:** Approved (design); ready for implementation plan
**Prior art:** Batch F (v0.99.0-alpha). This is the next feature, targeting
**v1.0.0-alpha** (splash/About is a natural 1.0 milestone).
**Origin:** user request -- mirror TableTools' IDE splash/logo-with-version, reuse
its icon, show version + MIT license, make About a live diagnostic surface that
talks to the exe, then prune the now-redundant debug menu; afterwards write a
YADF handoff note so YADFOT can do the same.

---

## 1. Goal

Give the drag-lint RAD Studio design-time package (BPL) two OTA presentation
surfaces, plus a small CLI verb that feeds the richer one:

- **Splash screen** entry (icon + caption + MIT + version) shown while the IDE
  initializes -- mirrors TableTools; **must not** delay startup.
- **About box** entry (Help -> About -> third-party plugins) that, when the user
  selects it, fetches **live self-info from `drag-lint.exe`** on a background
  thread and shows it -- version/build/capabilities/MIT, and a **structured
  error block** if the exe call fails (so problems self-diagnose).
- **`drag-lint info --json`** -- a new read-only CLI verb returning the exe's
  self-info, consumed by the About box.
- **Debug-menu prune** -- remove `Test Connection...` (now covered by About's
  live-info + error block); keep the rest.

Non-goal (YAGNI): no exe call during IDE startup; no persistent caching of exe
info; no new dependency; the splash/About do not change any analysis behavior.

---

## 2. Timing model (the load-bearing constraint)

The `Register` proc runs **during IDE initialization**. Shelling the exe there
would stall startup, so:

| Surface | When registered | Exe call? | Version source |
|---|---|---|---|
| Splash | startup (`Register`) | **NO** | static plugin const |
| About *entry* | startup (`Register`) | **NO** | static plugin const |
| About *memo content* | on user click (Help->About) | **YES**, backgrounded | live `drag-lint info --json` |

Measured: a one-shot `drag-lint.exe` self-info call is **~170-300ms** -- fine on
a click, unacceptable at startup. So startup is 100% static (instant); the live
fetch happens only when the About memo is actually viewed, on a background
thread, so even the click never blocks.

---

## 3. Splash screen

In `DragLint.Plugin.Wizard.pas` `Register` (mirroring TableTools'
`TableTool.Init.pas`):

```pascal
if Assigned(SplashScreenServices) then
begin
  HIcon := LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
  if HIcon <> 0 then
  begin
    Icon := TIcon.Create;
    try
      Icon.Handle := HIcon;
      Bmp := TBitmap.Create;
      try
        Bmp.Assign(Icon);
        SplashScreenServices.AddPluginBitmap(
          SPLASH_CAPTION,       // 'drag-lint'
          Bmp.Handle,
          False,                // AIsUnRegistered
          'MIT',                // ALicenseStatus -> shown in ()
          SPLASH_VERSION);      // ASKUName -> appended to caption (the version)
      finally Bmp.Free; end;
    finally Icon.Free; end;
  end;
end;
ForceDemandLoadState(dlDisable);  // eager-load so the splash shows every launch
```

- **Automatic display:** once `AddPluginBitmap` is called in `Register`, the IDE
  paints the splash entry itself -- no display code. `ForceDemandLoadState(
  dlDisable)` is the TableTools workaround that stops demand-loading from
  skipping `Register` at startup (so the splash reliably appears).
- **Field mapping (user spec):** caption `drag-lint`; LicenseStatus `MIT`;
  SKU/version = the static plugin version const.
- The OTA wants a 24x24 bitmap; the reused icon is 32x32 -- `TBitmap.Assign(
  TIcon)` is what TableTools ships; if the IDE visibly downscales, note it in the
  smoke report (cosmetic, not a blocker).

---

## 4. About box

Register the entry at startup (static), populate the memo on demand (live).

### 4.1 Registration (startup, static)

```pascal
if Assigned(AboutBoxServices) then
  GAboutIndex := AboutBoxServices.AddPluginInfo(
    ABOUT_TITLE,          // 'drag-lint'
    ABOUT_DESCRIPTION,    // static seed text (see 4.3) -- live info appended on click
    Bmp.Handle,           // same icon as splash
    False,                // AIsUnRegistered
    'MIT',                // ALicenseStatus
    ABOUT_SKU);           // version
```

Save `GAboutIndex`; call `AboutBoxServices.RemovePluginInfo(GAboutIndex)` in the
wizard teardown (finalization / `Destroyed`) -- mirrors the existing
Unregister* teardown discipline (Batch B teardown-leak lesson).

### 4.2 Live memo population (on click, backgrounded)

The About memo is a fixed string set at `AddPluginInfo` time; the OTA does not
call back when the user selects the plugin. So the pattern is:

1. At registration, seed the description with the static block **plus** a line
   `Live exe info: querying... (open this page again to refresh)`.
2. Kick a **one-shot background thread** shortly after startup (or on first
   idle) that runs `drag-lint info --json`, parses it, formats the live block +
   the error block on failure, and **re-registers** the About entry with the
   updated description (`RemovePluginInfo(GAboutIndex)` then `AddPluginInfo(...)`
   with the full text, saving the new index).
   - Rationale: because the memo can't be lazily fetched *on* selection, we fetch
     once in the background after startup and swap the entry's text in. The fetch
     is off the main thread; the swap is marshalled to the main thread via
     `TThread.Queue`. Startup is never blocked (the thread starts after
     `Register` returns and does its ~200ms work in the background).
   - A menu action **"Refresh About info"** (or reusing the existing
     `Test Connection` slot's intent) MAY re-run the fetch on demand; keep it
     minimal -- the automatic post-startup fetch is the primary path.

> Implementation note for planning: confirm whether re-`AddPluginInfo` after
> startup updates the visible entry in this IDE version. If the IDE snapshots the
> About list at startup and ignores later `AddPluginInfo`, fall back to: seed the
> description with the static block only, and expose the live info via a **menu
> action "drag-lint: About / Diagnostics..."** that shells `info --json` on click
> (~200ms, backgrounded) and shows the live block + error block in a dialog. The
> About *box* still carries icon+version+MIT+static description; the live
> diagnostic surface is the menu action. Decide in the plan after a quick OTA
> behavior check; both paths satisfy the requirement (live exe info + error
> surfacing, no startup block).

### 4.3 Memo content

**Static seed (always present):**
```
drag-lint -- symbol-aware index + RAG + lint for Delphi/Pascal
License: MIT
Plugin: <PLUGIN_VERSION> (BPL built <FileAge(BPL)>)
```

**Live block (from `drag-lint info --json`, appended on success):**
```
Engine (drag-lint.exe): <version>  (built <build_date>)
  exe: <exe_path>   platform: <platform>
  tree-sitter: core <..> / delphi13 <..> / dfm <..>
  capabilities: FTS5=<yes|no>, CLI verbs=<n>
Plugin log: <GetPluginLogPath>
```

**Error block (from a failed exe call, replaces the live block):**
```
Engine self-info UNAVAILABLE -- diagnostic:
  resolved exe path: <path tried>   (next-to-BPL: <yes/no>, else PATH)
  <one of:>
    - exe not found at the resolved path
    - spawn failed: <OS error / CreateProcess message>
    - exited <code>; stderr: <first line>
    - no response within <N> ms (timeout)
    - unparseable response: <first 120 chars of raw output>
Plugin log: <GetPluginLogPath>
```

This error block is what lets About **replace `Test Connection`** -- it reports
the same exe-path resolution + spawn/exit diagnostics, and additionally surfaces
the plugin-vs-exe version so drift is visible.

---

## 5. `drag-lint info --json` CLI verb

New read-only verb in `DRagLint.CLI.pas`. No DB, no side effects.

```json
{
  "schema": "info/1",
  "name": "drag-lint",
  "version": "0.99.0-alpha",
  "build_date": "2026-07-09 14:51:36",
  "license": "MIT",
  "description": "symbol-aware index + RAG + lint for Delphi/Pascal",
  "tree_sitter": { "core": "<ver>", "delphi13": "<ver>", "dfm": "<ver>" },
  "capabilities": { "fts5": true, "cli_verbs": <count> },
  "exe_path": "C:\\...\\drag-lint.exe",
  "platform": "Win64"
}
```

- **`version`** = the existing `VERSION` const.
- **`build_date`** = `FileAge(ParamStr(0))` formatted `yyyy-mm-dd hh:nn:ss` -- the
  exe's own file timestamp. **VERIFIED** this compiles + runs (0 errors) in the
  Studio 37 toolchain. **Do NOT use `{$I %DATE%}`** -- VERIFIED it does NOT
  compile here (`dcc32` treats it as an include directive: `F1026 File not
  found: '%DATE%.pas'`). This matches the repo's existing `PluginBuildTag`
  `FileAge(GetModuleName)` idiom.
- **`tree_sitter`** versions: source from whatever the parser layer already
  exposes; if no version is available for a grammar, emit `"unknown"` (don't
  fabricate). Confirm the source in planning.
- **`capabilities.fts5`**: probe as the existing code does (there is already an
  "FTS5 probe: AVAILABLE" path in the index build); reuse it.
- **`capabilities.cli_verbs`**: a small static count is fine (or derive if a
  verb table exists).
- **`exe_path`** = `ParamStr(0)`. **`platform`** = `{$IFDEF WIN64}` compile-time.
- Also print a plain-text form when `--json` is absent (human-friendly), for
  symmetry with other verbs. `--json` is what the plugin calls.
- Headless-testable: `run_info_verb.ps1` asserts schema `info/1`, non-empty
  `version`, a parseable `build_date`, `license == "MIT"`.

---

## 6. Icon resource

- Copy TableTools' `Micronite LOGO 4 32x32.ico` into
  `src/delphi-plugin/` (kept as-is; "reuse the TableTools icon for now" per user
  -- a drag-lint-specific icon is a later, optional swap).
- Add `src/delphi-plugin/DragLintSplash.rc` containing:
  `SPLASH_ICON_1 ICON "Micronite LOGO 4 32x32.ico"`
- Wire the `.rc` into the BPL build so it compiles to `.res` and links (the
  `.dproj` needs the resource; confirm whether to add `{$R DragLintSplash.res}`
  to the wizard unit + a build step, or add the `.rc` to the `.dproj`'s resource
  list -- follow whatever the existing `dclDragLintWizard.res` mechanism is).
- Loaded via `LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, ...)` exactly as
  TableTools does.

---

## 7. Debug-menu prune

Current Tools -> drag-lint items (in `RegisterDragLintMenu`, Editor.pas ~4096):
`Run Diagnostics (didSave)`, `Copy Diagnostics (Current File)`,
`Compile && Diagnose`, `Import Build Log...`, `Test Connection...`,
`Open Plugin Log`.

- **Remove `Test Connection...`** (`InvokeTestConnection`) -- its output
  (exe-path resolution + spawn/handshake success/failure + build tag) is now
  covered by About's live block + error block, which additionally surfaces the
  version drift. Delete the menu item; delete `InvokeTestConnection` +
  declaration if nothing else references it.
- **Keep everything else.** `Open Plugin Log` stays (opening the file is a
  distinct action); About *shows* the log path so the user knows where it is.

Do the prune **only after** splash+About are confirmed working (it is the last
step of this batch's IDE work, and its own commit, so it is trivially revertible
if the smoke test finds About insufficient).

---

## 8. Testing & verification

**Headless (automatable gates):**
- `run_info_verb.ps1` -- the `info --json` schema/fields test (Section 5).
- Full existing battery re-run -- no regression.

**NOT headless (user live-IDE smoke -- gates the YADF note):**
- Splash: the drag-lint logo + `drag-lint (MIT) <version>` appears on the IDE
  startup splash.
- About: Help -> About -> drag-lint shows the icon, MIT, version, the static
  block, and (after the background fetch) the live engine block; killing/renaming
  the exe shows the **error block** instead (diagnostic self-test).
- Debug menu: `Test Connection...` is gone; the rest work; About shows the log
  path.

**Build:** CLI Win64 (`info` verb) + Win32 BPL (splash/About/icon). BPL rebuild
rule: **RAD Studio CLOSED**; every BPL-building subagent carries the "DO NOT
close the user's RAD Studio -> report BLOCKED" rule.

**Release:** version bump -> **v1.0.0-alpha**; CHANGELOG/README/AI-docs; final
whole-branch review; pack + GH release (both CLI zips + Win32 BPL). User drives
final push per the batch pattern (this session: autonomous through release).

---

## 9. YADF handoff (after publish + user smoke)

Once splash/About are **confirmed working in the user's IDE**, write a detailed
porting note into the YADF repo (path to confirm with user; prior porting note
lives at `C:\Projects\YADF\docs\PORT-tools-options-page.md`) as
`PORT-ide-splash-and-about.md`, covering: the `Register`-proc splash +
`ForceDemandLoadState` pattern; the About entry + background-fetch/error-block
pattern; the icon `.rc` wiring; the `FileAge` build-date method (and the
`{$I %DATE%}` trap); the `info --json` verb shape for YADFOT's own exe; and the
debug-menu-prune rationale. Until the user confirms the live smoke, the note is a
**DRAFT marked "pending user smoke confirmation"** and is NOT presented as done.

---

## 10. Sequencing within Batch G

1. `info --json` verb (+ headless test) -- foundation, CLI-only, TDD.
2. Icon resource `.rc` + BPL wiring.
3. Splash registration (static) -- BPL.
4. About entry + background live-fetch + error block -- BPL.
5. Debug-menu prune (`Test Connection` removal) -- BPL.
6. Version bump v1.0.0-alpha + docs + battery + final review + release.
7. YADF note DRAFT.
8. (User smoke -> finalize YADF note.)

Independent enough for subagent-driven-development; the BPL steps (2-5) each
rebuild the Win32 BPL and gate on RAD Studio being closed.

---

## 11. Out of scope / deferred (this batch)

- A drag-lint-specific icon (reuse TableTools' for now).
- Persisting/caching exe info across sessions.
- Any exe call during IDE startup.
- The rest of the program's deferred backlog (housekeeping, Track 5.3, Track 3,
  ref-gap E) -- separate batches after Batch G ships.
