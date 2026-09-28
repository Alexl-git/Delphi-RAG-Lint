# Driven GUI check for the unit picker (feat/unit-picker, 2026-09-24).
# Usage: pwsh -File drive-unit-rules-toolbar.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it).
param([string]$Exe)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] public static extern IntPtr SendS(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] public static extern IntPtr SendSB(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr got);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> Tops(uint pid) { var r = new List<IntPtr>(); EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr parent) { var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Txt(IntPtr h) { int n = (int)Send(h, 0x000E, IntPtr.Zero, IntPtr.Zero); var s = new StringBuilder(n + 2); SendSB(h, 0x000D, (IntPtr)(n + 1), s); return s.ToString(); }
  public static int Top(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.T; }
  public static int Left(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.L; }
  /* Toolbar buttons are not windows. Read each button's idCommand and caption out
     of the editor's memory (TB_GETBUTTON / TB_GETBUTTONTEXTW write through a
     pointer IN that process), then post the WM_COMMAND a real click sends. */
  public static string Captions(IntPtr main) { var sb = new StringBuilder(); Walk(main, (tb, id, cap) => { sb.Append(cap).Append(" | "); return false; }); return sb.ToString(); }
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr put);
  /* Click the page-control tab captioned NAME: TCM_GETITEMW for each tab's text
     and TCM_GETITEMRECT for its rectangle, both through the editor's memory. */
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
  /* VCL routes a toolbar click to the TToolButton under the cursor, so post a
     real left click at the button's rectangle (TB_GETITEMRECT, by index). */
  public static bool InvokeByName(IntPtr main, string name) {
    uint pid; GetWindowThreadProcessId(main, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)1024, 0x3000, 0x04);
    try {
      foreach (var tb in Kids(main)) {
        if (Cls(tb) != "TToolBar") continue;
        int n = (int)Send(tb, 0x0418, IntPtr.Zero, IntPtr.Zero);
        for (int i = 0; i < n; i++) {
          Send(tb, 0x0417, (IntPtr)i, mem);
          var b = new byte[32]; UIntPtr got; ReadProcessMemory(hp, mem, b, (UIntPtr)32, out got);
          int id = BitConverter.ToInt32(b, 4);
          int len = (int)Send(tb, 0x044B, (IntPtr)id, mem);
          if (len <= 0) continue;
          var t = new byte[(len + 1) * 2]; ReadProcessMemory(hp, mem, t, (UIntPtr)t.Length, out got);
          if (Encoding.Unicode.GetString(t, 0, len * 2) != name) continue;
          Send(tb, 0x041D, (IntPtr)i, mem);
          var rc = new byte[16]; ReadProcessMemory(hp, mem, rc, (UIntPtr)16, out got);
          int x = (BitConverter.ToInt32(rc, 0) + BitConverter.ToInt32(rc, 8)) / 2, y = (BitConverter.ToInt32(rc, 4) + BitConverter.ToInt32(rc, 12)) / 2;
          IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
          PostMessage(tb, 0x0200, IntPtr.Zero, lp); PostMessage(tb, 0x0201, (IntPtr)1, lp); PostMessage(tb, 0x0202, IntPtr.Zero, lp);
          return true;
        }
      }
      return false;
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
  static bool Walk(IntPtr main, Func<IntPtr, int, string, bool> visit) {
    uint pid; GetWindowThreadProcessId(main, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)1024, 0x3000, 0x04);
    try {
      foreach (var tb in Kids(main)) {
        if (Cls(tb) != "TToolBar" && Cls(tb) != "ToolbarWindow32") continue;
        int n = (int)Send(tb, 0x0418, IntPtr.Zero, IntPtr.Zero);
        for (int i = 0; i < n; i++) {
          Send(tb, 0x0417, (IntPtr)i, mem);
          var b = new byte[32]; UIntPtr got; ReadProcessMemory(hp, mem, b, (UIntPtr)32, out got);
          int id = BitConverter.ToInt32(b, 4);
          int len = (int)Send(tb, 0x044B, (IntPtr)id, mem);
          if (len <= 0) continue;
          var t = new byte[(len + 1) * 2]; ReadProcessMemory(hp, mem, t, (UIntPtr)t.Length, out got);
          if (visit(tb, id, Encoding.Unicode.GetString(t, 0, len * 2))) return true;
        }
      }
      return false;
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
}
'@
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
function WaitFor($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function TopsNow($procId) { (Forms $procId | ForEach-Object { '{0}/{1}' -f [W]::Cls($_), [W]::Txt($_) }) -join ' | ' }
function Find($parent, $cls, $text) { [W]::Kids($parent) | Where-Object { [W]::Cls($_) -eq $cls -and ($text -eq $null -or [W]::Txt($_) -eq $text) } }
function SetText($h, $s) { [void][W]::SendS($h, 0x000C, [IntPtr]::Zero, $s) }
function Click($h) { [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
function Raw($main) { [void][W]::ClickTab($main, 'Raw DSL'); Start-Sleep -Milliseconds 400; [string](Find $main 'TMemo' $null | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ -match '#' } | Select-Object -First 1) }
function PickTyped($procId, $caption, $text) {
  $pk = WaitFor $procId $caption 90
  if ($pk -eq [IntPtr]::Zero) { return "no picker '$caption' (forms: $(TopsNow $procId))" }
  $ed = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })[0]
  SetText $ed $text
  Click (@(Find $pk 'TButton' 'OK')[0])
  return ''
}
function Answer($procId, $btnCaption) {
  $dlg = WaitCls $procId 'TMessageForm' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no message box (forms: $(TopsNow $procId))" }
  $b = @(Find $dlg 'TButton' $btnCaption)
  if ($b.Count -eq 0) { return "no '$btnCaption' in message box: " + ((Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) }) -join ',') }
  Click $b[0]
  return ''
}

