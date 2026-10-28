# Driven GUI check for STARTUP (2026-10-27): the editor answers its busy query and its menu within seconds
# of a launch that feeds the Unit Rules harvest behind the user's back (an IDE convert request: its source
# unit goes to the Convert tab, which feeds the harvest). Before the fix that feed classified the harvest at
# once, which read the WHOLE library-Win64 unit list (one engine `sql` read of a multi-GB index, 11 s warm
# and over 60 s while other sessions hold the DB) on the main thread: no busy answer, no menu, no paint.
# Now the classification waits for the Unit Rules tab (ClassifyDeferred); showing the tab classifies.
# Usage: pwsh -NoProfile -File drive-startup-responsive.ps1 -Exe <path\ConvRulesEditor.exe>
#        (a frozen drag-lint.exe beside it; its Win64 library index must answer). Run under gui-lock.ps1.
# The pre-fix exe FAILS startup.no.library.list (the RED); the pre-STARTUP2 exe FAILS startup.form.answers and
# unitrules.show.answers (the descendant sets / the library list on the main thread); the positive control
# (unitrules.classified) passes on both: the rows are classified once the list is on screen.
param([string]$Exe)
# Longest span (ms) the main thread may leave the busy query unanswered: the progress window appears after 400 ms,
# one sample waits up to 500 ms per query; a blocked load measured 6500 (sets) and 11500 (library list).
$MaxBlockedLimitMs = 2000
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class SR {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RC r);
  [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h, ref PT p);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW")] static extern IntPtr SendMessageTimeoutSB(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint ms, out IntPtr r);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr w);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr got);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static List<IntPtr> Tops(uint pid) { var r = new List<IntPtr>(); EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr parent) { var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  /* The editor's answer to a registered query, or -1 when it does not answer within 500 ms (main thread blocked). */
  public static long Ask(IntPtr main, string name) {
    IntPtr r; if (SendMessageTimeout(main, RegisterWindowMessage(name), IntPtr.Zero, IntPtr.Zero, 2, 500, out r) == IntPtr.Zero) return -1;
    return (long)r;
  }
  public static string TxtT(IntPtr h) { var s = new StringBuilder(1024); IntPtr r; SendMessageTimeoutSB(h, 0x000D, (IntPtr)1024, s, 2, 500, out r); return s.ToString(); }
  /* The LEFTMOST combo box in the second row of the top panel (the From picker): its handle, or 0. Row 2 = client y 60..100 of its parent. */
  public static IntPtr FromCombo(IntPtr main) {
    IntPtr best = IntPtr.Zero; int bestX = int.MaxValue;
    foreach (var c in Kids(main)) {
      if (Cls(c) != "TComboBox" || !IsWindowVisible(c)) continue;
      RC rc; GetWindowRect(c, out rc); PT p; p.X = rc.L; p.Y = rc.T; ScreenToClient(GetParent(c), ref p);
      if (p.Y >= 60 && p.Y <= 100 && p.X < bestX) { bestX = p.X; best = c; }
    }
    return best;
  }
  /* Click the page-control tab captioned NAME (TCM_GETITEMW / TCM_GETITEMRECT through the editor's memory). */
  public static bool ClickTab(IntPtr main, string name) {
    uint pid; GetWindowThreadProcessId(main, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)1024, 0x3000, 0x04);
    try {
      foreach (var tc in Kids(main)) {
        if (Cls(tc) != "TPageControl") continue;
        int n = (int)Send(tc, 0x1304, IntPtr.Zero, IntPtr.Zero);
        for (int i = 0; i < n; i++) {
          var item = new byte[40];
          BitConverter.GetBytes(1).CopyTo(item, 0);
          BitConverter.GetBytes((long)mem + 512).CopyTo(item, 16);
          BitConverter.GetBytes(120).CopyTo(item, 24);
          UIntPtr io; WriteProcessMemory(hp, mem, item, (UIntPtr)40, out io);
          Send(tc, 0x133C, (IntPtr)i, mem);
          var txt = new byte[240]; ReadProcessMemory(hp, mem + 512, txt, (UIntPtr)240, out io);
          string cap = Encoding.Unicode.GetString(txt); int z = cap.IndexOf('\0'); if (z >= 0) cap = cap.Substring(0, z);
          if (cap != name) continue;
          Send(tc, 0x130A, (IntPtr)i, mem);
          var rc = new byte[16]; ReadProcessMemory(hp, mem, rc, (UIntPtr)16, out io);
          int x = (BitConverter.ToInt32(rc, 0) + BitConverter.ToInt32(rc, 8)) / 2, y = (BitConverter.ToInt32(rc, 4) + BitConverter.ToInt32(rc, 12)) / 2;
          IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
          PostMessage(tc, 0x0201, (IntPtr)1, lp); PostMessage(tc, 0x0202, IntPtr.Zero, lp);
          return true;
        }
      }
      return false;
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
  /* One column of a report-view list view (LVM_GETITEMTEXTW, x64 LVITEMW: iSubItem @8, pszText @24, cchTextMax @32). */
  public static string[] Column(IntPtr lv, int sub) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)2048, 0x3000, 0x04);
    try {
      int n = (int)Send(lv, 0x1004, IntPtr.Zero, IntPtr.Zero);
      var r = new string[n];
      for (int i = 0; i < n; i++) {
        var item = new byte[88];
        BitConverter.GetBytes(sub).CopyTo(item, 8);
        BitConverter.GetBytes((long)mem + 512).CopyTo(item, 24);
        BitConverter.GetBytes(500).CopyTo(item, 32);
        UIntPtr io; WriteProcessMemory(hp, mem, item, (UIntPtr)88, out io);
        int len = (int)Send(lv, 0x1073, (IntPtr)i, mem);
        var t = new byte[Math.Max(0, len) * 2]; ReadProcessMemory(hp, mem + 512, t, (UIntPtr)t.Length, out io);
        r[i] = Encoding.Unicode.GetString(t);
      }
      return r;
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
}
'@
$script:pass = 0; $script:fail = 0
trap { $script:fail++; "FAIL  driver.crash  $($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]"; "driver crashed: $script:pass pass / $script:fail fail"; exit 1 }
. "$PSScriptRoot\vcl-atoms.ps1"; 'NOTE  ' + (VclAtomsReclaim)   # ATOMLOCK: start from a reclaimed atom table (idempotent)
function Check($name, $cond, $detail = '') { if ($cond -and $env:DRIVE_FORCE_FAIL -ne $name) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Find($parent, $cls) { [SR]::Kids($parent) | Where-Object { [SR]::Cls($_) -eq $cls } }
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
function Status($main) { $sb = @(Find $main 'TStatusBar')[0]; if ($sb) { [SR]::TxtT($sb) } else { '' } }
function Kids($procId) { @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$procId" -ErrorAction SilentlyContinue) }
function IsLibList($cl) { "$cl" -match "kind='unit'" -and "$cl" -match 'library-Win(32|64)\.sqlite' }

# Samples every ~100 ms until the editor has been responsive (busy query answers 1, menu query answers, no engine
# child) for $StableMs, or $Sec pass. Records engine children, the library unit-list read and the longest span
# in which the main thread did not answer at all.
function Watch($procId, $main, $Sec, $StableMs = 3000) {
  $r = [pscustomobject]@{ FirstResponsiveMs = $null; SettledMs = $null; MaxBlockedMs = 0; LibList = $false; LibMs = $null; Children = @() }
  $t0 = Get-Date; $okSince = $null; $blockedSince = $null; $seen = @{}
  while (((Get-Date) - $t0).TotalSeconds -lt $Sec) {
    $ms = [int]((Get-Date) - $t0).TotalMilliseconds
    $busy = [SR]::Ask($main, 'ConvRulesEditor.Busy'); $menu = [SR]::Ask($main, 'ConvRulesEditor.MainMenuHandle')
    if ($busy -lt 0) { if ($null -eq $blockedSince) { $blockedSince = $ms } ; $r.MaxBlockedMs = [Math]::Max($r.MaxBlockedMs, $ms - $blockedSince) } else { $blockedSince = $null }
    $kids = Kids $procId
    foreach ($k in $kids) {
      if (-not $seen.ContainsKey($k.ProcessId)) {
        $seen[$k.ProcessId] = $ms; $r.Children += "$ms ms: $($k.CommandLine)"
        if (IsLibList $k.CommandLine) { $r.LibList = $true; if ($null -eq $r.LibMs) { $r.LibMs = $ms } }
      }
    }
    $ok = ($busy -eq 1) -and ($menu -gt 0) -and ($kids.Count -eq 0)
    if ($ok -and $null -eq $r.FirstResponsiveMs) { $r.FirstResponsiveMs = $ms }
    if ($ok) { if ($null -eq $okSince) { $okSince = $ms } elseif ($ms - $okSince -ge $StableMs) { $r.SettledMs = $okSince; break } } else { $okSince = $null }
    Start-Sleep -Milliseconds 100
  }
  $r
}

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }

# --- fixture: the drive-convert-request.ps1 project (Fix.dproj / Fix.dpr / FixUnit), one rule book, one request ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('startup-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'
WriteAscii $dproj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{6D1C6B0E-2F3A-4C1B-9E55-0A1B2C3D4E5F}</ProjectGuid>
        <FrameworkType>VCL</FrameworkType>
        <Base>True</Base>
        <Config Condition="'$(Config)'==''">Debug</Config>
        <Platform Condition="'$(Platform)'==''">Win64</Platform>
        <AppType>Application</AppType>
        <MainSource>Fix.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Base)'=='true') or '$(Base_Win64)'!=''">
        <Base_Win64>true</Base_Win64>
        <CfgParent>Base</CfgParent>
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base)'!=''">
        <DCC_Namespace>System;Xml;Data;$(DCC_Namespace)</DCC_Namespace>
        <DCC_UnitSearchPath>.\;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base_Win64)'!=''">
        <DCC_Namespace>Winapi;System.Win;Vcl;$(DCC_Namespace)</DCC_Namespace>
    </PropertyGroup>
