# Installer test checklist (clean VM, no RAD Studio)

Run on a Windows x64 VM that has never had drag-lint or RAD Studio on it. Take a
snapshot first and revert to it before each pass, so every pass starts clean.
Each step says what to look for; anything else is a finding.

## 0. Before installing: record the starting state

In PowerShell on the VM:

```
reg export HKCU\Software C:\before-hkcu.reg /y
Get-ChildItem HKCU:\Software | Select-Object Name
```

## Pass A -- "Just for me", everything ticked (default)

1. Run `drag-lint-setup-<version>.exe`. Choose **Just for me**.
2. **Components page:** the four IDE plugin lines are greyed out and say
   "RAD Studio 13 not found" / "64-bit IDE not found". Everything else is ticked.
3. No PowerShell 7 page appears (the installer no longer looks for pwsh).
4. Finish. Folder `%LOCALAPPDATA%\Programs\drag-lint` holds `bin\`, `bin\rules\`,
   `bin\graphviz\bin\dot.exe`, `yadf\`, `licenses\` and `report-pairs.example.json`.
   There is **no** `bin\x64\` and **no** `.bpl` anywhere (no IDE, so no plugin).
5. Engine runs with nothing from the build machine:

   ```
   cd $env:LOCALAPPDATA\Programs\drag-lint\bin
   .\drag-lint.exe --version          # drag-lint <version>
   .\drag-lint.exe rules --json | Select-Object -First 1
   .\drag-lint.exe resolve-dbs --platform Win64   # exit 0, no WARNING
   ```

6. Index and lint a small sample folder with a `.dpr` (copy any small Delphi
   project onto the VM):

   ```
   .\drag-lint.exe index --project C:\sample\App.dproj --db C:\sample\_D-RAG\App.sqlite
   .\drag-lint.exe lint-all --db C:\sample\_D-RAG\App.sqlite
   ```

7. Charts (no PowerShell installed or needed):

   ```
   .\drag-lint.exe ask --help         # lists the 26 questions
   .\drag-lint.exe ask who-calls --target <X> --project C:\sample\App.dproj
   ```

   the question answers in-process; the SVG/HTML opens and has a drawing
   (Graphviz found beside the engine). Also check that `bin\` contains no
   `*.ps1` (`Get-ChildItem bin -Recurse -Filter *.ps1` returns nothing).
8. Open `drag-lint-config.exe`, `ConvRulesEditor.exe`, `drag_lint_graph.exe`,
   `..\yadf\YADF.exe --help`, `..\yadf\YADFSetup.exe`: each starts without a
   "missing DLL" or "package not found" error.
9. Registry -- only these may exist:
   * `HKCU\Software\YADF\ExePath` = `...\drag-lint\yadf\YADF.exe`
   * `HKCU\Software\Classes\draglint` and `HKCU\Software\drag-lint\Installer\ProtocolRegisteredBy`
     (written by `drag-lint protocol register`)
   * **nothing** under `HKCU\Software\Embarcadero`
   * the uninstall entry under `...\CurrentVersion\Uninstall\`
10. `draglint://` (no PowerShell needed; `drag-lint protocol status` must exit 0): `Start-Process 'draglint://open?file=C%3A%5Ctmp%5Cx.pas&line=1'`
    runs the handler (with no IDE it reports that nothing is listening -- that is fine).

### Uninstall pass A

11. Settings > Apps > drag-lint > Uninstall.
12. The folder is gone **except** `bin\drag-lint.json` (kept on purpose).
13. `reg export HKCU\Software C:\after-hkcu.reg /y`, then compare with
    `before-hkcu.reg` (e.g. `fc`). The only differences allowed are Windows'
    own (Explorer MRU, etc.). No `drag-lint`, `YADF`, `draglint` or
    `Embarcadero` keys remain.

## Pass B -- "All users" (revert the snapshot first)

1. Run setup, choose **All users**; Windows asks for admin rights.
2. Installs under `C:\Program Files\drag-lint`.
3. As a **standard user**, open `drag-lint-config.exe` and save a change: it
   must save (setup gave users write access to `bin\drag-lint.json`).
