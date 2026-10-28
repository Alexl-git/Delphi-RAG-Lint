# Driven GUI check for member migration (A4 #migrate slice 1, D9 = A; spec
# docs\superpowers\specs\2026-10-23-converter-migrate-slice1-design.md sections 5-9).
# Usage: pwsh -NoProfile -File drive-migrate.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoMigrate] [-ProofNoBulk]
#        A FROZEN drag-lint.exe that reports migrate_members (1.35.0-alpha pin or later) must sit beside the exe
#        (a staged copy of a pin, never dll-win64); its Win64 library index must answer (TLabel / TStaticText).
# Fixture: drive-work-list.ps1's (Fix.dpr / FixUnit.pas with Label1.Layout and Label1.WordWrap, which TStaticText
#   lacks -> two unmapped Work list rows).
# Flow: Convert -> Work list -> select Layout -> Migrate... -> DL_NONE -> Apply (status 'Wrote #migrate Layout ->
#   DL_NONE ...', Rule cell '(line N, unsaved)'); select WordWrap -> Migrate... -> rename AutoSize -> Apply;
#   File > Save (both lines on disk); restore the original unit, reindex, Convert again (the row note carries
#   '; migrate: 1 renamed, 1 deliberate break(s)', FixUnit.pas holds DL_NONE(Label1.Layout) and Label1.AutoSize).
# -ProofNoMigrate presses Cancel on the first dialog instead of Apply. These checks must then FAIL (6):
#   migrate.layout.status, migrate.layout.rule, migrate.saved.disk, migrate.rerun.note, migrate.pas.break
#   and migrate.worklist.after (Layout stays unmapped).
#   Measured 2026-10-26 on the 1.35.0-alpha pin: 18 pass / 0 fail in ~60 s; -ProofNoMigrate 12 pass / 6 fail (the six above).
# Follow-ups (spec 12a, D5 = B / D6 = B):
#   D6: before the first Migrate the editor is switched to Other.rules (no TLabel block); Migrate... on a row must
#     open Fix.rules -- the book that converted it, pas_uses[].rules_file -- and write there (migrate.d6.opened).
#   D5: after the two single edits, BOTH rows are selected; the dialog offers 'DL_NONE for all 2 selected rows'
#     (migrate.d5.offer); with it ticked, Apply writes DL_NONE for both (migrate.d5.status: 1 changed, 1 already
#     DL_NONE; migrate.d5.rule: WordWrap's Rule cell); WordWrap is then renamed back to AutoSize (migrate.d5.restore).
#   -ProofNoBulk leaves the box unticked: migrate.d5.status and migrate.d5.rule must FAIL (2). -ProofNoMigrate skips
#   the D5 section and also FAILS migrate.d6.opened (7).
#   A pre-follow-up exe (main before feat/conv-migrate-followups) must FAIL migrate.d6.opened and the d5 checks.
#   Measured 2026-10-26 on a staged copy of the 1.35.0-alpha pin (100 % CPU from other lanes): 24 pass / 0 fail in
#   ~150 s; -ProofNoBulk 22 / 2; -ProofNoMigrate 13 / 7; main's exe (9:24) 9 / 15.
param([string]$Exe, [switch]$ProofNoMigrate, [switch]$ProofNoBulk)
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
  /* Row IDX ALSO selected (not focused), as a Ctrl+click leaves it: D5 multi-select. */
  public static void AddSelected(IntPtr lv, int idx) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)256, 0x3000, 0x04);
    try { SetState(hp, mem, lv, idx, 2); }
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
  /* Task 3: the middle of list-view row IDX in the list view's CLIENT coordinates
     (LVM_GETITEMRECT, LVIR_BOUNDS, through the editor's memory) as a mouse lParam. */
  public static IntPtr RowClientPoint(IntPtr lv, int idx) {
    uint pid; GetWindowThreadProcessId(lv, out pid);
    IntPtr hp = OpenProcess(0x0438, false, pid);
    IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)256, 0x3000, 0x04);
    try {
      var rc = new byte[16]; UIntPtr io; WriteProcessMemory(hp, mem, rc, (UIntPtr)16, out io);
      Send(lv, 0x100E, (IntPtr)idx, mem);
      ReadProcessMemory(hp, mem, rc, (UIntPtr)16, out io);
      int x = (BitConverter.ToInt32(rc, 0) + BitConverter.ToInt32(rc, 8)) / 2, y = (BitConverter.ToInt32(rc, 4) + BitConverter.ToInt32(rc, 12)) / 2;
      return (IntPtr)((y << 16) | (x & 0xFFFF));
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
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class B {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint ms, out IntPtr r);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  /* N7/N11: 'ConvRulesEditor.Busy' answers 2 busy / 1 idle; no answer within the timeout = blocked = busy. */
  public static bool Busy(IntPtr main) {
    uint msg = RegisterWindowMessage("ConvRulesEditor.Busy"); IntPtr r;
    if (SendMessageTimeout(main, msg, IntPtr.Zero, IntPtr.Zero, 2 /* SMTO_ABORTIFHUNG */, 500, out r) == IntPtr.Zero) return true;
    return (long)r == 2;
  }
}
"@
# idle = no progress window / message box / common dialog, the editor enabled and saying idle (B::Busy), for 2 s
# running. Convert clicked during the C8 inherited-instances check after Add... is refused ("clicked while the
# editor was busy"), so RunConvert waits for this first.
function WaitIdle($procId, $main, $sec) {
  $idleSince = $null; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $busy = (@([W]::Tops($procId) | Where-Object { [W]::Cls($_) -in 'TEngineWaitForm', 'TMessageForm', '#32770' }).Count -gt 0) -or -not [B]::IsWindowEnabled($main) -or [B]::Busy($main)
    if ($busy) { $idleSince = $null } elseif ($null -eq $idleSince) { $idleSince = Get-Date } elseif (((Get-Date) - $idleSince).TotalSeconds -ge 2) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}
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

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }
function WorkTab($main) { @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) }) }
# Waits up to $Seconds for a status line matching $Like (status writes are queued).
function WaitLike($main, $Like, $Seconds) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) { $s = Status $main; if ($s -like $Like) { Start-Sleep -Milliseconds 300; return (Status $main) }; Start-Sleep -Milliseconds 250 }
  Status $main
}

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('migrate-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'
$book = Join-Path $rulesDir 'Fix.rules'
$other = Join-Path $tmp 'Other.rules'
# drive-convert-tab.ps1's Fix.dproj (the IDE's Base / Base_Win64 group shape), MainSource Fix.dpr.
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
    procedure FormCreate(Sender: TObject);
  end;

var
  FixForm: TFixForm;

implementation

{$R *.dfm}

procedure TFixForm.FormCreate(Sender: TObject);
begin
  Label1.Caption:= 'Hi';
  Label1.Layout:= tlCenter;
  Label1.WordWrap:= True;
end;

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
WriteAscii $other @'
#convert Vcl.StdCtrls.TButton -> Vcl.StdCtrls.TBitBtn, Vcl.StdCtrls
#link Caption <- Caption
'@

function MigrateDialog($procId) { WaitCls $procId 'TMigrateForm' 15 }
function DoMigrate($main, $lv, $member, $break, $newName, $cancel) {
  $members = @([W]::Column($lv, 3)); $idx = [Array]::IndexOf($members, $member)
  if ($idx -lt 0) { return "row $member not shown (rows: $($members -join ','))" }
  [W]::SelectRow($lv, $idx)
  Start-Sleep -Milliseconds 400
  $btn = @(Find $main 'TButton' 'Migrate...')
  if ($btn.Count -ne 1) { return "Migrate... buttons: $($btn.Count)" }
  Click $btn[0]
  $dlg = MigrateDialog $p.Id
  if ($dlg -eq [IntPtr]::Zero) { return "no Migrate dialog (forms: $(TopsNow $p.Id))" }
  Start-Sleep -Milliseconds 500
  if ($cancel) { Click (@(Find $dlg 'TButton' 'Cancel')[0]) }
  else {
    if ($break) { Click (@(Find $dlg 'TRadioButton' $null | Where-Object { [W]::Txt($_) -like 'DL_NONE*' })[0]) }
    else {
      # EdNew is the lower of the two edits (EdOld is read-only, above it).
      $edNew = @(Find $dlg 'TEdit' $null | Sort-Object { [W]::Top($_) })[-1]
      [void][W]::SendS($edNew, 0x000C, [IntPtr]::Zero, $newName)
    }
    Start-Sleep -Milliseconds 400
    Click (@(Find $dlg 'TButton' 'Apply')[0])
  }
  return (CloseMigrate)
}
# The Migrate dialog now up, or $null. (WaitCls with 0 s never looks -- its loop runs while elapsed < 0 -- so the
# pre-follow-up 'wait for the dialog to close' loop never waited.)
function MigrateUp { @([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TMigrateForm' })[0] }
# Waits for the dialog to close; one still up after 10 s (Apply disabled) is cancelled and reported.
function CloseMigrate {
  $t0 = Get-Date; while ((MigrateUp) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 250 }
  $left = MigrateUp
  if ($left) {
    $lbl = (@([W]::Kids($left) | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ -like 'no #convert*' }) -join ' ')
    Click (@(Find $left 'TButton' 'Cancel')[0])
    # Gone before the next step: a dialog still up would be found by the next MigrateDialog (seen under load).
    $t0 = Get-Date; while ((MigrateUp) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 250 }
    Start-Sleep -Milliseconds 500
    return "dialog stayed open after Apply, cancelled $lbl"
  }
  Start-Sleep -Milliseconds 500
  return ''
}
# D5: selects every row in $members (the first focused), opens Migrate..., reads the bulk box, ticks it unless
# -ProofNoBulk, Applies. Returns the box caption ('' when absent) and an error text.
function DoBulk($main, $lv, [string[]]$members) {
  $shown = @([W]::Column($lv, 3)); $first = $true
  foreach ($m in $members) {
    $idx = [Array]::IndexOf($shown, $m)
    if ($idx -lt 0) { return @('', "row $m not shown") }
    if ($first) { [W]::SelectRow($lv, $idx); $first = $false } else { [W]::AddSelected($lv, $idx) }
  }
  Start-Sleep -Milliseconds 400
  Click (@(Find $main 'TButton' 'Migrate...')[0])
  $dlg = MigrateDialog $p.Id
  if ($dlg -eq [IntPtr]::Zero) { return @('', "no Migrate dialog (forms: $(TopsNow $p.Id))") }
  Start-Sleep -Milliseconds 500
  $cb = @(Find $dlg 'TCheckBox' $null | Where-Object { [W]::IsWindowVisible($_) })
  $cap = if ($cb.Count -eq 1) { [W]::Txt($cb[0]) } else { '' }
  if ($cb.Count -eq 1 -and -not $ProofNoBulk) { Click $cb[0]; Start-Sleep -Milliseconds 400 }
  elseif ($cb.Count -ne 1) { Click (@(Find $dlg 'TRadioButton' $null | Where-Object { [W]::Txt($_) -like 'DL_NONE*' })[0]); Start-Sleep -Milliseconds 400 }
  Click (@(Find $dlg 'TButton' 'Apply')[0])
  return @($cap, (CloseMigrate))
}
function RunConvert($main) {
  # Idle BEFORE the menu too: 'Conversion|Convert...' during the C8 check after Add... is refused, and that
  # '[!] ... Convert was NOT started' line would otherwise be read below as this run's result (2026-10-26,
  # loaded machine: convert.first failed on main's exe and driver alike).
  [void](WaitIdle $p.Id $main 90)
  [void][W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })[0]
  [void](WaitIdle $p.Id $main 90)
  $pre = Status $main
  Click $conv
  $t0 = Get-Date; $st = ''
  while (((Get-Date) - $t0).TotalSeconds -lt 600) {
    Start-Sleep -Milliseconds 500
    $st = Status $main
    if ($st -eq $pre) { continue } # the line from before the click is not this run's answer
    if ($st -like 'Converted *' -or $st -like 'Convert stopped*' -or $st -like 'RESTORE FAILED*' -or $st -like '`[!`] *' -or $st -like 'Convert refused*') { break }
    if (@(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' }).Count -gt 0) { $script:dlg = TopsNow $p.Id; break }
  }
  Start-Sleep -Milliseconds 300
  Status $main
}
function WorkGrid($main) {
  $filter = @(Find $main 'TCheckListBox' $null | Where-Object { [CT]::Items($_) -contains 'unmapped' })
  if ($filter.Count -ne 1) { return $null }
  @(Find ([CT]::Parent([CT]::Parent($filter[0]))) 'TListView' $null)[0]
}

$p = $null
try {
  if ($ProofNoMigrate) { "NOTE  -ProofNoMigrate: the six checks named in the header are expected to FAIL" }
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  Check 'fixture.index' (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $db)) (($out -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1)
  $info = & { $ErrorActionPreference = 'Continue'; & $engine info --json 2>$null | Out-String }
  Check 'engine.migrate_members' ($info -match '"migrate_members":true') 'the frozen engine must report migrate_members'
  $origPas = [IO.File]::ReadAllText($pas); $origDfm = [IO.File]::ReadAllText($dfm)

  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2

  # --- 1. first Convert: the Work list has the two unmapped rows ---
  [void][W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'convert.controls' $false "Convert buttons: $($conv.Count)"; return }
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv[0])))
  Click (@(Find $tab 'TButton' 'Check all')[0])
  Start-Sleep -Milliseconds 500
  $e = AddViaDialog $p.Id (@(Find $tab 'TButton' 'Add...')[0]) $pas
  Check 'fixunit.added' ($e -eq '') $e
  Start-Sleep -Seconds 2
  $st = RunConvert $main
  Check 'convert.first' ($st -like 'Converted 1 of 1 unit x book pair(s)*') $st

  [void][W]::InvokeMenu($main, 'View|Work list')
  [void](WaitLike $main 'Work list: *' 10)
  $lv = WorkGrid $main
  Check 'worklist.controls' ($null -ne $lv)
  if ($null -eq $lv) { return }
  Check 'worklist.rows' ((@([W]::Column($lv, 3)) -join ',') -eq 'Layout,WordWrap') (@([W]::Column($lv, 3)) -join ',')
  $btn = @(Find $main 'TButton' 'Migrate...')
  Check 'migrate.button.visible' (($btn.Count -eq 1) -and [W]::IsWindowVisible($btn[0])) "buttons: $($btn.Count)"

  # --- 1b. D6: switch the editor to Other.rules (no TLabel block); the row names Fix.rules ---
  [void][W]::InvokeMenu($main, 'File|Open...')
  $od = WaitCls $p.Id '#32770' 20
  if ($od -ne [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 700
    [void][W]::SendS(@([W]::Kids($od) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0], 0x000C, [IntPtr]::Zero, $other)
    Click (@(Find $od 'Button' '&Open')[0])
  }
  $st = WaitLike $main 'Loaded Other.rules*' 15
  Check 'migrate.d6.other.open' ($st -like 'Loaded Other.rules*') $st

  # --- 2. Layout -> DL_NONE (the proof cancels here) ---
  $before = Status $main
  $e = DoMigrate $main $lv 'Layout' $true '' ([bool]$ProofNoMigrate)
  Check 'migrate.dialog' ($e -eq '') $e
  $st = WaitStatus $main $before 10
  # D6: the editor opened the row's book first, so the status starts with the Opened prefix.
  Check 'migrate.d6.opened' ($st -like 'Opened Fix.rules (it converted the row) -- Wrote #migrate Layout*') $st
  Check 'migrate.layout.status' ($st -like '*Wrote #migrate Layout -> DL_NONE into #convert *(line * of Fix.rules) -- not saved: File > Save, then Convert again*') $st
  $members = @([W]::Column($lv, 3)); $rules = @([W]::Column($lv, 8))
  $ri = [Array]::IndexOf($members, 'Layout')
  Check 'migrate.layout.rule' (($ri -ge 0) -and ($rules[$ri] -like '#migrate Layout -> DL_NONE (line *, unsaved)')) "rule cells: $($rules -join ' | ')"

  # --- 3. WordWrap -> AutoSize ---
  $before = Status $main
  $e = DoMigrate $main $lv 'WordWrap' $false 'AutoSize' $false
  $st = WaitStatus $main $before 10
  Check 'migrate.wordwrap.status' ($st -like 'Wrote #migrate WordWrap -> AutoSize into #convert *') "$e $st"

  # --- 3b. D5 (skipped under -ProofNoMigrate: its bulk DL_NONE would write Layout and hide the six) ---
  if ($ProofNoMigrate) { "NOTE  -ProofNoMigrate: D5 section skipped" }
  else {
    $before = Status $main
    $r = DoBulk $main $lv @('Layout', 'WordWrap')
    Check 'migrate.d5.offer' ($r[0] -eq 'DL_NONE for all 2 selected rows') "caption '$($r[0])' $($r[1])"
    $st = WaitStatus $main $before 10
    Check 'migrate.d5.status' ($st -like 'DL_NONE for 2 member(s) in Fix.rules: 1 changed, 1 already DL_NONE -- not saved: File > Save, then Convert again*') $st
    $members = @([W]::Column($lv, 3)); $rules = @([W]::Column($lv, 8))
    $ri = [Array]::IndexOf($members, 'WordWrap')
    Check 'migrate.d5.rule' (($ri -ge 0) -and ($rules[$ri] -like '#migrate WordWrap -> DL_NONE (line *, unsaved)')) "rule cells: $($rules -join ' | ')"
    # Back to the rename, so the rest of the flow (Save, second Convert) measures what it always did.
    $before = Status $main
    $e = DoMigrate $main $lv 'WordWrap' $false 'AutoSize' $false
    $st = WaitStatus $main $before 10
    Check 'migrate.d5.restore' ($st -like 'Changed #migrate WordWrap -> AutoSize *') "$e $st"
  }

  # --- 4. File > Save: the lines reach the disk ---
  [void][W]::InvokeMenu($main, 'File|Save')
  [void](WaitLike $main 'Saved *' 30)
  Start-Sleep -Seconds 1
  $disk = [IO.File]::ReadAllText($book)
  Check 'migrate.saved.disk' (($disk -match '(?m)^#migrate Layout -> DL_NONE\r?$') -and ($disk -match '(?m)^#migrate WordWrap -> AutoSize\r?$')) ($disk -replace "`r?`n", ' / ')

  # --- 5. restore the unconverted unit, reindex, Convert again: the engine applies both lines ---
  WriteAscii $pas $origPas; WriteAscii $dfm $origDfm
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $st = RunConvert $main
  Check 'convert.second' ($st -like 'Converted 1 of 1 unit x book pair(s)*') $st
  $notes = @(Find $main 'TListView' $null | ForEach-Object { @([W]::Column($_, 7)) } | Where-Object { $_ -like '*; migrate: *' })
  Check 'migrate.rerun.note' (($notes -join ' | ') -like '*; migrate: 1 renamed, 1 deliberate break(s)*') ($notes -join ' | ')
  $after = [IO.File]::ReadAllText($pas)
  $found = @($after -split "`r?`n" | Where-Object { $_ -match 'Layout|AutoSize|WordWrap' } | ForEach-Object { $_.Trim() }) -join ' / '
  Check 'migrate.pas.break' ($after -match 'DL_NONE\(Label1\.Layout\)') "expected DL_NONE(Label1.Layout); found: $found"
  Check 'migrate.pas.rename' ($after -match 'Label1\.AutoSize') "expected Label1.AutoSize; found: $found"

  # --- 6. Work list after the second run: both members are mapped now (the default filter hides them) ---
  [void][W]::InvokeMenu($main, 'View|Work list')
  [void](WaitLike $main 'Work list: *' 10)
  $lv = WorkGrid $main
  Check 'migrate.worklist.after' (($null -ne $lv) -and (@([W]::Column($lv, 3)) -notcontains 'Layout')) (@([W]::Column($lv, 3)) -join ',')
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-migrate: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}