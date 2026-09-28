# Driven GUI check for the Unit Rules harvest (feat/unit-harvest, 2026-09-28).
# Usage: pwsh -File drive-unit-harvest.ps1 -Exe <path\ConvRulesEditor.exe>  (a frozen drag-lint.exe beside it).
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
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Find($parent, $cls, $text) { [H]::Kids($parent) | Where-Object { [H]::Cls($_) -eq $cls -and ($text -eq $null -or [H]::Txt($_) -eq $text) } }
function LvCount($lv) { [int][H]::Send($lv, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero) }

$p = Start-Process $Exe -PassThru
try {
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [H]::Tops($p.Id) | Where-Object { [H]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
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
  Check 'unitrules.tab.active' ([H]::IsWindowVisible($paste[0]))
  $lvs = @(Find $main 'TListView' $null)
  $before = @{}; foreach ($lv in $lvs) { $before[$lv] = LvCount $lv }
  Set-Clipboard -Value 'uses Forms, NoSuchUnitXyz;'
  [void][H]::Send($paste[0], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
  $list = $null; $t0 = Get-Date
  while ($list -eq $null -and ((Get-Date) - $t0).TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500; foreach ($lv in $lvs) { if ((LvCount $lv) -ge $before[$lv] + 2) { $list = $lv } } }
  Check 'paste.adds.rows' ($list -ne $null)
  if ($list -eq $null) { return }
  $rows = @(0..((LvCount $list) - 1) | ForEach-Object { [pscustomobject]@{ Kind = [H]::LvText($list, $_, 0); Old = [H]::LvText($list, $_, 1); Status = [H]::LvText($list, $_, 4) } })
  $ns = $rows | Where-Object { $_.Old -eq 'NoSuchUnitXyz' }
  Check 'paste.row.nosuch' ($ns -ne $null -and $ns.Kind -eq '(used)') ($rows | Out-String)
  Check 'paste.row.nosuch.status' ($ns -ne $null -and ($ns.Status -eq 'MISSING' -or $ns.Status -eq 'no destination')) "$($ns.Status)"
  Check 'paste.row.forms' (($rows | Where-Object { $_.Old -eq 'Forms' }) -ne $null)
} finally {
  if (-not $p.HasExited) { $p.Kill() }
  "gui: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
