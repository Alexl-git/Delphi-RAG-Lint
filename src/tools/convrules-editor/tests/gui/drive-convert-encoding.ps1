# Driven GUI check for the Convert tab's encoding offers (feat/conv-enc-t, Task 6, 2026-10-25).
# Usage: pwsh -NoProfile -File drive-convert-encoding.ps1 -Exe <path\ConvRulesEditor.exe>
#        A FROZEN drag-lint.exe must sit beside the exe (a STAGED COPY of a pin, never dll-win64): the fixture
#        index is built with THAT engine, the editor finds its engine the same way.
# Fixture (drive-convert-tab.ps1's FixUnit family, in a fresh temp folder, _D-RAG layout):
#   Fix.dpr / Fix.dproj / FixUnit.pas (declares and uses OldName) / _D-RAG\Fix.sqlite /
#   rules\Lower.rules  -- UTF-16 with BOM, every character ASCII (a #migrate that matches nothing in FixUnit).
# lower.* (no engine change needed): Check all, Add FixUnit.pas, Convert -> a TMessageForm 'fits ASCII-7';
#   Yes -> Lower.rules has no BOM and is ASCII, a .bak beside it, the status 'Saved Lower.rules as ASCII-7';
#   the run then starts and ends.
# raise.* [needs an ENGINE with convert_encoding_guard; else every raise.* check prints SKIP, tallied apart]:
#   rules\Raise.rules (UTF-8 with BOM: '#use New<U+0414>me' (a unit rule: the engine runs a book with no .dfm and no #convert on unit rules alone); ruling I6: Cyrillic, which
#   cp1252 cannot hold) is added, Refresh, Check all, Convert -> a row 'refused -- not changed' and a
#   TMessageForm 'do not fit FixUnit.pas'; Yes -> the re-run row 'converted', FixUnit.pas starts EF BB BF, the
#   status 'Re-run after raising 1 file', FixUnit.pas.BCK1 exists. No second question after the re-run.
# Pre-feature RED (Task 8): lower.offer.asks FAILS on the pinned editor exe (no question; the run just starts).
# The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe)
# --- shared driver plumbing, verbatim from drive-convert-tab.ps1 ---
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  /* N1: a REAL left click (cursor + button down/up) at the centre of H. A posted BM_CLICK
     reaches a button even under a modal window; the user's mouse does not. */
  public static void MouseClick(IntPtr h) { RECT r; GetWindowRect(h, out r); SetCursorPos((r.L + r.R) / 2, (r.T + r.B) / 2); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
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
  /* "Top|Item" -> 1 enabled, 0 grayed/disabled, -1 not found (the native item
     state VCL keeps in step with TMenuItem.Enabled). */
  public static int MenuEnabled(IntPtr main, string path) {
    var parts = path.Split('|'); IntPtr m = MenuOf(main);
    for (int p = 0; p < parts.Length; p++) {
      int n = GetMenuItemCount(m), hit = -1;
      for (int i = 0; i < n; i++) if (Clean(m, i) == parts[p]) { hit = i; break; }
      if (hit < 0) return -1;
      if (p == parts.Length - 1) return (GetMenuState(m, (uint)hit, 0x400) & 0x3) != 0 ? 0 : 1;
      m = GetSubMenu(m, hit);
    }
    return -1;
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
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class CT {
  [DllImport("user32.dll", EntryPoint="SendMessageW")] static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageW")] static extern IntPtr SendSB(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", EntryPoint="GetParent")] public static extern IntPtr Parent(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr got);
  [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr put);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  /* A list box's item strings. LB_GETTEXT is SYSTEM-marshalled, so it takes a LOCAL
     buffer (the editor's memory, as a list view needs, reads back NULs). The source
     list is owner-drawn; its item string is the raw path, the flag is drawn only. */
  public static string[] Items(IntPtr lb) {
    int n = (int)Send(lb, 0x018B, IntPtr.Zero, IntPtr.Zero);
    var r = new string[Math.Max(0, n)];
    for (int i = 0; i < n; i++) {
      int len = (int)Send(lb, 0x018A, (IntPtr)i, IntPtr.Zero);
      var sb = new StringBuilder(Math.Max(0, len) + 2); SendSB(lb, 0x0189, (IntPtr)i, sb);
      r[i] = sb.ToString();
    }
    return r;
  }
  /* Caption of a page control's ACTIVE tab: TCM_GETCURSEL, then TCM_GETITEMW
     (TCITEMW x64: mask @0, pszText @16, cchTextMax @24) through the editor's memory. */
  public static string ActiveTab(IntPtr tc) {
    int sel = (int)Send(tc, 0x130B, IntPtr.Zero, IntPtr.Zero);
    if (sel < 0) return "";
    uint pid; GetWindowThreadProcessId(tc, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)1024, 0x3000, 0x04);
    try {
      var item = new byte[40];
      BitConverter.GetBytes(1).CopyTo(item, 0);
      BitConverter.GetBytes((long)mem + 512).CopyTo(item, 16);
      BitConverter.GetBytes(120).CopyTo(item, 24);
      UIntPtr io; WriteProcessMemory(hp, mem, item, (UIntPtr)40, out io);
      Send(tc, 0x133C, (IntPtr)sel, mem);
      var txt = new byte[240]; ReadProcessMemory(hp, mem + 512, txt, (UIntPtr)240, out io);
      string cap = Encoding.Unicode.GetString(txt); int z = cap.IndexOf('\0'); if (z >= 0) cap = cap.Substring(0, z);
      return cap;
    } finally { VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
  }
}
'@
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
# Looks at least ONCE: with $sec = 0 the old while-loop never looked, so "is the dialog still up" always said no.
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; do { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; if (((Get-Date) - $t0).TotalSeconds -ge $sec) { break }; Start-Sleep -Milliseconds 250 } while ($true); return [IntPtr]::Zero }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class B {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  /* N7/N11: the editor answers 'ConvRulesEditor.Busy' with 2 while busy (an engine wait or an hourglass
     section), 1 while idle. No answer within the timeout = the main thread is blocked = busy too: a click
     posted then is dispatched later, inside whatever pump comes next, where the editor refuses it.
     0 = an editor without the query (answered by DefWindowProc): not busy as far as this can tell. */
  public static bool Busy(IntPtr main) {
    uint msg = RegisterWindowMessage("ConvRulesEditor.Busy"); IntPtr r;
    if (SendMessageTimeout(main, msg, IntPtr.Zero, IntPtr.Zero, 2 /* SMTO_ABORTIFHUNG */, 500, out r) == IntPtr.Zero) return true;
    return (long)r == 2;
  }
}
'@
# N1: idle = no progress window / message box / common dialog and the editor enabled, for 2 s running.
# N7/N11: and the editor itself says it is idle (B::Busy): a main thread blocked between two engine calls
# shows no window and stays enabled, so the windows alone saw a false idle.
function WaitIdle($procId, $main, $sec) {
  $idleSince = $null; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $busy = (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -in 'TEngineWaitForm', 'TMessageForm', '#32770' }).Count -gt 0) -or -not [W]::IsWindowEnabled($main) -or [B]::Busy($main)
    if ($busy) { $idleSince = $null } elseif ($null -eq $idleSince) { $idleSince = Get-Date } elseif (((Get-Date) - $idleSince).TotalSeconds -ge 2) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}