4. Repeat steps 5-9 and the uninstall checks.

## Pass C -- silent install

```
drag-lint-setup-<version>.exe /VERYSILENT /SUPPRESSMSGBOXES /LOG=C:\setup.log
```

Same results as pass A, and still nothing under `HKCU\Software\Embarcadero`.
Uninstall silently: `"%LOCALAPPDATA%\Programs\drag-lint\unins000.exe" /VERYSILENT`.

## Pass D -- update in place

Install version N, then run the setup for version N+1 over it: no second entry
in Apps, `bin\drag-lint.json` unchanged, `--version` reports N+1.

## Section L -- installed layout v2 (setup built with `Build-Installer.ps1 -LayoutV2`)

Owed before the engine default flips (spec `docs\superpowers\specs\2026-11-06-installed-layout-v2.md`,
phases 4-5). Passes A-D above use the DEFAULT setup and must still show the flat v1 layout. Build the
v2 setup only after the plugin lookups (phase 3) are merged. Revert the snapshot before each pass.

L1. **Fresh, Just for me.** After setup: `%APPDATA%\drag-lint\drag-lint.json` exists with
    `"outDir": "%LOCALAPPDATA%\\drag-lint\\library"`; there is **no** `bin\drag-lint.json`;
    `HKCU\Environment\DRAGLINT_LAYOUT` = `v2`. In a NEW PowerShell window:
    `drag-lint manifest where` says layout v2, origin appdata, exists yes;
    `drag-lint register-project C:\sample\App.dproj --apply` then `index --all --only App` puts the
    DB under `%LOCALAPPDATA%\drag-lint\library`.
L2. **Fresh, All users, `{app}` not writable.** Install as admin, then as a STANDARD user: indexing
    works without write access to `C:\Program Files\drag-lint`. Note whose `%APPDATA%` got the
    starter (setup runs as the admin; `{userappdata}` is the admin's profile) -- a finding either way.
L3. **Second Windows user on the all-users install:** starts with no manifest;
    `drag-lint manifest where` and `drag-lint resolve-dbs --platform Win64` exit 0;
    `register-project --apply` creates that user's `%APPDATA%\drag-lint\drag-lint.json`.
L4. **Upgrade from a flat v1 install** (install the default setup, register a project, index it,
    then run the v2 setup over it): `bin\drag-lint.json` is gone and
    `bin\drag-lint.json.migrated-<yyyy-mm-dd>` holds the old text byte for byte;
    `%APPDATA%\drag-lint\drag-lint.json` lists the same sections with absolute paths;
    `drag-lint index --all --dry-run --json` names the SAME DB paths as before the upgrade (the DBs
    did not move); no starter file overwrote the migrated one.
L5. **Fatal log:** `drag-lint query --no-such-flag` writes `%LOCALAPPDATA%\drag-lint\logs\drag-lint-fatal.log`,
    nothing beside the exe.
L6. **Way back:** `setx DRAGLINT_LAYOUT v1`, new window: `manifest where` says v1 and reads beside
    the exe (no file there after L4: copy the `.migrated-` file back by hand to restore v1).
L7. **Uninstall** keeps `%APPDATA%\drag-lint` and `%LOCALAPPDATA%\drag-lint` and removes
    `HKCU\Environment\DRAGLINT_LAYOUT`.

## Not covered on this VM (needs RAD Studio 13)

On a machine with RAD Studio 13: plugin lines are enabled, `Known Packages`
gets one value per ticked plugin, the IDE loads both drag-lint and YADF
plugins, *drag-lint > Reports* calls `drag-lint ask` (no PowerShell),
setup refuses while `bds.exe` runs, and uninstall removes only those values.
If the developer's own `dll-win32` plugin is registered, setup warns about the
duplicate before installing; a `/VERYSILENT` install skips that plugin and logs
"plugin slot 0 skipped" instead of registering a second copy.

## What to send back

The setup log (`/LOG=` or `%TEMP%\Setup Log *.txt`), the two `.reg` exports,
and a line per step that did something other than what it says here.
