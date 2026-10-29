# Driven GUI check for the Work list tab (editor-1270 Task 3, 2026-10-11; engine 1.27.0 apply/1 pas_uses[]).
# Usage: pwsh -NoProfile -File drive-work-list.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoPasUses]
#        A FROZEN drag-lint.exe must sit beside the exe (a staged copy of a pin, never dll-win64): the fixture
#        index is built with THAT engine, and its Win64 library index must answer (TLabel / TStaticText).
# Fixture (fresh temp folder, the _D-RAG layout of drive-convert-tab.ps1): Fix.dpr / Fix.dproj / FixUnit.pas +
#   FixUnit.dfm (one TLabel; FormCreate sets Label1.Caption, .Layout and .WordWrap) / rules\Fix.rules (#convert
#   TLabel -> TStaticText linking Caption, Left, Top) / _D-RAG\Fix.sqlite. TStaticText has no Layout and no
#   WordWrap, so the run's pas_uses[] holds 2 unmapped rows and 1 mapped (measured with the 1.27.0 pin).
# Then: View > Work list before any run (the no-run text); Conversion > Convert..., Check all, Add FixUnit.pas,
#   Convert; View > Work list (the summary on the status bar, the two unmapped rows in the grid); a double-click
#   on row 0 copies '<path>(<line>)' and says 'Copied FixUnit.pas(<line>) -- ...'; with FixUnit.pas renamed
#   away the same double-click is a '[!] <path> not found' error, not an exception.
# -ProofNoPasUses: stage an engine WITHOUT the pas_uses capability (1.26.7) beside the exe. The Work list must
#   then say 'no work list (engine has no pas_uses)' (proof.no.pas_uses); the row and double-click checks are
#   expected to FAIL, which is the proof that they can.
# The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe, [switch]$ProofNoPasUses)
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
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('work-list-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'
$book = Join-Path $rulesDir 'Fix.rules'
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

$p = $null
try {
  if ($ProofNoPasUses) { "NOTE  -ProofNoPasUses: the row and double-click checks below are expected to FAIL" }
  $t0 = Get-Date
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  Check 'fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s $summary" -f ((Get-Date) - $t0).TotalSeconds)

  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2

  # --- 1. View > Work list before any run ---
  $invoked = [W]::InvokeMenu($main, 'View|Work list')
  $st = WaitLike $main 'Work list: *' 10
  Check 'worklist.menu' ($invoked -and ((WorkTab $main) -contains 'Work list')) ("invoked=$invoked active tabs: " + ((WorkTab $main) -join ', '))
  Check 'worklist.before.run' ($st -eq 'Work list: no work list yet -- run Convert first') $st

  # --- 2. Convert FixUnit.pas (as drive-convert-tab.ps1) ---
  [void][W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'convert.controls' $false "Convert buttons beside a progress bar: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  Click $checkAll
  Start-Sleep -Milliseconds 500
  $e = AddViaDialog $p.Id $add $pas
  Check 'fixunit.added' ($e -eq '') "$e; status: $(Status $main)"
  # Settle first: the Add's own status lines arrive after the dialog closes.
  Start-Sleep -Seconds 2
  # ... and the C8 inherited-instances check after Add... (a Convert clicked under it is refused).
  [void](WaitIdle $p.Id $main 90)
  $pre = Status $main
  Click $conv
  # The run's outcome, not just any change: the Add may still write a line after the click.
  $t0 = Get-Date; $st = ''
  while (((Get-Date) - $t0).TotalSeconds -lt 600) {
    Start-Sleep -Milliseconds 500
    $st = Status $main
    # A question can come up before the run writes any status: look for it before the pre-skip.
    if (@(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' }).Count -gt 0) { $script:dlg = TopsNow $p.Id; break }
    if ($st -eq $pre) { continue } # the line from before the click is not this run's answer
    if ($st -like 'Converted *' -or $st -like 'Convert stopped*' -or $st -like 'RESTORE FAILED*' -or $st -like '`[!`] *') { break }
  }
  $script:waited = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Milliseconds 300
  $st = Status $main
  "  run: {0:N0}s; status: {1}" -f $script:waited, $st
  Check 'convert.converted' ($st -like 'Converted 1 of 1 unit x book pair(s)*') "$st$(if ($dlg) { "; editor dialog: $dlg" })"

  # --- 3. View > Work list after the run ---
  [void][W]::InvokeMenu($main, 'View|Work list')
  $st = WaitLike $main 'Work list: *' 10
  if ($ProofNoPasUses) {
    Check 'proof.no.pas_uses' ($st -eq 'Work list: no work list (engine has no pas_uses)') $st
  }
  Check 'worklist.summary' ($st -eq 'Work list: 2 to work on (2 unmapped, 0 global, 0 cast-refused, 0 not-rewritten), 1 mapped / same-name; 2 shown') $st
  # The tab's controls by STRUCTURE: the status filter is the check list holding 'unmapped'; the grid is the
  # list view under the same tab panel.
  $filter = @(Find $main 'TCheckListBox' $null | Where-Object { [CT]::Items($_) -contains 'unmapped' })
  $lv = $null
  if ($filter.Count -eq 1) { $lv = @(Find ([CT]::Parent([CT]::Parent($filter[0]))) 'TListView' $null)[0] }
  Check 'worklist.controls' ($null -ne $lv) "status filters: $($filter.Count)"
  if ($null -eq $lv) { return }
  Check 'worklist.filter.statuses' (([CT]::Items($filter[0]) -join ',') -eq 'unmapped,global-dangling,cast-refused,not-rewritten,same-name,mapped,(other)') ([CT]::Items($filter[0]) -join ',')
  # Grid: Unit / Instance / From -> To / Member / Kind / Status / Lines / Declared in. The default filter
  # shows the work statuses only, so the mapped Caption row is hidden.
  $members = @([W]::Column($lv, 3)); $statuses = @([W]::Column($lv, 5)); $lines = @([W]::Column($lv, 6))
  for ($i = 0; $i -lt $members.Count; $i++) { '  row: ' + ((0..7 | ForEach-Object { @([W]::Column($lv, $_))[$i] }) -join ' / ') }
  Check 'worklist.grid.unmapped' ((($members -join ',') -eq 'Layout,WordWrap') -and (($statuses -join ',') -eq 'unmapped,unmapped')) ("members=" + ($members -join ',') + " statuses=" + ($statuses -join ','))

  # --- 4. double-click row 0: '<path>(<line>)' on the clipboard, 'Copied ...' on the status bar ---
  $line0 = if ($lines.Count -gt 0) { $lines[0] } else { '?' }
  Set-Clipboard -Value 'before-double-click'
  [W]::SelectRow($lv, 0)
  [void][W]::PostMessage($lv, 0x0203, [IntPtr]1, [W]::RowClientPoint($lv, 0))
  $st = WaitLike $main 'Copied *' 10
  $clip = $null; $clipBusy = $false
  for ($i = 0; $i -lt 10; $i++) {
    try { $clip = Get-Clipboard -Raw -ErrorAction Stop; $clipBusy = $false; break }
    catch { if ($_.Exception.Message -match 'Cannot open clipboard') { $clipBusy = $true; Start-Sleep -Milliseconds 200 } else { throw } }
  }
  Check 'worklist.dblclick.status' ($st -eq "Copied FixUnit.pas($line0) to the clipboard -- line $line0") $st
  Check 'worklist.dblclick.clipboard' (-not $clipBusy -and ($clip -eq "$pas($line0)")) $(if ($clipBusy) { 'clipboard busy (another process holds it)' } else { "clipboard: $clip" })

  # --- 5. the same double-click with the file gone: a status-bar error, never an exception ---
  $off = $pas + '.off'
  [IO.File]::Move($pas, $off)
  try {
    [W]::SelectRow($lv, 0)
    [void][W]::PostMessage($lv, 0x0203, [IntPtr]1, [W]::RowClientPoint($lv, 0))
    $st = WaitLike $main '`[!`] *' 10
    $dlgs = @(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' })
    Check 'worklist.dblclick.missing.file' (($st -eq "[!] $pas not found") -and $dlgs.Count -eq 0) "$st; dialogs: $($dlgs.Count)"
  } finally { [IO.File]::Move($off, $pas) }
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  # The engine child may still hold the index for a moment after the kill.
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-work-list: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
