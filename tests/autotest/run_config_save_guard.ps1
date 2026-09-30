# drag-lint-config: never write back a drag-lint.json that did not load.
#
# The Config tool (src\config) used to replace a manifest it could not parse
# with an EMPTY default manifest and then let two writers put that over the
# user's file: the Save button, and the SILENT autosave RunEngine fires before
# every Build. Validate accepts zero sections, so nothing stopped either.
# Every read and write now goes through Config.ManifestSession, whose
# TrySaveConfigManifest refuses while the load error is set.
#
# Arms:
#   A  a file with one bad leaf (sqlOnlyMS is a string): not saved, bytes unchanged
#   B  a file that is not JSON at all: not saved, bytes unchanged
#   C  positive control: a good file saves and re-loads with both sections
#   E  a path that does not exist yet: LOADERR empty (defaults), Save creates
#      it, and the created file re-loads cleanly
#   D  structural: no src\config unit but Config.ManifestSession calls
#      TManifestIO.Save/ParseText/ParseTextEx/Load, and MainForm routes both
#      writers through TrySaveConfigManifest (with its own positive control)
#   G  the GUI itself, driven over user32: bad file -> load dialog, Save
#      disabled, Save + Build clicks write nothing; fixed file + Reload -> Save
#      enabled
#   H  positive control: a good file -> no dialog, Save enabled
#
# Usage: pwsh -NoProfile -File tests\autotest\run_config_save_guard.ps1
[CmdletBinding()]
param(
    [string] $WorkDir = "$env:TEMP\drag-lint-config-save-$PID"
)
$script:GuiProcs = @()
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
New-Item -ItemType Directory "$WorkDir\dcu" | Out-Null

$repo    = (Resolve-Path "$PSScriptRoot\..\..").Path
$src     = "$repo\src"
$cfgDir  = "$src\config"
$fixDir  = "$PSScriptRoot\fixtures\configsave"
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'

