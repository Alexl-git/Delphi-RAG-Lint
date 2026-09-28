# Driven GUI check for the unit picker (feat/unit-picker, 2026-09-24).
# Usage: pwsh -File drive-unit-picker.ps1 -Exe <path\ConvRulesEditor.exe>  (put a frozen drag-lint.exe beside it).
param([string]$Exe)
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
  public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> Tops(uint pid) { var r = new List<IntPtr>(); EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr parent) { var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Txt(IntPtr h) { int n = (int)Send(h, 0x000E, IntPtr.Zero, IntPtr.Zero); var s = new StringBuilder(n + 2); SendSB(h, 0x000D, (IntPtr)(n + 1), s); return s.ToString(); }
  public static int Top(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.T; }
  public static int Left(IntPtr h) { RECT r; GetWindowRect(h, out r); return r.L; }
}
'@
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail = '') { if ($cond) { $script:pass++; "PASS  $name  $detail" } else { $script:fail++; "FAIL  $name  $detail" } }
function WaitFor($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { return $h } }; Start-Sleep -Milliseconds 250 }; return [IntPtr]::Zero }
function WaitGone($procId, $caption, $sec) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $sec) { $found = $false; foreach ($h in [W]::Tops($procId)) { if ([W]::Txt($h) -eq $caption) { $found = $true } }; if (-not $found) { return $true }; Start-Sleep -Milliseconds 250 }; return $false }
function Find($parent, $cls, $text) { [W]::Kids($parent) | Where-Object { [W]::Cls($_) -eq $cls -and ($text -eq $null -or [W]::Txt($_) -eq $text) } }
function Count($lb) { [int][W]::Send($lb, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero) }
function SetText($h, $s) { [void][W]::SendS($h, 0x000C, [IntPtr]::Zero, $s) }
function Key($h, $vk) { [void][W]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr]::Zero); [void][W]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr]::Zero) }
function Click($h) { [void][W]::PostMessage($h, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
$DEBOUNCE_WAIT = 900
$CAP = 'From Unit: the unit to convert'

$p = Start-Process $Exe -PassThru
try {
  $main = [IntPtr]::Zero; $t0 = Get-Date
  while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $main = [W]::Tops($p.Id) | Where-Object { [W]::Cls($_) -eq 'TConvRulesForm' } | Select-Object -First 1; if ($main -eq $null) { $main = [IntPtr]::Zero } }
  Check 'main.window' ($main -ne [IntPtr]::Zero)
  Start-Sleep -Seconds 2
  $btn = @(Find $main 'TButton' 'Pick...')
  Check 'main.has.pick.button' ($btn.Count -eq 1) "found=$($btn.Count)"
  if ($btn.Count -ne 1) { return }
  # FCbUnit: the combo just left of the Pick... button on the same row.
  $combo = Find $main 'TComboBox' $null | Where-Object { [Math]::Abs([W]::Top($_) - [W]::Top($btn[0])) -lt 6 -and [W]::Left($_) -lt [W]::Left($btn[0]) } | Sort-Object { [W]::Left($btn[0]) - [W]::Left($_) } | Select-Object -First 1
  Check 'main.from-unit.combo' ($combo -ne $null)

  # --- 1. open, lists loaded, filter by name, then by search, invalid mask ignored ---
  Click $btn[0]
  $pk = WaitFor $p.Id $CAP 90
  Check 'picker.opens' ($pk -ne [IntPtr]::Zero)
  $edits = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })
  $lists = @(Find $pk 'TListBox' $null | Sort-Object { [W]::Left($_) })
  Check 'picker.controls' ($edits.Count -eq 2 -and $lists.Count -eq 2) "edits=$($edits.Count) lists=$($lists.Count)"
  $name = $edits[0]; $search = $edits[1]; $proj = $lists[0]; $lib = $lists[1]
  $p0 = Count $proj; $l0 = Count $lib
  Check 'picker.project.loaded' ($p0 -gt 400) "project=$p0"
  Check 'picker.library.loaded' ($l0 -gt 5000) "library=$l0"

  SetText $name 'Grid'; Start-Sleep -Milliseconds $DEBOUNCE_WAIT
  $l1 = Count $lib; $p1 = Count $proj
  Check 'filter.name.narrows.library' ($l1 -ge 2 -and $l1 -lt $l0) "library=$l1"
  Check 'filter.name.narrows.project' ($p1 -lt $p0) "project=$p1 of $p0"

  SetText $search 'cx*'; Start-Sleep -Milliseconds $DEBOUNCE_WAIT
  $l2 = Count $lib
  Check 'filter.search.narrows.further' ($l2 -ge 1 -and $l2 -lt $l1) "library=$l2 (was $l1)"

  SetText $search '[cx'; Start-Sleep -Milliseconds $DEBOUNCE_WAIT
  $l3 = Count $lib
  Check 'filter.search.invalid.ignored' ($l3 -eq $l1) "library=$l3 (name-only=$l1)"

  # --- 2. Enter on a list item: that exact name lands in From Unit ---
  SetText $search ''; SetText $name 'System.SysUtils'; Start-Sleep -Milliseconds $DEBOUNCE_WAIT
  Check 'filter.exact.visible' ((Count $lib) -ge 1) "library=$(Count $lib)"
  [void][W]::Send($lib, 0x0186, [IntPtr]0, [IntPtr]::Zero)   # LB_SETCURSEL 0
  Key $lib 0x0D
  Check 'accept.list.enter.closes' (WaitGone $p.Id $CAP 10)
  Start-Sleep -Seconds 1
  Check 'accept.list.enter.result' ([W]::Txt($combo) -eq 'System.SysUtils') "combo='$([W]::Txt($combo))'"

  # --- 3. Esc cancels: From Unit unchanged; lists come from the cache ---
  $before = [W]::Txt($combo)
  Click $btn[0]
  $t = Get-Date; $pk = WaitFor $p.Id $CAP 30; $openSecs = ((Get-Date) - $t).TotalSeconds
  Check 'reopen.cached.fast' ($pk -ne [IntPtr]::Zero -and $openSecs -lt 3) ("{0:N1}s" -f $openSecs)
  $name = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })[0]
  Check 'reopen.prefilled' ([W]::Txt($name) -eq $before) "edit='$([W]::Txt($name))'"
  SetText $name 'SHOULD.NOT.LAND'
  Key $name 0x1B
  Check 'cancel.esc.closes' (WaitGone $p.Id $CAP 10)
  Start-Sleep -Milliseconds 500
  Check 'cancel.esc.unchanged' ([W]::Txt($combo) -eq $before) "combo='$([W]::Txt($combo))'"

  # --- 4. OK returns the typed text, even for a name no index knows ---
  Click $btn[0]
  $pk = WaitFor $p.Id $CAP 30
  $name = @(Find $pk 'TEdit' $null | Sort-Object { [W]::Top($_) })[0]
  SetText $name 'NotIndexed.Unit'; Start-Sleep -Milliseconds $DEBOUNCE_WAIT
  $okBtn = @(Find $pk 'TButton' 'OK')
  Click $okBtn[0]
  Check 'accept.ok.closes' (WaitGone $p.Id $CAP 10)
  Start-Sleep -Seconds 1
  Check 'accept.ok.typed.text' ([W]::Txt($combo) -eq 'NotIndexed.Unit') "combo='$([W]::Txt($combo))'"
}
finally {
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  "gui: $script:pass pass / $script:fail fail"
}
