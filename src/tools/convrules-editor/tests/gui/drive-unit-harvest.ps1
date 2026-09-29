# Driven GUI check for the Unit Rules harvest (feat/unit-harvest, 2026-09-28).
# Usage: pwsh -File drive-unit-harvest.ps1 -Exe <path\ConvRulesEditor.exe>  (a frozen drag-lint.exe beside it;
#        its Win64 library index must answer, or Forms cannot classify as "via scope").
# Builds a FIXTURE destination (Dest.dproj / Dest.dpr / Local.pas) and a fixture source unit (Src.pas) in a
# fresh temp folder, sets the Destination edit to it and commits with Enter, then asserts EXACT statuses.
# -ProofNoDestination leaves the Destination edit EMPTY instead: the status assertions must then FAIL, which
# is the proof this check can fail. Restores the clipboard and deletes the fixture on exit.
param([string]$Exe, [switch]$ProofNoDestination)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class H {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] public static extern IntPtr SendStr(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll", EntryPoint="PostMessageW")] public static extern bool Post(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool OpenClipboard(IntPtr owner);
  [DllImport("user32.dll")] public static extern bool CloseClipboard();
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] static extern IntPtr SendSB(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr w);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr got);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static List<IntPtr> Tops(uint pid) { var r = new List<IntPtr>(); EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr parent) { var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Txt(IntPtr h) { int n = (int)Send(h, 0x000E, IntPtr.Zero, IntPtr.Zero); var s = new StringBuilder(n + 2); SendSB(h, 0x000D, (IntPtr)(n + 1), s); return s.ToString(); }
  // LVM_GETITEMTEXTW across processes: LVITEMW (x64) iSubItem @8, pszText @24, cchTextMax @32.
  public static string LvText(IntPtr lv, int row, int col) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)1024, 0x3000, 0x04);
    try {
      var item = new byte[88]; UIntPtr io;
      BitConverter.GetBytes(col).CopyTo(item, 8);
      BitConverter.GetBytes((long)(mem + 512)).CopyTo(item, 24);
      BitConverter.GetBytes(255).CopyTo(item, 32);
      WriteProcessMemory(hp, mem, item, (UIntPtr)item.Length, out io);
      int n = (int)Send(lv, 0x1073, (IntPtr)row, mem);
      var t = new byte[512]; ReadProcessMemory(hp, mem + 512, t, (UIntPtr)512, out io);
      return Encoding.Unicode.GetString(t, 0, Math.Max(0, n) * 2);
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
}
'@
Add-Type -AssemblyName System.Windows.Forms
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'drive-unit-harvest.ps1 needs an STA thread for the clipboard (pwsh -File runs STA by default).' }
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Find($parent, $cls, $text) { [H]::Kids($parent) | Where-Object { [H]::Cls($_) -eq $cls -and ($null -eq $text -or [H]::Txt($_) -eq $text) } }
function LvCount($lv) { [int][H]::Send($lv, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero) }
# Text of any message box the editor raised (an unhandled exception, typically); '' when none.
function EditorDialog { @([H]::Tops($p.Id) | Where-Object { [H]::Cls($_) -eq '#32770' } | ForEach-Object { @([H]::Kids($_) | Where-Object { [H]::Cls($_) -eq 'Static' } | ForEach-Object { [H]::Txt($_) }) -join ' ' }) -join ' | ' }
# BM_CLICK is POSTED, not sent: a sent click blocks this script for as long as the
# handler runs, and forever if the handler raises a modal exception box.
function ClickPaste { Start-Sleep -Milliseconds 500; [void][H]::Post($paste[0], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
function LvRows($lv) { @(0..((LvCount $lv) - 1) | ForEach-Object { [pscustomobject]@{ Kind = [H]::LvText($lv, $_, 0); Old = [H]::LvText($lv, $_, 1); Status = [H]::LvText($lv, $_, 4) } }) }
function StatusText { if ($sb) { [H]::Txt($sb) } else { '' } }
# Waits until the status line differs from $Before and is not the transient library-load
# note, a message box appears, or the timeout passes; returns the final status text.
function WaitStatus($Before, $Seconds = 90) {
  $t0 = Get-Date; $txt = $Before; $script:dlg = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 500
    $script:dlg = EditorDialog; if ($script:dlg -ne '') { break }
    $txt = StatusText
    if ($txt -ne $Before -and $txt -notlike 'Loading unit lists*') { break }
  }
  Start-Sleep -Milliseconds 300
  StatusText
}
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }

