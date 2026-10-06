# Driven GUI check for the C10 glyph expression (feat/c10-glyph-editor, 2026-10-06).
# Usage: pwsh -NoProfile -File drive-glyph-link.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoGlyph]
#        A FROZEN drag-lint.exe (the 1.21.1 pin or later) must sit beside the exe; its Win64 library
#        index must answer (Vcl.Buttons.TBitBtn / cxButtons.TcxButton resolve there).
# Writes a fresh %TEMP%\glyph-<id> folder and deletes it on exit: rules\BitBtn-glyph.rules (the good
# G-link book, the text of tests\fixtures\glyph\BitBtn-glyph.rules), bad\BitBtn-glyph-bad.rules (its
# bad twin, in its own folder so the Convert tab lists one book), Fx.dfm (one TBitBtn, passed as --form:
# opening a book loads no tree, a double-click on the class's Classes row does) and a two-file Fix
# project indexed with the engine beside the exe (the Convert tab reads that index before it
# pre-flights). The editor is started on the good book: the rules folder is fixed at start-up.
# Checks: the Mapping menu carries 'Glyph expression...' and it is DISABLED with no rule loaded
# (ruling B2) and enabled once one is; the Convert tab greys the G-link book while the engine lacks
# glyph_stitch and the book stays unchecked through Check all, a Space and a click on its box -- a
# Convert then refuses with 'No rule book is checked.' (SKIP both when the engine has glyph_stitch;
# the book must then be listed without the suffix); File > Open the good book and load its rule, the
# glyph dialog on the Glyph row shows the 'Keep #link ... G[count]' box CHECKED (ruling R4:
# the grid shows only the first link per From, so the count link is checked through the dialog and the
# saved text); Mapping > Auto-Match then File > Save As keeps BOTH G-link lines byte-exact and writes
# no duplicate '#link OptionsImage.Glyph'; File > Save on the bad book shows the engine's
# 'G-expression column' error on the status bar; File > Exit ends the process.
# -ProofNoGlyph writes the books WITHOUT the G-expressions (the bad one equal to the good one): the
# greyed, never-checked, count-box, round-trip and error checks must then FAIL, which is the proof
# they can.
param([string]$Exe, [switch]$ProofNoGlyph)

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
  /* "Top|Item" -> True when the item is enabled (neither MF_GRAYED nor MF_DISABLED);
     False when it is disabled or not found. */
  public static bool MenuEnabled(IntPtr main, string path) {
    var parts = path.Split('|'); IntPtr m = MenuOf(main);
    for (int p = 0; p < parts.Length; p++) {
      int n = GetMenuItemCount(m), hit = -1;
      for (int i = 0; i < n; i++) if (Clean(m, i) == parts[p]) { hit = i; break; }
      if (hit < 0) return false;
      if (p == parts.Length - 1) return (GetMenuState(m, (uint)hit, 0x400) & 0x3) == 0;
      m = GetSubMenu(m, hit);
    }
    return false;
  }  public static string MenuCaptions(IntPtr main) {
    var sb = new StringBuilder(); IntPtr bar = MenuOf(main);
    for (int t = 0; t < GetMenuItemCount(bar); t++) {
      IntPtr sub = GetSubMenu(bar, t);
      for (int i = 0; sub != IntPtr.Zero && i < GetMenuItemCount(sub); i++) sb.Append(Clean(bar, t)).Append('|').Append(Clean(sub, i)).Append(" ; ");
    }
    return sb.ToString();
  }
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  public static IntPtr Parent(IntPtr h) { return GetParent(h); }
}
'@
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
function WaitFor($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
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
function Answer($procId, $btnCaption) {
  $dlg = WaitCls $procId 'TMessageForm' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no message box (forms: $(TopsNow $procId))" }
  $b = @(Find $dlg 'TButton' $btnCaption)
  if ($b.Count -eq 0) { return "no '$btnCaption' in message box: " + ((Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) }) -join ',') }
  Click $b[0]
  return ''
}
function SaveDialogTo($procId, $path) {
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no save dialog (forms: $(TopsNow $procId))" }
  $ed = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0]
  SetText $ed $path
  Click (@(Find $dlg 'Button' '&Save')[0])
  return ''
}
function StatusText($main) { (@(Find $main 'TStatusBar' $null) | ForEach-Object { [W]::Txt($_) }) -join ' | ' }
function WaitStatus($main, $pattern, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { $s = StatusText $main; if ($s -match $pattern) { return $s }; Start-Sleep -Milliseconds 500 }; return '' }
function WaitMsg($procId, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq 'TMessageForm') { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function ClickIn($dlg, $cap) { $b = @(Find $dlg 'TButton' $cap); if ($b.Count -gt 0) { Click $b[0]; return $true }; return $false }

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

function SkipLine($name, $why) { "SKIP  $name  $why" }
# The common Open dialog: the FILE NAME box is the Edit inside the ComboBoxEx32 whose control id
# is 0x47C (cmb13) -- the first Edit of the dialog can be another one. '' when the dialog closed.
function OpenDialogTo($procId, $path) {
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no open dialog (forms: $(TopsNow $procId))" }
  Start-Sleep -Milliseconds 700
  $edits = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })
  $ed = @($edits | Where-Object { [W]::GetDlgCtrlID([W]::Parent([W]::Parent($_))) -eq 0x47C })[0]
  if ($null -eq $ed) { $ed = $edits[0] }
  SetText $ed $path
  Click (@(Find $dlg 'Button' '&Open')[0])
  $t0 = Get-Date; while ((@([W]::Tops($procId)) -contains $dlg) -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep -Milliseconds 250 }
  if (@([W]::Tops($procId)) -contains $dlg) { return "open dialog still up (edit text '$([W]::Txt($ed))')" }
  return ''
}
# DblClickRow / OpenClass: as drive-engine-wait.ps1. Opening a book loads no tree; a double-click
# on the Classes row of a class in the --form .dfm opens that class's rule and loads the grid.
function ListTexts($lb) { $n = [int][W]::Send($lb, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero); @(for ($i = 0; $i -lt $n; $i++) { $sb = New-Object System.Text.StringBuilder 512; [void][W]::SendSB($lb, 0x0189, [IntPtr]$i, $sb); $sb.ToString() }) }
function DblClickRow($lb, $idx) {
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($lb, [ref]$r)
  $x = [int](($r.R - $r.L) - 40); $y = 9 + 18 * $idx   # ItemHeight = 18
  $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
  [void][W]::PostMessage($lb, 0x0201, [IntPtr]1, $lp); [void][W]::PostMessage($lb, 0x0202, [IntPtr]::Zero, $lp)
  [void][W]::PostMessage($lb, 0x0203, [IntPtr]1, $lp); [void][W]::PostMessage($lb, 0x0202, [IntPtr]::Zero, $lp)
}
function OpenClass($main, $cls) {
  [void][W]::ClickTab($main, 'Classes'); Start-Sleep -Milliseconds 500
  $lb = @(Find $main 'TCheckListBox' $null | Where-Object { [W]::IsWindowVisible($_) })[0]
  if ($null -eq $lb) { return 'no Classes list' }
  $rows = ListTexts $lb
  $row = -1; for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i] -match "\b$cls\b") { $row = $i; break } }
  if ($row -lt 0) { return "no $cls row (rows: $($rows -join ' | '))" }
  DblClickRow $lb $row
  return ''
}
# The editor is idle once it has had no engine child and no progress window (TEngineWaitForm)
# for 3 s running: a click and its double-click can start two loads back to back.
$ENGINE_IDLE_SEC = 900
function WaitIdle($procId) {
  $t0 = Get-Date; $quiet = $null
  while (((Get-Date) - $t0).TotalSeconds -lt $ENGINE_IDLE_SEC) {
    # Children created AFTER the editor started only: a reused PID can make an old orphan of
    # another session look like the editor's child (measured: a day-old tail.exe).
    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$procId" | Where-Object { $_.CreationDate -ge $script:editorStart })
    $busy = ($kids.Count -gt 0) -or ([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' })
    if ($busy) { $quiet = $null } elseif ($null -eq $quiet) { $quiet = Get-Date } elseif (((Get-Date) - $quiet).TotalSeconds -ge 3) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
function Lines($path) { if (Test-Path -LiteralPath $path) { @([IO.File]::ReadAllLines($path)) } else { @() } }

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the driver needs the editor's own frozen engine" }
$capsJson = & { $ErrorActionPreference = 'Continue'; & $engine info --json 2>$null | Out-String }
$hasGlyph = $capsJson -match '"glyph_stitch"\s*:\s*true'

# --- fixture ---
$GLINK = '#link OptionsImage.Glyph <- Glyph G[*/4], G[1/2]G[2/2] : AssignGraphic'
$CLINK = '#link OptionsImage.NumGlyphs <- Glyph G[count]'
$tmp = Join-Path $env:TEMP ('glyph-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$rulesDir = Join-Path $tmp 'rules'; $badDir = Join-Path $tmp 'bad'; $dragDir = Join-Path $tmp '_D-RAG'
foreach ($d in $rulesDir, $badDir, $dragDir) { [void][IO.Directory]::CreateDirectory($d) }
$good = Join-Path $rulesDir 'BitBtn-glyph.rules'; $bad = Join-Path $badDir 'BitBtn-glyph-bad.rules'; $out = Join-Path $rulesDir 'out.rules'
$head = "// C10 fixture: a G-link book on classes the Win64 library index resolves.`n#convert Vcl.Buttons.TBitBtn -> cxButtons.TcxButton, cxButtons, dxCore`n"
$tail = "#link Caption <- Caption`n#link Enabled <- Enabled`n"
if ($ProofNoGlyph) {
  "NOTE  -ProofNoGlyph: the books carry NO G-expression; the glyph checks below are expected to FAIL"
  $plain = $head + "#link OptionsImage.Glyph <- Glyph : AssignGraphic`n#link OptionsImage.NumGlyphs <- NumGlyphs`n" + $tail
  WriteAscii $good $plain
  WriteAscii $bad $plain
} else {
  WriteAscii $good ($head + "$GLINK`n$CLINK`n" + $tail)
  WriteAscii $bad ($head + "#link OptionsImage.Glyph <- Glyph G[5/4] : AssignGraphic`n$CLINK`n" + $tail)
}
$dfm = Join-Path $tmp 'Fx.dfm'
WriteAscii $dfm "object Fx: TFx`n  object B1: TBitBtn`n  end`nend`n"
# The smallest project the Convert tab can read: its pre-flight runs only once the
# project index answers (ListIndexedFiles), so an index must exist.
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
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
    <PropertyGroup Condition="'$(Base)'!=''">
        <DCC_UnitSearchPath>.\;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>
</Project>
'@
WriteAscii (Join-Path $tmp 'Fix.dpr') "program Fix;`n`nuses`n  FixUnit in 'FixUnit.pas';`n`nbegin`nend.`n"
WriteAscii (Join-Path $tmp 'FixUnit.pas') "unit FixUnit;`n`ninterface`n`nimplementation`n`nend.`n"

$p = $null
try {
  $t0 = Get-Date
  $idxOut = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  Check 'glyph.fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s " -f ((Get-Date) - $t0).TotalSeconds + (($idxOut -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1))


  # The good book FIRST (the editor auto-opens only a leading file argument, and the Convert
  # tab's rules folder and the Classes list's rule catalog are that book's folder), then the
  # flags. Opening a book loads no tree, so no rule is loaded until the Classes double-click.
  $p = Start-Process $Exe -ArgumentList "`"$good`" --form `"$dfm`" --project-db `"$db`"" -PassThru
  $script:editorStart = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CreationDate
  $main = WaitCls $p.Id 'TConvRulesForm' 60
  Check 'glyph.main' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  Start-Sleep -Seconds 2

  # --- the menu item, and B2: disabled while no rule is loaded ---
  $caps = [W]::MenuCaptions($main)
  Check 'glyph.menu.present' ($caps -match 'Mapping\|Glyph expression\.\.\.') $caps
  Check 'glyph.menu.disabled.no.rule' (($caps -match 'Mapping\|Glyph expression\.\.\.') -and -not [W]::MenuEnabled($main, 'Mapping|Glyph expression...'))

  # --- File > Open the good book (again: the File > Open path), then double-click its class ---
  [void](WaitIdle $p.Id)   # the start-up class-list queries
  Check 'glyph.open.invoke' ([W]::InvokeMenu($main, 'File|Open...'))
  $e = OpenDialogTo $p.Id $good
  $st = WaitStatus $main '^Loaded \d+ line' 30
  Check 'glyph.open.good' (($e -eq '') -and ($st -match '^Loaded 6 line\(s\), 1 rule\(s\)')) "$e $st"
  $e = OpenClass $main 'TBitBtn'
  Start-Sleep -Seconds 1
  [void](WaitIdle $p.Id)
  $st = StatusText $main
  Check 'glyph.rule.loaded' ($st -match '^Loaded Vcl\.Buttons\.TBitBtn -> cxButtons\.TcxButton from BitBtn-glyph\.rules') "$e $st"
  Check 'glyph.menu.enabled.rule' ([W]::MenuEnabled($main, 'Mapping|Glyph expression...'))

  # --- Convert tab (rules folder = the open book's): the G-link book is greyed and can never be checked ---
  [void][W]::InvokeMenu($main, 'Conversion|Convert...')
  Start-Sleep -Seconds 2
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { [W]::IsWindowVisible($_) -and @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  $books = $null; $checkAll = $null; $lv = $null
  if ($conv.Count -eq 1) {
    $tab = [CT]::Parent([CT]::Parent([CT]::Parent($conv[0])))
    $lv = @(Find ([CT]::Parent([CT]::Parent($conv[0]))) 'TListView' $null)[0]
    $checkAll = @(Find $tab 'TButton' 'Check all')[0]
    if ($null -ne $checkAll) { $books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0] }
  }
  $bookItems = @(if ($null -ne $books) { [CT]::Items($books) })
  $gItem = @($bookItems | Where-Object { $_ -like 'BitBtn-glyph.rules*' })
  if ($hasGlyph) {
    SkipLine 'glyph.convert.book.greyed' 'engine has glyph_stitch'
    Check 'glyph.convert.book.listed' (($gItem.Count -eq 1) -and ($gItem[0] -ceq 'BitBtn-glyph.rules')) ($bookItems -join ' | ')
    SkipLine 'glyph.convert.book.never.checked' 'engine has glyph_stitch'
  } else {
    Check 'glyph.convert.book.greyed' (($gItem.Count -eq 1) -and ($gItem[0] -ceq 'BitBtn-glyph.rules  (glyph links: engine support pending)')) ($bookItems -join ' | ')
    # Check all, then try by hand: select the row, Space, and a click on its box.
    if ($null -ne $checkAll) { Click $checkAll; Start-Sleep -Milliseconds 500 }
    if ($gItem.Count -eq 1) {
      $gi = [array]::IndexOf([string[]]$bookItems, $gItem[0])
      [void][W]::Send($books, 0x0186, [IntPtr]$gi, [IntPtr]0)
      [void][W]::Send($books, 0x0102, [IntPtr]0x20, [IntPtr]0)
      $ih = [int][W]::Send($books, 0x01A1, [IntPtr]0, [IntPtr]0)
      $lp = [IntPtr](($gi * $ih + [int]($ih / 2)) * 65536 + 6)
      [void][W]::Send($books, 0x0201, [IntPtr]1, $lp); [void][W]::Send($books, 0x0202, [IntPtr]0, $lp)
      Start-Sleep -Milliseconds 500
    }
    # The rules folder holds ONLY this book, so a Convert that sees it unchecked refuses
    # with 'No rule book is checked.' -- the pre-flight runs after the index read and
    # before the empty source list is refused. An inert gate (the book checked) gives a
    # refusal WITHOUT that sentence, and Preflight's defence-in-depth note in the grid.
    $before = StatusText $main
    if ($conv.Count -eq 1) { Click $conv[0] }
    $st = WaitStatus $main 'Convert refused|Cannot read' 30
    $notes = @(if ($null -ne $lv) { [W]::Column($lv, 7) })
    Check 'glyph.convert.book.never.checked' (($st -match 'No rule book is checked\.') -and -not ($notes -match 'glyph links: engine support pending')) ("status: $st; notes: " + ($notes -join ' | '))
  }

  [void][W]::ClickTab($main, 'Classes')
  Start-Sleep -Milliseconds 500

  # --- R4: the count link is not a grid row; the image link's dialog shows it as a CHECKED box ---
  $grid = @(Find $main 'TStringGrid' $null | Where-Object { [W]::IsWindowVisible($_) })[0]
  $boxText = ''; $boxChecked = $false; $dlgCap = ''
  if ($null -ne $grid) {
    $filters = @(Find $main 'TEdit' $null | Where-Object { [CT]::Parent([CT]::Parent($_)) -eq [CT]::Parent($grid) } | Sort-Object { [W]::Left($_) })
    if ($filters.Count -ge 2) { SetText $filters[1] 'OptionsImage.Glyph'; Start-Sleep -Milliseconds 700 }
    # Row 1 (below the 20 px header): the only row the To filter leaves.
    $lp = [IntPtr]((31 -shl 16) -bor 60)
    [void][W]::PostMessage($grid, 0x0201, [IntPtr]1, $lp); [void][W]::PostMessage($grid, 0x0202, [IntPtr]::Zero, $lp)
    Start-Sleep -Milliseconds 500
    [void][W]::InvokeMenu($main, 'Mapping|Glyph expression...')
    $gd = WaitCls $p.Id 'TGlyphExprForm' 10
    if ($gd -ne [IntPtr]::Zero) {
      $dlgCap = [W]::Txt($gd)
      $box = @(Find $gd 'TCheckBox' $null)[0]
      if ($null -ne $box) { $boxText = [W]::Txt($box); $boxChecked = ([int][W]::Send($box, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1) -and [W]::IsWindowVisible($box) }
      [void](ClickIn $gd 'Cancel')
      $t0 = Get-Date; while ((@([W]::Tops($p.Id)) -contains $gd) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }
    }
    if ($filters.Count -ge 2) { SetText $filters[1] ''; Start-Sleep -Milliseconds 500 }
  }
  Check 'glyph.dialog.count.box.checked' ($boxChecked -and ($boxText -ceq ('Keep ' + $CLINK))) "dialog '$dlgCap'; box '$boxText' checked=$boxChecked; status: $(StatusText $main)"

  # --- Auto-Match, then Save As: both G-link lines survive byte-exact, no duplicate ---
  $before = StatusText $main
  Check 'glyph.automatch.invoke' ([W]::InvokeMenu($main, 'Mapping|Auto-Match'))
  $st = WaitStatus $main '^Auto-Match: ' 30
  Check 'glyph.automatch' ($st -match '^Auto-Match: \d+ unambiguous assignment') $st
  Check 'glyph.saveas.invoke' ([W]::InvokeMenu($main, 'File|Save As...'))
  $e = SaveDialogTo $p.Id $out
  Start-Sleep -Seconds 1
  [void](WaitIdle $p.Id)
  $st = WaitStatus $main 'Validate:' 60
  Check 'glyph.saveas.written' (($e -eq '') -and (Test-Path -LiteralPath $out)) "$e $st"
  $outLines = Lines $out
  Check 'glyph.saveas.glink.exact' (@($outLines | Where-Object { $_ -ceq $GLINK }).Count -eq 1) (($outLines | Where-Object { $_ -like '#link OptionsImage.*' }) -join ' / ')
  Check 'glyph.saveas.count.exact' (@($outLines | Where-Object { $_ -ceq $CLINK }).Count -eq 1)
  Check 'glyph.saveas.no.duplicate' (@($outLines | Where-Object { $_ -clike '#link OptionsImage.Glyph *' }).Count -eq 1) ("lines: " + @($outLines | Where-Object { $_ -clike '#link OptionsImage.Glyph *' }).Count)

  # --- the bad book: Save shows the engine's CV-4 error ---
  Check 'glyph.bad.open.invoke' ([W]::InvokeMenu($main, 'File|Open...'))
  $m = WaitCls $p.Id 'TMessageForm' 3
  if ($m -ne [IntPtr]::Zero) { [void](ClickIn $m '&No') }
  $e = OpenDialogTo $p.Id $bad
  Start-Sleep -Seconds 2
  # The Raw DSL memo shows the open book's text: its G-link line identifies the bad book.
  $raw = Raw $main
  $badLine = (Lines $bad)[2]
  Check 'glyph.bad.open' (($e -eq '') -and $raw.Contains($badLine)) "$e; status: $(StatusText $main)"
  [void][W]::ClickTab($main, 'Classes')
  # The Classes selection survives the open, so the bad book's rule for it starts loading.
  [void](WaitIdle $p.Id)
  Check 'glyph.bad.save.invoke' ([W]::InvokeMenu($main, 'File|Save'))
  Start-Sleep -Seconds 1
  [void](WaitIdle $p.Id)
  $st = WaitStatus $main 'G-expression column|Validate:' 60
  Check 'glyph.bad.save.error' ($st -match 'G-expression column') $st

  # --- Exit ---
  [void][W]::InvokeMenu($main, 'File|Exit')
  $m = WaitCls $p.Id 'TMessageForm' 3
  if ($m -ne [IntPtr]::Zero) { [void](ClickIn $m '&No') }
  Check 'glyph.exit' ($p.WaitForExit(15000)) (TopsNow $p.Id)
}
finally {
  if ($null -ne $p -and -not $p.HasExited) { $p.Kill($true); [void]$p.WaitForExit(15000) }
  # An engine child may still hold the fixture index for a moment after the kill.
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if (-not $gone) { "WARN  fixture NOT removed: $tmp" }
}
"RESULT pass=$script:pass fail=$script:fail"
if ($script:fail -gt 0) { exit 1 }
