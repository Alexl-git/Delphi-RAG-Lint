# Driven GUI check for scoped validation on Save (fix/validate-edited-blocks, 2026-10-05):
# the progress window and its Cancel, the owed block revalidated on the next Save.
# A Save validates the syntax of the whole book plus each CHANGED #convert block with
# its OWN From/To pair, and the status line reports the warnings the engine prints
# (an unreachable member never changes convert-validate's exit code, so the old Save,
# which read only a failing exit's first line, never showed one).
# Usage: pwsh -File drive-validate-scope.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it,
# 1.20.6 or later, whose Win64 library index answers Bde.DBTables.TTable and FireDAC.Comp.Client.TFDTable).
# Writes its fixture book under a fresh %TEMP%\validatescope-<id> folder and deletes it on exit.
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

$SLOW_SEC = 900
$tmp = Join-Path $env:TEMP ('validatescope-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
# Depth 2 keeps both trees small and still reaches FieldOptions.AutoCreateMode, a
# member that is PROTECTED in Data.DB.TDataSet: a #link to it is an engine
# "unreachable" WARNING (exit code unchanged), which the old Save never showed.
$book = Join-Path $tmp 'Fix.rules'
[IO.File]::WriteAllText($book, "#depth 2`r`n", [Text.Encoding]::ASCII)

$p = Start-Process $Exe -ArgumentList "`"$book`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 60
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  Start-Sleep -Seconds 2
  # No rule is loaded yet: Auto-Match has nothing to match (job C6).
  Check 'automatch.disabled.no.rule' (-not [W]::MenuEnabled($main, 'Mapping|Auto-Match'))
  # New Conversion TTable -> TFDTable into the open book: a NEW block, so the save
  # below has exactly one changed block. New Conversion auto-matches the links.
  $pick = @(Find $main 'TButton' 'Pick...')[0]
  $row2 = @(Find $main 'TComboBox' $null | Where-Object { [W]::Top($_) -gt [W]::Top($pick) + 20 -and [W]::Top($_) -lt [W]::Top($pick) + 45 } | Sort-Object { [W]::Left($_) })
  SetText $row2[0] 'Bde.DBTables.TTable'
  SetText $row2[1] 'FireDAC.Comp.Client.TFDTable'
  Check 'newconv.invoke' ([W]::InvokeMenu($main, 'Conversion|New Conversion'))
  # "Where should the rule go?" -- Yes = append to the open book.
  $m1 = WaitMsg $p.Id $SLOW_SEC
  Check 'newconv.where.yes' (($m1 -ne [IntPtr]::Zero) -and (ClickIn $m1 '&Yes')) (TopsNow $p.Id)
  $s = WaitStatus $main 'set and auto-matched|cancelled|not indexed' $SLOW_SEC
  Check 'newconv.done' ($s -match 'set and auto-matched') $s
  Check 'automatch.enabled.with.rule' ([W]::MenuEnabled($main, 'Mapping|Auto-Match'))

  # Save 1, CANCELLED: the pair pass of the one changed block is slow (10-40 s), so
  # the progress window appears; Cancel stops it. The book is on disk regardless.
  [IO.File]::SetLastWriteTimeUtc($book, [DateTime]::UtcNow.AddHours(-2))
  Check 'save1.invoke' ([W]::InvokeMenu($main, 'File|Save'))
  $dlg = WaitCls $p.Id 'TEngineWaitForm' 60
  Check 'save1.window.appears' ($dlg -ne [IntPtr]::Zero) (TopsNow $p.Id)
  Start-Sleep -Seconds 3 # past the ~0.6 s syntax pass, into the block's pair pass
  if ($dlg -ne [IntPtr]::Zero) { $btn = @(Find $dlg 'TButton' 'Cancel'); if ($btn.Count -gt 0) { Click $btn[0] } }
  $t0 = Get-Date; while ((@([W]::Tops($p.Id)) -contains $dlg) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 200 }
  Check 'save1.cancel.closes' (-not (@([W]::Tops($p.Id)) -contains $dlg)) (TopsNow $p.Id)
  $s = WaitStatus $main 'Validate: cancelled' 60
  Check 'save1.status.cancelled' ($s -match '^Saved Fix\.rules .*Validate: cancelled -- 1 changed block\(s\) not checked: Bde\.DBTables\.TTable') $s
  $txt = [IO.File]::ReadAllText($book)
  # Positive control: without an unreachable link the warning check proves nothing.
  Check 'save1.wrote.unreachable.link' ($txt -match '(?m)^#link FieldOptions\.') ("FieldOptions links: " + ([regex]::Matches($txt, '(?m)^#link FieldOptions\.')).Count)

  # Save 2: the block is unchanged against the new snapshot but still OWED, so it
  # is validated now, with its own pair.
  $t0 = Get-Date
  Check 'save2.invoke' ([W]::InvokeMenu($main, 'File|Save'))
  $s = WaitStatus $main 'Validate: OK, \d+ warning' 300
  $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
  Check 'save2.status.saved' ($s -match '^Saved Fix\.rules') $s
  $m = [regex]::Match($s, 'Validate: OK, (\d+) warning\(s\) -- see marked rules')
  Check 'save2.revalidates.cancelled.block' ($m.Success -and [int]$m.Groups[1].Value -ge 1) "$s  [$secs s]"

  # Save 3, nothing changed or owed: syntax pass only -- fast, and no new diagnostics
  # (the marks from save 2 stay).
  $t0 = Get-Date
  Check 'resave.invoke' ([W]::InvokeMenu($main, 'File|Save'))
  $s2 = WaitStatus $main 'Validate: OK$' 120
  $secs2 = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
  Check 'resave.unchanged.ok' ($s2 -match 'Validate: OK$') "$s2  [$secs2 s]"
  Check 'resave.unchanged.fast' ($secs2 -lt $secs) "owed $secs s, unchanged $secs2 s"

  # A cancelled validation never made the book dirty: Exit asks nothing.
  [void][W]::InvokeMenu($main, 'File|Exit')
  $prompt = WaitCls $p.Id 'TMessageForm' 3
  Check 'exit.no.prompt' (($prompt -eq [IntPtr]::Zero) -and $p.WaitForExit(10000)) (TopsNow $p.Id)} finally {
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  [IO.Directory]::Delete($tmp, $true)
}
"RESULT pass=$script:pass fail=$script:fail"
if ($script:fail -gt 0) { exit 1 }
