# Driven GUI check for C8 (inherited instances, editor half -- spec 2026-10-05-c8-inherited-instances-design.md E5-E8).
# Usage: pwsh -NoProfile -File drive-inherited-offer.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoInheritance]
#        A FROZEN drag-lint.exe must sit beside the exe (a staged pin copy, never dll-win64); the fixture is indexed with it.
# Fixture (temp folder, _D-RAG layout): Fix.dproj / Fix.dpr with Anc (TAncForm, object Label1: TLabel) and Desc
#   (TDescForm = class(TAncForm), inherited Label1: TLabel), Desc2 (no .dfm block; its CODE writes Label1.Caption --
#   spec E2b), rules\Fix.rules (#convert TLabel -> TStaticText).
# Then: adding Desc.pas asks "Add Anc.pas ahead of Desc.pas?" (the text is mirrored on the status bar); No lists
#   only Desc and its row note names Anc; adding Anc below it and pressing Convert warns once (No = nothing runs);
#   Yes on a fresh add inserts Anc directly above Desc. On a correct build no conversion is run (the warning's No).
#   Each add / Convert runs the inherited-instance check, behind the progress window when it takes over 400 ms.
#   Measured 2026-10-05 on the 1.21.1 pin copy: 15 pass / 0 fail; the 5a776148 (pre-C8) editor: 7 pass / 7 fail
#   (offer.prompt, note.unconverted, order.warning, order.no.runs.nothing, engine.refusal.note,
#   offer.yes.inserts.above, note.code.use; it STARTS a real conversion on Convert -- ~20 s on this fixture).
# -ProofNoInheritance writes Desc.dfm with its OWN object instead of an inherited one (and Desc2's code writes Tag):
#   the offer / note / warning checks must then FAIL, which is the proof they can. With no warning a REAL conversion
#   starts on Convert. Measured 2026-10-05: 7 pass / 7 fail -- the same 7 FAILs as above; sources.cleared PASSES
#   (the run had finished before the list was cleared).
# The E10 check branches on the staged engine's inherited_instances capability: with it (1.22.0 pin copy,
#   measured 2026-10-06) engine.refusal.note.absent -- 15 / 0, and -ProofNoInheritance 8 / 6 (that check then
#   passes vacuously); WITHOUT it (stage a 1.21.1 pin copy beside the same exe) engine.refusal.note -- 15 / 0.
#   Run both stages: one stage proves only one branch.
param([string]$Exe, [switch]$ProofNoInheritance)
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
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
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
# 'Converting ...' line, or an editor dialog appears; returns the final status text.
function WaitStatus($main, $Before, $Seconds) {
  $t0 = Get-Date; $st = $Before; $script:dlg = ''
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 500
    $d = @(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' })
    if ($d.Count -gt 0) { $script:dlg = TopsNow $p.Id; break }
    $st = Status $main
    if ($st -ne $Before -and $st -notlike 'Converting *') { break }
  }
  $script:waited = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Milliseconds 300
  Status $main
}

# Waits for an add to settle instead of a fixed sleep: the Open dialog gone, no progress
# window (TEngineWaitForm, the inherited-instance check), and the status line reporting
# $count listed units -- or an editor message box (a prompt the check must not ask).
function WaitAddSettled($procId, $main, $count, $sec = 120) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $tops = @([W]::Tops($procId) | ForEach-Object { [W]::Cls($_) })
    if ($tops -contains 'TMessageForm') { return }
    if (($tops -notcontains '#32770') -and ($tops -notcontains 'TEngineWaitForm') -and ((Status $main) -like "$count source unit(s) listed*")) { return }
    Start-Sleep -Milliseconds 250
  }
}
function Answer($procId, $caption) {
  $dlg = WaitCls $procId 'TMessageForm' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no message box (forms: $(TopsNow $procId))" }
  $b = @(Find $dlg 'TButton' $null | Where-Object { ([W]::Txt($_) -replace '&', '') -eq $caption })
  if ($b.Count -eq 0) { return "no '$caption' in message box: " + ((Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) }) -join ',') }
  Click $b[0]
  $t0 = Get-Date; while ((WaitCls $procId 'TMessageForm' 0) -ne [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 250 }
  return ''
}
# AddViaDialog without its trailing wait: the C8 prompt is modal INSIDE AddSources.
function PickFile($procId, $addBtn, $path) {
  Click $addBtn
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no open dialog (forms: $(TopsNow $procId))" }
  Start-Sleep -Milliseconds 700
  $ed = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0]
  [void][W]::SendS($ed, 0x000C, [IntPtr]::Zero, $path)
  Click (@(Find $dlg 'Button' '&Open')[0])
  return ''
}
function ClearSources($src, $del) {
  [void][W]::Send($src, 0x0185, [IntPtr]1, [IntPtr](-1))   # LB_SETSEL all
  Click $del; Start-Sleep -Seconds 1
}

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- stage a pin copy" }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('c8-offer-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$anc = Join-Path $tmp 'Anc.pas'; $desc = Join-Path $tmp 'Desc.pas'; $desc2 = Join-Path $tmp 'Desc2.pas'; $book = Join-Path $rulesDir 'Fix.rules'
WriteAscii $dproj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{8E2D7C1F-3B4A-4D2C-8F66-1B2C3D4E5F60}</ProjectGuid>
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
  Anc in 'Anc.pas' {AncForm},
  Desc in 'Desc.pas' {DescForm},
  Desc2 in 'Desc2.pas' {Desc2Form};

