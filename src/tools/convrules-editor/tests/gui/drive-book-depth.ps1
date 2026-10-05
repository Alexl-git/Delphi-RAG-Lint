# Driven GUI check for the book tree-depth control (#depth; feat/engine-1206-adoption,
# Task 5, 2026-09-30): the combo shows the book's #depth, is enabled only when the
# engine reports capability book_depth, a change is saved as ONE #depth line, and a
# book without #depth shows the default and does not gain the line on save.
# Usage: pwsh -File drive-book-depth.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it).
# Writes its fixture books under a fresh %TEMP%\bookdepth-<id> folder and deletes it on exit.
# The depth.change.* checks run only against an engine with book_depth (1.20.6+); on an
# older one they print SKIP.
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
$CB_GETCOUNT = 0x0146; $CB_GETCURSEL = 0x0147; $CB_GETLBTEXT = 0x0148; $CB_SETCURSEL = 0x014E
$WM_COMMAND = 0x0111; $CBN_SELCHANGE = 1
function ComboItem($h, $i) { $sb = New-Object Text.StringBuilder 64; [void][W]::SendSB($h, $CB_GETLBTEXT, [IntPtr]$i, $sb); $sb.ToString() }
function DepthCombo($main) {
  foreach ($h in (Find $main 'TComboBox' $null)) {
    if ([int][W]::Send($h, $CB_GETCOUNT, [IntPtr]::Zero, [IntPtr]::Zero) -eq 10 -and (ComboItem $h 0) -eq '1' -and (ComboItem $h 9) -eq '10') { return $h }
  }
  return [IntPtr]::Zero
}
function Sel($h) { [int][W]::Send($h, $CB_GETCURSEL, [IntPtr]::Zero, [IntPtr]::Zero) }
function Choose($h, $i) {
  [void][W]::Send($h, $CB_SETCURSEL, [IntPtr]$i, [IntPtr]::Zero)
  # WM_COMMAND wParam = MAKEWPARAM(LOWORD(id), CBN_SELCHANGE). VCL does not assign
  # control IDs, so GetDlgCtrlID returns a full 32-bit value; unmasked, its high bits
  # overwrite the notification code and VCL never sees CBN_SELCHANGE.
  $wp = [IntPtr](([int]$CBN_SELCHANGE -shl 16) -bor ([W]::GetDlgCtrlID($h) -band 0xFFFF))
  [void][W]::Send([W]::Parent($h), $WM_COMMAND, $wp, $h)
}

$engine = Join-Path (Split-Path $Exe) 'drag-lint.exe'
$caps = & $engine info --json 2>$null | Out-String
$hasDepth = $caps -match '"book_depth"\s*:\s*true'
"engine book_depth = $hasDepth"

