# Driven GUI check for the rule book's text encoding: detect on open, File > Encoding,
# the pre-save question, Save As keeps the level, UTF-16 saved with a BOM
# (conv-enc Task 2, lane S, 2026-10-25; spec docs\superpowers\specs\2026-10-25-converter-text-encoding-design.md 4.1 / 4.2 / D-B).
# Usage: pwsh -File drive-save-encoding.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it).
# Writes its fixture books under a fresh %TEMP%\saveenc-<id> folder and deletes it on exit.
# RED proof (Task 8): on the pinned pre-encoding exe save.nonascii.asks and save.yes.writes.utf8 FAIL (no question; the file holds 3F = ?).
param([string]$Exe)
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
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
trap { $script:fail++; "FAIL  driver.crash  $($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]"; "driver crashed: $script:pass pass / $script:fail fail"; exit 1 }
. "$PSScriptRoot\vcl-atoms.ps1"; 'NOTE  ' + (VclAtomsReclaim)   # ATOMLOCK: start from a reclaimed atom table (idempotent)
function Check($name, $cond, $detail = '') { if ($cond -and $env:DRIVE_FORCE_FAIL -ne $name) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function Forms($procId) { @([W]::Tops($procId) | Where-Object { [W]::Cls($_) -notin 'TApplication', 'THintWindow' }) }
function WaitFor($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitCls($procId, $cls, $sec) { $t0 = Get-Date; do { foreach ($h in [W]::Tops($procId)) { if ([W]::Cls($h) -eq $cls) { return $h } }; if (((Get-Date) - $t0).TotalSeconds -ge $sec) { break }; Start-Sleep -Milliseconds 250 } while ($true); return [IntPtr]::Zero }
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
function UseList($main) { [void][W]::ClickTab($main, 'Unit Rules'); Start-Sleep -Milliseconds 500; @(Find $main 'TListView' $null | Where-Object { [W]::Column($_, 0) -contains '#use' })[0] }
function RowWith($lv, $unit) { foreach ($c in 1, 2) { $i = [array]::IndexOf([W]::Column($lv, $c), $unit); if ($i -ge 0) { return $i } }; return -1 }
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
# The message box's text: every TLabel / Static child (a TMessageForm's message is a TLabel).
# The message box's text: every TLabel / Static child (a TMessageForm's message is a TLabel).
# A TLabel has no window of its own; when no child answers, the dialog's own Ctrl+C (VCL TMessageForm copies
# its caption, message and buttons) is read from the clipboard. Needs the editor on the desktop (GUI lock).
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class FG {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  /* SetForegroundWindow; only when that is refused, an ALT tap (the process that sent the last input may set the
     foreground) and again. The tap can eat the next key, so the caller retries its Ctrl+C. */
  public static void Front(IntPtr h) { if (SetForegroundWindow(h) && GetForegroundWindow() == h) return; keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); SetForegroundWindow(h); }
}
"@
function MsgText($dlg) {
  $t = ((@([W]::Kids($dlg)) | Where-Object { [W]::Cls($_) -in 'TLabel', 'Static' } | ForEach-Object { [W]::Txt($_) }) -join ' ')
  if ($t.Trim() -ne '') { return $t }
  # DRV-1: the FIRST Ctrl+C sent to a fresh question is lost (save.nonascii.asks read '' in 1 of 3 runs): retry
  # the copy, only while the dialog really is the foreground window (same fix as drive-convert-encoding.ps1).
  $c = 'convert-encoding-sentinel'
  for ($try = 0; ($try -lt 6) -and ($c -eq 'convert-encoding-sentinel') -and [W]::IsWindowVisible($dlg); $try++) {
    Set-Clipboard -Value 'convert-encoding-sentinel'
    [FG]::Front($dlg); Start-Sleep -Milliseconds 300
    if ([FG]::GetForegroundWindow() -ne $dlg) { Start-Sleep -Milliseconds 500; continue }
    [System.Windows.Forms.SendKeys]::SendWait('^c'); Start-Sleep -Milliseconds 300
    for ($i = 0; $i -lt 10; $i++) { try { $c = [string](Get-Clipboard -Raw -ErrorAction Stop); break } catch { Start-Sleep -Milliseconds 200 } }
  }
  if ($c -eq 'convert-encoding-sentinel') { return '' }
  # '---' / caption / '---' / message / '---' / buttons: the message is the block after the second rule.
  $parts = $c -split '(?m)^-+\s*$'
  if ($parts.Count -ge 3) { return $parts[2].Trim() -replace '\s*\r?\n\s*', ' ' }
  return ($c.Trim() -replace '\s*\r?\n\s*', ' ')
}
# Yes is captioned 'Yes' or '&Yes' depending on the VCL version.
function AnswerYes($procId) { $e = Answer $procId 'Yes'; if ($e -match "no 'Yes'") { $e = Answer $procId '&Yes' }; return $e }
function Bytes($path) { [IO.File]::ReadAllBytes($path) }
function Hex($b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }
function HasSeq($b, $x, $y) { for ($i = 0; $i -lt $b.Length - 1; $i++) { if ($b[$i] -eq $x -and $b[$i + 1] -eq $y) { return $true } }; return $false }
function AllAscii($b) { foreach ($x in $b) { if ($x -ge 0x80) { return $false } }; return $true }
function BytesEqual($a, $b) { if ($a.Length -ne $b.Length) { return $false }; for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }; return $true }
function OpenDialogTo($procId, $path) {
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no open dialog (forms: $(TopsNow $procId))" }
  Start-Sleep -Milliseconds 700
  $ed = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })[0]
  SetText $ed $path
  Click (@(Find $dlg 'Button' '&Open')[0])
  return ''
}
function WaitWrite($path, $before, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { if ((Test-Path $path) -and ((Get-Item $path).LastWriteTimeUtc -ne $before)) { Start-Sleep -Milliseconds 500; return $true }; Start-Sleep -Milliseconds 300 }; return $false }
function Stamp($path) { if (Test-Path $path) { (Get-Item $path).LastWriteTimeUtc } else { [DateTime]::MinValue } }

