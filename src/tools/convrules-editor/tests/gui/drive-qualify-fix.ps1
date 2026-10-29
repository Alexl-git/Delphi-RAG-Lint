# Driven GUI check for the Qualify #convert quick fix (feat/convert-qualify-fix, A2, 2026-10-19).
# Usage: pwsh -NoProfile -File drive-qualify-fix.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoFix] [-UseAlt] [-QualifyAll] [-ProofNoQualifyAll]
#        A FROZEN drag-lint.exe must sit beside the exe (the fixture index is built with THAT engine, the
#        editor finds its engine the same way), never a live dll-win64 build. Its Win64 library index must
#        answer (the conversion resolves Vcl.StdCtrls.TLabel there). The engine must report convert_qualify_fix (1.28.3+).
# Fixture (fresh temp folder, the _D-RAG layout the editor derives the project file from): Fix.dpr / Fix.dproj with
#   LibA.pas + LibB.pas (each a TSolo, so the To side ties), FixUnit.pas + FixUnit.dfm (one TLabel, uses WITHOUT
#   Vcl.StdCtrls so TLabel is a bare ambiguous name) and rules\Fix.rules = '#convert TLabel -> TSolo' + 3 links.
# Flow: Convert tab -> Check all, add FixUnit.pas -> Convert is REFUSED (note '; 2 #convert side(s) to qualify')
#   -> select the row, Qualify #convert... -> the dialog lists 2 fixes (from: inferred TLabel preselected, to: refused
#   TSolo, nothing preselected) -> pick LibA.TSolo, Apply -> the book in the editor reads
#   '#convert Vcl.StdCtrls.TLabel -> LibA.TSolo', UNSAVED (File > Exit asks to save; Cancel) -> File > Save ->
#   Convert again -> converted, no qualify note; the FIRST run report holds the 2 'qualify' lines.
# The refused run takes seconds; the converting run ~100 s (wait 600 s).
# -ProofNoFix replaces the Apply click by Cancel (and does not press File > Exit, which would close a clean editor):
#   status.qualified, book.unsaved, file.line.qualified, run2.converted and run2.no.qualify.note must then FAIL,
#   which is the proof they can.
# The editor is killed (with its engine children) and the fixture deleted on exit.
# -UseAlt (D4): fix 1 (to TSolo) takes its '#use LibA' alternative via BtnUse instead of the LibA.TSolo candidate;
#   adds dialog.use.* checks, the status ends '; added #use LibA' (line 2), the book's lines 1-2 are '#use LibA' and
#   '#convert Vcl.StdCtrls.TLabel -> TSolo', and run 2 must still convert (the #use makes TSolo unambiguous).
#   Combine with -ProofNoFix for the same negative control.
# -QualifyAll (D6): the row is not selected for Qualify #convert...; the 'Qualify all...' button (BtnQualifyAll) is
#   clicked instead. The fixture has ONE book, so exactly one TQualifyForm must open (and no second one after Apply);
#   the closing status must read 'Qualify all (1 of 1 book(s)): ' + the per-book status. -ProofNoQualifyAll skips the
#   button click (handler skipped): qualifyall.dialog must then FAIL, which is the proof it can.
# Check counts: default 21; -QualifyAll 23; -UseAlt 25; -QualifyAll -UseAlt 27. -ProofNoFix = 16 pass / 5 fail;
#   -QualifyAll -ProofNoQualifyAll = 10 pass / 2 fail (qualifyall.dialog, qualify.dialog).
param([string]$Exe, [switch]$ProofNoFix, [switch]$UseAlt, [switch]$QualifyAll, [switch]$ProofNoQualifyAll)
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
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; do { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; if (((Get-Date) - $t0).TotalSeconds -ge $sec) { break }; Start-Sleep -Milliseconds 250 } while ($true); return [IntPtr]::Zero }
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

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Q {
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static int Count(IntPtr lb) { return (int)Send(lb, 0x018B, IntPtr.Zero, IntPtr.Zero); }
  public static int CurSel(IntPtr lb) { return (int)Send(lb, 0x0188, IntPtr.Zero, IntPtr.Zero); }
  /* Select item IDX and tell the dialog what a click does: WM_COMMAND with LBN_SELCHANGE (VCL's OnClick). */
  public static void Pick(IntPtr dlg, IntPtr lb, int idx) { Send(lb, 0x0186, (IntPtr)idx, IntPtr.Zero); Send(dlg, 0x0111, (IntPtr)(1 << 16), lb); }
}
'@
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class B {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  /* DRV-5 / N7/N11: 'ConvRulesEditor.Busy' answers 2 busy / 1 idle; no answer within the timeout = blocked = busy. */
  public static bool Busy(IntPtr main) {
    uint msg = RegisterWindowMessage("ConvRulesEditor.Busy"); IntPtr r;
    if (SendMessageTimeout(main, msg, IntPtr.Zero, IntPtr.Zero, 2 /* SMTO_ABORTIFHUNG */, 500, out r) == IntPtr.Zero) return true;
    return (long)r == 2;
  }
}
"@
# DRV-5: idle = no progress window / message box / common dialog, the editor enabled and saying idle (B::Busy), for 2 s.
function WaitIdle($procId, $main, $sec) {
  $idleSince = $null; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $busy = (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -in 'TEngineWaitForm', 'TMessageForm', '#32770' }).Count -gt 0) -or -not [Q]::IsWindowEnabled($main) -or [B]::Busy($main)
    if ($busy) { $idleSince = $null } elseif ($null -eq $idleSince) { $idleSince = Get-Date } elseif (((Get-Date) - $idleSince).TotalSeconds -ge 2) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}
