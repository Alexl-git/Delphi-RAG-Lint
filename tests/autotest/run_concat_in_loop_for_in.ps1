<#
  run_concat_in_loop_for_in.ps1 -- `concat-in-loop` must fire inside a
  `for X in Y do` loop, exactly as it does inside `for I := A to B do`.

  THE BUG (D20, 2026-09-24)
  -------------------------
  The loop requirement lives in the rule's sidecar json
  (rules\concat-in-loop.json, "require_ancestor"), matched by EXACT tree-sitter
  node kind. The list was ["for", "while", "repeat"]; the grammar's node for a
  for-in loop is `foreach`, so `for X in Arr do S := S + X;` -- the most common
  accumulate-a-string shape in modern Delphi -- was never reported. The L6
  reset predicate (DRagLint.Lint.QueryRules, LOOP_KINDS) already listed
  `foreach`; only the sidecar did not.

  Cases
  -----
    1. for X in Arr do S := S + X;            MUST fire   (red before the fix)
    2. for I := 0 to N do S := S + X;         MUST fire   (positive control)
    3. S := S + X; outside any loop           MUST NOT fire (control)
    4. for X in Arr do begin T := 'row '; T := T + X; end;
                                              MUST NOT fire (L6 reset inside a
                                              foreach -- proves the reset
                                              predicate and the new ancestor
                                              kind agree)
  Asserted on `lint --json` `start_line` (the output is a bare array).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-concat-for-in-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
try {
  $fixture = Join-Path $WorkDir 'ConcatForIn.pas'
  $body = @"
unit ConcatForIn;

interface

procedure P(const Arr: TArray<string>; N: Integer);

implementation

procedure P(const Arr: TArray<string>; N: Integer);
var
  S, S2, S3, T, X: string;
  I: Integer;
begin
  S := ''; S2 := ''; S3 := ''; T := ''; X := 'x';
  for X in Arr do S := S + X;
  for I := 0 to N do S2 := S2 + X;
  S3 := S3 + X;
  for X in Arr do
  begin
    T := 'row ';
    T := T + X;
    Writeln(T);
  end;
  Writeln(S, S2, S3);
end;

end.
"@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

  # Resolve the statement lines from the fixture, so edits cannot decouple them.
  $lines = [System.IO.File]::ReadAllLines($fixture)
  function LineOf([string]$Needle) {
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
    return -1
  }
  $lnForIn   = LineOf 'for X in Arr do S := S + X;'
  $lnForTo   = LineOf 'for I := 0 to N do S2 := S2 + X;'
  $lnNoLoop  = LineOf 'S3 := S3 + X;'
  $lnReset   = LineOf 'T := T + X;'
  Check 'all four fixture statements located' (@($lnForIn, $lnForTo, $lnNoLoop, $lnReset) -notcontains -1)

  # `lint --rule` cannot be used: its validator rejects external .scm ids.
  $raw = (& $Exe lint $fixture --json 2>$null) -join "`n"
  $all = @($raw | ConvertFrom-Json)
  $fired = @($all | Where-Object { $_.rule -eq 'concat-in-loop' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object -Unique)
  Check 'lint --json returned findings with a start_line (shape check)' (
    $all.Count -gt 0 -and $null -ne $all[0].start_line) "($($all.Count) findings total)"
  Write-Host ("  concat-in-loop fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

  Write-Host ''
  Write-Host 'Concatenation inside a loop MUST fire' -ForegroundColor Cyan
  Check "for X in Arr do S := S + X  (line $lnForIn) -- foreach" ($fired -contains $lnForIn)
  Check "for I := 0 to N do S2 := S2 + X  (line $lnForTo) -- positive control" ($fired -contains $lnForTo)

  Write-Host ''
  Write-Host 'MUST NOT fire' -ForegroundColor Cyan
  Check "S3 := S3 + X outside any loop (line $lnNoLoop)" (-not ($fired -contains $lnNoLoop))
  Check "T := 'row '; T := T + X in a foreach (line $lnReset) -- L6 reset" (-not ($fired -contains $lnReset))
}
finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