$tmp = Join-Path $env:TEMP ('bookdepth-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$d3 = Join-Path $tmp 'Depth3.rules';  [IO.File]::WriteAllText($d3, "#depth 3`r`n#unuse OldUnitZ`r`n", [Text.Encoding]::ASCII)
$nd = Join-Path $tmp 'NoDepth.rules'; [IO.File]::WriteAllText($nd, "#unuse OldUnitZ`r`n", [Text.Encoding]::ASCII)

# --- 0. start-up WITHOUT a book never runs LoadText: the combo is still gated ---
$p = Start-Process $Exe -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  Start-Sleep -Seconds 1
  $cb = DepthCombo $main
  Check 'depth.nobook.enabled.matches.capability' (($cb -ne [IntPtr]::Zero) -and ([W]::IsWindowEnabled($cb) -eq $hasDepth) -and ((Sel $cb) -eq 4)) ("enabled=" + [W]::IsWindowEnabled($cb) + " sel=" + (Sel $cb))
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
# --- 1. a book's #depth shows; the control is gated on the capability ---
$p = Start-Process $Exe -ArgumentList "`"$d3`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  $cb = DepthCombo $main
  Check 'depth.combo.found' ($cb -ne [IntPtr]::Zero)
  Check 'depth.load.shows.book.value' ((Sel $cb) -eq 2) ("sel=" + (Sel $cb))
  # The combo must exist: IsWindowEnabled(0) is False, which would pass on an engine without book_depth.
  Check 'depth.enabled.matches.capability' (($cb -ne [IntPtr]::Zero) -and ([W]::IsWindowEnabled($cb) -eq $hasDepth)) ("enabled=" + [W]::IsWindowEnabled($cb))
  if ($hasDepth) {
    Choose $cb 6
    # A CBN_SELCHANGE on the CLOSED combo is the wheel / arrow-key path: it only
    # starts the editor's debounce timer (DEPTH_COMMIT_DELAY_MS = 600), which then
    # commits once. Wait past it before saving.
    Start-Sleep -Milliseconds 1500
    Check 'depth.change.invoke.save' ([W]::InvokeMenu($main, 'File|Save'))
    Start-Sleep -Milliseconds 800
    $txt = [IO.File]::ReadAllText($d3)
    Check 'depth.change.saved' (($txt -match '(?m)^#depth 7\r$') -and ($txt -notmatch '#depth 3')) $txt
    Check 'depth.change.one.line' (([regex]::Matches($txt, '#depth')).Count -eq 1) $txt
  } else {
    'SKIP  depth.change.*  (engine lacks book_depth -- REQUIRED after the 1.20.6 re-pin)'
  }
  [void][W]::InvokeMenu($main, 'File|Exit')
  Start-Sleep -Milliseconds 500
  # The unsaved-changes prompt is Yes / No / Cancel; No = discard. The book is clean
  # here (saved above, or never changed), so normally no prompt appears at all.
  Answer $p.Id '&No' | Out-Null
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

# --- 2. a book WITHOUT #depth shows the default and does not gain one on save ---
$before = [IO.File]::ReadAllText($nd)
# Back-date the file so the save below is VISIBLE: without a write, "not added"
# would also pass for a Save that never ran.
$stamp = [DateTime]::UtcNow.AddHours(-2)
[IO.File]::SetLastWriteTimeUtc($nd, $stamp)
$p = Start-Process $Exe -ArgumentList "`"$nd`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  $cb = DepthCombo $main
  Check 'depth.absent.shows.default' ((Sel $cb) -eq 4) ("sel=" + (Sel $cb))
  $invoked = [W]::InvokeMenu($main, 'File|Save')
  $t0 = Get-Date; while ([IO.File]::GetLastWriteTimeUtc($nd) -eq $stamp -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }
  $wrote = [IO.File]::GetLastWriteTimeUtc($nd) -ne $stamp
  Check 'depth.absent.saved' ($invoked -and $wrote) ("invoked=$invoked wrote=$wrote")
  $after = [IO.File]::ReadAllText($nd)
  Check 'depth.absent.not.added' ($wrote -and ($after -notmatch '#depth') -and ($after -eq $before)) $after
  # Loading and saving must leave the book CLEAN: Exit closes with no prompt.
  [void][W]::InvokeMenu($main, 'File|Exit')
  $prompt = WaitCls $p.Id 'TMessageForm' 3
  Check 'depth.absent.exit.no.prompt' (($prompt -eq [IntPtr]::Zero) -and $p.WaitForExit(10000)) ("prompt=" + ($prompt -ne [IntPtr]::Zero))
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

# --- 3. New Conversion -> "start a NEW file" clears the book WITHOUT LoadText: the
#        combo must follow the new, empty book (default), not keep the old book's 3.
#        TBevel / TShape: small VCL classes that resolve; each proptree still costs
#        ~30 s on the shared build box (measured 2026-09-30), hence the long waits.
$SLOW_SEC = 600
function WaitMsg($procId, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq 'TMessageForm') { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function ClickIn($dlg, $cap) { $b = @(Find $dlg 'TButton' $cap); if ($b.Count -gt 0) { Click $b[0]; return $true }; return $false }
[IO.File]::WriteAllText($d3, "#depth 3`r`n#unuse OldUnitZ`r`n", [Text.Encoding]::ASCII)
$p = Start-Process $Exe -ArgumentList "`"$d3`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 30
  Start-Sleep -Seconds 2
  $cb = DepthCombo $main
  $pick = @(Find $main 'TButton' 'Pick...')[0]
  $row2 = @(Find $main 'TComboBox' $null | Where-Object { [W]::Top($_) -gt [W]::Top($pick) + 20 -and [W]::Top($_) -lt [W]::Top($pick) + 45 } | Sort-Object { [W]::Left($_) })
  SetText $row2[0] 'Vcl.ExtCtrls.TBevel'
  SetText $row2[1] 'Vcl.ExtCtrls.TShape'
  [void][W]::InvokeMenu($main, 'Conversion|New Conversion')
  # "Where should the rule go?" -- No = start a NEW file.
  $m1 = WaitMsg $p.Id $SLOW_SEC
  $where = ($m1 -ne [IntPtr]::Zero) -and (ClickIn $m1 '&No')
  # The click is POSTED: wait for this box to close, or the next wait finds it again.
  $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt 10 -and (@([W]::Tops($p.Id)) -contains $m1)) { Start-Sleep -Milliseconds 100 }
  # "Start <file>?" (the open book is not empty) -- No = discard it.
  $m2 = WaitMsg $p.Id 30
  $start = ($m2 -ne [IntPtr]::Zero) -and (ClickIn $m2 '&No')
  Check 'depth.newfile.prompts' ($where -and $start) ("where=$where start=$start")
  # The rest of New Conversion (proptree + grid load) runs on; the combo is set
  # right after the clear, so wait for the engine to finish before reading it.
  $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $SLOW_SEC -and ([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' })) { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Seconds 1
  Check 'depth.newfile.shows.default' ((Sel $cb) -eq 4) ("sel=" + (Sel $cb))
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
[IO.Directory]::Delete($tmp, $true)
"RESULT pass=$script:pass fail=$script:fail"
if ($script:fail -gt 0) { exit 1 }
