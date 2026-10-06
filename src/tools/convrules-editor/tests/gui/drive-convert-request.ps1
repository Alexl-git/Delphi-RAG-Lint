# Driven GUI check for the IDE convert-request hand-off (C12, 2026-10-06).
# Usage: pwsh -NoProfile -File drive-convert-request.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoRequest]
#        A FROZEN drag-lint.exe must sit beside the exe (see drive-convert-tab.ps1): the fixture index is built
#        with THAT engine, never with dll-win64. Its Win64 library index must answer (TLabel/TStaticText).
# Fixture (fresh temp folder, _D-RAG layout): Fix.dpr / Fix.dproj / FixUnit.pas + FixUnit.dfm (Label1, Label2:
#   TLabel; Btn1: TButton) / Loose.pas + Loose.dfm (NOT in the .dpr) / rules\Fix.rules (#convert TLabel ->
#   TStaticText) / rules\Btn.rules (#convert TButton -> TcxButton) / _D-RAG\Fix.sqlite. Every request carries
#   rules_folder (controller ruling B1) except the E3 one.
# Run 1 (selected, Label1): the editor opens on the Convert tab, FixUnit listed, Fix.rules checked, Btn.rules
#   unchecked, status 'Request from the IDE: convert 1 selected component(s) on FixUnit: Label1 (TLabel) with 1
#   matching book(s) ...' (the Scope line is a TLabel -- no window -- so its text is asserted through the status
#   line built from the same ScopeText; the label itself is an owner visual check); Convert -> Label1 is
#   TStaticText on disk, Label2 still TLabel, the report has 'Scope<TAB>1 selected ...' and the --only note,
#   Btn.rules is not in the run; Delete resets the scope; File > Exit closes without a prompt.
# Run 2 (form, TLabel): Label2 converts too. E3: no rules folder -> refused, the editor stays usable. A
#   project_db that does not exist -> refused. An unindexed unit -> the status says Convert will refuse, in red.
#   Probe: --write-capabilities writes within 5 s, no window.
# -ProofNoRequest launches every request run WITHOUT --convert-request: the request checks FAIL (the proof they can).
#   Expected 6 pass / 19 fail; the PROOF lines name the 6 passes: 4 positive controls and 2 checks that CANNOT
#   discriminate (req.label2.untouched, req.exit) -- they hold with or without a request, so they prove nothing.
# The editor is killed (with its engine children) and the fixture deleted on exit.
param([string]$Exe, [switch]$ProofNoRequest)
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
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class RQ {
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] static extern IntPtr Send(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr got);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  /* A TCheckListBox row's check state. VCL keeps it in a TCheckListBoxDataWrapper whose
     address is the row's LB item data (Vcl.CheckLst; Win64 layout: VMT @0, FData @8,
     FState @16). No wrapper (0) = never checked. 0 unchecked, 1 checked, 2 grayed,
     -1 unreadable. Only the pointer crosses the process; the byte is read from the editor. */
  public static int CheckState(IntPtr lb, int i) {
    IntPtr w = Send(lb, 0x0199, (IntPtr)i, IntPtr.Zero);
    if (w == IntPtr.Zero) return 0;
    if ((long)w == -1) return -1;
    uint pid; GetWindowThreadProcessId(lb, out pid);
    IntPtr hp = OpenProcess(0x0010, false, pid);
    try { var b = new byte[1]; UIntPtr got; if (!ReadProcessMemory(hp, w + 16, b, (UIntPtr)1, out got)) return -1; return b[0]; }
    finally { CloseHandle(hp); }
  }
}
'@
$script:pass = 0; $script:fail = 0
$script:passed = @()
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; $script:passed += $name; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function TopsNow($procId) { (Forms $procId | ForEach-Object { $h = $_; $s = '{0}/{1}' -f [W]::Cls($h), [W]::Txt($h); if ([W]::Cls($h) -eq '#32770') { $s += ' [' + ((Find $h 'Static' $null | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ }) -join ' ') + ']' }; $s }) -join ' | ' }
function Find($parent, $cls, $text) { [W]::Kids($parent) | Where-Object { [W]::Cls($_) -eq $cls -and ($text -eq $null -or [W]::Txt($_) -eq $text) } }
# BM_CLICK is POSTED: a sent click blocks this script for as long as the handler runs.
function Click($h) { [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
# The status line. FLblStatus is a TLabel -- a TGraphicControl, no window, so no
# message reads it; SetStatus/SetError write the SAME text to the TStatusBar, and
# SetError prefixes it '[!] ' there. The Scope line is a TLabel too: its text is
# asserted through the status line, which is built from the same ScopeText.
function Status($main) { (@(Find $main 'TStatusBar' $null) | ForEach-Object { [W]::Txt($_) }) -join ' | ' }
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
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
# The editor's engine children. A parent PID is REUSED by Windows: a process whose
# ParentProcessId matches but that started BEFORE this editor is not its child.
function EngineKids($proc) { @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" | Where-Object { $_.CreationDate -ge $proc.StartTime }) }
# Settled = no TEngineWaitForm, no engine child, and the status line unchanged for
# 2 s (the request's own text is written after the analysis AddSources runs).
function WaitSettled($proc, $main, $Seconds) {
  $t0 = Get-Date; $last = $null; $since = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 400
    $busy = ([W]::Tops($proc.Id) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' }) -or ((EngineKids $proc).Count -gt 0)
    $st = Status $main
    if ($busy -or $st -ne $last) { $last = $st; $since = Get-Date; continue }
    if (((Get-Date) - $since).TotalSeconds -ge 2) { break }
  }
  Status $main
}
# Starts the editor and waits for its main window and a settled status line.
function Launch($argLine) {
  $script:p = Start-Process $Exe -ArgumentList $argLine -PassThru
  $script:main = [IntPtr]::Zero; $t0 = Get-Date
  while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) {
    Start-Sleep -Milliseconds 500
    $m = [W]::Tops($script:p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1
    if ($m) { $script:main = $m }
  }
  if ($script:main -ne [IntPtr]::Zero) { [void](WaitSettled $script:p $script:main 180) }
}
function StopEditor { if ($null -ne $script:p -and -not $script:p.HasExited) { $script:p.Kill($true); [void]$script:p.WaitForExit(15000) } }
function ActiveTabs($main) { @(Find $main 'TPageControl' $null | ForEach-Object { [CT]::ActiveTab($_) }) }
function RequestArgs($reqPath, $withDb) {
  $a = @()
  if (-not $ProofNoRequest) { $a += "--convert-request `"$reqPath`"" }
  $a += "--form `"$pas`""
  if ($withDb) { $a += "--project-db `"$db`"" }
  $a -join ' '
}
function WriteRequest($path, $scope, $comps, $unitPas, $unitDfm, $projDb, $projFile, $rules) {
  $r = [ordered]@{
    schema = 'convert-request/1'; written = (Get-Date -Format s); source = 'gui-driver'; ide_pid = $PID
    scope = $scope; project_file = $projFile; project_db = $projDb; platform = 'Win64'
  }
  if ($rules) { $r.rules_folder = $rules }
  $r.units = @(@{ pas = $unitPas; dfm = $unitDfm; form_class = 'TFixForm'; components = @($comps) })
  [IO.File]::WriteAllText($path, ($r | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
# The Convert tab's controls, by STRUCTURE (other tabs have their own Add... / Delete):
# Convert is the button beside the progress bar; the tab panel is its row's grandparent.
function TabControls($main) {
  $c = [ordered]@{ conv = $null; clear = $null; books = $null; src = $null; del = $null }
  $conv = @(Find $main 'TButton' 'Convert' | Where-Object { @(Find ([CT]::Parent($_)) 'TProgressBar' $null).Count -eq 1 })
  if ($conv.Count -ne 1) { return $c }
  $c.conv = $conv[0]
  $tab = [CT]::Parent([CT]::Parent([CT]::Parent($c.conv)))
  $c.clear = @(Find $tab 'TButton' 'Clear scope')[0]
  $checkAll = @(Find $tab 'TButton' 'Check all')[0]
  if ($checkAll) { $c.books = @(Find ([CT]::Parent([CT]::Parent($checkAll))) 'TCheckListBox' $null)[0] }
  $add = @(Find $tab 'TButton' 'Add...')[0]
  if ($add) { $c.del = @(Find ([CT]::Parent($add)) 'TButton' 'Delete')[0]; $c.src = @(Find ([CT]::Parent([CT]::Parent($add))) 'TListBox' $null)[0] }
  $c
}
function BookState($books, $like) {
  if ($null -eq $books) { return 'no list' }
  $items = [CT]::Items($books)
  for ($i = 0; $i -lt $items.Count; $i++) { if ($items[$i] -like $like) { return [RQ]::CheckState($books, $i) } }
  'not listed: ' + ($items -join ' | ')
}
function Newest($dir) { Get-ChildItem -LiteralPath $dir -Filter 'convert-run-*.txt' | Sort-Object LastWriteTime | Select-Object -Last 1 }

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- the fixture index must be built with the editor's own frozen engine" }

# --- fixture ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('convert-request-fx-' + [guid]::NewGuid().ToString('N'))
$rulesDir = Join-Path $tmp 'rules'; $dragDir = Join-Path $tmp '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $tmp 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $tmp 'FixUnit.pas'; $dfm = Join-Path $tmp 'FixUnit.dfm'
$loosePas = Join-Path $tmp 'Loose.pas'; $looseDfm = Join-Path $tmp 'Loose.dfm'
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
    Label2: TLabel;
    Btn1: TButton;
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
  ClientHeight = 100
  ClientWidth = 200
  object Label1: TLabel
    Left = 8
    Top = 8
    Caption = 'one'
  end
  object Label2: TLabel
    Left = 8
    Top = 32
    Caption = 'two'
  end
  object Btn1: TButton
    Left = 8
    Top = 56
    Caption = 'go'
  end
end
'@
WriteAscii (Join-Path $rulesDir 'Fix.rules') @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
WriteAscii (Join-Path $rulesDir 'Btn.rules') @'
#convert Vcl.StdCtrls.TButton -> cxButtons.TcxButton, cxButtons
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
# NOT in Fix.dpr, so NOT in the project index: a request for it must say Convert will refuse.
WriteAscii $loosePas @'
unit Loose;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes;

type
  TFixForm = class(TForm)
    Label9: TLabel;
  end;

implementation

{$R *.dfm}

end.
'@
WriteAscii $looseDfm @'
object FixForm: TFixForm
  Caption = 'Loose'
  object Label9: TLabel
    Caption = 'nine'
  end
end
'@
$reqSel = Join-Path $tmp 'req-selected.json'; $reqForm = Join-Path $tmp 'req-form.json'
$reqNoFolder = Join-Path $tmp 'req-nofolder.json'; $reqNoDb = Join-Path $tmp 'req-nodb.json'; $reqLoose = Join-Path $tmp 'req-loose.json'
WriteRequest $reqSel 'selected' @(@{ name = 'Label1'; type = 'TLabel' }) $pas $dfm $db $dproj $rulesDir
WriteRequest $reqForm 'form' @(@{ name = 'Label2'; type = 'TLabel' }) $pas $dfm $db $dproj $rulesDir
WriteRequest $reqNoFolder 'selected' @(@{ name = 'Label1'; type = 'TLabel' }) $pas $dfm $db $dproj $null
$noDb = Join-Path $dragDir 'Nope.sqlite'
WriteRequest $reqNoDb 'selected' @(@{ name = 'Label1'; type = 'TLabel' }) $pas $dfm $noDb (Join-Path $tmp 'Nope.dproj') $rulesDir
WriteRequest $reqLoose 'selected' @(@{ name = 'Label9'; type = 'TLabel' }) $loosePas $looseDfm $db $dproj $rulesDir

$p = $null; $main = [IntPtr]::Zero
try {
  if ($ProofNoRequest) { "NOTE  -ProofNoRequest: every launch below goes WITHOUT --convert-request; the request checks are expected to FAIL" }
  $t0 = Get-Date
  $out = & { $ErrorActionPreference = 'Continue'; & $engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
  Check 'req.fixture.index' (($code -eq 0) -and (Test-Path -LiteralPath $db)) ("exit=$code {0:N0}s $summary" -f ((Get-Date) - $t0).TotalSeconds)

  # ===== Run 1: scope 'selected', Label1 =====
  Launch (RequestArgs $reqSel $true)
  Check 'req.main' ($main -ne [IntPtr]::Zero)
  # A zero HWND would make EnumChildWindows(NULL) walk every OTHER process's windows.
  if ($main -eq [IntPtr]::Zero) { return }
  $st1 = Status $main
  $c = TabControls $main
  $active = ActiveTabs $main
  Check 'req.tab.convert.active' (($active -contains 'Convert') -and $null -ne $c.clear -and [W]::IsWindowVisible($c.clear)) ("active tabs: " + ($active -join ', '))
  # @() around the if: an if-expression unrolls a one-element array to its string.
  $items = @(if ($c.src) { [CT]::Items($c.src) })
  Check 'req.unit.listed' (($items.Count -eq 1) -and ($items[0] -like '*FixUnit.pas')) ($items -join ' | ')
  $fixState = BookState $c.books 'Fix.rules*'; $btnState = BookState $c.books 'Btn.rules*'
  Check 'req.book.fix.checked' ($fixState -eq 1) "state=$fixState"
  Check 'req.book.btn.unchecked' ($btnState -eq 0) "state=$btnState"
  Check 'req.scope.text' ($st1 -like '*convert 1 selected component(s) on FixUnit: Label1 (TLabel) with 1 matching book(s)*') $st1
  Check 'req.status.request' ($st1 -like 'Request from the IDE:*') $st1
  Check 'req.clear.enabled' ($null -ne $c.clear -and [RQ]::IsWindowEnabled($c.clear))

  $before = Status $main
  # No visible Convert (no request: the tab never opened) = nothing to wait for.
  $st = if ($c.conv -and [W]::IsWindowVisible($c.conv)) { Click $c.conv; WaitStatus $main $before 600 } else { $script:waited = 0; Status $main }
  "  run 1: {0:N0}s; status: {1}" -f $script:waited, $st
  Check 'req.convert' ($st -like 'Converted 1 of 1 unit x book pair(s)*') "$st$(if ($dlg) { "; editor dialog: $dlg" })"
  $dfmText = [IO.File]::ReadAllText($dfm)
  Check 'req.label1.converted' ($dfmText -match 'object Label1: TStaticText')
  Check 'req.label2.untouched' ($dfmText -match 'object Label2: TLabel')
  $rep = Newest $rulesDir
  $repText = if ($rep) { [IO.File]::ReadAllText($rep.FullName) } else { '' }
  $repLines = $repText -split "`r?`n"
  Check 'req.btn.rules.not.run' ($rep -and $repText -notmatch 'Btn\.rules') ("report: " + $(if ($rep) { $rep.Name } else { 'none' }))
  Check 'req.report.scope.line' (@($repLines | Where-Object { $_ -like "Scope`t1 selected component(s)*" }).Count -eq 1) (@($repLines | Where-Object { $_ -like 'Scope*' }) -join ' / ')
  # The scoped note states what --only ASKED (C12 Task 3 fix round 1), not a per-name outcome.
  Check 'req.report.note' ($repText -match '--only 1 instance\(s\): Label1') (@($repLines | Where-Object { $_ -like '*Fix.rules*' }) -join ' / ')

  # Review Focus 5 as it reaches the GUI: changing the source list (Delete) drops the scope
  # back to a whole-unit run, so the scope can never name a unit the list no longer holds.
  $c = TabControls $main
  $clearBefore = $null -ne $c.clear -and [RQ]::IsWindowEnabled($c.clear)
  if ($c.src -and $c.del) { [void][W]::Send($c.src, 0x0185, [IntPtr]1, [IntPtr]0); Click $c.del; Start-Sleep -Seconds 1 }
  $n = if ($c.src) { [int][W]::Send($c.src, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero) } else { -1 }
  Check 'req.delete.resets.scope' ($clearBefore -and ($n -eq 0) -and -not [RQ]::IsWindowEnabled($c.clear)) "clear enabled before=$clearBefore; sources=$n"
  # Fix wave Minor 4: a delete that cleared a scope says so on the status line.
  $stDel = Status $main
  Check 'req.delete.says.scope.cleared' ($stDel -like '*Scope cleared -- the whole unit will be converted.*') $stDel

  $null = [W]::InvokeMenu($main, 'File|Exit')
  $t0 = Get-Date; $prompt = ''
  while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 20) {
    Start-Sleep -Milliseconds 250
    if (@(Forms $p.Id | Where-Object { [W]::Cls($_) -in 'TMessageForm', '#32770' }).Count -gt 0) { $prompt = TopsNow $p.Id; break }
  }
  Check 'req.exit' ($p.HasExited -and $prompt -eq '') $prompt
  StopEditor

  # ===== Run 2: scope 'form', TLabel -- Label1 is already a TStaticText =====
  Launch (RequestArgs $reqForm $true)
  if ($main -ne [IntPtr]::Zero) {
    $st2 = Status $main
    $c = TabControls $main
    $before = $st2
    $st = if ($c.conv -and [W]::IsWindowVisible($c.conv)) { Click $c.conv; WaitStatus $main $before 600 } else { $script:waited = 0; Status $main }
    "  run 2: {0:N0}s; status: {1}" -f $script:waited, $st
  } else { $st2 = 'no main window' }
  Check 'req.form.run' (([IO.File]::ReadAllText($dfm)) -match 'object Label2: TStaticText') $st
  Check 'req.form.status' ($st2 -like 'Request from the IDE: convert all TLabel instances on FixUnit (1 found) with 1 matching book(s)*') $st2
  StopEditor

  # ===== E3: no rules_folder and no --rules-folder -- refused; the editor stays usable =====
  Launch (RequestArgs $reqNoFolder $true)
  if ($main -ne [IntPtr]::Zero) {
    $st3 = Status $main; $tabs3 = ActiveTabs $main
    Check 'req.nofolder.refused' (($st3 -like '`[!`] Convert request*refused: No book in <no rules folder*converts TLabel*') -and ($tabs3 -notcontains 'Convert')) ("$st3; tabs: " + ($tabs3 -join ', '))
    $inv = [W]::InvokeMenu($main, 'Conversion|Convert...'); Start-Sleep -Seconds 2
    Check 'req.nofolder.usable' ($inv -and ((ActiveTabs $main) -contains 'Convert') -and -not $p.HasExited) ("menu=$inv tabs: " + ((ActiveTabs $main) -join ', '))
  } else { Check 'req.nofolder.refused' $false 'no main window'; Check 'req.nofolder.usable' $false 'no main window' }
  StopEditor

  # ===== project_db that does not exist (adopted: no --project-db) -- refused =====
  Launch (RequestArgs $reqNoDb $false)
  $st4 = if ($main -ne [IntPtr]::Zero) { Status $main } else { 'no main window' }
  Check 'req.db.missing.refused' ($st4 -like "``[!``] Convert request*refused: the project index $noDb does not exist -- index the project first*") $st4
  StopEditor

  # ===== a unit not in the project index -- the E5 line says Convert will refuse, in red =====
  Launch (RequestArgs $reqLoose $true)
  $st5 = if ($main -ne [IntPtr]::Zero) { Status $main } else { 'no main window' }
  Check 'req.unindexed.tail' ($st5 -like "``[!``] Request from the IDE: convert 1 selected component(s) on Loose: Label9 (TLabel)*Also: $loosePas is not in the project index -- Convert will refuse.*") $st5
  StopEditor

  # ===== the capabilities probe: written within 5 s, no window =====
  $caps = Join-Path $tmp 'caps.json'
  $cp = Start-Process $Exe -ArgumentList "--write-capabilities `"$caps`"" -PassThru
  $t0 = Get-Date; $wins = 0
  while (-not $cp.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 5) { $wins = [Math]::Max($wins, [W]::Tops($cp.Id).Count); Start-Sleep -Milliseconds 100 }
  $exited = $cp.HasExited
  if (-not $exited) { $wins = [Math]::Max($wins, [W]::Tops($cp.Id).Count); $cp.Kill($true); [void]$cp.WaitForExit(5000) }
  $capsText = if (Test-Path -LiteralPath $caps) { [IO.File]::ReadAllText($caps) } else { '' }
  Check 'req.caps.probe' ($exited -and ($wins -eq 0) -and ($capsText -match '"convert_request":1')) "exited=$exited windows=$wins file=$capsText"
}
finally {
  StopEditor
  # The engine child may still hold the index for a moment after the kill.
  $gone = $false
  for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
    try { if ([IO.Directory]::Exists($tmp)) { [IO.Directory]::Delete($tmp, $true) }; $gone = $true } catch { Start-Sleep -Seconds 1 }
  }
  if ($gone) { "fixture removed: $tmp" } else { "WARN  fixture NOT removed: $tmp" }
  "gui-convert-request: $script:pass pass / $script:fail fail"
  if ($ProofNoRequest) {
    # Which passes the proof run EXPECTS, and why each cannot tell a request launch from none.
    $why = [ordered]@{
      'req.fixture.index'    = 'positive control: the fixture indexes before any launch'
      'req.main'             = 'positive control: the editor starts either way'
      'req.label2.untouched' = 'CANNOT DISCRIMINATE: Label2 stays a TLabel whether run 1 converted only Label1 or nothing ran'
      'req.exit'             = 'CANNOT DISCRIMINATE: File > Exit closes without a prompt with or without a request'
      'req.nofolder.usable'  = 'positive control: Conversion > Convert... works on a plain launch'
      'req.caps.probe'       = 'positive control: --write-capabilities does not use --convert-request'
    }
    foreach ($k in $why.Keys) { "PROOF  {0,-22} {1}  -- {2}" -f $k, $(if ($script:passed -contains $k) { 'passed' } else { 'FAILED' }), $why[$k] }
    $odd = @($script:passed | Where-Object { -not $why.Contains($_) })
    if ($odd.Count -gt 0) { "PROOF  UNEXPECTED pass without --convert-request: " + ($odd -join ', ') + " -- that check cannot fail" }
    else { "PROOF  the other {0} check(s) failed without --convert-request: each one can fail" -f $script:fail }
  }
  if ($script:fail -gt 0) { exit 1 }
}
