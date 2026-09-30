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
  /* Unit-list rows (2026-09-29, the row-is-the-Old-unit fix). A report-view list
     view keeps its text in the editor's memory: LVITEMW (x64 layout: iSubItem @8,
     state @12, stateMask @16, pszText @24, cchTextMax @32) is written there, the
     message is sent, and the answer is read back. */
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref PT p);
  public struct PT { public int X, Y; }
  [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr m);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetMenuStringW(IntPtr m, uint id, StringBuilder s, int n, uint flags);
  [DllImport("user32.dll")] static extern uint GetMenuState(IntPtr m, uint id, uint flags);
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
  static void SetState(IntPtr hp, IntPtr mem, IntPtr lv, int idx, int state) {
    var item = new byte[88];
    BitConverter.GetBytes(state).CopyTo(item, 12);
    BitConverter.GetBytes(3).CopyTo(item, 16);
    UIntPtr io; WriteProcessMemory(hp, mem, item, (UIntPtr)88, out io);
    Send(lv, 0x102B, (IntPtr)idx, mem);
  }
  /* Exactly row IDX selected and focused, as a left click leaves it (-1 = none). */
  public static void SelectRow(IntPtr lv, int idx) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)256, 0x3000, 0x04);
    try { SetState(hp, mem, lv, -1, 0); if (idx >= 0) SetState(hp, mem, lv, idx, 3); }
    finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
  /* WM_CONTEXTMENU lParam for the middle of row IDX, in SCREEN coordinates. */
  public static IntPtr RowScreenPoint(IntPtr lv, int idx) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)256, 0x3000, 0x04);
    try {
      var rc = new byte[16]; UIntPtr io; WriteProcessMemory(hp, mem, rc, (UIntPtr)16, out io);
      Send(lv, 0x100E, (IntPtr)idx, mem);
      ReadProcessMemory(hp, mem, rc, (UIntPtr)16, out io);
      var p = new PT { X = (BitConverter.ToInt32(rc, 0) + BitConverter.ToInt32(rc, 8)) / 2, Y = (BitConverter.ToInt32(rc, 4) + BitConverter.ToInt32(rc, 12)) / 2 };
      ClientToScreen(lv, ref p);
      return (IntPtr)((p.Y << 16) | (p.X & 0xFFFF));
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
  /* The open popup menu's items ('#32768' window, MN_GETHMENU), '&' removed; a
     grayed / disabled item is prefixed '[off] '. */
  public static string[] MenuItems(IntPtr menuWnd) {
    IntPtr hm = Send(menuWnd, 0x01E1, IntPtr.Zero, IntPtr.Zero);
    int n = GetMenuItemCount(hm);
    var r = new string[Math.Max(0, n)];
    for (int i = 0; i < n; i++) {
      var s = new StringBuilder(256); GetMenuStringW(hm, (uint)i, s, 256, 0x400);
      uint st = GetMenuState(hm, (uint)i, 0x400);
      r[i] = ((st & 0x3) != 0 ? "[off] " : "") + s.ToString().Replace("&", "");
    }
    return r;
  }
  [DllImport("user32.dll")] static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetSubMenu(IntPtr m, int pos);
  [DllImport("user32.dll")] static extern uint GetMenuItemID(IntPtr m, int pos);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
  /* The main menu's HMENU. A VCL style detaches the native menu from the window
     (GetMenu -> 0) and paints its own bar, so the editor answers the registered
     message 'ConvRulesEditor.MainMenuHandle' (MAIN_MENU_QUERY_MSG) with it. */
  static IntPtr MenuOf(IntPtr main) {
    IntPtr m = GetMenu(main);
    return m != IntPtr.Zero ? m : Send(main, RegisterWindowMessage("ConvRulesEditor.MainMenuHandle"), IntPtr.Zero, IntPtr.Zero);
  }
  /* A main-menu caption without its '&' hot-key markers and without the
     TAB-separated shortcut text VCL appends ("Save\tCtrl+S" -> "Save"). */
  static string Clean(IntPtr m, int i) {
    var s = new StringBuilder(256); GetMenuStringW(m, (uint)i, s, 256, 0x400);
    string t = s.ToString().Replace("&", ""); int tab = t.IndexOf('\t');
    return tab >= 0 ? t.Substring(0, tab) : t;
  }
  /* "Top|Item" -> post the item's WM_COMMAND to the main form, exactly what a
     click sends. VCL's TMenuItem.Click ignores a disabled item. */
  public static bool InvokeMenu(IntPtr main, string path) {
    var parts = path.Split('|'); IntPtr m = MenuOf(main);
    for (int p = 0; p < parts.Length; p++) {
      int n = GetMenuItemCount(m), hit = -1;
      for (int i = 0; i < n; i++) if (Clean(m, i) == parts[p]) { hit = i; break; }
      if (hit < 0) return false;
      if (p == parts.Length - 1) { uint id = GetMenuItemID(m, hit); PostMessage(main, 0x0111, (IntPtr)id, IntPtr.Zero); return true; }
      m = GetSubMenu(m, hit);
    }
    return false;
  }
  public static string MenuCaptions(IntPtr main) {
    var sb = new StringBuilder(); IntPtr bar = MenuOf(main);
    for (int t = 0; t < GetMenuItemCount(bar); t++) {
      IntPtr sub = GetSubMenu(bar, t);
      for (int i = 0; sub != IntPtr.Zero && i < GetMenuItemCount(sub); i++) sb.Append(Clean(bar, t)).Append('|').Append(Clean(sub, i)).Append(" ; ");
    }
    return sb.ToString();
  }
}
'@
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
# TEngineWaitForm (Task 4, 2026-09-30) is the editor's progress window for slow
# property-tree loads: correct behaviour, never the dialog a step waits for. Forms
# leaves it out, and WaitFor / WaitCls first wait for it to close (WaitEngineIdle),
# so a slow engine delays a step instead of being mistaken for its dialog.
# ENGINE_IDLE_SEC: the TcxButton proptree alone measured 37.5-60+ s on the shared
# build box (2026-09-30); a New Conversion runs up to four such calls.
$ENGINE_IDLE_SEC = 900
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow', 'TEngineWaitForm' }) }
function WaitEngineIdle($procId) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $ENGINE_IDLE_SEC) { if (-not ([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' })) { return $true }; Start-Sleep -Milliseconds 250 }; return $false }
function WaitFor($procId, $caption, $sec) { [void](WaitEngineIdle $procId); $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitCls($procId, $cls, $sec) { [void](WaitEngineIdle $procId); $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function TopsNow($procId) { (Forms $procId | ForEach-Object { $h = $_; $s = '{0}/{1}' -f [W]::Cls($h), [W]::Txt($h); if ([W]::Cls($h) -eq '#32770') { $s += ' [' + ((Find $h 'Static' $null | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ }) -join ' ') + ']' }; $s }) -join ' | ' }
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
function KeyEnter($h) { [void][W]::PostMessage($h, 0x0100, [IntPtr]0x0D, [IntPtr]::Zero); Start-Sleep -Milliseconds 400 }
# The replacement picker's Replacements list: the only NON-virtual TListBox, the bottom-most one.
function Chosen($pk) {
  $lb = @(Find $pk 'TListBox' $null | Sort-Object { [W]::Top($_) } -Descending)[0]
  $n = [int][W]::Send($lb, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)
  @(for ($i = 0; $i -lt $n; $i++) { $sb = New-Object System.Text.StringBuilder 256; [void][W]::SendSB($lb, 0x0189, [IntPtr]$i, $sb); $sb.ToString() })
}
function UnitList($main) { [void][W]::ClickTab($main, 'Unit Rules'); Start-Sleep -Milliseconds 500; @(Find $main 'TListView' $null | Where-Object { [W]::Column($_, 0) -contains '#useswap' })[0] }
function RowOf($lv, $old) { [array]::IndexOf([W]::Column($lv, 1), $old) }
# The replacement picker: type each name and press Enter (adds, no dialog), then OK.
function PickReplacements($procId, $caption, [string[]]$units) {
  $pk = WaitFor $procId $caption 60
  if ($pk -eq [IntPtr]::Zero) { return "no picker '$caption' (forms: $(TopsNow $procId))" }
  $ed = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })[0]
  foreach ($u in $units) { SetText $ed $u; KeyEnter $ed }
  $got = (Chosen $pk) -join ','
  Click (@(Find $pk 'TButton' 'OK')[0])
  if ($got -ne ($units -join ',')) { return "replacements list read '$got', expected '$($units -join ',')'" }
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
  $caps = [W]::MenuCaptions($main)
  Check 'menubar.items' (($caps -match 'File\|Open\.\.\.') -and ($caps -match 'Conversion\|New Conversion') -and ($caps -match 'Mapping\|Auto-Match') -and ($caps -match 'Uses Units\|Swap\.\.\.') -and ($caps -match 'View\|Theme')) $caps
  Check 'toolbar.gone' (@(Find $main 'TToolBar' $null).Count -eq 0)

  # --- 1. + New Conversion adds #unuse <From unit> and #use <To unit> ---
  $pick = @(Find $main 'TButton' 'Pick...')[0]
  $row2 = @(Find $main 'TComboBox' $null | Where-Object { [W]::Top($_) -gt [W]::Top($pick) + 20 -and [W]::Top($_) -lt [W]::Top($pick) + 45 } | Sort-Object { [W]::Left($_) })
  Check 'pickers.found' ($row2.Count -ge 2) "row2 combos=$($row2.Count)"
  SetText $row2[0] 'Vcl.CheckLst.TCheckListBox'
  SetText $row2[1] 'cxCheckListBox.TcxCheckListBox'
  Check 'invoke.new-conversion' ([W]::InvokeMenu($main, 'Conversion|New Conversion'))
  $t0 = Get-Date; $raw = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $ENGINE_IDLE_SEC -and ($raw -notmatch '(?m)^#link ')) { Start-Sleep -Seconds 1; $raw = Raw $main; if ((Forms $p.Id).Count -gt 1) { break } }
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
  Check 'invoke.derive' ([W]::InvokeMenu($main, 'Uses Units|Derive units'))
  Start-Sleep -Seconds 8
  $after = Raw $main
  Check 'derive.button.idempotent' ($after -eq $before) ("lines {0} -> {1}" -f ($before -split "`n").Count, ($after -split "`n").Count)

  # --- 3. + Use through the picker ---
  Check 'invoke.use' ([W]::InvokeMenu($main, 'Uses Units|Add unit...'))
  $e = PickTyped $p.Id 'Add unit (#use)' 'cxEdit'; Check 'use.picker' ($e -eq '') $e
  Start-Sleep -Seconds 1
  Check 'use.rule.written' ((Raw $main) -match '(?m)^#use cxEdit\s*$')

  # --- 4. + Swap with NO row selected: Old picker, then the multi-pick replacement
  #        picker (Enter adds, no Yes/No; the old unit and repeats are refused) ---
  Check 'invoke.swap' ([W]::InvokeMenu($main, 'Uses Units|Swap...'))
  $e = PickTyped $p.Id 'Unit swap: the OLD unit to replace' 'OldUnitA'; Check 'swap.old.picker' ($e -eq '') $e
  $pk = WaitFor $p.Id 'Replacements for OldUnitA' 60
  Check 'swap.replacements.picker' ($pk -ne [IntPtr]::Zero) (TopsNow $p.Id)
  if ($pk -ne [IntPtr]::Zero) {
    $ed = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })[0]
    SetText $ed 'NewUnitB'; KeyEnter $ed
    SetText $ed 'OldUnitA'; KeyEnter $ed   # refused: the unit being replaced
    SetText $ed 'newunitb'; KeyEnter $ed   # refused: already chosen, any case
    SetText $ed 'NewUnitC'; KeyEnter $ed
    Check 'swap.multi.list' (((Chosen $pk) -join ',') -eq 'NewUnitB,NewUnitC') ((Chosen $pk) -join ',')
    Click (@(Find $pk 'TButton' 'OK')[0])
  }
  Check 'swap.no.confirmation' ((WaitCls $p.Id 'TMessageForm' 2) -eq [IntPtr]::Zero) (TopsNow $p.Id)
  Start-Sleep -Seconds 1
  Check 'swap.rule.written' ((Raw $main) -match '(?m)^#useswap OldUnitA -> NewUnitB, NewUnitC\s*$') ((Raw $main) -split "`n" | Where-Object { $_ -match 'useswap' })

  # --- 4b. THE REPORTED DEFECT (2026-09-29): with several Old units listed, swap the
  #         first, then the second. The SELECTED ROW is the Old unit: no Old picker
  #         opens, and the second swap replaces the second unit -- never the first
  #         unit's replacement. ---
  $lv = UnitList $main
  Check 'unitlist.found' ($null -ne $lv) ((Find $main 'TListView' $null).Count)
  [W]::SelectRow($lv, (RowOf $lv 'Vcl.CheckLst'))
  Check 'row.swap.invoke' ([W]::InvokeMenu($main, 'Uses Units|Swap...'))
  Check 'row.swap.no.old.picker' ((WaitFor $p.Id 'Unit swap: the OLD unit to replace' 3) -eq [IntPtr]::Zero) (TopsNow $p.Id)
  $e = PickReplacements $p.Id 'Replacements for Vcl.CheckLst' @('NewUnitX'); Check 'row.swap.first' ($e -eq '') $e
  Start-Sleep -Seconds 1
  $lv = UnitList $main
  [W]::SelectRow($lv, (RowOf $lv 'OldUnitA'))
  Check 'row.swap2.invoke' ([W]::InvokeMenu($main, 'Uses Units|Swap...'))
  $e = PickReplacements $p.Id 'Replacements for OldUnitA' @('NewUnitD'); Check 'row.swap.second.is.second.row' ($e -eq '') $e
  Start-Sleep -Seconds 1
  $raw = Raw $main
  Check 'row.swap.first.rule' ($raw -match '(?m)^#useswap Vcl\.CheckLst -> NewUnitX\s*$') (($raw -split "`n" | Where-Object { $_ -match 'useswap' }) -join ' / ')
  Check 'row.swap.second.merged' ($raw -match '(?m)^#useswap OldUnitA -> NewUnitB, NewUnitC, NewUnitD\s*$') (($raw -split "`n" | Where-Object { $_ -match 'useswap' }) -join ' / ')
  Check 'row.swap.no.replacement.as.old' ($raw -notmatch '(?m)^#useswap NewUnit') (($raw -split "`n" | Where-Object { $_ -match 'useswap' }) -join ' / ')
  Check 'row.swap.one.rule.per.old' (([regex]::Matches($raw, '(?m)^#useswap OldUnitA ')).Count -eq 1)

  # --- 4c. Right-click menu on a row: Swap is captioned with the row's unit and
  #         goes straight to the replacement picker; a #use row cannot be swapped. ---
  $lv = UnitList $main
  [W]::SelectRow($lv, -1)
  [void][W]::PostMessage($lv, 0x007B, $lv, [W]::RowScreenPoint($lv, (RowOf $lv 'Vcl.CheckLst')))
  $menu = WaitCls $p.Id '#32768' 10
  Check 'popup.shown' ($menu -ne [IntPtr]::Zero) (TopsNow $p.Id)
  if ($menu -ne [IntPtr]::Zero) {
    $items = [W]::MenuItems($menu)
    Check 'popup.swap.caption' ($items[0] -eq 'Swap Vcl.CheckLst with...') ($items -join ' | ')
    [void][W]::PostMessage($menu, 0x0100, [IntPtr]0x28, [IntPtr]::Zero); Start-Sleep -Milliseconds 200
    [void][W]::PostMessage($menu, 0x0100, [IntPtr]0x0D, [IntPtr]::Zero)
    $e = PickReplacements $p.Id 'Replacements for Vcl.CheckLst' @('NewUnitY'); Check 'popup.swap.picker' ($e -eq '') $e
    Start-Sleep -Seconds 1
    Check 'popup.swap.merged' ((Raw $main) -match '(?m)^#useswap Vcl\.CheckLst -> NewUnitX, NewUnitY\s*$') (((Raw $main) -split "`n" | Where-Object { $_ -match 'useswap' }) -join ' / ')
  }
  $lv = UnitList $main
  [void][W]::PostMessage($lv, 0x007B, $lv, [W]::RowScreenPoint($lv, [array]::IndexOf([W]::Column($lv, 2), 'cxEdit')))
  $menu = WaitCls $p.Id '#32768' 10
  if ($menu -ne [IntPtr]::Zero) {
    $items = [W]::MenuItems($menu)
    Check 'popup.use.row.no.swap' ($items[0] -like '`[off`] Swap*') ($items -join ' | ')
    [void][W]::PostMessage($menu, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero); Start-Sleep -Milliseconds 400
  } else { Check 'popup.use.row.shown' $false (TopsNow $p.Id) }
  # Right-click over EMPTY space below the rows: no row, so nothing row-bound is
  # enabled -- and no access violation (IfThen evaluated a nil row's SubItems).
  $lv = UnitList $main
  [W]::SelectRow($lv, -1)
  $r = New-Object W+RECT; [void][W]::GetWindowRect($lv, [ref]$r)
  $lp = [IntPtr]((([int]($r.T + ($r.B - $r.T) * 3 / 4)) -shl 16) -bor (($r.L + 40) -band 0xFFFF))  # client area, clear of the rows and the scroll bar
  [void][W]::PostMessage($lv, 0x007B, $lv, $lp)
  $menu = WaitCls $p.Id '#32768' 10
  Check 'popup.empty.no.error' ((WaitCls $p.Id '#32770' 1) -eq [IntPtr]::Zero) (TopsNow $p.Id)
  if ($menu -ne [IntPtr]::Zero) {
    $items = [W]::MenuItems($menu)
    Check 'popup.empty.nothing.row.bound' (($items[0] -like '`[off`] Swap*') -and ($items[5] -like '`[off`] Delete')) ($items -join ' | ')
    [void][W]::PostMessage($menu, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero); Start-Sleep -Milliseconds 400
  } else { Check 'popup.empty.shown' $false (TopsNow $p.Id) }

  # --- 5. + Unuse, cancelled: nothing written ---
  $before = Raw $main
  Check 'invoke.unuse' ([W]::InvokeMenu($main, 'Uses Units|Remove unit'))
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
