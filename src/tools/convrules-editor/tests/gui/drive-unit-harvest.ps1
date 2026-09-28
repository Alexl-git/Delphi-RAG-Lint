# Driven GUI check for the Unit Rules harvest (feat/unit-harvest, 2026-09-28).
# Usage: pwsh -File drive-unit-harvest.ps1 -Exe <path\ConvRulesEditor.exe>  (a frozen drag-lint.exe beside it).
# Needs C:\Projects\DB\ORM3\CLIENT\DM\dmCPData.pas (file-list case). Restores the clipboard on exit.
param([string]$Exe)
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
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
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

# The file-list case needs a real unit with a known uses clause. dmCPData.pas uses
# PathToData, which the text paste below never adds, so a PathToData row can only
# have come from the CF_HDROP branch of DoPasteUnits (Task 7).
$FileListUnit = 'C:\Projects\DB\ORM3\CLIENT\DM\dmCPData.pas'
$FileListUsed = 'PathToData'

# The script overwrites the clipboard twice: copy every format the user's clipboard
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

  # --- 1. text paste (Task 5) ---
  $lvs = @(Find $main 'TListView' $null)
  $before = @{}; foreach ($lv in $lvs) { $before[$lv] = LvCount $lv }
  [Windows.Forms.Clipboard]::SetText('uses Forms, NoSuchUnitXyz;')
  ClickPaste
  $list = $null; $dlg = ''; $t0 = Get-Date
  while ($null -eq $list -and $dlg -eq '' -and ((Get-Date) - $t0).TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500; $dlg = EditorDialog; foreach ($lv in $lvs) { if ((LvCount $lv) -ge $before[$lv] + 2) { $list = $lv } } }
  Check 'paste.adds.rows' ($null -ne $list) $(if ($dlg) { "editor dialog: $dlg" })
  if ($null -eq $list) { return }
  $rows = LvRows $list
  $ns = $rows | Where-Object { $_.Old -eq 'NoSuchUnitXyz' } | Select-Object -First 1
  Check 'paste.row.nosuch' ($null -ne $ns -and $ns.Kind -eq '(used)') ($rows | Out-String)
  Check 'paste.row.nosuch.status' ($null -ne $ns -and ($ns.Status -eq 'MISSING' -or $ns.Status -eq 'no destination')) "$($ns.Status)"
  Check 'paste.row.forms' (@($rows | Where-Object { $_.Old -eq 'Forms' }).Count -gt 0)
  Check 'paste.text.no.filelist.row' (@($rows | Where-Object { $_.Old -eq $FileListUsed }).Count -eq 0) "(precondition: $FileListUsed must come only from the file list)"

  # --- 2. copied Explorer file list (Task 7: CF_HDROP branch of DoPasteUnits) ---
  Check 'filelist.fixture.exists' (Test-Path -LiteralPath $FileListUnit) $FileListUnit
  $drop = New-Object System.Collections.Specialized.StringCollection
  [void]$drop.Add($FileListUnit)
  [Windows.Forms.Clipboard]::SetFileDropList($drop)
  ClickPaste
  $sb = Find $main 'TStatusBar' $null | Select-Object -First 1
  $fl = $null; $dlg = ''; $sbText = ''; $t0 = Get-Date
  # Stop early on a status-line error ('[!] ...') or a message box: both mean no rows are coming.
  while ($null -eq $fl -and $dlg -eq '' -and -not $sbText.StartsWith('[!]') -and ((Get-Date) - $t0).TotalSeconds -lt 90) {
    Start-Sleep -Milliseconds 500
    $dlg = EditorDialog
    $sbText = if ($sb) { [H]::Txt($sb) } else { '' }
    $fl = LvRows $list | Where-Object { $_.Old -eq $FileListUsed } | Select-Object -First 1
  }
  Start-Sleep -Milliseconds 500   # the handler writes the status line after the rows
  $sbText = if ($sb) { [H]::Txt($sb) } else { '' }
  Check 'filelist.row.pathtodata' ($null -ne $fl -and $fl.Kind -eq '(used)') "status bar: $sbText$(if ($dlg) { "; editor dialog: $dlg" })"
  Check 'filelist.status.one.file' ($sbText -like '1 source file(s):*') $sbText

  # --- 3. clipboard held open by another process (Task 7 fix round 1) ---
  # OpenClipboard fails while someone else has it open; the editor must say so on the
  # status line, not raise a modal "Cannot open clipboard" exception box.
  $held = [H]::OpenClipboard([IntPtr]::Zero)
  Check 'busy.clipboard.held' $held
  if (-not $held) { return }
  try {
    $sbBefore = if ($sb) { [H]::Txt($sb) } else { '' }
    ClickPaste
    $dlg = ''; $sbText = $sbBefore; $t0 = Get-Date
    while ($dlg -eq '' -and $sbText -eq $sbBefore -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 500; $dlg = EditorDialog; $sbText = if ($sb) { [H]::Txt($sb) } else { '' } }
  } finally { [void][H]::CloseClipboard() }
  Check 'busy.no.dialog' ($dlg -eq '') "editor dialog: $dlg"
  Check 'busy.status.error' ($sbText -like '`[!`] Paste:*clipboard open*') $sbText
} finally {
  if (-not $p.HasExited) { $p.Kill($true) }
  if ($savedClip.GetFormats().Count -gt 0) { [Windows.Forms.Clipboard]::SetDataObject($savedClip, $true) } else { [Windows.Forms.Clipboard]::Clear() }
  "gui: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
