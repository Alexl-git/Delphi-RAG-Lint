# Installer layout v2 -- APPROVED with owner rulings (2026-10-13)

## 0. Owner rulings (2026-10-13, relayed by ENGINE) -- these OVERRIDE sections 2-4 below

1. **Manifest order: explicit > %APPDATA% > exe dir.** An EXPLICIT manifest -- env
   `DRAGLINT_MANIFEST` or `--manifest <path>` -- wins over both (57 test scripts copy the engine
   beside their own fixture drag-lint.json and must not load the real 37-DB manifest). Then
   `%APPDATA%\drag-lint\drag-lint.json`, then `<exe dir>\drag-lint.json`.
   The exe-side manifest is moved into %APPDATA% by a one-time EXPLICIT verb
   `drag-lint manifest migrate`: it RENAMES the old file to `drag-lint.json.migrated-<date>`,
   never deletes, never runs automatically. The installer runs it; ENGINE runs it once on the dev box.
   (Supersedes section 3's "existing location stays FIRST" rule for the manifest.)
2. **Library DBs default to %LOCALAPPDATA%\drag-lint\library** -- E6 (env-var expansion in
   `outDir`) is IN.
3. **Logs ALWAYS go to %LOCALAPPDATA%\drag-lint\logs**, dev box included -- not "beside the exe if
   writable". Applies to E4 and P3.

Ownership: ENGINE implements E1-E4, E6, the explicit override and the `manifest migrate` verb,
sequenced after the multi-project-rename branch. CHARTS: P1-P3, C1-C2 (+E5 for review); P2 uses
the SAME order as E1 (explicit > APPDATA > exe dir); P3 = logs always in LOCALAPPDATA. Anything
that depends on the engine's GlobalPath lands after E1.

Batched with P2 (ENGINE asked 2026-10-13: ONE plugin branch per round -- each costs a double BPL
rebuild + deploy): the log READERS (About, Diagnose, Open Plugin Log via GetPluginLogPath) must show
"no log folder" when the path is '' (no local-app-data root) instead of opening ''.

Installer consequences: no starter manifest in {app}; [Run] `drag-lint manifest migrate` after an
upgrade from a flat (v1) install; starter manifest (if any) to {userappdata}\drag-lint with
`outDir` = `%LOCALAPPDATA%\drag-lint\library`.

---

## Original proposal (sections 1-7, kept for the record)

Owner direction 2026-10-13: one folder for all drag-lint files; spillover in theme
subfolders, not ~100 files in one; BPLs/DLLs in bin\; DATA in %APPDATA% per Windows
convention. Reverses D1 (flat {app}\bin).

## 1. Program files ({app} = %LOCALAPPDATA%\Programs\drag-lint or C:\Program Files\drag-lint)

```
{app}\
  bin\             drag-lint.exe, drag-lint-config.exe, drag-lint-switch.exe, ConvRulesEditor.exe,
                   drag_lint_graph.exe, tree-sitter.dll, tree-sitter-delphi13.dll, tree-sitter-dfm.dll,
                   dclDragLintWizard.bpl (32-bit IDE)                         -> 9 files
  bin\x64\         dclDragLintWizard.bpl (64-bit IDE)
  bin\rules\       shipped lint rules (*.scm, *.json, builtin*.txt)  -- UNCHANGED place
  charts\          the 35 chart scripts (Ask-Report.ps1, Emit-*.ps1, ...)    -- the spillover
  graphviz\bin\    dot.exe + its DLLs + config8
  yadf\            YADF.exe, YADFSetup.exe, YADFOT.bpl;  yadf\x64\YADFOT.bpl
  licenses\
```

Why the DLLs and rules stay right beside the exe: Windows loads tree-sitter*.dll from the
exe's folder (moving them needs SetDllDirectory/explicit paths -- risk, no gain), and
`<exe>\rules` is the documented default with `--rules-dir` as the override. Both are ZERO
lookup changes. Everything is read-only after install.

## 2. Data -- what moves out of {app}

| Data | Where | Why there |
|---|---|---|
| `drag-lint.json` (index manifest) | **%APPDATA%\drag-lint\** | small, user-edited, per user, roams |
| `settings.json` (chart paths) | %APPDATA%\drag-lint\ | **already there** |
| `report-pairs.json` (client/server/SQL pairs) | %APPDATA%\drag-lint\ | user data; today `{app}\report-pairs.json` |
| logs: `drag-lint-fatal.log`, `drag-lint-plugin.log`, `drag-lint-telemetry.log` | **%LOCALAPPDATA%\drag-lint\logs\** | today beside exe/BPL -- NOT WRITABLE under Program Files |
| library indexes (`library-Win32/Win64.sqlite`) | %LOCALAPPDATA%\drag-lint\library\ | large, machine-specific -- must not roam |
| engine-hold, control-channel audit, protocol handler copy, ConvRulesEditor scratch | %LOCALAPPDATA%\drag-lint\ | **already there** (ConvRulesEditor uses `DragLint\` casing -- same folder on Windows) |
| plugin settings | HKCU\Software\drag-lint | unchanged (registry is the Windows standard for this) |
| project indexes | `<project>\_D-RAG\` | unchanged -- they belong to the project |

## 3. Every lookup that changes

Rule for all of them: **the existing location stays FIRST**, the new one is a fallback. A
developer box (manifest beside `third_party\dll-win64\drag-lint.exe`, repo `charts\src`)
behaves exactly as today; only an installed copy reaches the new steps.

**ENGINE (engine-reviewed; touches Manifest.pas + CLI.pas, not the rename regions):**
* **E1 manifest read** -- `TManifestIO.Load` (`DRagLint.Index.Manifest.pas` ~1186): `<engine
  dir>\drag-lint.json`, else `%APPDATA%\drag-lint\drag-lint.json`. ONE function serves ~20
  call sites in CLI.pas (query, index, lint, lsp, serve, docs ...). Relative paths inside the
  file must resolve against the folder the file was FOUND in (today: the engine dir).
* **E2 manifest write** -- `ManifestWrite.pas` ~154 (`RegisterProjectSection`), CLI.pas ~30542
  (config default path): write to the same file E1 read; if none exists, create it in
  %APPDATA% when the engine dir is not writable. Expose one `TManifestIO.GlobalPath` and use it
  everywhere so read and write cannot disagree.
* **E3 drag-lint-config.exe** -- `Config.MainForm.pas` ~104-121, `Config.EngineRunner.pas` ~92:
  use the same `GlobalPath`.
* **E4 fatal log** -- CLI.pas ~31466: engine dir if writable, else %LOCALAPPDATA%\drag-lint\logs.
* **E5 compare's Ask-Report** -- `DRagLint.Charts.Producer.PowerShell.pas` ~178: add
  `<exe>\..\charts\Ask-Report.ps1` after `<exe>\Ask-Report.ps1`.
* (E6, only if wanted) a manifest `outDir` that names %LOCALAPPDATA% -- needs env-var expansion
  in `outDir` or an installer-written absolute path. Open question 2.

**PLUGIN:**
* **P1** `ReportText.AskReportCandidates`: add `<engine>\..\charts\Ask-Report.ps1` second.
* **P2** manifest: `DbResolver.pas` ~160 and ~481, `OptionsFrames.pas` ~683: beside BPL, beside
  exe, then %APPDATA% (same order as E1).
* **P3** logs: `LspClient.pas` ~118, `Telemetry.pas` ~32 write beside the BPL -- under Program
  Files that fails. BPL dir if writable, else %LOCALAPPDATA%\drag-lint\logs.
* No change: ExeResolver (installer sets ExePath), GraphWindow/Diagnose graph lookup (graph exe
  stays in bin\ beside the BPL), YADF lookups (registry ExePath).

**CHARTS (mine):**
* **C1** `Emit-Common.ps1` resolvers: add `<scripts>\..\bin\drag-lint.exe` and
  `<scripts>\..\graphviz\bin\dot.exe` (existing steps kept).
* **C2** `Ask-Report.ps1` `-PairsFile` default: `%APPDATA%\drag-lint\report-pairs.json` first,
  then the repo's `charts\report-pairs.json`.

**INSTALLER (mine):** the layout above; starter manifest written to the INSTALLING user's
`{userappdata}\drag-lint\drag-lint.json` (onlyifdoesntexist, kept on uninstall). The
users-modify permission on a file under Program Files goes away. Other users on an all-users
install simply start with no manifest, which the engine accepts (measured: exit 0, test
`run_starter_manifest.ps1`).

## 4. Open questions for the owner

1. **Manifest search order** -- keep "beside the exe FIRST, then %APPDATA%" (dev box unchanged;
   proposed), or %APPDATA% first (an installed engine and a dev engine on one box would then
   share one manifest)?
2. **Library indexes** -- default the starter manifest's `outDir` to
   %LOCALAPPDATA%\drag-lint\library (needs E6), or leave `outDir` unset until the user builds a
   library index with drag-lint-config?
3. **Logs on the dev box** -- they stay beside the exe/BPL there (writable). OK?

## 5. Order and size

1. ENGINE: E1-E4 (+E6 if Q2 says so) with tests -- the only part with real reach (~20 call
   sites through one function). 2. PLUGIN P1-P3 + CHARTS C1-C2 + E5 (small, mine, ENGINE
   reviews). 3. Installer layout + checklist update + rebuild. Steps 2-3 are about half a day
   once step 1 lands.

## 6. YADF (from the yadf-e7 source audit, 2026-10-13)

* YADF settings already live in %APPDATA%\YADF (yadf.ini, profiles.ini, yadf-<name>.ini), shared by
  YADF.exe, YADFSetup.exe and YADFOT.bpl. Nothing is read beside the binaries. The installer ships NO
  yadf.ini (the CLI writes a commented default on first run), and uninstall leaves %APPDATA%\YADF.
* Preview sample: YADF 4b01ac1 embeds it and writes it once per user to %APPDATA%\YADF; the installer
  ships Demo\Sample.pas only with YADF <= 1.0.18.0 (compile-time version check), never seeds %APPDATA%.
* `YADF.exe --log` appends to %APPDATA%\YADF\yadf-startup.log since 4b01ac1 -- works from Program Files.
  YADF writes nothing beside its binaries.
* HKCU\Software\YADF\ExePath must name the Win64 YADF.exe; the installer already does this. If it is
  missing, drag-lint falls back to build-tree paths and fails loudly; keep that behaviour.
* The owner's dev box registers the Debug YADFOT BPLs from the YADF tree. The installer already warns
  before adding a second registration, and a silent install skips it.

## 7. Found while answering ENGINE: stale Win64 plugin BPL

`third_party\dll-win64\dclDragLintWizard.bpl` is dated 2026-09-02, six weeks older than the source.
The setup packs it for the 64-bit IDE. A current Win64 build compiles clean (exit 0, built to scratch
only). It needs a deploy, and Build-Installer.ps1 should age-check the x64 BPL as it does the Win32 one.