</Project>
'@
WriteAscii (Join-Path $tmp 'Fix.dpr') "program Fix;`n`nuses`n  Vcl.Forms,`n  FixUnit in 'FixUnit.pas' {FixForm};`n`nbegin`n  Application.Initialize;`n  Application.Run;`nend.`n"
WriteAscii $pas "unit FixUnit;`n`ninterface`n`nuses`n  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;`n`ntype`n  TFixForm = class(TForm)`n    Label1: TLabel;`n  end;`n`nvar`n  FixForm: TFixForm;`n`nimplementation`n`n{`$R *.dfm}`n`nend.`n"
WriteAscii $dfm "object FixForm: TFixForm`n  Caption = 'Fix'`n  object Label1: TLabel`n    Caption = 'one'`n  end`nend`n"
WriteAscii (Join-Path $rulesDir 'Fix.rules') "#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls`n#link Caption <- Caption`n"
$req = Join-Path $tmp 'req.json'
$r = [ordered]@{ schema = 'convert-request/1'; written = (Get-Date -Format s); source = 'gui-driver'; ide_pid = $PID
  scope = 'selected'; project_file = $dproj; project_db = $db; platform = 'Win64'; rules_folder = $rulesDir
  units = @(@{ pas = $pas; dfm = $dfm; form_class = 'TFixForm'; components = @(@{ name = 'Label1'; type = 'TLabel' }) }) }
