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
# GATELEAK env.vcl.atoms (2026-10-27): before the launch, the VCL atoms leaked by killed Delphi processes are
# reclaimed (vcl-atoms.ps1); after it, the editor's own two VCL atoms must exist, else FindControl is nil and every
# button is dead (the 'add.dialog' flake). -ProofAtomCheck asks for a wrong atom name: env.vcl.atoms must FAIL.
param([string]$Exe, [switch]$ProofNoIndex, [switch]$ProofNoWindow, [switch]$ProofOccluded, [switch]$ForeignActive, [switch]$ProofAtomCheck)
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
  /* DRV-2: a press at the spot the cursor already stands on (the previous run's last click, same layout) did not reach
     the editor's WM_SETCURSOR hit-test path in runs 2 and 3 of every batch: the cursor is moved away first, so the click is a real MOVE + press. */
  public static void MouseClickFresh(IntPtr h) { SetCursorPos(2, 2); System.Threading.Thread.Sleep(200); MouseClick(h); }
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
  [DllImport("user32.dll", EntryPoint="WindowFromPoint")] static extern IntPtr WFP(PT p);
  public static IntPtr WindowFromPoint(int x, int y) { PT p; p.X = x; p.Y = y; return WFP(p); }
  public static List<IntPtr> Tops(uint pid) { var r = new List<IntPtr>(); EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr parent) { var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  // Two messages (length, then text) race a status written in between: read with slack, then re-read until two reads agree.
  static string TxtOnce(IntPtr h) { int n = (int)Send(h, 0x000E, IntPtr.Zero, IntPtr.Zero); int cap = n + 1024; var s = new StringBuilder(cap); SendSB(h, 0x000D, (IntPtr)cap, s); return s.ToString(); }
  public static string Txt(IntPtr h) { string p = TxtOnce(h); for (int i = 0; i < 5; i++) { string c = TxtOnce(h); if (c == p) return c; p = c; } return p; }
  /* DRV-2b: Txt that gives up after MS (null) instead of blocking. While EngineHold has suspended an engine child that the
     editor waits for SYNCHRONOUSLY (the project-index listing after the C8 check), the editor's main thread answers no
     message: a plain SendMessage then waits for the editor's 180 s engine timeout, and the driver cannot resume the child
     meanwhile (a deadlock that turned every run's status into "file listing failed ... timeout"). */
  [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW")] static extern IntPtr SMT(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="SendMessageTimeoutW")] static extern IntPtr SMTSB(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint ms, out IntPtr r);
  static string TxtTOnce(IntPtr h, uint ms) { IntPtr n; if (SMT(h, 0x000E, IntPtr.Zero, IntPtr.Zero, 2, ms, out n) == IntPtr.Zero) return null; int cap = (int)n + 1024; var s = new StringBuilder(cap); IntPtr r; if (SMTSB(h, 0x000D, (IntPtr)cap, s, 2, ms, out r) == IntPtr.Zero) return null; return s.ToString(); }
  public static string TxtT(IntPtr h, uint ms) { string p = TxtTOnce(h, ms); if (p == null) return null; for (int i = 0; i < 5; i++) { string c = TxtTOnce(h, ms); if (c == null) return null; if (c == p) return c; p = c; } return p; }
  public static uint PidOf(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  /* DRV-2b: the N1 click is a REAL click at screen coordinates; another application's window over the Convert button
     (seen: Chrome_RenderWidgetHostHWND) takes it, so the editor never sees it. The editor is made topmost (no activation:
     it is disabled under the progress window) for the click and put back afterwards. */
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  public static void SetTopmost(IntPtr h, bool on) { SetWindowPos(h, (IntPtr)(on ? -1 : -2), 0, 0, 0, 0, 0x0013); }
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
# DRV-2b: WaitIdle that also records every DISTINCT status line it sees (sampled every 50 ms) into
# $script:trail -- tells "the notice was never raised" from "it was raised and then overwritten".
function WaitIdleTrail($procId, $main, $sec) {
  $idleSince = $null; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $s = Status $main; if ($script:trail.Count -eq 0 -or $script:trail[-1] -ne $s) { $script:trail += $s }
    $busy = (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -in 'TEngineWaitForm', 'TMessageForm', '#32770' }).Count -gt 0) -or -not [W]::IsWindowEnabled($main) -or [B]::Busy($main)
    if ($busy) { $idleSince = $null } elseif ($null -eq $idleSince) { $idleSince = Get-Date } elseif (((Get-Date) - $idleSince).TotalSeconds -ge 2) { return $true }
    Start-Sleep -Milliseconds 50
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
# DRV-2b -ProofOccluded: a topmost window of THIS process over H's rectangle (shown after the editor went topmost),
# so the N1 click lands on it: n1.click.under.progress must FAIL with editor=False.
function NewOccluder($h) {
  Add-Type -AssemblyName System.Windows.Forms
  $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
  $fm = New-Object System.Windows.Forms.Form
  $fm.FormBorderStyle = 'None'; $fm.ShowInTaskbar = $false; $fm.TopMost = $true; $fm.StartPosition = 'Manual'
  $fm.Bounds = New-Object System.Drawing.Rectangle(($r.L - 20), ($r.T - 20), ($r.R - $r.L + 40), ($r.B - $r.T + 40))
  $fm.Show(); [System.Windows.Forms.Application]::DoEvents(); return $fm
}
# DRV-2b -ForeignActive: another application's window (here: one of the driver's own process) takes the foreground while
# the progress window is up, as when the user switches away from a long Add. The lost-command notice must still appear
# once the operation ends (an exe whose notice waits for Screen.ActiveForm = main form fails n1/n7 then).
function NewForeign {
  Add-Type -AssemblyName System.Windows.Forms
  $fm = New-Object System.Windows.Forms.Form
  $fm.Text = 'drv2b foreign'; $fm.ShowInTaskbar = $false; $fm.StartPosition = 'Manual'
  $fm.Bounds = New-Object System.Drawing.Rectangle(0, 0, 240, 120)
  $fm.Show(); [System.Windows.Forms.Application]::DoEvents(); [void][W]::SetForegroundWindow($fm.Handle); [System.Windows.Forms.Application]::DoEvents()
  return $fm
}
function CloseForm($fm) { if ($null -ne $fm) { $fm.Close(); $fm.Dispose() } }
# DRV-2b: Status that returns $null instead of blocking on an editor whose main thread waits for a HELD engine child.
function StatusT($main) { $parts = @(Find $main 'TStatusBar' $null | ForEach-Object { [W]::TxtT($_, 200) }); if ($parts -contains $null) { return $null }; $parts -join ' | ' }
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
# Add... -> the common Open dialog ('#32770'): the file name goes into its 'Edit', then '&Open'.
# DRV-2b: the Open dialog, i.e. a visible #32770 of the editor WITH an Edit child. A bare '#32770' also matches a
# task dialog / message box (seen twice: no Edit child, the run then threw in SendS).
function WaitOpenDlg($procId, $sec) { $t0 = Get-Date; do { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq '#32770' -and @([W]::Kids($h) | Where-Object { [W]::Cls($_) -eq 'Edit' }).Count -gt 0) { return $h } }; Start-Sleep -Milliseconds 250 } while (((Get-Date) - $t0).TotalSeconds -lt $sec); return [IntPtr]::Zero }
function AddViaDialog($procId, $addBtn, $path) {
  Click $addBtn
  $dlg = WaitOpenDlg $procId 20
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

# DRV-2: the engine call behind Add... can be shorter than the progress window's 400 ms show delay (or a cache hit),
# so the N1/N7 preconditions were met in only 1 of 3 runs. EngineHold makes the call long on purpose: it watches for
# a NEW drag-lint.exe (the one beside the editor, so other sessions' engines do not count) at ~1 ms and SUSPENDS it
# (NtSuspendProcess) until Release(); the editor then waits on its engine call, shows the progress window after
# 400 ms and stays behind it for as long as the driver holds. Release() resumes everything it suspended (idempotent).
# No product code involved. If no engine child ever starts (an editor-side cache hit), nothing is held and the
# precondition check reports "progress window never appeared" as before.
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Threading; using System.Diagnostics;
using System.Collections.Generic; using System.Runtime.InteropServices;
public static class EngineHold {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int f, StringBuilder s, ref int n);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr h);
  [DllImport("ntdll.dll")] static extern int NtResumeProcess(IntPtr h);
  static volatile bool run; static Thread th; static HashSet<int> seen; static List<IntPtr> held = new List<IntPtr>(); static List<int> hpid = new List<int>(); public static List<string> Log = new List<string>(); static int total; public static int LastPid; static readonly object gate = new object();
  static string Image(int pid) {
    IntPtr h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return "";
    try { var s = new StringBuilder(1024); int n = 1024; return QueryFullProcessImageNameW(h, 0, s, ref n) ? s.ToString() : ""; } finally { CloseHandle(h); }
  }
  static int[] Ids() { var ps = Process.GetProcessesByName("drag-lint"); var r = new int[ps.Length]; for (int i = 0; i < ps.Length; i++) { r[i] = ps[i].Id; ps[i].Dispose(); } return r; }
  public static void Arm(string exe) {
    Release();
    seen = new HashSet<int>(Ids()); run = true; total = 0; lock (gate) { Log.Clear(); }
    th = new Thread(() => { while (run) { foreach (int id in Ids()) if (seen.Add(id) && string.Equals(Image(id), exe, StringComparison.OrdinalIgnoreCase)) {
      IntPtr h = OpenProcess(0x0800, false, id); if (h != IntPtr.Zero) { int rs = NtSuspendProcess(h); lock (gate) { held.Add(h); hpid.Add(id); total++; LastPid = id; Log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " S" + id + "=" + rs); } } }
      Thread.Sleep(1); } });
    th.IsBackground = true; th.Start();
  }
  public static int Total() { return total; }
  public static int Held() { lock (gate) { return held.Count; } }
  /* Resumes what is held NOW but keeps watching: the next engine child is held again (its pid was never seen). */
  public static int ResumeHeld() { int n; lock (gate) { n = held.Count; for (int i = 0; i < held.Count; i++) { int rr = NtResumeProcess(held[i]); Log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " R" + hpid[i] + "=" + rr); CloseHandle(held[i]); } held.Clear(); hpid.Clear(); } return n; }
  public static int Release() {
    run = false; if (th != null) { th.Join(); th = null; }
    int n; lock (gate) { n = held.Count; for (int i = 0; i < held.Count; i++) { int rr = NtResumeProcess(held[i]); Log.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " X" + hpid[i] + "=" + rr); CloseHandle(held[i]); } held.Clear(); hpid.Clear(); }
    return n;
  }
}
"@
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
  . "$PSScriptRoot\vcl-atoms.ps1"; 'NOTE  ' + (VclAtomsReclaim)
  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  # GATELEAK: no VCL atoms = FindControl nil = every button click lost; a precondition, not an editor defect.
  $atoms = VclAtomsOf $p.Id $main -WrongName:$ProofAtomCheck
  Check 'env.vcl.atoms' (($atoms.Control -ne 0) -and ($atoms.Window -ne 0)) ("control=$($atoms.Control) window=$($atoms.Window) ($($atoms.Names)); 0 = the global atom table was full when the editor started")
  if (($atoms.Control -eq 0) -or ($atoms.Window -eq 0)) { return }
  Start-Sleep -Seconds 2
  # DRV-2b: the start-up work (book load, engine probes) runs behind the InputGate; a menu command posted then is
  # refused like any other (seen: 'active tabs: Classes' + busy=True, then every later step cascaded). Wait (up to the
  # engine timeout) until idle. (The 60 s+ block seen while other sessions held the library DB is NOT start-up: it is the
  # library unit-list read on the first Add..., not this wait.)
  [void](WaitIdle $p.Id $main 180)

  # --- 1. Conversion > Convert... shows the Convert tab ---
  # The start-up work comes in bursts (two 'info' probes, then the book load); a 2 s idle gap between them
  # satisfies WaitIdle, and a command posted into the next burst is refused. So: up to 3 tries, each after WaitIdle.
  for ($try = 1; $try -le 3; $try++) {
    $invoked = [W]::InvokeMenu($main, 'Conversion|Convert...')
    Start-Sleep -Seconds 2
    $active = @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) })
    if ((-not $invoked) -or ($active -contains 'Convert')) { break }
    [void](WaitIdle $p.Id $main 180)
  }
  Check 'menu.convert' ($invoked -and ($active -contains 'Convert')) ("invoked=$invoked tries=$([Math]::Min($try, 3)) active tabs: " + ($active -join ', ') + '; status: ' + (Status $main) + '; enabled=' + [W]::MenuEnabled($main, 'Conversion|Convert...') + ' busy=' + [B]::Busy($main))

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
  [void](WaitIdle $p.Id $main 60)
  Click $add
  $dlg = WaitOpenDlg $p.Id 20
  # DRV-2b: a BM_CLICK that reaches the editor in a busy burst is refused (InputGate); once idle, click again.
  if ($dlg -eq [IntPtr]::Zero) { [void](WaitIdle $p.Id $main 60); Click $add; $dlg = WaitOpenDlg $p.Id 20 }
  if ($dlg -eq [IntPtr]::Zero) { Check 'add.dialog' $false "no Open dialog after two Add... clicks; windows: $(TopsNow $p.Id); status: $(Status $main)"; return }
  Start-Sleep -Milliseconds 700
  [void][W]::SendS(@([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0], 0x000C, [IntPtr]::Zero, $pas)
  if (-not $ProofNoWindow) { [EngineHold]::Arm($engine) }   # DRV-2: hold the engine call so the progress window is up
  Click (@(Find $dlg 'Button' '&Open')[0])
  # N9: the progress window is timing-dependent. If it never appears, a REAL click would start an actual
  # Convert and every later check would cascade. So the click is only made while the window holds the
  # editor; otherwise 3b FAILS with a clear precondition detail, the add is waited out, and the click is skipped.
  # -ProofNoWindow skips the wait for the window: 3b must FAIL and every later check must still pass.
  $wait = [IntPtr]::Zero; $t0 = Get-Date
  if ($ProofNoWindow) { "NOTE  -ProofNoWindow: the wait for the progress window is SKIPPED; only n1.click.under.progress is expected to FAIL" }
  else {
    # DRV-2: Add... runs several engine calls (the unit-name lists of the picker, then the C8 class-ancestor and field
    # lookups of 'Checking N source unit(s) for inherited instances'); only the C8 stage is one the lost-click notice
    # survives (it waits for the OPERATION to end), and only some stages sit behind the progress window. So: every NEW
    # engine child is looked at (its command line); one that is not the C8 lookup of TFixForm is resumed at once, the
    # first C8 child stays suspended until the click is made.
    $lastPid = 0; $c8 = $false
    while ($wait -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) {
      if ([EngineHold]::LastPid -ne $lastPid) {
        $lastPid = [EngineHold]::LastPid
        $cl = try { (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $lastPid) -ErrorAction Stop).CommandLine } catch { '' }
        if (-not $c8) { if ($cl -match "TFixForm") { $c8 = $true } else { [void][EngineHold]::ResumeHeld() } }
      }
      if ($c8) { $wait = WaitCls $p.Id 'TEngineWaitForm' 0 }
      if ($wait -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 50 }
    }
  }
  $disabled = -not [W]::IsWindowEnabled($main)
  if (($wait -ne [IntPtr]::Zero) -and $disabled) {
    $script:dbg = 'wait=({0},{1}) conv=({2},{3}) held={4}' -f [W]::Left($wait), [W]::Top($wait), [W]::Left($conv), [W]::Top($conv), [EngineHold]::Held()
    $script:trail = @(Status $main)
    [W]::SetTopmost($main, $true)
    $occluder = if ($ProofOccluded) { NewOccluder $conv } else { $null }   # forced-wrong: another window over Convert
    [W]::MouseClickFresh($conv); [EngineHold]::Log.Add((Get-Date -Format 'HH:mm:ss.fff') + ' CLICK')
    $hit = [W]::WindowFromPoint([W]::Left($conv) + 5, [W]::Top($conv) + 5)
    $hitOk = ([W]::PidOf($hit) -eq [uint32]$p.Id); $hitCls = [W]::Cls($hit)
    $script:dbg += (' hit={0}/{1} editor={2}' -f [W]::Cls($hit), ($hit -eq $conv), $hitOk)
    if ($null -ne $occluder) { $occluder.Close(); $occluder.Dispose() }
    $foreign = if ($ForeignActive) { NewForeign } else { $null }
    if ($ForeignActive) { [EngineHold]::Log.Add('foreign.fg=' + ([W]::GetForegroundWindow() -eq $foreign.Handle)) }
    # DRV-2: the lost-click notice is appended once the OPERATION ends, so it only survives a click made during the
    # operation's LAST engine call (between calls it can fire and be overwritten by the next status). Add... makes a
    # few C8 calls: each further child is held and clicked under too, until none starts for 3 s.
    Start-Sleep -Milliseconds 700; [void][EngineHold]::ResumeHeld()
    for ($quiet = Get-Date; ((Get-Date) - $quiet).TotalSeconds -lt 3; ) {
      if ([EngineHold]::Held() -gt 0) {
        $w2 = WaitCls $p.Id 'TEngineWaitForm' 2
        if (($w2 -ne [IntPtr]::Zero) -and -not [W]::IsWindowEnabled($main)) { [W]::MouseClickFresh($conv) }
        Start-Sleep -Milliseconds 700; [void][EngineHold]::ResumeHeld(); $quiet = Get-Date
      } else { $s = StatusT $main; if ($null -ne $s -and $script:trail[-1] -ne $s) { $script:trail += $s }; Start-Sleep -Milliseconds 50 }
    }
    [EngineHold]::Log.Add((Get-Date -Format 'HH:mm:ss.fff') + ' REL'); $held = [EngineHold]::Release()
    [W]::SetTopmost($main, $false)
    [void](WaitIdleTrail $p.Id $main 90)
    $script:dbg += ' trail=[' + ($script:trail -join ' >> ') + '] hold=[' + ([EngineHold]::Log -join ' ') + ']'
    $st = Status $main
    Check 'n1.click.under.progress' $hitOk "(precondition: the click landed on the editor while the progress window disabled it) window=True disabled=$disabled editor=$hitOk hit=$hitCls"
    Check 'n1.lost.click.reported' ($st -match 'Convert was NOT started: it was clicked while the editor was busy \(.+\)\. Click Convert again\.$') ($st + ' | ' + $script:dbg)
    CloseForm $foreign
    Check 'n1.lost.click.no.run' ((-not (RunInProgress $st)) -and ($st -notlike '*Convert refused*') -and -not (Test-Path -LiteralPath ($pas + '.BCK1'))) $st
  } else {
    # let the add finish; NO click, so no real Convert is started. The progress window shows only after a 400 ms delay,
    # so first wait for the row to land (WaitIdle alone can see a brief false idle before the window opens).
    $heldN = '{0}/{1} c8={2}' -f [EngineHold]::Held(), [EngineHold]::Total(), $c8; [void][EngineHold]::Release()
    $t1 = Get-Date; while (((Get-Date) - $t1).TotalSeconds -lt 60 -and -not ([CT]::Items($src) -contains $pas)) { Start-Sleep -Milliseconds 250 }
    [void](WaitIdle $p.Id $main 90)
    Check 'n1.click.under.progress' $false "precondition: progress window never appeared (engine children held/total=$heldN window=$($wait -ne [IntPtr]::Zero) disabled=$disabled); click skipped, n1.lost.click.* not evaluated"
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
  [void](WaitIdle $p.Id $main 60)
  Click $add
  $dlg = WaitOpenDlg $p.Id 20
  # DRV-2b: a BM_CLICK that reaches the editor in a busy burst is refused (InputGate); once idle, click again.
  if ($dlg -eq [IntPtr]::Zero) { [void](WaitIdle $p.Id $main 60); Click $add; $dlg = WaitOpenDlg $p.Id 20 }
  if ($dlg -eq [IntPtr]::Zero) { Check 'add.dialog' $false "no Open dialog after two Add... clicks; windows: $(TopsNow $p.Id); status: $(Status $main)"; return }
  Start-Sleep -Milliseconds 700
  # GATELEAK: the Open dialog is a native modal loop that never calls Application.OnMessage, so InputGate cannot see
  # a WM_COMMAND(Add...) posted to the disabled editor meanwhile; AddClick must not nest a second Open dialog.
  [void][W]::PostMessage([CT]::Parent($add), 0x0111, [IntPtr]::Zero, $add)
  Start-Sleep -Milliseconds 1200
  $nOpen = @([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq '#32770' -and @([W]::Kids($_) | Where-Object { [W]::Cls($_) -eq 'Edit' }).Count -gt 0 }).Count
  Check 'add.reentrant.not.nested' ($nOpen -eq 1) ('Open dialogs while one is up and Add... is posted again: ' + $nOpen)
  [void][W]::SendS(@([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0], 0x000C, [IntPtr]::Zero, $pas)
  [EngineHold]::Arm($engine)   # DRV-2
  Click (@(Find $dlg 'Button' '&Open')[0])
  $wait = [IntPtr]::Zero; $t0 = Get-Date
  while ($wait -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { $wait = WaitCls $p.Id 'TEngineWaitForm' 0; if ($wait -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 50 } }
  $disabled = -not [W]::IsWindowEnabled($main)
  if (($wait -ne [IntPtr]::Zero) -and $disabled) {
    $script:trail = @(Status $main); [EngineHold]::Log.Add((Get-Date -Format 'HH:mm:ss.fff') + ' POST under=[' + [W]::Txt($wait) + '] child=[' + $(try { (Get-CimInstance Win32_Process -Filter ('ProcessId=' + [EngineHold]::LastPid) -ErrorAction Stop).CommandLine } catch { '' }) + ']')
    [void][W]::PostMessage([CT]::Parent($add), 0x0111, [IntPtr]::Zero, $add)    # WM_COMMAND, BN_CLICKED (0), lParam = the button
    [void][W]::PostMessage([CT]::Parent($conv), 0x0111, [IntPtr]::Zero, $conv)
    Click $del
    $foreign = if ($ForeignActive) { NewForeign } else { $null }
    if ($ForeignActive) { [EngineHold]::Log.Add('foreign.fg=' + ([W]::GetForegroundWindow() -eq $foreign.Handle)) }
    Start-Sleep -Milliseconds 1500; [void][EngineHold]::Release()   # DRV-2: the posts are handled inside the held window
    # Anything the posted commands opened is recorded and closed, so a RED run still ends.
    $opened = @(); $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 120) {
      foreach ($h in @(Forms $p.Id | Where-Object { [W]::Cls($_) -in '#32770', 'TMessageForm' })) {
        $opened += ('{0}/{1}' -f [W]::Cls($h), [W]::Txt($h))
        if ([W]::Cls($h) -eq '#32770') { Click (@(Find $h 'Button' 'Cancel')[0]) } else { [void][W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
        Start-Sleep -Milliseconds 500
      }
      if ((WaitCls $p.Id 'TEngineWaitForm' 0) -eq [IntPtr]::Zero -and -not [B]::Busy($main) -and [W]::IsWindowEnabled($main)) { break }
      $s = Status $main; if ($script:trail[-1] -ne $s) { $script:trail += $s }
      Start-Sleep -Milliseconds 100
    }
    [void](WaitIdleTrail $p.Id $main 90)
    $st = Status $main
    $items = [CT]::Items($src)
    Check 'n7.posted.under.progress' $true "(precondition: posted while the progress window disabled the editor) window=True disabled=$disabled"
    Check 'n7.add.not.run' ($opened.Count -eq 0) ("dialogs opened by the posted commands: " + ($opened -join ' | '))
    Check 'n7.convert.not.run' ((-not (RunInProgress $st)) -and ($st -notlike '*Convert refused*') -and -not (Test-Path -LiteralPath ($pas + '.BCK1'))) $st
    Check 'n7.delete.not.run' (($n0 -eq 0) -and ($items.Count -eq 1) -and ($items -contains $pas)) ("before=$n0 items: " + ($items -join ' | '))
    $fgOk = ([W]::PidOf([W]::GetForegroundWindow()) -eq [uint32]$p.Id); [EngineHold]::Log.Add('fg.editor=' + $fgOk)
    Check 'n7.refusal.reported' ($st -match 'Add was NOT run: it was clicked while the editor was busy \(.+\)\. Click it again\.$') ($st + ' | trail=[' + ($script:trail -join ' >> ') + '] hold=[' + ([EngineHold]::Log -join ' ') + ']')
    CloseForm $foreign
    if ($st -notmatch 'Add was NOT run') { [void][W]::SetForegroundWindow($main); Start-Sleep -Milliseconds 1500; "NOTE  n7.late  after SetForegroundWindow: $(Status $main)" }
  } else {
    [void][EngineHold]::Release()
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
  [void][EngineHold]::Release()   # DRV-2: never leave a suspended engine behind
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