function TopsNow($procId) { (Forms $procId | ForEach-Object { $h = $_; $s = '{0}/{1}' -f [W]::Cls($h), [W]::Txt($h); if ([W]::Cls($h) -eq '#32770') { $s += ' [' + ((Find $h 'Static' $null | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ }) -join ' ') + ']' }; $s }) -join ' | ' }
function Find($parent, $cls, $text) { [W]::Kids($parent) | Where-Object { [W]::Cls($_) -eq $cls -and ($text -eq $null -or [W]::Txt($_) -eq $text) } }
# BM_CLICK is POSTED: a sent click blocks this script for as long as the handler runs
# (Convert's ListUnits, the Add dialog's modal loop).
function Click($h) { [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
# The status line. FLblStatus is a TLabel -- a TGraphicControl, no window, so no
# message reads it; SetStatus/SetError write the SAME text to the TStatusBar, and
# SetError prefixes it '[!] ' there.
function Status($main) { (@(Find $main 'TStatusBar' $null) | ForEach-Object { [W]::Txt($_) }) -join ' | ' }
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
# Add... -> the common Open dialog ('#32770'): the file name goes into its 'Edit', then '&Open'.
function AddViaDialog($procId, $addBtn, $path) {
  Click $addBtn
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no open dialog (forms: $(TopsNow $procId))" }
  Start-Sleep -Milliseconds 700
  $ed = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0]
  [void][W]::SendS($ed, 0x000C, [IntPtr]::Zero, $path)
  Click (@(Find $dlg 'Button' '&Open')[0])
  $t0 = Get-Date; while ((WaitCls $procId '#32770' 0) -ne [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep -Milliseconds 250 }
  if ((WaitCls $procId '#32770' 0) -ne [IntPtr]::Zero) { return "open dialog still up (forms: $(TopsNow $procId))" }
  Start-Sleep -Seconds 2   # AddSources reads the project index (ListUnits) before it writes the status line
  [void](WaitIdle $procId (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' })[0]) 90)   # and the C8 analysis behind the progress window
  return ''
}
# Waits until the status line differs from $Before and is not the run's own
# 'Converting ...' line or a C16 progress line (RunInProgress), or an editor dialog appears;
# returns the final status text.
function RunInProgress($st) { ($st -like 'Converting *') -or ($st -match '^Unit \d+ of \d+: ') -or ($st -like 'Final reindex (total *') }
function WaitStatus($main, $Before, $Seconds) {
  $t0 = Get-Date; $st = $Before; $script:dlg = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 500
    $d = @(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' })
    if ($d.Count -gt 0) { $script:dlg = TopsNow $p.Id; break }
    $st = Status $main
    if ($st -ne $Before -and -not (RunInProgress $st)) { break }
  }
  $script:waited = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Milliseconds 300
  Status $main
}

# The message box's text: every TLabel / Static child (a TMessageForm's message is a TLabel).
# A TLabel has no window of its own; when no child answers, the dialog's own Ctrl+C (VCL TMessageForm copies
# its caption, message and buttons) is read from the clipboard. Needs the editor on the desktop (GUI lock).
Add-Type -AssemblyName System.Windows.Forms
function MsgText($dlg) {
  $t = ((@([W]::Kids($dlg)) | Where-Object { [W]::Cls($_) -in 'TLabel', 'Static' } | ForEach-Object { [W]::Txt($_) }) -join ' ')
  if ($t.Trim() -ne '') { return $t }
  Set-Clipboard -Value 'convert-encoding-sentinel'
  [void][W]::SetForegroundWindow($dlg); Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('^c'); Start-Sleep -Milliseconds 300
  $c = ''
  for ($i = 0; $i -lt 10; $i++) { try { $c = [string](Get-Clipboard -Raw -ErrorAction Stop); break } catch { Start-Sleep -Milliseconds 200 } }
  if ($c -eq 'convert-encoding-sentinel') { return '' }
  # '---' / caption / '---' / message / '---' / buttons: the message is the block after the second rule.
  $parts = $c -split '(?m)^-+\s*$'
  if ($parts.Count -ge 3) { return $parts[2].Trim() -replace '\s*\r?\n\s*', ' ' }
  return ($c.Trim() -replace '\s*\r?\n\s*', ' ')
}
function AnswerDlg($dlg, $btnCaption) {
  $b = @(Find $dlg 'TButton' $btnCaption)
  if ($b.Count -eq 0) { $b = @(Find $dlg 'TButton' ('&' + $btnCaption)) }
  if ($b.Count -eq 0) { return "no '$btnCaption' in message box: " + ((Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) }) -join ',') }
  Click $b[0]
  $t0 = Get-Date; while ([W]::IsWindowVisible($dlg) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }
  return ''
}
function Head($path, $n) { $b = [IO.File]::ReadAllBytes($path); (($b | Select-Object -First $n) | ForEach-Object { $_.ToString('X2') }) -join ' ' }
function AllAscii($path) { foreach ($x in [IO.File]::ReadAllBytes($path)) { if ($x -ge 0x80) { return $false } }; return $true }
function WriteUtf16Bom($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.UnicodeEncoding]::new($false, $true)) }
function WriteUtf8Bom($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.UTF8Encoding]::new($true)) }
function WaitStatusMatch($main, $pattern, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { $s = Status $main; if ($s -match $pattern) { return $s }; Start-Sleep -Milliseconds 300 }; return (Status $main) }
$script:skip = 0
function RCheck($name, $cond, $detail = '') { if ($script:raiseWhy) { $script:skip++; "SKIP  $name  ($script:raiseWhy)" } else { Check $name $cond $detail } }

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }
$info = & { $ErrorActionPreference = 'Continue'; & $engine info --json 2>&1 | Out-String }
$script:raiseWhy = if ($info -match 'convert_encoding_guard') { '' } else { 'the staged engine lacks convert_encoding_guard (info --json)' }

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('convert-enc-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'
# Two UTF-16-with-BOM books, every character ASCII: Z is the OPEN book (SetBookLevel + SaveBook), Y is not
# (re-encoded byte for byte, ruling I5). Their #convert finds nothing in FixUnit (no TLabel).
$bookY = Join-Path $rulesDir 'YLower.rules'; $bookZ = Join-Path $rulesDir 'ZLower.rules'
$bookR = Join-Path $rulesDir 'Raise.rules'
WriteAscii $dproj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{6D1C6B0E-2F3A-4C1B-9E55-0A1B2C3D4E60}</ProjectGuid>
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
WriteAscii (Join-Path $tmp 'Fix.dpr') @'
program Fix;

uses
  FixUnit in 'FixUnit.pas';

begin
end.
'@
# Task 5's live fixture unit (TestEncodingApplyLive): it declares OldName and uses it.
WriteAscii $pas @'
unit FixUnit;
interface
procedure OldName;
implementation
procedure OldName;
begin
end;
procedure Use;
begin
  OldName;
end;
end.
'@
$lowerText = @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
'@
WriteUtf16Bom $bookY $lowerText
WriteUtf16Bom $bookZ $lowerText

$p = $null
try {
  $t0 = Get-Date
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  Check 'fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s $summary" -f ((Get-Date) - $t0).TotalSeconds)

  $p = Start-Process $Exe -ArgumentList "`"$bookZ`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2
  $invoked = [W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'tab.controls' $false "invoked=$invoked Convert buttons beside a progress bar: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $lv = @(Find ([CT]::Parent([CT]::Parent($conv))) 'TListView' $null)[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $refresh = @(Find $tab 'TButton' 'Refresh')[0]
  $books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  Check 'tab.controls' ($null -ne $lv -and $null -ne $checkAll -and $null -ne $refresh -and $null -ne $books -and $null -ne $add)
  if ($null -eq $lv -or $null -eq $checkAll -or $null -eq $refresh -or $null -eq $books -or $null -eq $add) { return }
  Click $checkAll
  Start-Sleep -Milliseconds 500
  $e = AddViaDialog $p.Id $add $pas
  Check 'fixunit.added' (($e -eq '') -and (([CT]::Items((Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0])) -contains $pas)) "$e status: $(Status $main)"

  # --- lower.*: the offer before the run, once per book; Yes lowers it losslessly ---
  Click $conv
  $asked = @()
  for ($i = 0; $i -lt 2; $i++) {
    $dlg = WaitCls $p.Id 'TMessageForm' 120
    if ($dlg -eq [IntPtr]::Zero) { break }
    $txt = MsgText $dlg
    $asked += $txt
    if ($txt -notmatch 'fits ASCII-7') { break }
    $e = AnswerDlg $dlg 'Yes'
    if ($e -ne '') { $asked += "answer: $e"; break }
  }
  Check 'lower.offer.asks' ((@($asked | Where-Object { $_ -match '^YLower\.rules is saved as UTF-16 with BOM but every character in it fits ASCII-7\.' }).Count -eq 1) -and (@($asked | Where-Object { $_ -match '^ZLower\.rules .* fits ASCII-7' }).Count -eq 1)) ($asked -join ' || ')
  # The start status ('Saved ... before converting ... Converting 1 unit(s) ...') may last only a moment: the
  # run's final status is waited for, and the lowering notes are read from the grid and the report.
  $t0 = Get-Date; $first = ''
  do { $s = Status $main; if ($first -eq '' -and $s -match 'Converting 1 unit') { $first = $s }; if ($s -match 'Converted \d+ of \d+ unit x book') { break }; Start-Sleep -Milliseconds 200 } while (((Get-Date) - $t0).TotalSeconds -lt 600)
  "INFO  lower run ended ({0:N0}s): {1}" -f ((Get-Date) - $t0).TotalSeconds, $s
  if ($first -ne '') { "INFO  its start status: $first" }
  $notes = @([W]::Column($lv, 7))
  $report = @(Get-ChildItem -LiteralPath $rulesDir -Filter 'convert-run-*.txt' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
  Check 'lower.notes' ((@($notes | Where-Object { $_ -like 'Saved YLower.rules as ASCII-7 before converting*' }).Count -eq 1) -and (@($notes | Where-Object { $_ -like 'Saved ZLower.rules as ASCII-7 before converting*' }).Count -eq 1) -and ($report -match 'Saved YLower\.rules as ASCII-7') -and ($report -match 'Saved ZLower\.rules as ASCII-7')) ($notes -join ' | ')
  Check 'lower.other.book.bytes' (((Head $bookY 2) -ne 'FF FE') -and (AllAscii $bookY) -and ((Head $bookY 1) -eq '23')) ("head=" + (Head $bookY 4))
  Check 'lower.other.book.backup' ((Test-Path -LiteralPath ($bookY + '.bak')) -and ((Head ($bookY + '.bak') 2) -eq 'FF FE')) 'YLower.rules.bak holds the UTF-16 original'
  Check 'lower.open.book.bytes' (((Head $bookZ 2) -ne 'FF FE') -and (AllAscii $bookZ)) ("head=" + (Head $bookZ 4))
  Check 'lower.run.starts' ($s -match 'Converted \d+ of 2 unit x book pair') $s
  # Asked once per book and session: a second Convert asks nothing (the books are ASCII-7 now anyway).
  Click $conv
  $again = WaitCls $p.Id 'TMessageForm' 20
  Check 'lower.asked.once' (($again -eq [IntPtr]::Zero) -or ((MsgText $again) -notmatch 'fits ASCII-7')) $(if ($again -ne [IntPtr]::Zero) { MsgText $again } else { 'no question' })
  if ($again -ne [IntPtr]::Zero) { [void](AnswerDlg $again 'No') }
  $t0 = Get-Date; do { Start-Sleep -Milliseconds 500; $s2 = Status $main } while (($s2 -eq $s -or $s2 -notmatch 'Converted \d+ of \d+ unit x book') -and ((Get-Date) - $t0).TotalSeconds -lt 600)

  # --- raise.*: the question per encoding-refused unit, and the re-run ---
  if ($script:raiseWhy) {
    foreach ($n in 'raise.refused.row', 'raise.question', 'raise.rerun.converted', 'raise.rerun.status', 'raise.unit.bom', 'raise.backup', 'raise.no.second.question') { RCheck $n $false }
  } else {
    # Only Raise.rules runs: the lower books leave the folder (a refusal stops a unit's later books).
    [IO.File]::Move($bookY, $bookY + '.off'); [IO.File]::Move($bookZ, $bookZ + '.off')
    WriteUtf8Bom $bookR ('#use New' + [char]0x0414 + 'me' + "`r`n")
    Click $refresh; Start-Sleep -Seconds 2
    Click $checkAll; Start-Sleep -Milliseconds 500
    Click $conv
    $dlg = WaitCls $p.Id 'TMessageForm' 600
    $txt = if ($dlg -ne [IntPtr]::Zero) { MsgText $dlg } else { '' }
    RCheck 'raise.refused.row' (@([W]::Column($lv, 2)) -contains 'refused -- not changed') ((@([W]::Column($lv, 2))) -join ' | ')
    RCheck 'raise.question' ($txt -match 'do not fit FixUnit\.pas') "$txt | status: $(Status $main)"
    if ($dlg -ne [IntPtr]::Zero) { [void](AnswerDlg $dlg 'Yes') }
    $st = WaitStatusMatch $main 'Re-run after raising' 900
    RCheck 'raise.rerun.status' ($st -match '^Re-run after raising 1 file\(s\) to UTF-8 with BOM: FixUnit\.pas\. ') $st
    RCheck 'raise.rerun.converted' (@([W]::Column($lv, 2)) -contains 'converted') ((@([W]::Column($lv, 2))) -join ' | ')
    RCheck 'raise.unit.bom' ((Head $pas 3) -eq 'EF BB BF') ("head=" + (Head $pas 4))
    RCheck 'raise.backup' (@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count -ge 1) ((@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*' | ForEach-Object Name)) -join ',')
    Start-Sleep -Seconds 3
    RCheck 'raise.no.second.question' ((WaitCls $p.Id 'TMessageForm' 0) -eq [IntPtr]::Zero) (TopsNow $p.Id)
  }
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-convert-encoding: $script:pass pass / $script:fail fail / $script:skip skip"
  if ($script:fail -gt 0) { exit 1 }
}