$tmp = Join-Path $env:TEMP ('saveenc-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$book = Join-Path $tmp 'Start.rules'
$fixture = "#convert Unit.TFrom -> Unit.TTo, Unit`r`n#link Text <- Text`r`n#default Caption = 'untitled'`r`n"
[IO.File]::WriteAllText($book, $fixture, [Text.Encoding]::ASCII)
$u16 = Join-Path $tmp 'U16.rules'
[IO.File]::WriteAllBytes($u16, [Text.Encoding]::Unicode.GetBytes($fixture)) # no preamble: GetBytes only
$value = 'Gr' + [char]0x00F6 + 'sse'

$p = Start-Process $Exe -ArgumentList "`"$book`"" -PassThru
try {
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $main = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($null -eq $main) { $main = [IntPtr]::Zero } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  Start-Sleep -Seconds 2
  $caps = [W]::MenuCaptions($main)
  Check 'encoding.menu' ($caps -match 'File\|Encoding') $caps
  $s = WaitStatus $main 'ASCII-7' 20; Check 'load.status.ascii7' ($s -ne '') (StatusText $main)

  # An untouched ASCII book saves silently, as ASCII.
  $before = Stamp $book
  [void][W]::InvokeMenu($main, 'File|Save')
  $asked = (WaitCls $p.Id 'TMessageForm' 3) -ne [IntPtr]::Zero
  $wrote = WaitWrite $book $before 30
  Check 'save.ascii.wrote' $wrote ('LastWriteTime unchanged: ' + (Stamp $book))
  $b = Bytes $book
  Check 'save.ascii.silent' ((-not $asked) -and (AllAscii $b) -and (BytesEqual $b ([Text.Encoding]::ASCII.GetBytes($fixture)))) ("asked=$asked len=$($b.Length) bytes=" + (Hex $b[0..15]))
  Start-Sleep -Seconds 1

  # Bring in a non-ASCII character. The Raw DSL memo has no apply path (it is a
  # one-way view of the model), so this goes in through Uses Units > Add unit...,
  # the picker drive-file-menu.ps1 drives: a #use whose name carries the value.
  Check 'nonascii.invoke' ([W]::InvokeMenu($main, 'Uses Units|Add unit...'))
  $e = PickTyped $p.Id 'Add unit (#use)' $value; Check 'nonascii.picker' ($e -eq '') $e
  Start-Sleep -Seconds 1
  Check 'nonascii.in.model' ((Raw $main).Contains($value)) (Raw $main)

  # Save -> the question; Cancel writes nothing.
  $bytesBefore = Bytes $book
  [void][W]::InvokeMenu($main, 'File|Save')
  $dlg = WaitCls $p.Id 'TMessageForm' 20
  $txt = if ($dlg -ne [IntPtr]::Zero) { MsgText $dlg } else { '' }
  Check 'save.nonascii.asks' (($txt -match 'cannot be saved as ASCII-7') -and ($txt -match 'U\+00F6')) ("text='$txt' forms: " + (TopsNow $p.Id))
  $e = Answer $p.Id 'Cancel'
  Start-Sleep -Seconds 1
  $same = [Linq.Enumerable]::SequenceEqual([byte[]]$bytesBefore, [byte[]](Bytes $book))
  $s = WaitStatus $main 'cancelled' 10
  Check 'save.cancel.keeps.bytes' (($e -eq '') -and $same -and ($s -ne '')) ("answer='$e' same=$same status=" + (StatusText $main))

  # Save -> Yes raises the book to UTF-8 (no BOM).
  $before = Stamp $book
  [void][W]::InvokeMenu($main, 'File|Save')
  $e = AnswerYes $p.Id
  $wrote = WaitWrite $book $before 30
  $b = Bytes $book
  $noBom = -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
  $s = WaitStatus $main 'as UTF-8' 30
  Check 'save.yes.writes.utf8' (($e -eq '') -and $wrote -and $noBom -and (HasSeq $b 0xC3 0xB6) -and ([IO.File]::ReadAllText($book, [Text.Encoding]::UTF8).Contains($value)) -and ($s -ne '')) ("answer='$e' wrote=$wrote noBom=$noBom status=" + (StatusText $main))
  Start-Sleep -Seconds 1

  # The book is UTF-8 now: a second Save asks nothing.
  $before = Stamp $book
  [void][W]::InvokeMenu($main, 'File|Save')
  $asked = (WaitCls $p.Id 'TMessageForm' 3) -ne [IntPtr]::Zero
  if ($asked) { [void](Answer $p.Id 'Cancel') }
  [void](WaitWrite $book $before 30)
  Check 'save.again.silent' (-not $asked) (TopsNow $p.Id)
  Start-Sleep -Seconds 1

  # Save As keeps the level: the chosen File > Encoding item is the Save As encoding.
  $out = Join-Path $tmp 'Saved.rules'
  [void][W]::InvokeMenu($main, 'File|Save As...')
  $e = SaveDialogTo $p.Id $out
  $t0 = Get-Date; while (-not (Test-Path $out) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Seconds 1
  $asked = (WaitCls $p.Id 'TMessageForm' 3) -ne [IntPtr]::Zero
  if ($asked) { [void](Answer $p.Id 'Cancel') }
  $b = if (Test-Path $out) { Bytes $out } else { [byte[]]@() }
  $i = [array]::IndexOf($b, [byte]0xC3)
  $q = ($i -gt 0) -and ($b[$i - 1] -eq 0x3F)
  Check 'saveas.keeps.level' (($e -eq '') -and (-not $asked) -and (HasSeq $b 0xC3 0xB6) -and (-not $q)) ("dialog='$e' asked=$asked bytes=$($b.Length)")
  Start-Sleep -Seconds 1

  # Reopen: detected as UTF-8.
  [void][W]::InvokeMenu($main, 'File|Open...')
  $e = OpenDialogTo $p.Id $out
  $s = WaitStatus $main 'Loaded Saved\.rules \(UTF-8\)' 30
  Check 'reopen.detects.utf8' (($e -eq '') -and ($s -ne '')) ("dialog='$e' status=" + (StatusText $main))
  Start-Sleep -Seconds 1

  # A BOM-less UTF-16 book: detected, and saved WITH a BOM (D-B), said once.
  [void][W]::InvokeMenu($main, 'File|Open...')
  $e = OpenDialogTo $p.Id $u16
  $s1 = WaitStatus $main 'Loaded U16\.rules \(UTF-16\)' 30
  $before = Stamp $u16
  [void][W]::InvokeMenu($main, 'File|Save')
  $asked = (WaitCls $p.Id 'TMessageForm' 3) -ne [IntPtr]::Zero
  if ($asked) { [void](Answer $p.Id 'Cancel') }
  [void](WaitWrite $u16 $before 30)
  $b = Bytes $u16
  $s2 = WaitStatus $main 'saved with a BOM' 30
  Check 'utf16.bom.added' (($e -eq '') -and ($s1 -ne '') -and (-not $asked) -and ($b.Length -ge 2) -and ($b[0] -eq 0xFF) -and ($b[1] -eq 0xFE) -and ($s2 -ne '')) ("open='$e' loaded='$s1' asked=$asked head=" + (Hex $b[0..3]) + ' status=' + (StatusText $main))
}
finally {
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  [void]$p.WaitForExit(15000)
  # Cleanup is not a check: a just-killed editor (or its engine child) can still hold the folder for a moment.
  try { Get-ChildItem $tmp -File | ForEach-Object { [IO.File]::Delete($_.FullName) }; [IO.Directory]::Delete($tmp) } catch { "INFO  cleanup: $($_.Exception.Message)" }
  "gui-save-encoding: $script:pass pass / $script:fail fail"
}
if ($script:fail -gt 0) { exit 1 }