$p = Start-Process $Exe -PassThru
try {
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $main = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($main -eq $null) { $main = [IntPtr]::Zero } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  Start-Sleep -Seconds 2
  $caps = [W]::Captions($main)
  Check 'toolbar.readable' ($caps -match '\+ New Conversion' -and $caps -match '\+ Add unit') $caps

  # --- 1. + New Conversion adds #unuse <From unit> and #use <To unit> ---
  $pick = @(Find $main 'TButton' 'Pick...')[0]
  $row2 = @(Find $main 'TComboBox' $null | Where-Object { [W]::Top($_) -gt [W]::Top($pick) + 20 -and [W]::Top($_) -lt [W]::Top($pick) + 45 } | Sort-Object { [W]::Left($_) })
  Check 'pickers.found' ($row2.Count -ge 2) "row2 combos=$($row2.Count)"
  SetText $row2[0] 'Vcl.CheckLst.TCheckListBox'
  SetText $row2[1] 'cxCheckListBox.TcxCheckListBox'
  Check 'invoke.new-conversion' ([W]::InvokeByName($main, '+ New Conversion'))
  $t0 = Get-Date; $raw = ''
  while (((Get-Date) - $t0).TotalSeconds -lt 300 -and ($raw -notmatch '(?m)^#link ')) { Start-Sleep -Seconds 1; $raw = Raw $main; if ((Forms $p.Id).Count -gt 1) { break } }
  "  debug: waited {0:N0}s, forms=[{1}], memos={2}, raw.len={3}" -f ((Get-Date)-$t0).TotalSeconds, (TopsNow $p.Id), (@(Find $main 'TMemo' $null).Count), $raw.Length
  (Find $main 'TMemo' $null | ForEach-Object { '  memo: ' + ([W]::Txt($_) -replace '\s+',' ').Substring(0, [Math]::Min(80, ([W]::Txt($_)).Length)) })
  Check 'derive.unuse.from.unit' ($raw -match '(?m)^#unuse Vcl\.CheckLst\s*$')
  Check 'derive.use.to.unit' ($raw -match '(?m)^#use cxCheckListBox\s*$')
  Check 'derive.convert.present.once' (([regex]::Matches($raw, '(?m)^#convert .*TCheckListBox')).Count -eq 1)
  $raw = [string]$raw; $iUse = $raw.IndexOf('#use cxCheckListBox'); $iConv = $raw.IndexOf('#convert')
  Check 'derive.units.above.convert' ($iUse -ge 0 -and $iConv -gt $iUse) "use@$iUse convert@$iConv"
  # Auto-match fills the ACTIVE block's grid; #link lines under the new #convert
  # prove the grid loaded the new block, not a neighbour shifted by the inserts.
  $blk = [regex]::Match($raw, '(?ms)^#convert Vcl\.CheckLst\.TCheckListBox.*?(?=^#convert|\z)').Value
  Check 'derive.grid.loaded.new.block' (([regex]::Matches($blk, '(?m)^#link ')).Count -gt 5) ("links in new block: " + ([regex]::Matches($blk, '(?m)^#link ')).Count)

  # --- 2. Derive units again: idempotent ---
  $before = Raw $main
  Check 'invoke.derive' ([W]::InvokeByName($main, 'Derive units'))
  Start-Sleep -Seconds 8
  $after = Raw $main
  Check 'derive.button.idempotent' ($after -eq $before) ("lines {0} -> {1}" -f ($before -split "`n").Count, ($after -split "`n").Count)

  # --- 3. + Use through the picker ---
  Check 'invoke.use' ([W]::InvokeByName($main, '+ Add unit'))
  $e = PickTyped $p.Id 'Add unit (#use)' 'cxEdit'; Check 'use.picker' ($e -eq '') $e
  Start-Sleep -Seconds 1
  Check 'use.rule.written' ((Raw $main) -match '(?m)^#use cxEdit\s*$')

  # --- 4. + Swap: Old, New, Yes, New, No ---
  Check 'invoke.swap' ([W]::InvokeByName($main, '+ Swap'))
  $e = PickTyped $p.Id 'Unit swap: the OLD unit to replace' 'OldUnitA'; Check 'swap.old.picker' ($e -eq '') $e
  $e = PickTyped $p.Id 'Unit swap: a NEW unit replacing OldUnitA' 'NewUnitB'; Check 'swap.new.picker' ($e -eq '') $e
  $e = Answer $p.Id '&Yes'; Check 'swap.another.yes' ($e -eq '') $e
  $e = PickTyped $p.Id 'Unit swap: another NEW unit replacing OldUnitA' 'NewUnitC'; Check 'swap.another.picker' ($e -eq '') $e
  $e = Answer $p.Id '&No'; Check 'swap.another.no' ($e -eq '') $e
  Start-Sleep -Seconds 1
  Check 'swap.rule.written' ((Raw $main) -match '(?m)^#useswap OldUnitA -> NewUnitB, NewUnitC\s*$') ((Raw $main) -split "`n" | Where-Object { $_ -match 'useswap' })

  # --- 5. + Unuse, cancelled: nothing written ---
  $before = Raw $main
  Check 'invoke.unuse' ([W]::InvokeByName($main, '+ Remove unit'))
  $pk = WaitFor $p.Id 'Remove unit (#unuse)' 30
  Check 'unuse.picker' ($pk -ne [IntPtr]::Zero)
  if ($pk -ne [IntPtr]::Zero) { Click (@(Find $pk 'TButton' 'Cancel')[0]) }
  Start-Sleep -Seconds 1
  Check 'unuse.cancel.nothing.written' ((Raw $main) -eq $before)
  "---- raw DSL head ----"; ((Raw $main) -split "`n" | Select-Object -First 12) -join "`n"
}
finally {
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  "gui2: $script:pass pass / $script:fail fail"
}
