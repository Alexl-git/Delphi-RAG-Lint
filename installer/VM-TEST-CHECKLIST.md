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

If the VM has no PowerShell 7, do pass A first without it, then install it
(https://aka.ms/powershell) and do pass B.

## Pass A -- "Just for me", everything ticked (default)

1. Run `drag-lint-setup-<version>.exe`. Choose **Just for me**.
2. **Components page:** the four IDE plugin lines are greyed out and say
   "RAD Studio 13 not found" / "64-bit IDE not found". Everything else is ticked.
3. **Without PowerShell 7:** a page says "PowerShell 7 was not found" and setup
   continues. With it, that page does not appear.
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

7. Charts (needs PowerShell 7):

   ```
   pwsh -File .\Ask-Report.ps1 -List
   ```

   then one question against the sample index; the SVG/HTML opens and has a
   drawing (Graphviz found beside the scripts).
8. Open `drag-lint-config.exe`, `ConvRulesEditor.exe`, `drag_lint_graph.exe`,
   `..\yadf\YADF.exe --help`, `..\yadf\YADFSetup.exe`: each starts without a
   "missing DLL" or "package not found" error.
9. Registry -- only these may exist:
   * `HKCU\Software\YADF\ExePath` = `...\drag-lint\yadf\YADF.exe`
   * `HKCU\Software\Classes\draglint` and `HKCU\Software\drag-lint\Installer\ProtocolRegisteredBy`
     (only with PowerShell 7)
   * **nothing** under `HKCU\Software\Embarcadero`
   * the uninstall entry under `...\CurrentVersion\Uninstall\`
10. `draglint://` (PowerShell 7 only): `Start-Process 'draglint://open?file=C%3A%5Ctmp%5Cx.pas&line=1'`
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

## Not covered on this VM (needs RAD Studio 13)

On a machine with RAD Studio 13: plugin lines are enabled, `Known Packages`
gets one value per ticked plugin, the IDE loads both drag-lint and YADF
plugins, *drag-lint > Reports* finds `Ask-Report.ps1` beside the engine,
setup refuses while `bds.exe` runs, and uninstall removes only those values.
If the developer's own `dll-win32` plugin is registered, setup warns about the
duplicate before installing; a `/VERYSILENT` install skips that plugin and logs
"plugin slot 0 skipped" instead of registering a second copy.

## What to send back

The setup log (`/LOG=` or `%TEMP%\Setup Log *.txt`), the two `.reg` exports,
and a line per step that did something other than what it says here.