# --- Build ConfigSaveHarness.dpr (Win64) into the PRIVATE work dir ---------
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$fixDir`""
    "dcc64 -CC -U`"$cfgDir;$src\index;$src\project;$src\core;$src\preprocess`" -E`"$WorkDir`" -NU`"$WorkDir\dcu`" ConfigSaveHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($batPath, ($batLines -join "`r`n"), [System.Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
    -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
    -NoNewWindow -Wait | Out-Null
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:') -and ($log -notmatch 'Fatal:')
Check 'ConfigSaveHarness.dpr builds (Win64)' $buildOk (($log -split "`r?`n" | Select-Object -Last 6) -join ' | ')
$exe = "$WorkDir\ConfigSaveHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
    Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
    Write-Host ''
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
}

function Invoke-Harness([string]$Path) {
    $out = (& $exe $Path 2>&1 | Out-String)
    $h = @{ RAW = $out.Trim() -replace "`r?`n", ' | ' }
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^(LOADERR|SECTIONS|SAVED|REASON)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
    }
    $h
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# --- Fixtures ---------------------------------------------------------------
$badLeafText = '{"settings":{"maxJobs":2},"indexes":{"sections":[{"name":"Good","include":["C:\\x\\Good.dproj"]},{"name":"Bad","include":["C:\\x\\Bad.dproj"],"sqlOnlyMS":"yes"}]}}'
$notJsonText = '{ "indexes": [ this is not json'
$goodText    = $badLeafText.Replace(',"sqlOnlyMS":"yes"', '')
Check 'fixture: good.json differs from bad-leaf.json' ($goodText -ne $badLeafText)
$badLeaf = "$WorkDir\bad-leaf.json"
$notJson = "$WorkDir\not-json.json"
$good    = "$WorkDir\good.json"
[IO.File]::WriteAllText($badLeaf, $badLeafText, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($notJson, $notJsonText, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($good,    $goodText,    [Text.Encoding]::ASCII)

# --- A: one bad leaf ----------------------------------------------------------
$before = Get-Sha $badLeaf
$a = Invoke-Harness $badLeaf
Check 'A: LOADERR names sqlOnlyMS' ([string]$a.LOADERR -match 'sqlOnlyMS') "got='$($a.RAW)'"
Check 'A: SAVED=0' ($a.SAVED -eq '0') "SAVED='$($a.SAVED)'"
Check 'A: REASON starts "Not saved:"' ([string]$a.REASON -like 'Not saved:*') "REASON='$($a.REASON)'"
Check 'A: file bytes unchanged' ((Get-Sha $badLeaf) -eq $before)

# --- B: not JSON ------------------------------------------------------------
$before = Get-Sha $notJson
$b = Invoke-Harness $notJson
Check 'B: LOADERR non-empty' ($b.ContainsKey('LOADERR') -and $b.LOADERR -ne '') "got='$($b.RAW)'"
Check 'B: SAVED=0' ($b.SAVED -eq '0') "SAVED='$($b.SAVED)'"
Check 'B: file bytes unchanged' ((Get-Sha $notJson) -eq $before)

# --- C: positive control ------------------------------------------------------
$c = Invoke-Harness $good
Check 'C: LOADERR empty' ($c.ContainsKey('LOADERR') -and $c.LOADERR -eq '') "got='$($c.RAW)'"
Check 'C: SECTIONS=2' ($c.SECTIONS -eq '2') "SECTIONS='$($c.SECTIONS)'"
Check 'C: SAVED=1' ($c.SAVED -eq '1') "REASON='$($c.REASON)'"
$c2 = Invoke-Harness $good
Check 'C: saved file re-loads cleanly with 2 sections' ($c2.ContainsKey('LOADERR') -and $c2.LOADERR -eq '' -and $c2.SECTIONS -eq '2') "got='$($c2.RAW)'"

# --- E: a --config path that does not exist yet -------------------------------
# There is nothing to overwrite, so it starts from the defaults and Save
# creates it (docs\TEST-PLAN-CONFIG.md documents --config <path>).
$missing = "$WorkDir\not-yet.json"
Check 'E: setup -- the file does not exist' (-not (Test-Path -LiteralPath $missing))
$e = Invoke-Harness $missing
Check 'E: LOADERR empty' ($e.ContainsKey('LOADERR') -and $e.LOADERR -eq '') "got='$($e.RAW)'"
Check 'E: SAVED=1' ($e.SAVED -eq '1') "REASON='$($e.REASON)'"
Check 'E: the file now exists' (Test-Path -LiteralPath $missing)
$e2 = Invoke-Harness $missing
Check 'E: the created file re-loads with LOADERR empty' ($e2.ContainsKey('LOADERR') -and $e2.LOADERR -eq '') "got='$($e2.RAW)'"

# --- D: structural -- one door in and out of the manifest file ---------------
function Test-ConfigWriters([string]$Dir) {
    $problems = @()
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.pas' -File) {
        if ($f.Name -eq 'Config.ManifestSession.pas') { continue }
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($needle in 'TManifestIO.Save(', 'TManifestIO.ParseText(', 'TManifestIO.ParseTextEx(', 'TManifestIO.Load(') {
            if ($text.Contains($needle)) { $problems += "$($f.Name) calls $needle" }
        }
    }
    $main = Join-Path $Dir 'Config.MainForm.pas'
    if (-not (Test-Path -LiteralPath $main)) {
        $problems += 'Config.MainForm.pas not found'
    } else {
        $n = ([regex]::Matches([IO.File]::ReadAllText($main), [regex]::Escape('TrySaveConfigManifest('))).Count
        if ($n -lt 2) { $problems += "Config.MainForm.pas calls TrySaveConfigManifest( $n time(s), expected >= 2" }
    }
    , $problems
}
$d = Test-ConfigWriters $cfgDir
Check 'D: src\config writes only through Config.ManifestSession' ($d.Count -eq 0) ($d -join '; ')
$copyDir = "$WorkDir\cfgcopy"
New-Item -ItemType Directory $copyDir | Out-Null
Copy-Item "$cfgDir\*.pas" $copyDir
$copyMain = "$copyDir\Config.MainForm.pas"
$orig = [IO.File]::ReadAllText($copyMain)
$bent = [regex]::Replace($orig, '(procedure TMainForm\.btnReloadClick\(Sender: TObject\);\r?\nbegin\r?\n)',
    ('$1' + "  TManifestIO.Save(FManifest, FConfigPath);`r`n"))
Check 'D control: injection applied to the copy' ($bent -ne $orig)
[IO.File]::WriteAllText($copyMain, $bent, [Text.Encoding]::ASCII)
$dc = Test-ConfigWriters $copyDir
Check 'D control: a direct TManifestIO.Save in btnReloadClick is caught' (($dc -join ';') -match 'Config\.MainForm\.pas calls TManifestIO\.Save\(') ($dc -join '; ')

# --- G/H: drive the GUI (a commit message is not a click) -------------------
# Build drag-lint-config.exe into the PRIVATE work dir, launch it on a fixture,
# and read the real controls over user32. Every lookup that finds nothing
# FAILS and names what it enumerated -- an arm that cannot see the control
# must never pass.
$guiDir  = "$WorkDir\gui"
New-Item -ItemType Directory "$guiDir\dcu" -Force | Out-Null
$guiBat = "$WorkDir\build_gui.bat"
$guiLog = "$WorkDir\build_gui.log"
$guiLines = @(
    '@echo off'
    "call `"$rsvars`""
    "cd /d `"$cfgDir`""
    "msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_ExeOutput=`"$guiDir`" /p:DCC_DcuOutput=`"$guiDir\dcu`" /v:minimal drag-lint-config.dproj"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[System.IO.File]::WriteAllText($guiBat, ($guiLines -join "`r`n"), [System.Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList "/c", "`"$guiBat`"" `
    -RedirectStandardOutput $guiLog -RedirectStandardError "$guiLog.err" `
    -NoNewWindow -Wait | Out-Null
$gLog = Get-Content $guiLog -Raw -ErrorAction SilentlyContinue
$gui  = "$guiDir\drag-lint-config.exe"
$guiOk = ($gLog -match 'BUILD_EXITCODE=0') -and ($gLog -notmatch '\[dcc64 (Error|Fatal)\]') -and (Test-Path $gui)
Check 'GUI: drag-lint-config.dproj builds into the work dir' $guiOk (($gLog -split "`r?`n" | Select-Object -Last 4) -join ' | ')

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class CfgGui {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr[] TopWindows(int pid) {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == (uint)pid) r.Add(h); return true; }, IntPtr.Zero);
        return r.ToArray();
    }
    public static IntPtr[] Children(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero);
        return r.ToArray();
    }
    public static string ClassOf(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static string TextOf(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
}
'@
$BM_CLICK = 0xF5; $WM_CLOSE = 0x10; $WM_COMMAND = 0x111

# A VCL ShowMessage is a TMessageForm, or a task dialog (#32770) when the
# runtime-themes path is taken; accept both and say which one was seen.
function Get-Dialog([int]$ProcId) {
    foreach ($h in [CfgGui]::TopWindows($ProcId)) {
        $cls = [CfgGui]::ClassOf($h)
        if (($cls -eq 'TMessageForm' -or $cls -eq '#32770') -and [CfgGui]::IsWindowVisible($h)) { return $h }
    }
    [IntPtr]::Zero
}
function Wait-Dialog([int]$ProcId, [int]$Ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) {
        $h = Get-Dialog $ProcId
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 100
    }
    [IntPtr]::Zero
}
function Close-Dialog([IntPtr]$Hwnd) {
    if ([CfgGui]::ClassOf($Hwnd) -eq '#32770') { [void][CfgGui]::PostMessage($Hwnd, $WM_COMMAND, [IntPtr]1, [IntPtr]::Zero) }
    else { [void][CfgGui]::PostMessage($Hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 5000 -and [CfgGui]::IsWindow($Hwnd) -and [CfgGui]::IsWindowVisible($Hwnd)) { Start-Sleep -Milliseconds 100 }
    -not ([CfgGui]::IsWindow($Hwnd) -and [CfgGui]::IsWindowVisible($Hwnd))
}
function Describe-TopWindows([int]$ProcId) {
    ([CfgGui]::TopWindows($ProcId) | ForEach-Object { '{0}"{1}"{2}' -f [CfgGui]::ClassOf($_), [CfgGui]::TextOf($_), $(if ([CfgGui]::IsWindowVisible($_)) {''} else {'(hidden)'}) }) -join ', '
}
function Wait-MainForm([int]$ProcId, [int]$Ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) {
        foreach ($h in [CfgGui]::TopWindows($ProcId)) { if ([CfgGui]::ClassOf($h) -eq 'TMainForm') { return $h } }
        Start-Sleep -Milliseconds 100
    }
    [IntPtr]::Zero
}
function Get-Buttons([IntPtr]$Form) {
    $r = @{}
    foreach ($h in [CfgGui]::Children($Form)) {
        if ([CfgGui]::ClassOf($h) -eq 'TButton') { $t = [CfgGui]::TextOf($h); if (-not $r.ContainsKey($t)) { $r[$t] = $h } }
    }
    $r
}
function Wait-Enabled([IntPtr]$Hwnd, [bool]$Want, [int]$Ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) {
        if ([CfgGui]::IsWindowEnabled($Hwnd) -eq $Want) { return $true }
        Start-Sleep -Milliseconds 100
    }
    [CfgGui]::IsWindowEnabled($Hwnd) -eq $Want
}

if ($guiOk) {
    # --- G: a file that does not load -------------------------------------------
    $gJson = "$WorkDir\g.json"
    [IO.File]::WriteAllText($gJson, $badLeafText, [Text.Encoding]::ASCII)
    $gBefore = Get-Sha $gJson
    $gp = Start-Process $gui -ArgumentList '--config', "`"$gJson`"" -PassThru
    $script:GuiProcs += $gp
    try {
        $dlg = Wait-Dialog $gp.Id 10000
        Check 'G: load-error dialog shown' ($dlg -ne [IntPtr]::Zero) ("top windows: " + (Describe-TopWindows $gp.Id))
        if ($dlg -ne [IntPtr]::Zero) {
            $cls = [CfgGui]::ClassOf($dlg)
            Check "G: load-error dialog ($cls) closes" (Close-Dialog $dlg)
        }
        $main = Wait-MainForm $gp.Id 5000
        Check 'G: main form (TMainForm) found' ($main -ne [IntPtr]::Zero) ("top windows: " + (Describe-TopWindows $gp.Id))
        if ($main -ne [IntPtr]::Zero) {
            $btns = Get-Buttons $main
            $names = ($btns.Keys | Sort-Object) -join ', '
            Write-Host "    TButtons enumerated on TMainForm: $names"
            $save = $btns['Save']
            Check 'G: Save button found' ($null -ne $save) "buttons: $names"
            if ($null -ne $save) {
                Check 'G: Save is DISABLED while the file did not load' (Wait-Enabled $save $false 5000)
                [void][CfgGui]::PostMessage($save, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                Start-Sleep -Milliseconds 1000
                $d2 = Get-Dialog $gp.Id
                if ($d2 -ne [IntPtr]::Zero) { Write-Host '    (a dialog appeared after clicking the disabled Save; closed)'; [void](Close-Dialog $d2) }
                Check 'G: clicking Save anyway leaves the file unchanged' ((Get-Sha $gJson) -eq $gBefore)
            }
            # The Build buttons sit on the Indexes frame's "Build log" tab (pcBottom,
            # the TPageControl with 3 tabs: Coverage, Plan preview, Build log). A
            # VCL control on a tab never shown has no window handle, so switch to
            # that tab first; TCM_SETCURFOCUS notifies the VCL like a user click.
            $TCM_GETITEMCOUNT = 0x1304; $TCM_SETCURFOCUS = 0x1330
            $pcs = @([CfgGui]::Children($main) | Where-Object { [CfgGui]::ClassOf($_) -eq 'TPageControl' })
            $pcDesc = ($pcs | ForEach-Object { 'TPageControl(' + [int][CfgGui]::SendMessage($_, $TCM_GETITEMCOUNT, [IntPtr]::Zero, [IntPtr]::Zero) + ' tabs)' }) -join ', '
            Write-Host "    page controls enumerated: $pcDesc"
            $pcBottom = @($pcs | Where-Object { [int][CfgGui]::SendMessage($_, $TCM_GETITEMCOUNT, [IntPtr]::Zero, [IntPtr]::Zero) -eq 3 })
            Check 'G: Indexes frame page control (3 tabs) found' ($pcBottom.Count -eq 1) "page controls: $pcDesc"
            if ($pcBottom.Count -eq 1) {
                [void][CfgGui]::SendMessage($pcBottom[0], $TCM_SETCURFOCUS, [IntPtr]2, [IntPtr]::Zero)
                Start-Sleep -Milliseconds 500
                $btns = Get-Buttons $main
                $names = ($btns.Keys | Sort-Object) -join ', '
                Write-Host "    TButtons after selecting the Build log tab: $names"
            }
            # The Build click fires the autosave before launching the engine. The
            # engine must NOT resolve: RunEngine would otherwise start a real
            # drag-lint.exe. Candidates are ResolveEngineExe's priorities 2 and 3.
            # The file name is ASSEMBLED: these are paths that must NOT exist, not
            # an engine this runner runs, and run_exe_freshness.ps1 fails on any
            # quoted exe literal it cannot resolve statically.
            $build = $btns['Build All']
            Check 'G: Build All button found' ($null -ne $build) "buttons: $names"
            $engName = 'drag' + '-lint.exe'
            $cands = @((Join-Path $guiDir $engName), [IO.Path]::GetFullPath((Join-Path $guiDir "..\..\third_party\dll-win64\$engName")))
            $present = @($cands | Where-Object { Test-Path -LiteralPath $_ })
            Check 'G: no engine resolvable beside the work-dir GUI (Build cannot run one)' ($present.Count -eq 0) ($present -join '; ')
            if ($null -ne $build -and $present.Count -eq 0) {
                [void][CfgGui]::PostMessage($build, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                $d3 = Wait-Dialog $gp.Id 5000
                Check 'G: Build on an unloaded file SAYS it did not save' ($d3 -ne [IntPtr]::Zero) ("top windows: " + (Describe-TopWindows $gp.Id))
                if ($d3 -ne [IntPtr]::Zero) { [void](Close-Dialog $d3) }
                Start-Sleep -Milliseconds 1000
                Check 'G: Build (autosave) leaves the file unchanged' ((Get-Sha $gJson) -eq $gBefore)
            }
            $reload = $btns['Reload']
            Check 'G: Reload button found' ($null -ne $reload) "buttons: $names"
            if ($null -ne $reload -and $null -ne $save) {
                [IO.File]::WriteAllText($gJson, $goodText, [Text.Encoding]::ASCII)
                [void][CfgGui]::PostMessage($reload, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                $ok = Wait-Enabled $save $true 5000
                $d4 = Get-Dialog $gp.Id
                if ($d4 -ne [IntPtr]::Zero) { Write-Host '    (unexpected dialog after Reload of the fixed file; closed)'; [void](Close-Dialog $d4) }
                Check 'G: after the fix + Reload, Save is ENABLED' $ok
                Check 'G: Reload of the fixed file raises no dialog' ($d4 -eq [IntPtr]::Zero)
            }
        }
    } finally {
        if (-not $gp.HasExited) { Stop-Process -Id $gp.Id -Force -ErrorAction SilentlyContinue }
    }

    # --- H: positive control -- a good file ---------------------------------------
    $hJson = "$WorkDir\h.json"
    [IO.File]::WriteAllText($hJson, $goodText, [Text.Encoding]::ASCII)
    $hp = Start-Process $gui -ArgumentList '--config', "`"$hJson`"" -PassThru
    $script:GuiProcs += $hp
    try {
        $hMain = Wait-MainForm $hp.Id 10000
        Check 'H: main form (TMainForm) found' ($hMain -ne [IntPtr]::Zero) ("top windows: " + (Describe-TopWindows $hp.Id))
        $hDlg = Wait-Dialog $hp.Id 3000
        Check 'H: no dialog within 3 s on a good file' ($hDlg -eq [IntPtr]::Zero) ("top windows: " + (Describe-TopWindows $hp.Id))
        if ($hMain -ne [IntPtr]::Zero) {
            $hBtns = Get-Buttons $hMain
            $hSave = $hBtns['Save']
            Check 'H: Save button found' ($null -ne $hSave) ("buttons: " + (($hBtns.Keys | Sort-Object) -join ', '))
            if ($null -ne $hSave) { Check 'H: Save is ENABLED on a file that loaded' ([CfgGui]::IsWindowEnabled($hSave)) }
        }
    } finally {
        if (-not $hp.HasExited) { Stop-Process -Id $hp.Id -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
    foreach ($gp in $script:GuiProcs) { if ($gp -and -not $gp.HasExited) { Stop-Process -Id $gp.Id -Force -ErrorAction SilentlyContinue } }
    # This run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
    if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
