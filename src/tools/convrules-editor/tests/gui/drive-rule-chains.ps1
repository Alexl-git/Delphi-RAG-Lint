# Driven GUI check for CHAIN-1 rule chains (plan docs\superpowers\plans\2026-10-27-converter-chain1.md,
# Task 4; spec 2026-10-27-converter-chain1-design.md 5.2-5.5): a Save of a book holding
# #convert TA -> TB and #convert TB -> TC marks it, names it in the status and offers the
# Rule chains dialog ONCE; Conversion > Rule chains... reopens it; Split writes
# Chain.stage2.rules and the Convert tab lists it after the base book; Merge composes the
# chain in the model (dirty, not saved); a Save from closing the editor never offers it.
# double.*: Rule chains... posted twice opens ONE dialog and the second is refused with a
# notice (an exe before conv/chainform raises "A component named ChainForm already exists").
# Usage: pwsh -NoProfile -File drive-rule-chains.ps1 -Exe <path\ConvRulesEditor.exe> [-ProofNoChain]
#   The exe beside a STAGED COPY of a pin (never dll-win64) whose Win64 library index answers
#   Bde.DBTables.TTable and FireDAC.Comp.Client.TFDTable / TFDMemTable / TFDQuery; run under
#   tests\gui\gui-lock.ps1. -ProofNoChain drops the second #convert: the negative control --
#   save1.status.chains, save1.dialog and save1.dialog.row must then FAIL, reported as proof.* PASS.
# Fixtures under a fresh %TEMP%\rulechains-<id> folder, deleted on exit.
param([string]$Exe, [switch]$ProofNoChain)
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
function TopBy($procId, $caption) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; return [IntPtr]::Zero }
function Caps($dlg) { @(Find $dlg 'TButton' $null | ForEach-Object { [W]::Txt($_) -replace '&', '' }) }
function ButtonOf($dlg, $cap) { @(Find $dlg 'TButton' $null | Where-Object { ([W]::Txt($_) -replace '&', '') -eq $cap })[0] }
function ChainRows($dlg) { $lv = @(Find $dlg 'TListView' $null)[0]; if ($null -eq $lv) { return @() }; @([W]::Column($lv, 0)) }
function ChainRowCount($dlg) { $lv = @(Find $dlg 'TListView' $null)[0]; if ($null -eq $lv) { return -1 }; [int][W]::Send($lv, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero) }
function WaitGone($procId, $h, $sec) { $t0 = Get-Date; while ((@([W]::Tops($procId)) -contains $h) -and ((Get-Date) - $t0).TotalSeconds -lt $sec) { Start-Sleep -Milliseconds 200 }; -not (@([W]::Tops($procId)) -contains $h) }
# The common Open dialog: the FILE NAME box is the Edit inside the ComboBoxEx32 whose control id
# is 0x47C (cmb13) -- the first Edit of the dialog can be another one (as drive-glyph-link.ps1).
function OpenDialogTo($procId, $path) {
  $dlg = WaitCls $procId '#32770' 20
  if ($dlg -eq [IntPtr]::Zero) { return "no open dialog (forms: $(TopsNow $procId))" }
  Start-Sleep -Milliseconds 700
  $edits = @([W]::Kids($dlg) | Where-Object { [W]::Cls($_) -eq 'Edit' })
  $ed = @($edits | Where-Object { [W]::GetDlgCtrlID([W]::Parent([W]::Parent($_))) -eq 0x47C })[0]
  if ($null -eq $ed) { $ed = $edits[0] }
  SetText $ed $path
  Click (@(Find $dlg 'Button' '&Open')[0])
  if (-not (WaitGone $procId $dlg 20)) { return "open dialog still up (edit text '$([W]::Txt($ed))')" }
  return ''
}
function ListTexts($lb) { $n = [int][W]::Send($lb, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero); @(for ($i = 0; $i -lt $n; $i++) { $sb = New-Object System.Text.StringBuilder 512; [void][W]::SendSB($lb, 0x0189, [IntPtr]$i, $sb); $sb.ToString() }) }
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
# Idle = no engine child created after the editor started, no progress window and the editor
# answering 'not busy', for 3 s running (as drive-glyph-link.ps1). A modal dialog of OURS
# (Rule chains, a message box) makes the editor busy-by-blocking, so callers wait for those
# windows by caption / class instead.
function WaitIdle($procId, $main, $sec) {
  $t0 = Get-Date; $quiet = $null
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$procId" | Where-Object { $_.CreationDate -ge $script:editorStart })
    $busy = ($kids.Count -gt 0) -or ([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' }) -or [B]::Busy($main)
    if ($busy) { $quiet = $null } elseif ($null -eq $quiet) { $quiet = Get-Date } elseif (((Get-Date) - $quiet).TotalSeconds -ge 3) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
# A File > Save that ends in a status line ('Saved ...') or the Rule chains dialog, whichever comes first.
function SaveAndWait($procId, $main, $sec) {
  [IO.File]::SetLastWriteTimeUtc($script:current, [DateTime]::UtcNow.AddHours(-2))
  $ok = [W]::InvokeMenu($main, 'File|Save')
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
    if ((TopBy $procId 'Rule chains') -ne [IntPtr]::Zero) { break }
    if (((StatusText $main) -match '^(\[!\] )?Saved ') -and -not ([W]::Tops($procId) | Where-Object { [W]::Cls($_) -eq 'TEngineWaitForm' })) { break }
    Start-Sleep -Milliseconds 300
  }
  return $ok
}

$SLOW_SEC = 900
$CHAIN_TEXT = "#depth 2`r`n#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable`r`n#link TableName <- TableName`r`n#convert FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable`r`n#link Name <- Name`r`n"
$PLAIN_TEXT = "#depth 2`r`n#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable`r`n#link TableName <- TableName`r`n"
$THREE_TEXT = $CHAIN_TEXT + "#convert FireDAC.Comp.Client.TFDMemTable -> FireDAC.Comp.Client.TFDQuery`r`n#link Name <- Name`r`n"
$STAGE2_TEXT = "#depth 2`r`n#convert FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable`r`n#link Name <- Name`r`n"

$engine = Join-Path (Split-Path -Parent $Exe) 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no drag-lint.exe beside $Exe -- run beside a STAGED COPY of a pin, never dll-win64" }
$tmp = Join-Path $env:TEMP ('rulechains-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$book  = Join-Path $tmp 'Chain.rules'
$merge = Join-Path $tmp 'Merge.rules'
$close = Join-Path $tmp 'Close.rules'
WriteAscii $book $(if ($ProofNoChain) { $PLAIN_TEXT } else { $CHAIN_TEXT })
WriteAscii $merge $CHAIN_TEXT
WriteAscii $close $THREE_TEXT
$script:current = $book

$script:editorStart = Get-Date
$p = Start-Process $Exe -ArgumentList "`"$book`"" -PassThru
try {
  $main = WaitCls $p.Id 'TConvRulesForm' 60
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  [void](WaitIdle $p.Id $main 120)

  # --- Save 1: marks, status, the offer ---
  Check 'save1.invoke' (SaveAndWait $p.Id $main $SLOW_SEC)
  $dlg = WaitFor $p.Id 'Rule chains' 60
  $s = StatusText $main
  if ($ProofNoChain) {
    # Negative control: the same checks against a book WITHOUT a chain must fail.
    Check 'proof.status.chains.absent' ($s -notmatch 'Rule chains: 1 chain -- see marked rules') $s
    Check 'proof.dialog.absent' ($dlg -eq [IntPtr]::Zero) (TopsNow $p.Id)
    Check 'proof.dialog.row.absent' (($dlg -eq [IntPtr]::Zero) -or ((ChainRowCount $dlg) -ne 1)) (TopsNow $p.Id)
    if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Keep') }
    return
  }
  Check 'save1.status.chains' ($s -match 'Rule chains: 1 chain -- see marked rules') $s
  Check 'save1.dialog' ($dlg -ne [IntPtr]::Zero) (TopsNow $p.Id)
  $rows = @(if ($dlg -ne [IntPtr]::Zero) { ChainRows $dlg })  # @(): one row must stay an array, not unroll to a string
  Check 'save1.dialog.row' (($rows.Count -eq 1) -and $rows[0].StartsWith('chain Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable')) ($rows -join ' | ')
  $caps = if ($dlg -ne [IntPtr]::Zero) { Caps $dlg } else { @() }
  $bm = if ($dlg -ne [IntPtr]::Zero) { ButtonOf $dlg 'Merge' } else { $null }
  $bs = if ($dlg -ne [IntPtr]::Zero) { ButtonOf $dlg 'Split' } else { $null }
  Check 'save1.dialog.buttons' (($caps -contains 'Merge') -and ($caps -contains 'Split') -and ($caps -contains 'Keep') -and ($null -ne $bm) -and [W]::IsWindowEnabled($bm) -and ($null -ne $bs) -and [W]::IsWindowEnabled($bs)) ($caps -join ',')
  if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Keep') }
  Check 'save1.keep' (($dlg -ne [IntPtr]::Zero) -and (WaitGone $p.Id $dlg 10)) (TopsNow $p.Id)

  # --- Save 2: asked once per session ---
  [void](SaveAndWait $p.Id $main $SLOW_SEC)
  $again = WaitFor $p.Id 'Rule chains' 10
  Check 'save2.no.dialog' (((StatusText $main) -match '^Saved ') -and ($again -eq [IntPtr]::Zero)) ((StatusText $main) + ' / ' + (TopsNow $p.Id))
  if ($again -ne [IntPtr]::Zero) { Click (ButtonOf $again 'Keep'); [void](WaitGone $p.Id $again 10) }

  # --- chainform: a forced double open. Two posted Rule chains... commands: the second is
  # dispatched by the first dialog's modal loop. Before the fix it ran re-entrantly and raised
  # "A component named ChainForm already exists."; now the input gate refuses it and says so. ---
  [void](WaitIdle $p.Id $main 60)
  [void][W]::InvokeMenu($main, 'Conversion|Rule chains...')
  [void][W]::InvokeMenu($main, 'Conversion|Rule chains...')
  $dlg = WaitFor $p.Id 'Rule chains' 20
  Start-Sleep -Milliseconds 1500
  $chainsUp = @([W]::Tops($p.Id) | Where-Object { [W]::Txt($_) -eq 'Rule chains' }).Count
  $errBox = @([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -in '#32770', 'TMessageForm' }).Count
  Check 'double.one.dialog' (($dlg -ne [IntPtr]::Zero) -and ($chainsUp -eq 1) -and ($errBox -eq 0)) ("dialogs=$chainsUp errorBoxes=$errBox; " + (TopsNow $p.Id))
  foreach ($h in @([W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -in '#32770', 'TMessageForm' })) { $ok = @(Find $h 'Button' $null) + @(Find $h 'TButton' $null); if ($ok.Count -gt 0) { Click $ok[0] } }
  if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Keep'); [void](WaitGone $p.Id $dlg 10) }
  $s = WaitStatus $main 'NOT run' 15
  Start-Sleep -Milliseconds 1000
  $again = TopBy $p.Id 'Rule chains'
  Check 'double.refused' (($s -match 'NOT run: it was clicked while the editor was busy \(Rule chains\)') -and ($again -eq [IntPtr]::Zero)) "$s / $(TopsNow $p.Id)"
  if ($again -ne [IntPtr]::Zero) { Click (ButtonOf $again 'Keep'); [void](WaitGone $p.Id $again 10) }

  # --- Conversion > Rule chains... reopens it, asked or not (O4) ---
  Check 'menu.invoke' ([W]::InvokeMenu($main, 'Conversion|Rule chains...'))
  $dlg = WaitFor $p.Id 'Rule chains' 20
  Check 'menu.reopens' (($dlg -ne [IntPtr]::Zero) -and ((ChainRowCount $dlg) -eq 1)) (TopsNow $p.Id)

  # --- Split ---
  $splitStart = Get-Date
  if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Split') }
  Check 'split.click' (($dlg -ne [IntPtr]::Zero) -and (WaitGone $p.Id $dlg 10)) (TopsNow $p.Id)
  $s = WaitStatus $main '^(Split|Nothing to split|Wrote)' $SLOW_SEC
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  $s = StatusText $main
  $stage = Join-Path $tmp 'Chain.stage2.rules'
  $stageText = if (Test-Path -LiteralPath $stage) { [IO.File]::ReadAllText($stage) } else { '<missing>' }
  Check 'split.stage.file' ($stageText -eq $STAGE2_TEXT) ($stageText -replace "`r`n", '\n')
  $src = [IO.File]::ReadAllText($book)
  $baks = @(Get-ChildItem -LiteralPath $tmp -Filter 'Chain.rules.bak*' | Where-Object { $_.LastWriteTime -ge $splitStart.AddSeconds(-2) -or $_.CreationTime -ge $splitStart.AddSeconds(-2) })
  Check 'split.source' (($src -notmatch 'TFDMemTable') -and ($baks.Count -ge 1)) ("bak since split: $($baks.Count); " + ($src -replace "`r`n", '\n'))
  Check 'split.status' ($s -match '^Split 1 block\(s\) into Chain\.stage2\.rules -- convert with Chain\.rules first, then Chain\.stage2\.rules') $s
  [void][W]::ClickTab($main, 'Convert'); Start-Sleep -Milliseconds 800
  $books = @()
  foreach ($lb in @(Find $main 'TCheckListBox' $null | Where-Object { [W]::IsWindowVisible($_) })) { $t = @(ListTexts $lb); if (($t | Where-Object { $_ -match '\.rules' }).Count -gt 0) { $books = $t; break } }
  $iBase = -1; $iStage = -1
  for ($i = 0; $i -lt $books.Count; $i++) { if ($books[$i] -match '(^|\\|\s)Chain\.rules\b') { $iBase = $i }; if ($books[$i] -match 'Chain\.stage2\.rules') { $iStage = $i } }
  Check 'split.convert.tab' (($iBase -ge 0) -and ($iStage -gt $iBase)) ($books -join ' | ')

  # --- Merge, in a second book opened through File > Open (asked set cleared, O5) ---
  [void](WaitIdle $p.Id $main 60)
  [void][W]::InvokeMenu($main, 'File|Open...')
  $o = OpenDialogTo $p.Id $merge
  $s = WaitStatus $main 'Merge\.rules' 60
  Check 'merge.open' (($o -eq '') -and ($s -ne '')) "$o / $(StatusText $main)"
  $script:current = $merge
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  [void](SaveAndWait $p.Id $main $SLOW_SEC)
  $dlg = WaitFor $p.Id 'Rule chains' 60
  Check 'merge.save.dialog' (($dlg -ne [IntPtr]::Zero) -and ((ChainRowCount $dlg) -eq 1)) (TopsNow $p.Id)
  if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Merge') }
  $gone = ($dlg -ne [IntPtr]::Zero) -and (WaitGone $p.Id $dlg 10)
  # Whole text: Txt reads the length then the text, so a read racing the status change returns it cut short.
  $s = WaitStatus $main '^(Merged.*then Save|Nothing merged)' $SLOW_SEC
  Check 'merge.click' ($gone -and ($s -match '^Merged 1 chain') -and ($s -match 'dropped 1 line\(s\) the later stage does not map: #link TableName <- TableName')) $s
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  $raw = Raw $main
  $okHead = $raw -match '#convert Bde\.DBTables\.TTable -> FireDAC\.Comp\.Client\.TFDMemTable\r?\n#note chain merge:[^\r\n]*1 dropped[^\r\n]*\r?\n#note chain merge: dropped #link TableName <- TableName because [^\r\n]*\r?\n#ignore TableName\r?\n' -and ($raw -notmatch '(?m)^#link TableName')
  $nConv = ([regex]::Matches($raw, '#convert Bde\.DBTables\.TTable')).Count
  $nName = ([regex]::Matches($raw, '#link Name <- Name')).Count
  $okTail = $raw -match '#convert FireDAC\.Comp\.Client\.TFDTable -> FireDAC\.Comp\.Client\.TFDMemTable\r?\n#link Name <- Name'
  Check 'merge.raw' ($okHead -and ($nConv -eq 1) -and ($nName -eq 1) -and $okTail) ("head=$okHead convert=$nConv nameLinks=$nName tail=$okTail; " + ($raw -replace "`r?`n", '\n'))
  # Dirty signal: the editor has no caption marker; File > New asks 'Save changes' only for a dirty book.
  [void][W]::InvokeMenu($main, 'File|New')
  $m = WaitMsg $p.Id 10
  Check 'merge.title.dirty' ($m -ne [IntPtr]::Zero) (TopsNow $p.Id)
  if ($m -ne [IntPtr]::Zero) { Click (ButtonOf $m 'Cancel'); [void](WaitGone $p.Id $m 10) }
  [void](SaveAndWait $p.Id $main $SLOW_SEC)
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  $again = WaitFor $p.Id 'Rule chains' 10
  $s = StatusText $main
  Check 'merge.save.no.dialog' (($s -match '^Saved Merge\.rules') -and ($s -notmatch 'Rule chains:') -and ($again -eq [IntPtr]::Zero)) "$s / $(TopsNow $p.Id)"
  if ($again -ne [IntPtr]::Zero) { Click (ButtonOf $again 'Keep'); [void](WaitGone $p.Id $again 10) }

  # --- Close with a dirty book that still has a chain: the Save from the guard never offers (O3) ---
  # Close.rules is a three-stage chain: merging it leaves TFDTable -> TFDMemTable -> TFDQuery, dirty.
  [void][W]::InvokeMenu($main, 'File|Open...')
  $o = OpenDialogTo $p.Id $close
  [void](WaitStatus $main 'Close\.rules' 60)
  $script:current = $close
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  [void][W]::InvokeMenu($main, 'Conversion|Rule chains...')
  $dlg = WaitFor $p.Id 'Rule chains' 20
  if ($dlg -ne [IntPtr]::Zero) { Click (ButtonOf $dlg 'Merge'); [void](WaitGone $p.Id $dlg 10) }
  $sMerged = WaitStatus $main '^(Merged|Nothing merged)' $SLOW_SEC
  [void](WaitIdle $p.Id $main $SLOW_SEC)
  [void][W]::InvokeMenu($main, 'File|Exit')
  $m = WaitMsg $p.Id 20
  $yes = ($m -ne [IntPtr]::Zero) -and ($null -ne (ButtonOf $m 'Yes'))
  if ($yes) { Click (ButtonOf $m 'Yes') }
  $sawChains = $false; $t0 = Get-Date
  while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt $SLOW_SEC) { if ((TopBy $p.Id 'Rule chains') -ne [IntPtr]::Zero) { $sawChains = $true; break }; Start-Sleep -Milliseconds 300 }
  $closeText = [IO.File]::ReadAllText($close)
  Check 'close.no.dialog' ($yes -and (-not $sawChains) -and $p.HasExited -and ($closeText -match '#convert Bde\.DBTables\.TTable -> FireDAC\.Comp\.Client\.TFDQuery')) ("open='$o' merged='$sMerged' yes=$yes sawChains=$sawChains exited=$($p.HasExited)")
} finally {
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  [IO.Directory]::Delete($tmp, $true)
  # Here, not after the try: the -ProofNoChain branch returns early.
  "RESULT pass=$script:pass fail=$script:fail"
  if ($script:fail -gt 0) { exit 1 }
}
