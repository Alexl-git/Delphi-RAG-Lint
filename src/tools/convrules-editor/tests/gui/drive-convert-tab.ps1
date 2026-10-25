# Driven GUI check for the Convert tab (feat/convert-tab, Task 7, 2026-09-29).
# Usage: pwsh -NoProfile -File drive-convert-tab.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoIndex]
#        A FROZEN drag-lint.exe must sit beside the exe: the fixture index is built with THAT engine (the
#        editor finds its engine the same way), never with a live dll-win64 build another session may be
#        redeploying. Its Win64 library index must answer (the conversion resolves TLabel/TStaticText there).
# Builds a fixture project in a fresh temp folder, in the _D-RAG layout the editor derives the project file
# from (ProjectFileForDb: <dir>\_D-RAG\Fix.sqlite -> <dir>\Fix.dproj -- the run's project file, whatever the Destination):
#   Fix.dpr / Fix.dproj / FixUnit.pas + FixUnit.dfm (one TLabel) / Loose.pas (NOT in the .dpr) /
#   rules\Fix.rules (one #convert TLabel -> TStaticText) / _D-RAG\Fix.sqlite (index --project Fix.dproj).
# Then: Conversion > Convert..., Check all, Add Loose.pas -> Convert is REFUSED (unindexed) and nothing is
# backed up; delete it; Add FixUnit.pas -> Convert converts it in place (.BCK1 for .pas and .dfm, both named
# in the grid and the report; the report is UTF-8 without a BOM and records the final reindex). One convert-apply on this fixture takes ~90-110 s; the wait is 600 s.
# C16 (2026-10-10): mid-run the status bar shows the progress line (run.progress.status), Reindex project is locked.
# C17: Conversion > Reindex project after the run (reindex.status) and with Fix.dproj renamed away (reindex.refused.no.project.file).
# N1 (2026-10-23): a REAL mouse click on Convert while the progress window holds the editor is reported on the
# status line once idle, and nothing runs (n1.*). Needs the editor visible on the desktop (run under the GUI lock).
# N7/N11 (2026-10-23): POSTED commands under the progress window (WM_COMMAND for Add... and Convert, BM_CLICK for
# Delete) are refused, the first one reported, none run (n7.*); WaitIdle also asks the editor ('ConvRulesEditor.Busy').
# -ProofNoIndex skips the index step: the conversion checks must then FAIL, which is the proof they can.
# The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe, [switch]$ProofNoIndex, [switch]$ProofNoWindow)
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

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('convert-tab-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'; $loose = Join-Path $tmp 'Loose.pas'
$book = Join-Path $rulesDir 'Fix.rules'
# The Dest.dproj template of drive-unit-harvest.ps1 (the IDE's Base / Base_Win64 group shape), MainSource Fix.dpr.
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
# Task 5's live-runner fixture text (TestConvertRunnerLive), verbatim.
WriteAscii (Join-Path $tmp 'Fix.dpr') @'
program Fix;

uses
  Vcl.Forms,
  FixUnit in 'FixUnit.pas' {FixForm};

begin
  Application.Initialize;
  Application.Run;
end.
'@
WriteAscii $pas @'
unit FixUnit;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;

type
  TFixForm = class(TForm)
    Label1: TLabel;
  end;

var
  FixForm: TFixForm;

implementation

{$R *.dfm}

end.
'@
WriteAscii $dfm @'
object FixForm: TFixForm
  Left = 0
  Top = 0
  Caption = 'Fix'
  object Label1: TLabel
    Left = 8
    Top = 8
    Caption = 'Hello'
  end
end
'@
WriteAscii $book @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
# NOT in Fix.dpr, so NOT in the project index (the closure is the .dpr's members).
WriteAscii $loose @'
unit Loose;

interface

implementation

end.
'@

$p = $null
try {
  if ($ProofNoIndex) {
    "NOTE  -ProofNoIndex: the index step is SKIPPED; the conversion checks below are expected to FAIL"
  } else {
    $t0 = Get-Date
    $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
    $code = $LASTEXITCODE
    $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
    Check 'fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s $summary" -f ((Get-Date) - $t0).TotalSeconds)
  }

  # The file FIRST, then the flags: ConvRulesEditor.dpr auto-opens only a LEADING file argument,
  # and the rules folder of the run is that book's folder.
  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2

  # --- 1. Conversion > Convert... shows the Convert tab ---
  $invoked = [W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $active = @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) })
  Check 'menu.convert' ($invoked -and ($active -contains 'Convert')) ("invoked=$invoked active tabs: " + ($active -join ', '))

  # The tab's controls, located by STRUCTURE, not by caption alone (other tabs have
  # their own Add... / Delete): Convert is the button beside the progress bar; the
  # tab panel is its row's grandparent.
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'tab.controls' $false "Convert buttons beside a progress bar: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $lv = @(Find ([CT]::Parent([CT]::Parent($conv))) 'TListView' $null)[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  $del = @(Find ([CT]::Parent($add)) 'TButton' 'Delete')[0]
  $src = @(Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0]
  Check 'tab.controls' ($null -ne $lv -and $null -ne $checkAll -and $null -ne $books -and $null -ne $add -and $null -ne $del -and $null -ne $src) `
    ("lv={0} checkAll={1} books={2} add={3} delete={4} sources={5}" -f ($null -ne $lv), ($null -ne $checkAll), ($null -ne $books), ($null -ne $add), ($null -ne $del), ($null -ne $src))
  if ($null -eq $lv -or $null -eq $checkAll -or $null -eq $books -or $null -eq $add -or $null -eq $del -or $null -eq $src) { return }

  # --- 2. the rules folder's books are listed ---
  $bookItems = [CT]::Items($books)
  Check 'books.listed' (@($bookItems | Where-Object { $_ -like 'Fix.rules*' }).Count -eq 1) ($bookItems -join ' | ')

  # --- 3. Check all ---
  Click $checkAll
  Start-Sleep -Milliseconds 500

  # --- 3b. N1: a Convert click while the progress window holds the editor is REPORTED ---
  # Adding a unit runs long calls behind the modal progress window (the unit picker's lists,
  # the C8 analysis). A mouse click on Convert then lands on a disabled window: Windows drops
  # it, ConvertClick never runs. The editor must say so once it is idle again, and not run.
  # FixUnit.pas: its C8 analysis (class lookups) reliably outlasts the window's 400 ms delay.
  [void][W]::SetForegroundWindow($main)
  Click $add
  $dlg = WaitCls $p.Id '#32770' 20
  Start-Sleep -Milliseconds 700
  [void][W]::SendS(@([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0], 0x000C, [IntPtr]::Zero, $pas)
  Click (@(Find $dlg 'Button' '&Open')[0])
  # N9: the progress window is timing-dependent. If it never appears, a REAL click would start an actual
  # Convert and every later check would cascade. So the click is only made while the window holds the
  # editor; otherwise 3b FAILS with a clear precondition detail, the add is waited out, and the click is skipped.
  # -ProofNoWindow skips the wait for the window: 3b must FAIL and every later check must still pass.
  $wait = [IntPtr]::Zero; $t0 = Get-Date
  if ($ProofNoWindow) { "NOTE  -ProofNoWindow: the wait for the progress window is SKIPPED; only n1.click.under.progress is expected to FAIL" }
  else { while ($wait -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { $wait = WaitCls $p.Id 'TEngineWaitForm' 0; if ($wait -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 50 } } }
  $disabled = -not [W]::IsWindowEnabled($main)
  if (($wait -ne [IntPtr]::Zero) -and $disabled) {
    [W]::MouseClick($conv)
    [void](WaitIdle $p.Id $main 90)
    $st = Status $main
    Check 'n1.click.under.progress' $true "(precondition: the click landed while the progress window disabled the editor) window=True disabled=$disabled"
    Check 'n1.lost.click.reported' ($st -match 'Convert was NOT started: it was clicked while the editor was busy \(.+\)\. Click Convert again\.$') $st
    Check 'n1.lost.click.no.run' ((-not (RunInProgress $st)) -and ($st -notlike '*Convert refused*') -and -not (Test-Path -LiteralPath ($pas + '.BCK1'))) $st
  } else {
    # let the add finish; NO click, so no real Convert is started. The progress window shows only after a 400 ms delay,
    # so first wait for the row to land (WaitIdle alone can see a brief false idle before the window opens).
    $t1 = Get-Date; while (((Get-Date) - $t1).TotalSeconds -lt 60 -and -not ([CT]::Items($src) -contains $pas)) { Start-Sleep -Milliseconds 250 }
    [void](WaitIdle $p.Id $main 90)
    Check 'n1.click.under.progress' $false "precondition: progress window never appeared (window=$($wait -ne [IntPtr]::Zero) disabled=$disabled); click skipped, n1.lost.click.* not evaluated"
  }
  [void](WaitIdle $p.Id $main 30)
  [void][W]::Send($src, 0x0185, [IntPtr]1, [IntPtr]0)   # LB_SETSEL row 0, then Delete: step 3c starts from an empty list
  Click $del
  Start-Sleep -Seconds 1

  # --- 3c. N7/N11: commands POSTED while the progress window holds the editor are refused, reported, never run ---
  # A disabled window does not stop a posted message: a WM_COMMAND (BN_CLICKED) reached AddClick / ConvertClick
  # INSIDE the progress window's modal loop (the Open dialog on top of TEngineWaitForm, a re-entrant Convert),
  # and a BM_CLICK was dropped without a word (the lost second Add...). While the window is up: WM_COMMAND for
  # Add..., WM_COMMAND for Convert, BM_CLICK for Delete. None may run; the first is reported once idle.
  $n0 = [int][W]::Send($src, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)
  [void][W]::SetForegroundWindow($main)
  Click $add
  $dlg = WaitCls $p.Id '#32770' 20
  Start-Sleep -Milliseconds 700
  [void][W]::SendS(@([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0], 0x000C, [IntPtr]::Zero, $pas)
  Click (@(Find $dlg 'Button' '&Open')[0])
  $wait = [IntPtr]::Zero; $t0 = Get-Date
  while ($wait -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { $wait = WaitCls $p.Id 'TEngineWaitForm' 0; if ($wait -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 50 } }
  $disabled = -not [W]::IsWindowEnabled($main)
  if (($wait -ne [IntPtr]::Zero) -and $disabled) {
    [void][W]::PostMessage([CT]::Parent($add), 0x0111, [IntPtr]::Zero, $add)    # WM_COMMAND, BN_CLICKED (0), lParam = the button
    [void][W]::PostMessage([CT]::Parent($conv), 0x0111, [IntPtr]::Zero, $conv)
    Click $del
    # Anything the posted commands opened is recorded and closed, so a RED run still ends.
    $opened = @(); $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 120) {
      foreach ($h in @(Forms $p.Id | Where-Object { [W]::Cls($_) -in '#32770', 'TMessageForm' })) {
        $opened += ('{0}/{1}' -f [W]::Cls($h), [W]::Txt($h))
        if ([W]::Cls($h) -eq '#32770') { Click (@(Find $h 'Button' 'Cancel')[0]) } else { [void][W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
        Start-Sleep -Milliseconds 500
      }
      if ((WaitCls $p.Id 'TEngineWaitForm' 0) -eq [IntPtr]::Zero -and -not [B]::Busy($main) -and [W]::IsWindowEnabled($main)) { break }
      Start-Sleep -Milliseconds 100
    }
    [void](WaitIdle $p.Id $main 90)
    $st = Status $main
    $items = [CT]::Items($src)
    Check 'n7.posted.under.progress' $true "(precondition: posted while the progress window disabled the editor) window=True disabled=$disabled"
    Check 'n7.add.not.run' ($opened.Count -eq 0) ("dialogs opened by the posted commands: " + ($opened -join ' | '))
    Check 'n7.convert.not.run' ((-not (RunInProgress $st)) -and ($st -notlike '*Convert refused*') -and -not (Test-Path -LiteralPath ($pas + '.BCK1'))) $st
    Check 'n7.delete.not.run' (($n0 -eq 0) -and ($items.Count -eq 1) -and ($items -contains $pas)) ("before=$n0 items: " + ($items -join ' | '))
    Check 'n7.refusal.reported' ($st -match 'Add was NOT run: it was clicked while the editor was busy \(.+\)\. Click it again\.$') $st
  } else {
    $t1 = Get-Date; while (((Get-Date) - $t1).TotalSeconds -lt 60 -and -not ([CT]::Items($src) -contains $pas)) { Start-Sleep -Milliseconds 250 }
    [void](WaitIdle $p.Id $main 90)
    Check 'n7.posted.under.progress' $false "precondition: progress window never appeared (window=$($wait -ne [IntPtr]::Zero) disabled=$disabled); nothing posted, n7.* not evaluated"
  }
  # Idle now: the same Delete click must work (step 4 starts from an empty list).
  [void][W]::Send($src, 0x0185, [IntPtr]1, [IntPtr]0)
  Click $del
  Start-Sleep -Seconds 1
  $n = [int][W]::Send($src, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)
  Check 'n7.idle.delete.runs' ($n -eq 0) "count=$n"

  # --- 4./5. an UNINDEXED unit: Convert refuses, and nothing is touched ---
  $e = AddViaDialog $p.Id $add $loose
  $items = [CT]::Items($src)
  Check 'loose.added' (($e -eq '') -and ($items -contains $loose)) ("$e items: " + ($items -join ' | ') + '; status: ' + (Status $main))
  $before = Status $main
  Click $conv
  $st = WaitStatus $main $before 30
  Check 'unindexed.refused' (($st -like '`[!`] Convert refused*') -and ($st -match 'Loose\.pas')) "$st$(if ($dlg) { "; editor dialog: $dlg" })"
  Check 'unindexed.no.backup' (-not (Test-Path -LiteralPath ($loose + '.BCK1'))) '(negative control: a refused run touches nothing)'

  # --- 6. Delete the row ---
  [void][W]::Send($src, 0x0185, [IntPtr]1, [IntPtr]0)   # LB_SETSEL: select row 0 (multi-select list)
  Click $del
  Start-Sleep -Seconds 1
  $n = [int][W]::Send($src, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)
  Check 'sources.deleted' ($n -eq 0) "count=$n"

  # --- 7. an INDEXED unit: Convert converts it in place ---
  $e = AddViaDialog $p.Id $add $pas
  $items = [CT]::Items($src)
  Check 'fixunit.added' (($e -eq '') -and ($items -contains $pas)) ("$e items: " + ($items -join ' | ') + '; status: ' + (Status $main))
  $before = Status $main
  Click $conv
  # --- 7a. mid-run: File > Save / Save As / Curate and Conversion > Reindex project (C17) are locked, Open is not ---
  $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 20 -and -not (RunInProgress (Status $main))) { Start-Sleep -Milliseconds 250 }
  $lockPaths = 'File|Save', 'File|Save As...', 'File|Curate...', 'File|Open...', 'Conversion|Reindex project'
  $midRun = @($lockPaths | ForEach-Object { [W]::MenuEnabled($main, $_) })
  Check 'run.locks.file.menu' ((RunInProgress (Status $main)) -and ($midRun -join ',') -eq '0,0,0,1,0') ("Save,SaveAs,Curate,Open,Reindex = " + ($midRun -join ',') + "; status: " + (Status $main))
  # --- 7b. C16: the status bar names the unit, the book, the phase and both clocks while the apply runs ---
  $progressRe = '^Unit 1 of 1: FixUnit -- book 1 of 1 Fix: applying \(\d+:\d\d, total \d+:\d\d\)$'
  $seen = ''; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt 120 -and $seen -eq '') { $s = Status $main; if ($s -match $progressRe) { $seen = $s } elseif (-not (RunInProgress $s)) { break }; Start-Sleep -Milliseconds 250 }
  Check 'run.progress.status' ($seen -ne '') "seen: $seen; last: $(Status $main)"
  $st = WaitStatus $main $before 600
  $afterRun = @($lockPaths | ForEach-Object { [W]::MenuEnabled($main, $_) })
  Check 'run.unlocks.file.menu' (($afterRun -join ',') -eq '1,1,1,1,1') ("Save,SaveAs,Curate,Open,Reindex = " + ($afterRun -join ','))
  # Results grid: Book / Unit / Status / Edits / Remaining / Backup / Backup .dfm / Note.
  $cols = @(0..7 | ForEach-Object { , @([W]::Column($lv, $_)) })
  "  run: {0:N0}s; status: {1}" -f $script:waited, $st
  for ($i = 0; $i -lt $cols[0].Count; $i++) { '  row: ' + ((0..7 | ForEach-Object { $cols[$_][$i] }) -join ' / ') }
  Check 'convert.converted' (@([W]::Column($lv, 2)) -contains 'converted') "$(if ($dlg) { "editor dialog: $dlg" })"
  Check 'convert.summary' ($st -like 'Converted 1 of 1 unit x book pair(s); 0 failed and were restored.*Report: *') $st
  # Both restore points are named, with ONE shared number (.pas in col 5, .dfm in col 6).
  Check 'convert.grid.dfm.backup' ((@([W]::Column($lv, 5)) -contains 'FixUnit.pas.BCK1') -and (@([W]::Column($lv, 6)) -contains 'FixUnit.dfm.BCK1')) `
    ("Backup: " + (@([W]::Column($lv, 5)) -join ',') + "; Backup .dfm: " + (@([W]::Column($lv, 6)) -join ','))

  # --- 8. the files on disk ---
  Check 'convert.pas.changed' ((Get-Content -LiteralPath $pas -Raw) -match 'TStaticText')
  Check 'convert.bck1' ((Test-Path -LiteralPath ($pas + '.BCK1')) -and (Test-Path -LiteralPath ($dfm + '.BCK1')) -and ((Get-Content -LiteralPath ($pas + '.BCK1') -Raw) -match 'TLabel')) `
    ("FixUnit.pas.BCK1={0} FixUnit.dfm.BCK1={1}" -f (Test-Path -LiteralPath ($pas + '.BCK1')), (Test-Path -LiteralPath ($dfm + '.BCK1')))
  # A converted .dfm must still be TEXT (a binary one converts cleanly and dies at form load).
  Check 'convert.dfm.still.text' ((Get-Content -LiteralPath $dfm -Raw).StartsWith('object ')) ((Get-Content -LiteralPath $dfm -TotalCount 2) -join ' / ')
  $reports = @([IO.Directory]::GetFiles($rulesDir, 'convert-run-*.txt'))
  Check 'convert.report' ($reports.Count -eq 1) (($reports | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', ')
  # The report names the .dfm backup, records the closing reindex and the run's end, and is UTF-8 WITHOUT a BOM.
  # (An if-expression would unroll an empty byte[] to $null and GetString would throw.)
  [byte[]]$repBytes = [byte[]]::new(0)
  if ($reports.Count -eq 1) { $repBytes = [IO.File]::ReadAllBytes($reports[0]) }
  $repText = [Text.Encoding]::UTF8.GetString($repBytes)
  $bom = ($repBytes.Length -ge 3) -and ($repBytes[0] -eq 0xEF) -and ($repBytes[1] -eq 0xBB) -and ($repBytes[2] -eq 0xBF)
  Check 'convert.report.content' ((-not $bom) -and ($repText -match 'FixUnit\.dfm\.BCK1') -and ($repText -match "Final reindex`tok") -and ($repText -match "Run`tcompleted")) `
    ("bom=$bom bytes=$($repBytes.Length) dfmBackup=$($repText -match 'FixUnit\.dfm\.BCK1') final=$($repText -match "Final reindex`t\S+")")

  # --- 9. C17: Conversion > Reindex project on the fixture ---
  # Waits for a reindex outcome: a status that DIFFERS from $Before (an earlier '[!]' line
  # must not pass) and is a reindex outcome or an error, not the 'Reindexing ...' line.
  function WaitReindex($main, $Before, $Seconds) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
      Start-Sleep -Milliseconds 300
      $s = Status $main
      if ($s -eq $Before) { continue }
      # Re-read after a pause: WM_GETTEXTLENGTH and WM_GETTEXT are two messages, and a status
      # written between them came back cut to the OLD length ('Reindexed Fix.dproj: fi').
      if ($s -like 'Reindexed *' -or $s -like 'Reindex of *' -or $s -like '`[!`] *') { Start-Sleep -Milliseconds 500; return (Status $main) }
    }
    Status $main
  }
  $before = Status $main
  $invoked = [W]::InvokeMenu($main, 'Conversion|Reindex project')
  $st = WaitReindex $main $before 120
  Check 'reindex.status' ($invoked -and ($st -match '^Reindexed Fix\.dproj \(Fix\.sqlite\): \d+ file\(s\) in the index, compile closure \d+ \(\d+:\d\d\)$')) "invoked=$invoked status: $st"
  # The refusal: the project file gone (renamed away and back).
  $off = $dproj + '.off'
  [IO.File]::Move($dproj, $off)
  try {
    $before = Status $main
    [void][W]::InvokeMenu($main, 'Conversion|Reindex project')
    $st = WaitReindex $main $before 20
    Check 'reindex.refused.no.project.file' ($st -like ('`[!`] Reindex refused: the project index ' + $db + ' has no project file on disk -- expected ' + $dproj + '.')) $st
  } finally { [IO.File]::Move($off, $dproj) }
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  # The engine child may still hold the index for a moment after the kill.
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-convert: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
