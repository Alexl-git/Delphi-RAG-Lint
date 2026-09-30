# Driven GUI check for the engine progress window (feat/engine-1206-adoption, Task 4,
# 2026-09-30): a slow property-tree load shows TEngineWaitForm, one Cancel closes it and
# stops the WHOLE block load (no second window for the To tree), and a fast load shows
# nothing at all.
# Usage: pwsh -File drive-engine-wait.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it).
# Writes its fixture books under a fresh %TEMP%\enginewait-<id> folder and deletes it on exit.
param([string]$Exe)
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
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
function WaitFor($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function TopsNow($procId) { (Forms $procId | ForEach-Object { $h = $_; $s = '{0}/{1}' -f [W]::Cls($h), [W]::Txt($h); if ([W]::Cls($h) -eq '#32770') { $s += ' [' + ((Find $h 'Static' $null | ForEach-Object { [W]::Txt($_) } | Where-Object { $_ }) -join ' ') + ']' }; $s }) -join ' | ' }
function Find($parent, $cls, $text) { [W]::Kids($parent) | Where-Object { [W]::Cls($_) -eq $cls -and ($text -eq $null -or [W]::Txt($_) -eq $text) } }
function SetText($h, $s) { [void][W]::SendS($h, 0x000C, [IntPtr]::Zero, $s) }
function Click($h) { [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
# ListTexts / DblClickRow: copied verbatim from drive-owning-open.ps1.
function ListTexts($lb) { $n = [int][W]::Send($lb, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero); @(for ($i = 0; $i -lt $n; $i++) { $sb = New-Object System.Text.StringBuilder 512; [void][W]::SendSB($lb, 0x0189, [IntPtr]$i, $sb); $sb.ToString() }) }
# A real double-click on row IDX of a list box: LB_GETITEMRECT for the row, then the
# mouse messages a user's double-click sends, at the row's right-hand text area
# (clear of the check box, which a click would toggle).
function DblClickRow($lb, $idx) {
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($lb, [ref]$r)
  $x = [int](($r.R - $r.L) - 40); $y = 9 + 18 * $idx   # ItemHeight = 18
  $lp = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
  [void][W]::PostMessage($lb, 0x0201, [IntPtr]1, $lp); [void][W]::PostMessage($lb, 0x0202, [IntPtr]::Zero, $lp)
  [void][W]::PostMessage($lb, 0x0203, [IntPtr]1, $lp); [void][W]::PostMessage($lb, 0x0202, [IntPtr]::Zero, $lp)
}

# Engine children started by the editor, counted by a background thread that
# polls every millisecond or so: a proptree on an unknown class lives ~60 ms, which
# a PowerShell polling loop missed in 1 of 3 runs. Only processes whose image is
# the drag-lint.exe beside the editor count, so other sessions' engines do not.
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Threading; using System.Diagnostics;
using System.Collections.Generic; using System.Runtime.InteropServices;
public static class ChildWatch {
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int f, StringBuilder s, ref int n);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  static volatile bool run; static Thread th; static HashSet<int> seen, hits;
  static string Image(int pid) {
    IntPtr h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return "";
    try { var s = new StringBuilder(1024); int n = 1024; return QueryFullProcessImageNameW(h, 0, s, ref n) ? s.ToString() : ""; } finally { CloseHandle(h); }
  }
  static int[] Ids() { var ps = Process.GetProcessesByName("drag-lint"); var r = new int[ps.Length]; for (int i = 0; i < ps.Length; i++) { r[i] = ps[i].Id; ps[i].Dispose(); } return r; }
  public static void Start(string exe) {
    seen = new HashSet<int>(Ids()); hits = new HashSet<int>(); run = true;
    th = new Thread(() => { while (run) { foreach (int id in Ids()) if (seen.Add(id) && string.Equals(Image(id), exe, StringComparison.OrdinalIgnoreCase)) hits.Add(id); Thread.Sleep(1); } });
    th.IsBackground = true; th.Start();
  }
  public static int Stop() { run = false; th.Join(); return hits.Count; }
}
"@
$tmp = Join-Path $env:TEMP ('enginewait-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$slow = Join-Path $tmp 'Slow.rules'
# TcxButton -> TcxButton: measured ~7 s per tree on the 1.20.3 pin (well over the 400 ms show delay).
[IO.File]::WriteAllText($slow, "#convert TcxButton -> TcxButton`r`n#link Caption <- Caption`r`n", [Text.Encoding]::ASCII)
$fast = Join-Path $tmp 'Fast.rules'
# A From-only rule whose class resolves nowhere: ONE proptree call, measured 58-93 ms
# in the editor on the 1.20.3 pin (5 of 5 runs, 2026-09-30). Written with a unit
# suffix because the plain From-only form (`#convert X -> `) does not survive a
# reload: TRuleBook's parser trims the line before looking for ' -> ', so the rule
# comes back with an EMPTY From type and no load ever runs. A two-class rule
# (X -> Y) makes TWO calls, and the second one measured 533-748 ms in 3 of 5 runs.
[IO.File]::WriteAllText($fast, "#convert TNoSuchClassXyz -> , NoSuchUnitXyz`r`n#link Caption <- Caption`r`n", [Text.Encoding]::ASCII)
# Opening a book selects no rule, so nothing loads on its own. A form holding the
# class puts it in the Classes list; a double-click on that row is the user's
# "open this class's rule", which loads the grid (FormTypeDblClick).
$dfm = Join-Path $tmp 'Fx.dfm'
[IO.File]::WriteAllText($dfm, "object Fx: TFx`r`n  object B1: TcxButton`r`n  end`r`n  object N1: TNoSuchClassXyz`r`n  end`r`nend`r`n", [Text.Encoding]::ASCII)

function StatusText($main) { (@(Find $main 'TStatusBar' $null) | ForEach-Object { [W]::Txt($_) }) -join ' | ' }

# Double-click the Classes row for CLS; '' when done, else why not.
function OpenClass($main, $cls) {
  [void][W]::ClickTab($main, 'Classes'); Start-Sleep -Milliseconds 500
  $lb = @(Find $main 'TCheckListBox' $null)[0]
  if ($null -eq $lb) { return 'no Classes list' }
  $rows = ListTexts $lb
  $row = -1; for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i] -match "\b$cls\b") { $row = $i; break } }
  if ($row -lt 0) { return "no $cls row (rows: $($rows -join ' | '))" }
  DblClickRow $lb $row
  return ''
}