# --- fixture: a destination the check can classify against, independent of any real tree ---
# Shape mirrors a real IDE .dproj (DMTEST.dproj): the Base / Base_Win64 activation groups, then the
# '$(Base)'!='' and '$(Base_Win64)'!='' groups that carry DCC_Namespace with $(DCC_Namespace) inheritance.
# Vcl is a Win64 scope name here, so Forms resolves as "via scope -> Vcl.Forms" on the default TO=Win64.
$fx = Join-Path ([IO.Path]::GetTempPath()) ('unit-harvest-fx-' + [guid]::NewGuid().ToString('N'))
$destDir = Join-Path $fx 'dest'; $srcDir = Join-Path $fx 'source'
[void][IO.Directory]::CreateDirectory($destDir); [void][IO.Directory]::CreateDirectory($srcDir)
$destProj = Join-Path $destDir 'Dest.dproj'
WriteAscii $destProj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{6D1C6B0E-2F3A-4C1B-9E55-0A1B2C3D4E5F}</ProjectGuid>
        <FrameworkType>VCL</FrameworkType>
        <Base>True</Base>
        <Config Condition="'$(Config)'==''">Debug</Config>
        <Platform Condition="'$(Platform)'==''">Win64</Platform>
        <AppType>Application</AppType>
        <MainSource>Dest.dpr</MainSource>
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
WriteAscii (Join-Path $destDir 'Dest.dpr') "program Dest;`n`nuses`n  Local in 'Local.pas';`n`nbegin`nend.`n"
WriteAscii (Join-Path $destDir 'Local.pas') "unit Local;`n`ninterface`n`nimplementation`n`nend.`n"
# The fixture SOURCE. FileOnlyXyz is named nowhere else, so its row can only come from the file list.
$srcUnit = Join-Path $srcDir 'Src.pas'
WriteAscii $srcUnit "unit Src;`n`ninterface`n`nuses`n  Local, Forms, NoSuchUnitXyz, FileOnlyXyz;`n`nimplementation`n`nend.`n"
$FileListUsed = 'FileOnlyXyz'

# The script overwrites the clipboard several times: copy every format the user's clipboard
# offers (text, file list, image, HTML, ...) into a DataObject now and put it back in
# the finally block. A format that cannot be read back as data is skipped.
$savedClip = New-Object System.Windows.Forms.DataObject
$userClip = [Windows.Forms.Clipboard]::GetDataObject()
if ($null -ne $userClip) { foreach ($fmt in $userClip.GetFormats($false)) { try { $d = $userClip.GetData($fmt); if ($null -ne $d) { $savedClip.SetData($fmt, $d) } } catch { } } }