begin
  Application.Initialize;
  Application.Run;
end.
'@
WriteAscii $anc @'
unit Anc;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;

type
  TAncForm = class(TForm)
    Label1: TLabel;
  end;

implementation

{$R *.dfm}

end.
'@
WriteAscii (Join-Path $tmp 'Anc.dfm') @'
object AncForm: TAncForm
  Caption = 'Anc'
  object Label1: TLabel
    Caption = 'Hello'
  end
end
'@
if ($ProofNoInheritance) {
  "NOTE  -ProofNoInheritance: Desc.dfm holds its OWN Label2; the offer / note / warning checks are expected to FAIL"
  WriteAscii $desc @'
unit Desc;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes, Anc;

type
  TDescForm = class(TAncForm)
    Label2: TLabel;
  end;

implementation

{$R *.dfm}

end.
'@
  WriteAscii (Join-Path $tmp 'Desc.dfm') @'
inherited DescForm: TDescForm
  object Label2: TLabel
    Caption = 'Own'
  end
end
'@
} else {
  WriteAscii $desc @'
unit Desc;

interface

uses
  Anc;

type
  TDescForm = class(TAncForm)
  end;

implementation

{$R *.dfm}

end.
'@
  WriteAscii (Join-Path $tmp 'Desc.dfm') @'
inherited DescForm: TDescForm
  inherited Label1: TLabel
    Caption = 'Desc'
  end
end
'@
}
# E2b: Desc2's .dfm has NO block for Label1; its CODE writes Label1.Caption (the proof run writes Tag only).
$useLine = if ($ProofNoInheritance) { '  Tag:= 2;' } else { '  Label1.Caption:= ''Two'';' }
WriteAscii $desc2 (@'
unit Desc2;

interface

uses
  System.Classes, Anc;

type
  TDesc2Form = class(TAncForm)
    procedure FormCreate(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TDesc2Form.FormCreate(Sender: TObject);
begin
'@ + "`n$useLine`n" + @'
end;

end.
'@)
WriteAscii (Join-Path $tmp 'Desc2.dfm') @'
inherited Desc2Form: TDesc2Form
  OnCreate = FormCreate
end
'@
WriteAscii $book @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
'@

$p = $null
try {
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  Check 'fixture.index' (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $db)) ((($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1))
  $caps = & { $ErrorActionPreference = 'Continue'; & $engine info --json 2>$null | Out-String }
  $inheritedCap = $caps -match '"inherited_instances"\s*:\s*true'

  $p = Start-Process $Exe -ArgumentList "`"$book`" --project-db `"$db`"" -PassThru
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $m = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($m) { $main = $m } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2
  [void][W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { Check 'tab.controls' $false "Convert buttons: $($conv.Count)"; return }
  $conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv)))
  $lv = @(Find ([CT]::Parent([CT]::Parent($conv))) 'TListView' $null)[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  $add = @(Find $tab 'TButton' 'Add...')[0]
  $del = @(Find ([CT]::Parent($add)) 'TButton' 'Delete')[0]
  $src = @(Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0]
  Check 'tab.controls' ($null -ne $lv -and $null -ne $checkAll -and $null -ne $add -and $null -ne $del -and $null -ne $src)
  Click $checkAll
  Start-Sleep -Seconds 1

  # --- E6: adding the descendant asks; No adds only it ---
  $e = PickFile $p.Id $add $desc
  $prompt = WaitCls $p.Id 'TMessageForm' 20
  $st = Status $main
  Check 'offer.prompt' (($e -eq '') -and ($prompt -ne [IntPtr]::Zero) -and ($st -eq 'Add Anc.pas ahead of Desc.pas?')) "$e status: $st; forms: $(TopsNow $p.Id)"
  if ($prompt -ne [IntPtr]::Zero) { $e = Answer $p.Id 'No'; Check 'offer.answer.no' ($e -eq '') $e }
  Start-Sleep -Seconds 2
  $items = [CT]::Items($src)
  Check 'offer.no.only.desc' (($items.Count -eq 1) -and ($items[0] -eq $desc)) ($items -join ' | ')
  # --- E5: the row note, as the source summary on the status bar ---
  $st = Status $main
  Check 'note.unconverted' ($st -like '*Desc.pas: inherits 1 TLabel instance(s) from Anc -- convert it first (recommended)*') $st

  # --- E7: the descendant ABOVE its ancestor warns once; No runs nothing ---
  $e = PickFile $p.Id $add $anc
  WaitAddSettled $p.Id $main 2
  Check 'anc.no.prompt' (($e -eq '') -and ((WaitCls $p.Id 'TMessageForm' 0) -eq [IntPtr]::Zero)) "$e forms: $(TopsNow $p.Id)"
  $items = [CT]::Items($src)
  Check 'order.desc.above.anc' (($items.Count -eq 2) -and ($items[0] -eq $desc) -and ($items[1] -eq $anc)) ($items -join ' | ')
  Click $conv
  $warn = WaitCls $p.Id 'TMessageForm' 30
  $st = Status $main
  Check 'order.warning' (($warn -ne [IntPtr]::Zero) -and ($st -like '*Desc.pas is listed above its ancestor Anc.pas, which is not converted yet*')) "status: $st; forms: $(TopsNow $p.Id)"
  if ($warn -ne [IntPtr]::Zero) { [void](Answer $p.Id 'No') }
  Start-Sleep -Seconds 2
  $st = Status $main
  Check 'order.no.runs.nothing' (($st -eq 'Convert cancelled: reorder the source units (ancestors first) and press Convert again.') -and -not (Test-Path -LiteralPath ($desc + '.BCK1'))) $st
  # --- E10 gate: without inherited_instances the run notes say the engine will refuse Desc ---
  $notes = @([W]::Column($lv, 7))
  if ($inheritedCap) { Check 'engine.refusal.note.absent' (-not ($notes -like '*refuses such a unit*')) ($notes -join ' | ') }
  else { Check 'engine.refusal.note' (@($notes | Where-Object { $_ -like 'Desc.pas: 1 inherited instance(s) of a From type -- this engine refuses such a unit*' }).Count -eq 1) ($notes -join ' | ') }

  # --- E6 Yes: inserts the ancestor directly above the descendant ---
  ClearSources $src $del
  Check 'sources.cleared' ([int][W]::Send($src, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero) -eq 0)
  $e = PickFile $p.Id $add $desc
  $prompt = WaitCls $p.Id 'TMessageForm' 20
  if ($prompt -ne [IntPtr]::Zero) { $e = Answer $p.Id 'Yes' } else { $e = 'no prompt' }
  Start-Sleep -Seconds 2
  $items = [CT]::Items($src)
  Check 'offer.yes.inserts.above' (($e -eq '') -and ($items.Count -eq 2) -and ($items[0] -eq $anc) -and ($items[1] -eq $desc)) "$e items: $($items -join ' | ')"

  # --- E2b: a CODE-only use is noted like an inherited instance (Anc is listed: no prompt) ---
  $e = PickFile $p.Id $add $desc2
  WaitAddSettled $p.Id $main 3
  $st = Status $main
  Check 'note.code.use' (($e -eq '') -and ((WaitCls $p.Id 'TMessageForm' 0) -eq [IntPtr]::Zero) -and ($st -like '*Desc2.pas: inherits 1 TLabel instance(s) from Anc -- convert it first (recommended)*')) "$e status: $st"
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-inherited-offer: $script:pass pass / $script:fail fail"
  if ($script:fail -gt 0) { exit 1 }
}
