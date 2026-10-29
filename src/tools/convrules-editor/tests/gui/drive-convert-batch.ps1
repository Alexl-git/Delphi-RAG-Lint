# Driven GUI check for the Convert tab's BATCH MODE (B4 Task 6, 2026-10-23): two units, one book, one
# convert-apply call (engine apply-batch/1, `--unit` repeated) instead of one call per unit.
# Usage: pwsh -NoProfile -File drive-convert-batch.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoBatch]
#        A FROZEN drag-lint.exe must sit beside the exe (see drive-convert-tab.ps1): the fixture index is built
#        with THAT engine, and it must report the batch_units capability. Run under the GUI lock.
# Fixture (a fresh temp folder, the _D-RAG layout of drive-convert-tab.ps1): Fix.dpr lists FixUnit.pas/.dfm AND
# Second.pas/.dfm (one TLabel each), rules\Fix.rules (#convert TLabel -> TStaticText), _D-RAG\Fix.sqlite.
# Run 1 (batch): both units added, Convert -> the start status names batch mode, the status bar shows
# 'applying units 1-2 of 2 in one batch', exactly ONE convert-apply engine child (two --unit) lives, two
# 'converted' rows, .BCK1 for both .pas and both .dfm, the report holds ONE note row ('note' column, text 'batch: 2 unit(s) -- 2 ok ...')
# line and 'Final reindex<TAB>ok'.
# Run 2 (proof.env.off): the fixture is reset, the editor relaunched with CONVRULES_BATCH=off: no 'batch:' note,
# TWO convert-apply children (one per unit), two converted rows.
# -ProofNoBatch skips run 1 and judges the per-unit run (CONVRULES_BATCH=off) by the BATCH checks: they must FAIL,
# which is the proof they can. The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe, [switch]$ProofNoBatch)
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
  [void](WaitIdle $procId (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' })[0]) 90)   # and the C8 analysis behind the progress window
  return ''
}
# Waits until the status line differs from $Before and is not the run's own
# 'Converting ...' line or a C16 progress line (RunInProgress), or an editor dialog appears;
# returns the final status text.
function RunInProgress($st) { ($st -like 'Converting *') -or ($st -match '^(Unit|Book) \d+ of \d+[: ]') -or ($st -match '^All \d+ unit\(s\): ') -or ($st -like 'Final reindex (total *') }
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

# The convert-apply engine children of the editor (a batch run has ONE, with every unit as --unit).
function ApplyKids($proc) { @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" | Where-Object { $_.CommandLine -like '*convert-apply*' }) }

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('convert-batch-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas1 = Join-Path $tmp 'FixUnit.pas'; $dfm1 = Join-Path $tmp 'FixUnit.dfm'
$pas2 = Join-Path $tmp 'Second.pas'; $dfm2 = Join-Path $tmp 'Second.dfm'
$book = Join-Path $rulesDir 'Fix.rules'
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
WriteAscii (Join-Path $tmp 'Fix.dpr') @'
program Fix;

uses
  Vcl.Forms,
  FixUnit in 'FixUnit.pas' {FixForm},
  Second in 'Second.pas' {SecondForm};

begin
  Application.Initialize;
  Application.Run;
end.
'@
WriteAscii $book @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
# The two units' ORIGINAL text; the proof.env.off run starts from it again.
function WriteUnits {
  WriteAscii $pas1 @'
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
  WriteAscii $dfm1 @'
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
  WriteAscii $pas2 @'
unit Second;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;

type
  TSecondForm = class(TForm)
    Label2: TLabel;
  end;

var
  SecondForm: TSecondForm;

implementation

{$R *.dfm}

end.
'@
  WriteAscii $dfm2 @'
object SecondForm: TSecondForm
  Left = 0
  Top = 0
  Caption = 'Second'
  object Label2: TLabel
    Left = 8
    Top = 8
    Caption = 'World'
  end
end
'@
}
function IndexFixture {
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  return @{ Code = $code; Summary = $summary }
}
function ResetFixture {
  WriteUnits
  foreach ($f in @([IO.Directory]::GetFiles($tmp, '*.BCK*')) + @([IO.Directory]::GetFiles($rulesDir, 'convert-run-*.txt'))) { [IO.File]::Delete($f) }
  return (IndexFixture)
}

# One editor session: launch (CONVRULES_BATCH = $BatchEnv, unset when ''), open the Convert tab, check all
# books, add the two units, press Convert, sample the status bar and the engine children until the run ends.
# Returns the evidence (null when the session could not get that far); the editor is killed at the end.
function RunScenario([string]$BatchEnv, [string]$Tag) {
  $script:R = $null   # the evidence goes here, not down the pipeline (Check writes its PASS/FAIL lines there)
  $r = @{}
  [Environment]::SetEnvironmentVariable('CONVRULES_BATCH', $(if ($BatchEnv) { $BatchEnv } else { $null }), 'Process')
  try {
    # The file FIRST, then the flags (ConvRulesEditor.dpr auto-opens only a LEADING file argument).
    $script:p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  } finally { [Environment]::SetEnvironmentVariable('CONVRULES_BATCH', $null, 'Process') }
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($script:p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check "$Tag.main.window" ($main -ne [IntPtr]::Zero)
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2
  $invoked = [W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $active = @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) })
  Check "$Tag.menu.convert" ($invoked -and ($active -contains 'Convert')) ("invoked=$invoked active tabs: " + ($active -join ', '))
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check "$Tag.tab.controls" $false "Convert buttons beside a progress bar: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $lv = @(Find ([CT]::Parent([CT]::Parent($conv))) 'TListView' $null)[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  $src = @(Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0]
  $ok = ($null -ne $lv -and $null -ne $checkAll -and $null -ne $books -and $null -ne $add -and $null -ne $src)
  Check "$Tag.tab.controls" $ok
  if (-not $ok) { return }
  $bookItems = [CT]::Items($books)
  Check "$Tag.books.listed" (@($bookItems | Where-Object { $_ -like 'Fix.rules*' }).Count -eq 1) ($bookItems -join ' | ')
  Click $checkAll
  Start-Sleep -Milliseconds 500
  # One Add... per unit (the common dialog takes one path), each after the editor is idle. N11 (fixed 2026-10-23):
  # the second Add's click used to be lost -- WaitIdle saw a false idle while the main thread was blocked between
  # the first Add's engine calls, and the click was then dispatched inside the C8 analysis' progress window, where
  # Windows dropped it. WaitIdle now asks the editor (B::Busy), and a click that still lands in busy work is
  # refused and reported by the editor (ConvRules.InputGate), never run inside the window. No retry.
  function AddUnit($path) {
    [void](WaitIdle $script:p.Id $main 60)
    [void][W]::SetForegroundWindow($main)
    return (AddViaDialog $script:p.Id $add $path)
  }
  $e1 = AddUnit $pas1
  $e2 = AddUnit $pas2
  $items = [CT]::Items($src)
  Check "$Tag.units.added" (($e1 -eq '') -and ($e2 -eq '') -and ($items -contains $pas1) -and ($items -contains $pas2)) ("$e1 $e2 items: " + ($items -join ' | ') + '; status: ' + (Status $main))
  # --- Convert, and sample until the run ends ---
  $r.Start = ''; $r.Batch = ''; $r.Pids = @{}; $r.Dialog = ''
  [void](WaitIdle $script:p.Id $main 60)
  $before = Status $main
  Click $conv
  $sawRun = $false
  $t0 = Get-Date; $lastCim = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt 600) {
    $s = Status $main
    if ($r.Start -eq '' -and $s -like 'Converting *') { $r.Start = $s }
    if ($r.Batch -eq '' -and $s -match 'applying units 1-2 of 2 in one batch') { $r.Batch = $s }
    if (((Get-Date) - $lastCim).TotalMilliseconds -ge 1000) {
      foreach ($k in (ApplyKids $script:p)) { $r.Pids[[string]$k.ProcessId] = [regex]::Matches($k.CommandLine, '--unit').Count }
      $lastCim = Get-Date
    }
    $d = @(Forms $script:p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' })
    if ($d.Count -gt 0) { $r.Dialog = TopsNow $script:p.Id; break }
    if (RunInProgress $s) { $sawRun = $true }
    # A status that merely differs from the pre-click one is not the end: the Add flow may still be writing it.
    if ($sawRun -and -not (RunInProgress $s)) { break }
    if (-not $sawRun -and ((Get-Date) - $t0).TotalSeconds -gt 30) { break }   # the run never started
    Start-Sleep -Milliseconds 40
  }
  $r.Seconds = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Milliseconds 500
  $r.Status = Status $main
  $r.Cols = @(0..7 | ForEach-Object { , @([W]::Column($lv, $_)) })
  "  $Tag run: {0:N0}s; status: {1}" -f $r.Seconds, $r.Status
  for ($i = 0; $i -lt $r.Cols[0].Count; $i++) { '  row: ' + ((0..7 | ForEach-Object { $r.Cols[$_][$i] }) -join ' / ') }
  if ($null -ne $script:p -and -not $script:p.HasExited) { $script:p.Kill($true); [void]$script:p.WaitForExit(15000) }
  $script:R = $r
}
function ReportText {
  $reports = @([IO.Directory]::GetFiles($rulesDir, 'convert-run-*.txt'))
  if ($reports.Count -ne 1) { return }
  return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($reports[0]))
}
function ConvertedRows($r) { @($r.Cols[2] | Where-Object { $_ -eq 'converted' }).Count }
# The batch checks: true on a batch run, expected to FAIL on a per-unit one (-ProofNoBatch).
function BatchChecks($r, $repText, $Tag) {
  $kids = @($r.Pids.Keys)
  # The 'Converting ... batch mode (8 per call)...' line is overwritten by the first step within milliseconds, so it
  # is reported, not asserted (a sampled read of it is racy): the progress line below is the assertion.
  "  $Tag start status (informational): $($r.Start)"
  Check "$Tag.run.progress.batch" ($r.Batch -match '^Book 1 of 1 Fix: applying units 1-2 of 2 in one batch \(\d+:\d\d, total \d+:\d\d\)$') "seen: $($r.Batch); last: $($r.Status)"
  Check "$Tag.one.engine.call" (($kids.Count -eq 1) -and ($r.Pids[$kids[0]] -eq 2)) ("convert-apply children: {0}; --unit counts: {1}" -f $kids.Count, (($kids | ForEach-Object { $r.Pids[$_] }) -join ','))
  # @(if ...) keeps a single match an array (a bare if-expression unrolls it to a string, and $lines[0] is a char).
  $lines = @(if ($null -eq $repText) { @() } else { @([regex]::Matches($repText, '(?m)^\t\tnote\t+batch:.*$') | ForEach-Object { $_.Value.TrimEnd() }) })
  Check "$Tag.report.batch.note" (($lines.Count -eq 1) -and ($lines[0] -match '^\t\tnote\t+batch: 2 unit\(s\) -- 2 ok')) "report batch lines: $($lines -join ' | ')"
}
$p = $null
try {
  WriteUnits
  $t0 = Get-Date
  $ix = IndexFixture
  Check 'fixture.index' (($ix.Code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$($ix.Code) {0:N0}s $($ix.Summary)" -f ((Get-Date) - $t0).TotalSeconds)

  if ($ProofNoBatch) {
    "NOTE  -ProofNoBatch: the run is per-unit (CONVRULES_BATCH=off); the batch checks below are expected to FAIL"
    RunScenario 'off' 'proof'; $r = $script:R
    if ($null -ne $r) { BatchChecks $r (ReportText) 'proof' }
    return
  }

  # ===== run 1: batch mode =====
  RunScenario '' 'batch'; $r = $script:R
  if ($null -eq $r) { return }
  $rep = ReportText
  BatchChecks $r $rep 'batch'
  Check 'batch.convert.two.converted' ((ConvertedRows $r) -eq 2) "converted rows: $(ConvertedRows $r)$(if ($r.Dialog) { "; editor dialog: $($r.Dialog)" })"
  Check 'batch.convert.summary' ($r.Status -like 'Converted 2 of 2 unit x book pair(s); 0 failed and were restored.*Report: *') $r.Status
  Check 'batch.convert.grid.backups' ((@($r.Cols[5]) -contains 'FixUnit.pas.BCK1') -and (@($r.Cols[5]) -contains 'Second.pas.BCK1') -and (@($r.Cols[6]) -contains 'FixUnit.dfm.BCK1') -and (@($r.Cols[6]) -contains 'Second.dfm.BCK1')) `
    ("Backup: " + (@($r.Cols[5]) -join ',') + "; Backup .dfm: " + (@($r.Cols[6]) -join ','))
  $bck = ((Test-Path -LiteralPath ($pas1 + '.BCK1')) -and (Test-Path -LiteralPath ($dfm1 + '.BCK1')) -and (Test-Path -LiteralPath ($pas2 + '.BCK1')) -and (Test-Path -LiteralPath ($dfm2 + '.BCK1')))
  Check 'batch.convert.bck1' ($bck -and ((Get-Content -LiteralPath ($pas1 + '.BCK1') -Raw) -match 'TLabel') -and ((Get-Content -LiteralPath ($pas2 + '.BCK1') -Raw) -match 'TLabel')) "all four .BCK1 present: $bck"
  Check 'batch.convert.files.changed' (((Get-Content -LiteralPath $pas1 -Raw) -match 'TStaticText') -and ((Get-Content -LiteralPath $pas2 -Raw) -match 'TStaticText') -and (Get-Content -LiteralPath $dfm1 -Raw).StartsWith('object ') -and (Get-Content -LiteralPath $dfm2 -Raw).StartsWith('object '))
  Check 'batch.report.final.reindex' (($null -ne $rep) -and ($rep -match "Final reindex`tok") -and ($rep -match "Run`tcompleted") -and ($rep -match 'Second\.dfm\.BCK1')) "report: $(if ($null -eq $rep) { 'none' } else { 'present' })"

  # ===== run 2: CONVRULES_BATCH=off -> the per-unit path =====
  $ix = ResetFixture
  Check 'proof.env.off.reset' ($ix.Code -eq 0) "exit=$($ix.Code) $($ix.Summary)"
  RunScenario 'off' 'off'; $r2 = $script:R
  if ($null -eq $r2) { return }
  $rep2 = ReportText
  $kids2 = @($r2.Pids.Keys)
  Check 'proof.env.off' (($r2.Start -notlike '*batch mode*') -and ($kids2.Count -eq 2) -and (@($kids2 | Where-Object { $r2.Pids[$_] -ne 1 }).Count -eq 0) -and ($null -ne $rep2) -and ($rep2 -notmatch 'batch:') -and ((ConvertedRows $r2) -eq 2)) `
    ("start: $($r2.Start); convert-apply children: {0}; report batch line: {1}; converted rows: {2}" -f $kids2.Count, ($null -ne $rep2 -and $rep2 -match 'batch:'), (ConvertedRows $r2))
}
finally {
  if ($null -ne $script:p -and -not $script:p.HasExited) { $script:p.Kill($true); [void]$script:p.WaitForExit(15000) }
  [Environment]::SetEnvironmentVariable('CONVRULES_BATCH', $null, 'Process')
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-convert-batch: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