# --- 1. slow load: the window appears, Cancel stops the WHOLE load ---
$p = Start-Process $Exe -ArgumentList "`"$slow`" --form `"$dfm`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  Check 'wait.main' ($main -ne [IntPtr]::Zero)
  Start-Sleep -Seconds 2
  $e = OpenClass $main 'TcxButton'
  $dlg = WaitCls $p.Id 'TEngineWaitForm' 20
  Check 'wait.window.appears' ($dlg -ne [IntPtr]::Zero) $e
  $btn = @(Find $dlg 'TButton' 'Cancel')[0]
  Check 'wait.cancel.button' ($btn -ne $null)
  $t0 = Get-Date
  if ($btn -ne $null) { Click $btn }
  $gone = $false
  while (((Get-Date) - $t0).TotalSeconds -lt 3) { if (-not (@([W]::Tops($p.Id)) -contains $dlg)) { $gone = $true; break }; Start-Sleep -Milliseconds 100 }
  Check 'wait.cancel.closes' (($dlg -ne [IntPtr]::Zero) -and $gone) ("{0:n1} s" -f ((Get-Date) - $t0).TotalSeconds)
  $again = WaitCls $p.Id 'TEngineWaitForm' 3
  Check 'wait.cancel.stops.to.tree' (($dlg -ne [IntPtr]::Zero) -and ($again -eq [IntPtr]::Zero)) 'a second progress window appeared after Cancel (or none appeared at all)'
  $st = StatusText $main
  Check 'wait.cancel.status' ($st -match 'load cancelled') $st
  # The retry the status names must really load: a cancelled block is left NOT
  # loaded, so the same double-click starts the engine (and the window) again.
  $e = OpenClass $main 'TcxButton'
  $dlg2 = WaitCls $p.Id 'TEngineWaitForm' 20
  Check 'wait.retry.after.cancel' ($dlg2 -ne [IntPtr]::Zero) $e
  $btn2 = @(Find $dlg2 'TButton' 'Cancel')[0]
  if ($btn2 -ne $null) { Click $btn2 }
  $t0 = Get-Date
  while ((((Get-Date) - $t0).TotalSeconds -lt 3) -and (@([W]::Tops($p.Id)) -contains $dlg2)) { Start-Sleep -Milliseconds 100 }
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

# --- 2. fast load: no window flashes ---
# Positive control: the ENGINE must actually run. The load's two engine children
# (the class-name query, then proptree) are counted by PID from the drag-lint.exe
# beside the editor; and the open path must finish (status 'Loaded TNoSuchClassXyz').
$engineExe = Join-Path (Split-Path $Exe) 'drag-lint.exe'
$p = Start-Process $Exe -ArgumentList "`"$fast`" --form `"$dfm`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  Start-Sleep -Seconds 2
  # The editor's own start-up engine calls (the class lists: three `query
  # descendants` runs, ~1 s each on the shared box, started AFTER the window shows)
  # must be finished first: overlapping them made the fast load take >400 ms and
  # counted a third child (measured 2026-09-30, Task 5 fix round 1).
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt 60 -and @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)").Count -gt 0) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 500
  [ChildWatch]::Start($engineExe)
  $e = OpenClass $main 'TNoSuchClassXyz'
  # No StatusText inside the loop: WM_GETTEXT blocks while the editor's UI thread
  # waits on the engine, which would stall the window poll for the whole call.
  $t0 = Get-Date; $seen = $false; $loaded = $false
  while (((Get-Date) - $t0).TotalSeconds -lt 5) {
    if ([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' }) { $seen = $true }
    Start-Sleep -Milliseconds 10
  }
  $kids = [ChildWatch]::Stop()
  $st = StatusText $main; if ($st -match 'Loaded TNoSuchClassXyz') { $loaded = $true }
  Check 'wait.fast.no.window' ($loaded -and ($kids -ge 2) -and -not $seen) ("load ran: $loaded; engine children: $kids; window seen: $seen; $e $st")
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
[IO.Directory]::Delete($tmp, $true)
"RESULT pass=$script:pass fail=$script:fail"
if ($script:fail -gt 0) { exit 1 }