# Waits for a run to END: the unit's row has a status AND Convert is enabled again AND the status line is not a
# progress line (WaitStatus alone returns on the analysis' own '1 source unit(s) listed.' line).
function WaitRun($main, $lv, $conv, $Seconds) {
  $t0 = Get-Date; $script:dlg = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 700
    $d = @(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' })
    if ($d.Count -gt 0) { $script:dlg = TopsNow $p.Id; break }
    $rows = @([W]::Column($lv, 2) | Where-Object { $_ })
    if ($rows.Count -gt 0 -and [Q]::IsWindowEnabled($conv) -and -not [B]::Busy($main) -and -not (RunInProgress (Status $main))) { break }
  }
  $script:waited = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Seconds 2
  Status $main
}# A message box button by caption, hot-key '&' ignored.
function AnswerBox($procId, $caption) {
  $dlg = WaitCls $procId 'TMessageForm' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no message box (forms: $(TopsNow $procId))" }
  $b = @(Find $dlg 'TButton' $null | Where-Object { ([W]::Txt($_) -replace '&', '') -eq $caption })
  if ($b.Count -eq 0) { return "no '$caption' in message box: " + ((Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) }) -join ',') }
  Click $b[0]
  return ''
}
function BoxText($dlg) { (@(Find $dlg 'TLabel' $null) + @(Find $dlg 'Static' $null) | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ }) -join ' ' }
function ListItemsAt($lb) { [CT]::Items($lb) }

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('qualify-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'
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
  LibA in 'LibA.pas',
  LibB in 'LibB.pas',
  FixUnit in 'FixUnit.pas' {FixForm};

begin
  Application.Initialize;
  Application.Run;
end.
'@
foreach ($lib in 'LibA', 'LibB') {
  WriteAscii (Join-Path $tmp "$lib.pas") @"
unit $lib;

interface

uses
  Vcl.Controls, System.Classes;

type
  TSolo = class(TGraphicControl)
  private
    FCaption: string;
  published
    property Left;
    property Top;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
"@
}
WriteAscii $pas @'
unit FixUnit;

interface

uses
  Vcl.Forms, Vcl.Controls, System.Classes;

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
#convert TLabel -> TSolo
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@

$p = $null
try {
  $t0 = Get-Date
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  Check 'fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s $summary" -f ((Get-Date) - $t0).TotalSeconds)

  # The file FIRST, then the flags: ConvRulesEditor.dpr auto-opens only a LEADING file argument.
  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2

  # --- 1. Conversion > Convert... shows the Convert tab ---
  $invoked = [W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $active = @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) })
  Check 'menu.convert' ($invoked -and ($active -contains 'Convert')) ("invoked=$invoked active tabs: " + ($active -join ', '))

  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'tab.controls' $false "Convert buttons beside a progress bar: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $lv = @(Find ([CT]::Parent([CT]::Parent($conv))) 'TListView' $null)[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  $src = @(Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0]
  $qbtn = @(Find ([CT]::Parent($conv)) 'TButton' 'Qualify #convert...')[0]
  $qall = @(Find ([CT]::Parent($conv)) 'TButton' 'Qualify all...')[0]
  Check 'tab.controls' ($null -ne $lv -and $null -ne $checkAll -and $null -ne $books -and $null -ne $add -and $null -ne $src -and $null -ne $qbtn) `
    ("lv={0} checkAll={1} books={2} add={3} sources={4} qualify={5}" -f ($null -ne $lv), ($null -ne $checkAll), ($null -ne $books), ($null -ne $add), ($null -ne $src), ($null -ne $qbtn))
  if ($null -eq $lv -or $null -eq $checkAll -or $null -eq $books -or $null -eq $add -or $null -eq $src -or $null -eq $qbtn) { return }

  # --- 2. the book is listed; Check all; add the unit ---
  $bookItems = [CT]::Items($books)
  Check 'books.listed' (@($bookItems | Where-Object { $_ -like 'Fix.rules*' }).Count -eq 1) ($bookItems -join ' | ')
  Click $checkAll
  Start-Sleep -Milliseconds 500
  $e = AddViaDialog $p.Id $add $pas
  # Wait on the CONDITION (the unit is in the source list), not a sleep: the list fills after the project index read.
  $items = [CT]::Items($src)
  $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 60 -and -not ($items -contains $pas)) { Start-Sleep -Milliseconds 500; $items = [CT]::Items($src) }  Check 'fixunit.added' (($e -eq '') -and ($items -contains $pas)) ("$e items: " + ($items -join ' | ') + '; status: ' + (Status $main))

  # --- 3. run 1: the bare TLabel / TSolo make the unit REFUSED, with the qualify note ---
  # Adding a unit starts an analysis behind a progress window; a Convert click that lands in it is lost, so wait for its closing status line.
  $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 60 -and -not ((Status $main) -like '*source unit(s) listed*')) { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Seconds 1
  $before = Status $main
  [void](WaitIdle $p.Id $main 90)
  Click $conv
  $st = WaitRun $main $lv $conv 180
  $cols = @(0..7 | ForEach-Object { , @([W]::Column($lv, $_)) })
  "  run1: {0:N0}s; status: {1}" -f $script:waited, $st
  for ($i = 0; $i -lt $cols[0].Count; $i++) { '  row: ' + ((0..7 | ForEach-Object { $cols[$_][$i] }) -join ' / ') }
  $row = [array]::IndexOf($cols[1], 'FixUnit.pas')
  Check 'run1.refused' (($row -ge 0) -and ($cols[2][$row] -like 'refused*') -and ($st -like '*refused by the engine*')) "row=$row status col: $(if ($row -ge 0) { $cols[2][$row] }); status: $st$(if ($dlg) { "; editor dialog: $dlg" })"
  Check 'row.note.qualify' (($row -ge 0) -and $cols[7][$row].EndsWith('; 2 #convert side(s) to qualify')) "note: $(if ($row -ge 0) { $cols[7][$row] })"

  # --- 4. the row's fixes: Qualify #convert... is enabled on it ---
  if ($row -ge 0) { [W]::SelectRow($lv, $row); Start-Sleep -Milliseconds 500 }
  Check 'qualify.button.enabled' ([W]::IsWindowVisible($qbtn) -and [Q]::IsWindowEnabled($qbtn)) "visible=$([W]::IsWindowVisible($qbtn)) enabled=$([Q]::IsWindowEnabled($qbtn))"
  Check 'qualifyall.button.enabled' (($null -ne $qall) -and [W]::IsWindowVisible($qall) -and [Q]::IsWindowEnabled($qall)) "found=$($null -ne $qall)"
  if ($QualifyAll) {
    if ($ProofNoQualifyAll) { "NOTE  -ProofNoQualifyAll: the Qualify all button is not clicked; qualifyall.dialog is expected to FAIL" }
    elseif ($qall) { Click $qall }
  } else {
    Click $qbtn
  }
  $dlgQ = WaitCls $p.Id 'TQualifyForm' 10
  if ($QualifyAll) { Check 'qualifyall.dialog' ($dlgQ -ne [IntPtr]::Zero) (TopsNow $p.Id) }  Check 'qualify.dialog' ($dlgQ -ne [IntPtr]::Zero) (TopsNow $p.Id)
  if ($dlgQ -eq [IntPtr]::Zero) { return }
  $lists = @(Find $dlgQ 'TListBox' $null | Sort-Object { [W]::Top($_) })
  $lbFixes = $lists[0]; $lbCand = $lists[1]
  $fixItems = [CT]::Items($lbFixes)
  Check 'dialog.two.fixes' (([Q]::Count($lbFixes) -eq 2) -and ($fixItems[0] -eq 'line 1  from  TLabel  inferred -> Vcl.StdCtrls.TLabel') -and ($fixItems[1] -eq 'line 1  to  TSolo  refused')) ($fixItems -join ' | ')
  [Q]::Pick($dlgQ, $lbFixes, 0); Start-Sleep -Milliseconds 400
  Check 'dialog.inferred.preselected' (([Q]::Count($lbCand) -eq 2) -and ([Q]::CurSel($lbCand) -eq 0)) ("candidates=" + ([CT]::Items($lbCand) -join ' | ') + " cursel=$([Q]::CurSel($lbCand))")
  [Q]::Pick($dlgQ, $lbFixes, 1); Start-Sleep -Milliseconds 400
  Check 'dialog.refused.unselected' (([Q]::Count($lbCand) -eq 2) -and ([Q]::CurSel($lbCand) -eq -1)) ("candidates=" + ([CT]::Items($lbCand) -join ' | ') + " cursel=$([Q]::CurSel($lbCand))")
  [Q]::Pick($dlgQ, $lbCand, 0); Start-Sleep -Milliseconds 400   # LibA.TSolo
  if ($UseAlt) {
    # D4: the to side's alternative '#use LibA' is clickable; pressing BtnUse replaces the candidate pick.
    $btnUse = @(Find $dlgQ 'TButton' 'Add #use LibA')[0]
    Check 'dialog.use.button' (($null -ne $btnUse) -and [Q]::IsWindowEnabled($btnUse)) ("BtnUse: $(if ($btnUse) { 'found' } else { 'missing' }); " + (TopsNow $p.Id))
    if ($btnUse) { Click $btnUse; Start-Sleep -Milliseconds 400 }
    Check 'dialog.use.candidate.dropped' ([Q]::CurSel($lbCand) -eq -1) "cursel=$([Q]::CurSel($lbCand))"
    Check 'dialog.use.button.toggles' ($null -ne @(Find $dlgQ 'TButton' 'Remove #use LibA')[0]) (TopsNow $p.Id)
    [Q]::Pick($dlgQ, $lbFixes, 0); Start-Sleep -Milliseconds 400
    Check 'dialog.use.from.disabled' (-not [Q]::IsWindowEnabled(@(Find $dlgQ 'TButton' 'Add #use')[0])) 'the from side offers no #use'
  }
  $before = Status $main
  if ($ProofNoFix) {
    "NOTE  -ProofNoFix: Cancel is pressed instead of Apply; the checks that need the fix are expected to FAIL"
    Click (@(Find $dlgQ 'TButton' 'Cancel')[0])
  } else {
    Click (@(Find $dlgQ 'TButton' 'Apply')[0])
  }
  $st = WaitStatus $main $before 30
  $pre = ''
  if ($QualifyAll) {
    # One book in the fixture: no second dialog may follow the first one's Apply.
    Start-Sleep -Seconds 2
    $second = WaitCls $p.Id 'TQualifyForm' 2
    Check 'qualifyall.one.dialog' ($second -eq [IntPtr]::Zero) (TopsNow $p.Id)
    $pre = 'Qualify all (1 of 1 book(s)): '
  }
  if ($UseAlt) {
    Check 'status.qualified' ($st -eq ($pre + 'Qualified 1 #convert side(s) in Fix.rules (line 2) -- not saved: File > Save, then Convert again; added #use LibA')) $st
  } else {
    Check 'status.qualified' ($st -eq ($pre + 'Qualified 2 #convert side(s) in Fix.rules (line 1) -- not saved: File > Save, then Convert again')) $st
  }

  # --- 5. the edit is unsaved: File > Exit asks (Cancel keeps the editor) ---
  if ($ProofNoFix) {
    $box = WaitCls $p.Id 'TMessageForm' 3
    Check 'book.unsaved' ($box -ne [IntPtr]::Zero) "no unsaved prompt without the fix (File > Exit not pressed): $(TopsNow $p.Id)"
  } else {
    [void][W]::InvokeMenu($main, 'File|Exit')
    $box = WaitCls $p.Id 'TMessageForm' 10
    # A TMessageForm's text has no window (VCL paints it): the prompt's presence IS the proof.
    Check 'book.unsaved' ($box -ne [IntPtr]::Zero) "message box: $(TopsNow $p.Id)"
    $e = AnswerBox $p.Id 'Cancel'
    Start-Sleep -Milliseconds 800
    if ($e -ne '') { "  WARN  $e" }
  }

  # --- 6. File > Save writes the qualified line ---
  $saved = [W]::InvokeMenu($main, 'File|Save')
  Start-Sleep -Seconds 2
  Check 'book.saved' $saved "invoked=$saved; status: $(Status $main)"
  $first = (Get-Content -LiteralPath $book -TotalCount 1)
  if ($UseAlt) {
    $second = @(Get-Content -LiteralPath $book -TotalCount 2)[1]
    Check 'file.line.qualified' (($first -eq '#use LibA') -and ($second -eq '#convert Vcl.StdCtrls.TLabel -> TSolo')) "first lines: $first | $second"
  } else {
    Check 'file.line.qualified' ($first -eq '#convert Vcl.StdCtrls.TLabel -> LibA.TSolo') "first line: $first"
  }

  # --- 7. run 2: the unit now converts ---
  # The save starts the scoped validation of the changed block; a Convert click that lands in it is lost. Wait for a quiet status line, and click again if no run starts.
  $last = ''; $quiet = 0; $t0 = Get-Date
  while ($quiet -lt 4 -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Seconds 1; $now = Status $main; if ($now -eq $last) { $quiet++ } else { $quiet = 0; $last = $now } }
  $before = Status $main
  $oldCols = @([W]::Column($lv, 2)) -join ','
  for ($try = 0; $try -lt 3; $try++) {
    [void](WaitIdle $p.Id $main 90)
    Click $conv
    $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 20 -and -not (RunInProgress (Status $main)) -and ((@([W]::Column($lv, 2)) -join ',') -eq $oldCols)) { Start-Sleep -Milliseconds 400 }
    if ((RunInProgress (Status $main)) -or ((@([W]::Column($lv, 2)) -join ',') -ne $oldCols)) { break }
  }
  $st = WaitRun $main $lv $conv 600
  $cols = @(0..7 | ForEach-Object { , @([W]::Column($lv, $_)) })
  "  run2: {0:N0}s; status: {1}" -f $script:waited, $st
  for ($i = 0; $i -lt $cols[0].Count; $i++) { '  row: ' + ((0..7 | ForEach-Object { $cols[$_][$i] }) -join ' / ') }
  Check 'run2.converted' ((@($cols[2]) -contains 'converted') -and (Test-Path -LiteralPath ($pas + '.BCK1')) -and (Test-Path -LiteralPath ($dfm + '.BCK1'))) `
    "status col: $(@($cols[2]) -join ','); status: $st$(if ($dlg) { "; editor dialog: $dlg" })"
  Check 'run2.no.qualify.note' (-not (@($cols[7]) -like '*#convert side(s)*')) ("notes: " + (@($cols[7]) -join ' | '))

  # --- 8. the FIRST run's report holds the two qualify lines (8 TAB columns, column 3 = qualify) ---
  $reports = @([IO.Directory]::GetFiles($rulesDir, 'convert-run-*.txt') | Sort-Object)
  $qLines = @()
  if ($reports.Count -gt 0) { $qLines = @([IO.File]::ReadAllLines($reports[0], [Text.Encoding]::UTF8) | Where-Object { ($_ -split "`t").Count -eq 8 -and ($_ -split "`t")[2] -eq 'qualify' }) }
  Check 'report.qualify.lines' ($qLines.Count -eq 2) ("reports=$($reports.Count); qualify lines in the first: $($qLines.Count)" + $(if ($qLines.Count -gt 0) { '; e.g. ' + (($qLines[0] -split "`t")[7]) }))
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-qualify: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
