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
#   cp1252 cannot hold) is added, Refresh, Check all, Convert -> owner ruling 2026-10-26: BEFORE the run a TMessageForm
#   names 'FixUnit.pas is ASCII-7', 'Raise.rules 1:9', U+0414 and the rule; No -> 'Convert not started', a note row per place,
#   FixUnit.pas untouched; Convert again, Cancel -> 'Convert cancelled', NO note row (ENC-N2); Convert again, Yes -> status 'Raised 1 file(s) ... (asked before the run)', row 'converted',
#   the note row for the place is kept (ENC-N2), FixUnit.pas starts EF BB BF, FixUnit.pas.BCK1 exists. No question after the run.
# mixed.* (N4-1, ENC-N4; needs the same capability and batch_units): Second.pas / Third.pas (UTF-8 with BOM, nothing to raise) + FixUnit.pas back to ASCII-7;
#   the question names only FixUnit.pas; Yes -> 3 'converted' rows, ONE report note 'batch: 2 unit(s) -- 2 ok' (the two unraised units batched), FixUnit.pas raised (BOM) and run per unit, .BCK1 for all.
#   -ProofNoMixed launches the editor with CONVRULES_BATCH=off: only mixed.batch.note.two must FAIL (28 pass / 1 fail).
# Pre-feature RED (Task 8): lower.offer.asks FAILS on the pinned editor exe (no question; the run just starts).
# The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe, [switch]$ProofNoMixed)
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
  // Two messages (length, then text) race a status written in between: read with slack, then re-read until two reads agree.
  static string TxtOnce(IntPtr h) { int n = (int)Send(h, 0x000E, IntPtr.Zero, IntPtr.Zero); int cap = n + 1024; var s = new StringBuilder(cap); SendSB(h, 0x000D, (IntPtr)cap, s); return s.ToString(); }
  public static string Txt(IntPtr h) { string p = TxtOnce(h); for (int i = 0; i < 5; i++) { string c = TxtOnce(h); if (c == p) return c; p = c; } return p; }
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
trap { $script:fail++; "FAIL  driver.crash  $($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]"; "driver crashed: $script:pass pass / $script:fail fail"; exit 1 }
. "$PSScriptRoot\vcl-atoms.ps1"; 'NOTE  ' + (VclAtomsReclaim)   # ATOMLOCK: start from a reclaimed atom table (idempotent)
function Check($name, $cond, $detail = '') { if ($cond -and $env:DRIVE_FORCE_FAIL -ne $name) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
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
  # and the C8 analysis behind the progress window (10-86 s seen on the 1.35.1 pin): a timeout is reported
  if (-not (WaitIdle $procId (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' })[0]) 180)) { return "editor still busy 180 s after the add (forms: $(TopsNow $procId))" }
  return ''
}
# DRV: Convert only on an idle editor; a click the editor still refused ('Convert was NOT started: it was clicked
# while the editor was busy') is clicked once more after the next idle. Returns '' or why it could not click.
function ClickConvert($procId, $main, $btn) {
  if (-not (WaitIdle $procId $main 180)) { return "editor busy for 180 s before Convert (forms: $(TopsNow $procId))" }
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    Click $btn
    $t0 = Get-Date; $refused = $false
    while (((Get-Date) - $t0).TotalSeconds -lt 3) {
      if (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TMessageForm' }).Count -gt 0) { return '' }
      if ((Status $main) -like '*Convert was NOT started: it was clicked while the editor was busy*') { $refused = $true; break }
      Start-Sleep -Milliseconds 200
    }
    if (-not $refused) { return '' }
    "INFO  Convert refused as busy (attempt $($attempt + 1)): $(Status $main)" | Out-Host
    if (-not (WaitIdle $procId $main 180)) { return "editor busy for 180 s after a refused Convert" }
  }
  return "Convert refused twice: $(Status $main)"
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
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class FG {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  /* SetForegroundWindow; only when that is refused, an ALT tap (the process that sent the last input may set the
     foreground) and again. The tap can eat the next key, so the caller retries its Ctrl+C. */
  public static void Front(IntPtr h) { if (SetForegroundWindow(h) && GetForegroundWindow() == h) return; keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); SetForegroundWindow(h); }
}
"@
function MsgText($dlg) {
  $t = ((@([W]::Kids($dlg)) | Where-Object { [W]::Cls($_) -in 'TLabel', 'Static' } | ForEach-Object { [W]::Txt($_) }) -join ' ')
  if ($t.Trim() -ne '') { return $t }
  # DRV: the FIRST Ctrl+C sent to a fresh question is lost (seen 2026-10-26: foreground = the dialog, clipboard
  # untouched; the second copy works), so lower.offer.asks read '' and the question stayed unanswered.
  # The copy is retried, and only sent while the dialog really is the foreground window.
  $c = 'convert-encoding-sentinel'
  for ($try = 0; ($try -lt 6) -and ($c -eq 'convert-encoding-sentinel') -and [W]::IsWindowVisible($dlg); $try++) {
    Set-Clipboard -Value 'convert-encoding-sentinel'
    [FG]::Front($dlg); Start-Sleep -Milliseconds 300
    if ([FG]::GetForegroundWindow() -ne $dlg) { Start-Sleep -Milliseconds 500; continue }
    [System.Windows.Forms.SendKeys]::SendWait('^c'); Start-Sleep -Milliseconds 300
    for ($i = 0; $i -lt 10; $i++) { try { $c = [string](Get-Clipboard -Raw -ErrorAction Stop); break } catch { Start-Sleep -Milliseconds 200 } }
  }
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
$pas = Join-Path $tmp 'FixUnit.pas'; $pas2 = Join-Path $tmp 'Second.pas'; $pas3 = Join-Path $tmp 'Third.pas'
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
  FixUnit in 'FixUnit.pas',
  Second in 'Second.pas',
  Third in 'Third.pas';

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
WriteUtf8Bom $pas2 "unit Second;`ninterface`nprocedure OldName2;`nimplementation`nprocedure OldName2;`nbegin`nend;`nend."
WriteUtf8Bom $pas3 "unit Third;`ninterface`nprocedure OldName3;`nimplementation`nprocedure OldName3;`nbegin`nend;`nend."
$lowerText = @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
'@
WriteUtf16Bom $bookY $lowerText
WriteUtf16Bom $bookZ $lowerText

$p = $null
if ($ProofNoMixed) { $env:CONVRULES_BATCH = 'off'; 'NOTE  -ProofNoMixed: CONVRULES_BATCH=off, the run is per-unit; the mixed.batch.note.two check is expected to FAIL' }
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
  $ce = ClickConvert $p.Id $main $conv; if ($ce -ne '') { "WARN  $ce" | Out-Host }
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
  $ce = ClickConvert $p.Id $main $conv; if ($ce -ne '') { "WARN  $ce" | Out-Host }
  $again = WaitCls $p.Id 'TMessageForm' 20
  Check 'lower.asked.once' (($again -eq [IntPtr]::Zero) -or ((MsgText $again) -notmatch 'fits ASCII-7')) $(if ($again -ne [IntPtr]::Zero) { MsgText $again } else { 'no question' })
  if ($again -ne [IntPtr]::Zero) { [void](AnswerDlg $again 'No') }
  $t0 = Get-Date; do { Start-Sleep -Milliseconds 500; $s2 = Status $main } while (($s2 -eq $s -or $s2 -notmatch 'Converted \d+ of \d+ unit x book') -and ((Get-Date) - $t0).TotalSeconds -lt 600)

  # --- raise.*: owner ruling 2026-10-26 -- the question comes BEFORE the run, naming every place ---
  $names = 'raise.prerun.question', 'raise.prerun.no.stops', 'raise.prerun.no.notes', 'raise.prerun.no.untouched', 'raise.prerun.cancel.no.notes', 'raise.prerun.status', 'raise.prerun.yes.notes', 'raise.converted', 'raise.unit.bom', 'raise.backup', 'raise.no.second.question'
  if ($script:raiseWhy) {
    foreach ($n in $names) { RCheck $n $false }
  } else {
    # Only Raise.rules runs: the lower books leave the folder.
    [IO.File]::Move($bookY, $bookY + '.off'); [IO.File]::Move($bookZ, $bookZ + '.off')
    WriteUtf8Bom $bookR ('#use New' + [char]0x0414 + 'me' + "`r`n")
    Click $refresh; Start-Sleep -Seconds 2
    Click $checkAll; Start-Sleep -Milliseconds 500
    $before = [IO.File]::ReadAllBytes($pas)
    $bckBefore = @(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count  # the lower run above already backed it up
    $ce = ClickConvert $p.Id $main $conv; if ($ce -ne '') { "WARN  $ce" | Out-Host }
    $dlg = WaitCls $p.Id 'TMessageForm' 120
    $txt = if ($dlg -ne [IntPtr]::Zero) { MsgText $dlg } else { '' }
    RCheck 'raise.prerun.question' (($txt -match 'FixUnit\.pas is ASCII-7') -and ($txt -match 'Raise\.rules 1:9') -and ($txt -match 'U\+0414') -and ($txt -match '#use New') -and ($txt -match 'Yes = raise')) "$txt | status: $(Status $main)"
    # No = change the rules: the run does not start, every place is a note row, the unit is untouched.
    if ($dlg -ne [IntPtr]::Zero) { [void](AnswerDlg $dlg 'No') }
    $st = WaitStatusMatch $main 'Convert not started' 30
    RCheck 'raise.prerun.no.stops' ($st -match 'Convert not started: change the rule text') $st
    RCheck 'raise.prerun.no.notes' (@(@([W]::Column($lv, 7)) | Where-Object { $_ -like 'encoding: Raise.rules 1:9 U+0414*FixUnit.pas (ASCII-7)*' }).Count -eq 1) ((@([W]::Column($lv, 7))) -join ' | ')
    $after = [IO.File]::ReadAllBytes($pas)
    RCheck 'raise.prerun.no.untouched' (([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after)) -and (@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count -eq $bckBefore)) ("head=" + (Head $pas 4) + " BCK before=$bckBefore after=" + @(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count)
    # Cancel = nothing converted, and (ENC-N2) no note rows for the places.
    Click $conv
    $dlg = WaitCls $p.Id 'TMessageForm' 120
    if ($dlg -ne [IntPtr]::Zero) { [void](AnswerDlg $dlg 'Cancel') }
    $st = WaitStatusMatch $main 'Convert cancelled' 30
    RCheck 'raise.prerun.cancel.no.notes' (($st -match '^Convert cancelled') -and (@(@([W]::Column($lv, 7)) | Where-Object { $_ -like 'encoding:*' }).Count -eq 0) -and ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($pas)))) ("$st | " + ((@([W]::Column($lv, 7))) -join ' | '))
    # Yes = raise FixUnit.pas, then convert: the first run carries --raise-encoding.
    $ce = ClickConvert $p.Id $main $conv; if ($ce -ne '') { "WARN  $ce" | Out-Host }
    $dlg = WaitCls $p.Id 'TMessageForm' 120
    if ($dlg -ne [IntPtr]::Zero) { [void](AnswerDlg $dlg 'Yes') }
    $st = WaitStatusMatch $main 'Raised 1 file' 900
    RCheck 'raise.prerun.status' ($st -match '^Raised 1 file\(s\) to UTF-8 with BOM \(asked before the run\): FixUnit\.pas\. ') $st
    # ENC-N2: Yes keeps every place as a note row beside the run's rows.
    RCheck 'raise.prerun.yes.notes' (@(@([W]::Column($lv, 7)) | Where-Object { $_ -like 'encoding: Raise.rules 1:9 U+0414*FixUnit.pas (ASCII-7)*' }).Count -eq 1) ((@([W]::Column($lv, 7))) -join ' | ')
    RCheck 'raise.converted' (@([W]::Column($lv, 2)) -contains 'converted') ((@([W]::Column($lv, 2))) -join ' | ')
    RCheck 'raise.unit.bom' ((Head $pas 3) -eq 'EF BB BF') ("head=" + (Head $pas 4))
    RCheck 'raise.backup' (@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count -ge 1) ((@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*' | ForEach-Object Name)) -join ',')
    Start-Sleep -Seconds 3
    RCheck 'raise.no.second.question' ((WaitCls $p.Id 'TMessageForm' 2) -eq [IntPtr]::Zero) (TopsNow $p.Id)
  }
  # --- mixed.*: N4-1 / ENC-N4 -- three units, ONE needs a raise (FixUnit.pas, ASCII-7), two already hold UTF-8 with BOM:
  # the question names only the refused one; Yes runs the two others as ONE batch and the raised one per unit, in one run ---
  $names = 'mixed.question.names.only.refused', 'mixed.status.raised.one', 'mixed.converted.three', 'mixed.batch.note.two', 'mixed.unit.bom', 'mixed.backups', 'mixed.no.second.question'
  if ($script:raiseWhy) {
    foreach ($n in $names) { RCheck $n $false }
  } else {
    [IO.File]::WriteAllBytes($pas, $before)  # back to the ASCII-7 original
    foreach ($u in $pas2, $pas3) { $e = AddViaDialog $p.Id $add $u; if ($e -ne '') { "WARN  add $u : $e" | Out-Host } }
    $reports0 = @(Get-ChildItem -LiteralPath $rulesDir -Filter 'convert-run-*.txt').Count
    $ce = ClickConvert $p.Id $main $conv; if ($ce -ne '') { "WARN  $ce" | Out-Host }
    $dlg = WaitCls $p.Id 'TMessageForm' 120
    $txt = if ($dlg -ne [IntPtr]::Zero) { MsgText $dlg } else { '' }
    RCheck 'mixed.question.names.only.refused' (($txt -match 'FixUnit\.pas is ASCII-7') -and ($txt -notmatch 'Second\.pas') -and ($txt -notmatch 'Third\.pas') -and ($txt -match 'Raise\.rules 1:9')) "$txt | status: $(Status $main)"
    if ($dlg -ne [IntPtr]::Zero) { [void](AnswerDlg $dlg 'Yes') }
    $st = WaitStatusMatch $main 'Raised 1 file' 900
    RCheck 'mixed.status.raised.one' ($st -match '^Raised 1 file\(s\) to UTF-8 with BOM \(asked before the run\): FixUnit\.pas\. ') $st
    $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 600 -and -not ((Status $main) -match 'Converted \d+ of \d+ unit x book')) { Start-Sleep -Milliseconds 300 }
    $st = Status $main
    $col = @([W]::Column($lv, 2))
    RCheck 'mixed.converted.three' ((@($col | Where-Object { $_ -eq 'converted' }).Count -eq 3) -and ($st -match 'Converted 3 of 3 unit x book pair')) ("rows: $($col -join ' | ') status: $st")
    $newest = Get-ChildItem -LiteralPath $rulesDir -Filter 'convert-run-*.txt' | Sort-Object LastWriteTime | Select-Object -Last 1
    $rep = if ($null -ne $newest) { [IO.File]::ReadAllText($newest.FullName) } else { '' }
    RCheck 'mixed.batch.note.two' ((@(Get-ChildItem -LiteralPath $rulesDir -Filter 'convert-run-*.txt').Count -gt $reports0) -and ($rep -match '(?m)^\t\tnote\t+batch: 2 unit\(s\) -- 2 ok')) ("report: " + (($rep -split "`r?`n" | Where-Object { $_ -match 'batch:' }) -join ' | '))
    RCheck 'mixed.unit.bom' ((Head $pas 3) -eq 'EF BB BF') ("head=" + (Head $pas 4))
    RCheck 'mixed.backups' ((Test-Path -LiteralPath ($pas2 + '.BCK1')) -and (Test-Path -LiteralPath ($pas3 + '.BCK1')) -and (@(Get-ChildItem -LiteralPath $tmp -Filter 'FixUnit.pas.BCK*').Count -ge 1)) ((@(Get-ChildItem -LiteralPath $tmp -Filter '*.BCK*' | ForEach-Object Name)) -join ',')
    Start-Sleep -Seconds 3
    RCheck 'mixed.no.second.question' ((WaitCls $p.Id 'TMessageForm' 2) -eq [IntPtr]::Zero) (TopsNow $p.Id)
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