$p = Start-Process $Exe -PassThru
try {
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [H]::Tops($p.Id) | Where-Object { [H]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2
  # A VCL TTabSheet creates its controls' window handles only when first shown, so the
  # Paste button has NO HWND until its tab has been active once. Walk every tab of every
  # TPageControl (TCM_SETCURFOCUS; a non-TCS_BUTTONS tab control sends TCN_SELCHANGE, which
  # the VCL turns into an ActivePage change) until a visible Paste button exists.
  $paste = @()
  $pc = @(Find $main 'TPageControl' $null)
  foreach ($c in $pc) {
    $tabs = [int][H]::Send($c, 0x1304, [IntPtr]::Zero, [IntPtr]::Zero)   # TCM_GETITEMCOUNT
    for ($i = 0; $i -lt $tabs -and $paste.Count -eq 0; $i++) {
      [void][H]::Send($c, 0x1330, [IntPtr]$i, [IntPtr]::Zero)             # TCM_SETCURFOCUS
      Start-Sleep -Milliseconds 300
      $paste = @(Find $main 'TButton' 'Paste' | Where-Object { [H]::IsWindowVisible($_) })
    }
  }
  Check 'unitrules.has.paste.button' ($paste.Count -eq 1) "found=$($paste.Count)"
  if ($paste.Count -ne 1) { return }
  $sb = Find $main 'TStatusBar' $null | Select-Object -First 1

  # --- 0. set the destination explicitly and commit it with Enter (ruling R18) ---
  # The Destination row is the one plain TPanel holding a '...' button and a TEdit (the
  # folder mask's '...' sits in a TFlowPanel).
  $destEdit = @(Find $main 'TButton' '...' | ForEach-Object { [H]::GetParent($_) } | Where-Object { [H]::Cls($_) -eq 'TPanel' } |
    ForEach-Object { Find $_ 'TEdit' $null } | Select-Object -First 1)
  Check 'dest.edit.found' ($destEdit.Count -eq 1) "found=$($destEdit.Count)"
  if ($destEdit.Count -ne 1) { return }
  $destValue = if ($ProofNoDestination) { '' } else { $destProj }
  [void][H]::SendStr($destEdit[0], 0x000C, [IntPtr]::Zero, $destValue)          # WM_SETTEXT
  $sbBefore = StatusText
  [void][H]::Post($destEdit[0], 0x0102, [IntPtr]13, [IntPtr]::Zero)               # WM_CHAR Enter
  if ($ProofNoDestination) {
    "NOTE  -ProofNoDestination: Destination left EMPTY; the status assertions below are expected to FAIL"
    Start-Sleep -Seconds 1
  } else {
    $sbText = WaitStatus $sbBefore
    # Not '[!] ...': a library list that failed to load would say so through SetError.
    Check 'dest.enter.commits' ($sbText -like 'Destination: Dest.dproj (Win64).*') "$sbText$(if ($dlg) { "; editor dialog: $dlg" })"
  }

  # --- 1. text paste: exact classification against the fixture destination ---
  $lvs = @(Find $main 'TListView' $null)
  $before = @{}; foreach ($lv in $lvs) { $before[$lv] = LvCount $lv }
  [Windows.Forms.Clipboard]::SetText('uses Local, Forms, NoSuchUnitXyz;')
  $sbBefore = StatusText
  ClickPaste
  $list = $null; $dlg = ''; $t0 = Get-Date
  while ($null -eq $list -and $dlg -eq '' -and ((Get-Date) - $t0).TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500; $dlg = EditorDialog; foreach ($lv in $lvs) { if ((LvCount $lv) -ge $before[$lv] + 2) { $list = $lv } } }
  Check 'paste.adds.rows' ($null -ne $list) $(if ($dlg) { "editor dialog: $dlg" })
  if ($null -eq $list) { return }
  $sbText = WaitStatus $sbBefore
  $rows = LvRows $list
  $ns = $rows | Where-Object { $_.Old -eq 'NoSuchUnitXyz' } | Select-Object -First 1
  $fm = $rows | Where-Object { $_.Old -eq 'Forms' } | Select-Object -First 1
  Check 'paste.row.nosuch' ($null -ne $ns -and $ns.Kind -eq '(used)') ($rows | Out-String)
  Check 'paste.row.nosuch.status' ($null -ne $ns -and $ns.Status -ceq 'MISSING') "$($ns.Status)"
  Check 'paste.row.forms.status' ($null -ne $fm -and $fm.Status -ceq 'via scope -> Vcl.Forms') "$($fm.Status)"
  Check 'paste.row.local.not.listed' (@($rows | Where-Object { $_.Old -eq 'Local' }).Count -eq 0) '(a destination member; Find missing is ON)'
  # Exact: any destination note ("Unclassified: ...", "Library list unavailable ...") fails it.
  Check 'paste.status.clean' ($sbText -ceq 'Pasted text: 3 used unit(s), 3 new; 3 in the list.') $sbText
  Check 'paste.text.no.filelist.row' (@($rows | Where-Object { $_.Old -eq $FileListUsed }).Count -eq 0) "(precondition: $FileListUsed must come only from the file list)"

  # --- 2. copied Explorer file list (CF_HDROP branch of DoPasteUnits) ---
  $drop = New-Object System.Collections.Specialized.StringCollection
  [void]$drop.Add($srcUnit)
  [Windows.Forms.Clipboard]::SetFileDropList($drop)
  ClickPaste
  $fl = $null; $dlg = ''; $sbText = ''; $t0 = Get-Date
  # Stop early on a status-line error ('[!] ...') or a message box: both mean no rows are coming.
  while ($null -eq $fl -and $dlg -eq '' -and -not $sbText.StartsWith('[!]') -and ((Get-Date) - $t0).TotalSeconds -lt 90) {
    Start-Sleep -Milliseconds 500
    $dlg = EditorDialog
    $sbText = StatusText
    $fl = LvRows $list | Where-Object { $_.Old -eq $FileListUsed } | Select-Object -First 1
  }
  Start-Sleep -Milliseconds 500   # the handler writes the status line after the rows
  $sbText = StatusText
  Check 'filelist.row.fileonly' ($null -ne $fl -and $fl.Kind -eq '(used)' -and $fl.Status -ceq 'MISSING') "status=$($fl.Status); status bar: $sbText$(if ($dlg) { "; editor dialog: $dlg" })"
  Check 'filelist.status.one.file' ($sbText -ceq '1 source file(s): 4 used unit(s), 1 new; 4 in the list.') $sbText

  # --- 3. clipboard held open by another process ---
  # OpenClipboard fails while someone else has it open; the editor must say so on the
  # status line, not raise a modal "Cannot open clipboard" exception box.
  $held = [H]::OpenClipboard([IntPtr]::Zero)
  Check 'busy.clipboard.held' $held
  if (-not $held) { return }
  try {
    $sbBefore = StatusText
    ClickPaste
    $dlg = ''; $sbText = $sbBefore; $t0 = Get-Date
    while ($dlg -eq '' -and $sbText -eq $sbBefore -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 500; $dlg = EditorDialog; $sbText = StatusText }
  } finally { [void][H]::CloseClipboard() }
  Check 'busy.no.dialog' ($dlg -eq '') "editor dialog: $dlg"
  Check 'busy.status.error' ($sbText -like '`[!`] Paste:*clipboard open*') $sbText

  # --- 4. the destination is re-read on every harvest (ruling R13) ---
  # LateUnit is MISSING; copy it into the destination; the SAME paste must now find it.
  [Windows.Forms.Clipboard]::SetText('uses LateUnit;')
  $sbBefore = StatusText
  ClickPaste
  $sbText = WaitStatus $sbBefore
  $late = LvRows $list | Where-Object { $_.Old -eq 'LateUnit' } | Select-Object -First 1
  Check 'late.before.missing' ($null -ne $late -and $late.Status -ceq 'MISSING') "status=$($late.Status); status bar: $sbText"
  WriteAscii (Join-Path $destDir 'LateUnit.pas') "unit LateUnit;`n`ninterface`n`nimplementation`n`nend.`n"
  $sbBefore = StatusText
  ClickPaste
  $sbText = WaitStatus $sbBefore
  Check 'late.after.not.listed' (@(LvRows $list | Where-Object { $_.Old -eq 'LateUnit' }).Count -eq 0) "(now project, and Find missing is ON); status bar: $sbText"
  # Untick Find missing: every row shows, so LateUnit's status can be read. A check box
  # only re-filters, it never reclassifies.
  $fmChk = @(Find $main 'TCheckBox' 'Find missing')
  Check 'findmissing.found' ($fmChk.Count -eq 1) "found=$($fmChk.Count)"
  if ($fmChk.Count -ne 1) { return }
  [void][H]::Post($fmChk[0], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  $late = $null; $t0 = Get-Date
  while ($null -eq $late -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 500; $late = LvRows $list | Where-Object { $_.Old -eq 'LateUnit' } | Select-Object -First 1 }
  Check 'late.after.project' ($null -ne $late -and $late.Status -ceq 'project') "status=$($late.Status)"
  $loc = LvRows $list | Where-Object { $_.Old -eq 'Local' } | Select-Object -First 1
  Check 'local.project.when.all.listed' ($null -ne $loc -and $loc.Status -ceq 'project') "status=$($loc.Status)"
} finally {
  if (-not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(10000) }
  if ($savedClip.GetFormats().Count -gt 0) { [Windows.Forms.Clipboard]::SetDataObject($savedClip, $true) } else { [Windows.Forms.Clipboard]::Clear() }
  try { Remove-Item -LiteralPath $fx -Recurse -Force } catch { "WARN  fixture not removed: $fx -- $($_.Exception.Message)" }
  "gui: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