[IO.File]::WriteAllText($req, ($r | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

$p = $null
try {
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  Check 'fixture.index' (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $db)) "exit=$LASTEXITCODE"

  $t0 = Get-Date
  $p = Start-Process $Exe -ArgumentList "--convert-request `"$req`" --form `"$pas`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 100; $m = [SR]::Tops($p.Id) | Where-Object { [SR]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  $windowMs = [int]((Get-Date) - $t0).TotalMilliseconds
  Check 'main.window' ($main -ne [IntPtr]::Zero) "after $windowMs ms"
  if ($main -eq [IntPtr]::Zero) { return }

  # --- 1. the launch: request -> Convert tab -> harvest feed. Responsive, no library unit list. ---
  $w = Watch $p.Id $main 240
  $w.Children | ForEach-Object { "INFO  child $_" }
  "INFO  first responsive $($w.FirstResponsiveMs) ms, settled $($w.SettledMs) ms after the window ($windowMs ms after launch); longest unanswered span $($w.MaxBlockedMs) ms"
  Check 'startup.settled' ($null -ne $w.SettledMs) "settled=$($w.SettledMs) ms"
  Check 'startup.no.library.list' (-not $w.LibList) "(library unit list read at $($w.LibMs) ms)"
  # STARTUP2: the --form start-up's TControl/TComponent/TPersistent descendant sets (~6.5 s on library-Win64) ran on
  # the main thread with no answer at all; they now run behind the progress window, whose modal loop keeps answering
  # (busy = 2). The pre-STARTUP2 exe FAILS this (the RED): ~6500 ms unanswered.
  Check 'startup.form.answers' ($w.MaxBlockedMs -lt $MaxBlockedLimitMs) "longest unanswered span $($w.MaxBlockedMs) ms (limit $MaxBlockedLimitMs; descendant sets of --form included)"
  $st = Status $main
  "INFO  status: $st"

  # --- 2. positive control: showing the Unit Rules tab classifies the fed harvest (the list is loaded now). ---
  [void][SR]::ClickTab($main, 'Unit Rules')
  $w2 = Watch $p.Id $main 240
  $w2.Children | ForEach-Object { "INFO  child (tab) $_" }
  # "Find missing" (on by default) hides classified library rows: switch it off so every harvested row is listed.
  $chk = @(Find $main 'TCheckBox' | Where-Object { [SR]::TxtT($_) -eq 'Find missing' })[0]
  if ($chk -and [int][SR]::Send($chk, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1) { [void][SR]::PostMessage($chk, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 800 }   # BM_GETCHECK / BM_CLICK
  # A harvested row is Kind '(used)', Old = the unit, Status in column 4.
  $lv = @(Find $main 'TListView' | Where-Object { [SR]::IsWindowVisible($_) -and ([SR]::Column($_, 0) -contains '(used)') })[0]
  $stat = '(no harvest row)'
  if ($lv) { $kinds = [SR]::Column($lv, 0); $names = [SR]::Column($lv, 1); $stats = [SR]::Column($lv, 4); for ($i = 0; $i -lt $names.Count; $i++) { if ($kinds[$i] -eq '(used)' -and $names[$i] -eq 'Vcl.StdCtrls') { $stat = $stats[$i] } } }
  Check 'unitrules.harvest.fed' ($stat -ne '(no harvest row)') "(the request unit's uses reached the Unit Rules list; Find missing box found=$($null -ne $chk))"
  Check 'unitrules.classified' ($stat -in 'library', 'project' -or $stat -like 'via scope*') "Vcl.StdCtrls status='$stat'; status line: $(Status $main)"
  "INFO  tab show: library list read=$($w2.LibList), settled $($w2.SettledMs) ms, longest unanswered span $($w2.MaxBlockedMs) ms"
  # STARTUP2: showing the tab reads the Win64 library unit list (11.5 s); it now runs behind the progress window
  # (Cancel works), so the editor keeps answering. The pre-STARTUP2 exe FAILS this (the RED).
  Check 'unitrules.show.answers' ($w2.LibList -and $w2.MaxBlockedMs -lt $MaxBlockedLimitMs) "library list read=$($w2.LibList), longest unanswered span $($w2.MaxBlockedMs) ms (limit $MaxBlockedLimitMs)"

  # --- 3. LIBDESC: dropping the From picker loads the class lists (library-wide TComponent / TControl descendants).
  # They used to run on the main thread (no answer at all); now behind the progress window. The pre-LIBDESC exe FAILS this (the RED).
  $cb = [SR]::FromCombo($main)
  Check 'classes.combo.found' ($cb -ne [IntPtr]::Zero) 'the From picker (leftmost combo of row 2)'
  if ($cb -ne [IntPtr]::Zero) {
    [void][SR]::PostMessage($cb, 0x014F, [IntPtr]1, [IntPtr]::Zero)   # CB_SHOWDROPDOWN -> CBN_DROPDOWN -> CbLoadClasses
    Start-Sleep -Milliseconds 300
    $w3 = Watch $p.Id $main 240
    $w3.Children | ForEach-Object { "INFO  child (classes) $_" }
    "INFO  class lists: settled $($w3.SettledMs) ms, longest unanswered span $($w3.MaxBlockedMs) ms; status: $(Status $main)"
    Check 'classes.engine.ran' (@($w3.Children).Count -gt 0) "engine children seen: $(@($w3.Children).Count)"
    Check 'classes.load.answers' (@($w3.Children).Count -gt 0 -and $w3.MaxBlockedMs -lt $MaxBlockedLimitMs) "longest unanswered span $($w3.MaxBlockedMs) ms (limit $MaxBlockedLimitMs)"
    Check 'classes.loaded' ((Status $main) -like '*classes available*') "status: $(Status $main)"
  }
} finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
"gui-startup-responsive: $script:pass pass / $script:fail fail"
if ($script:fail -gt 0) { exit 1 }
