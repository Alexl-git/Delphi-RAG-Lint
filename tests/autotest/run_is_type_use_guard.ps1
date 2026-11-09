<#
  run_is_type_use_guard.ps1 -- 149 INT (GA E1, extractor): the right of `is` emits type_use refs
  when grammar v1.4.5 spells it as a TYPE node (typerefDot / typerefTpl).

  Fixture: tests\fixtures\grammar-shape-audit\GA_IsType.pas
    L59 / L98  `pObj is TList<Integer>`         -> type_use TList AND Integer (typerefTpl)
    L53        `pObj is System.Classes.TComponent` -> a type_use naming TComponent (typerefDot)
  Checks:
    T1  L59 has a type_use 'Integer'            -- FAILS on 1.48.0-alpha (0 type_use on the line)
    T2  L98 has a type_use 'Integer'            -- FAILS on 1.48.0-alpha
    T3  L53 `is System.Classes.TComponent` (typerefDot) emits NO type_use: the dotted form is
        deliberately out (cycle planner qualified-ref, run_cyclefix_r2 f8; 150 row) -- passes on both.
    T4  L59 has exactly ONE type_use 'TList'    -- no double emit from the default recursion
    P1  POSITIVE CONTROL: the bare `is TBase`-style identifier arm still emits (some type_use exists
        on an identifier `is` line of the same file) -- passes on both engines.
  Negative control for the guard itself: -Exe on a 1.48.0-alpha engine -> T1, T2, T4 FAIL.

  Usage: pwsh -File tests\autotest\run_is_type_use_guard.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $Repo 'tests\fixtures\grammar-shape-audit'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("istypeuse-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$db = Join-Path $tmp 'g.sqlite'
$script:Failed = $false

function IsTU-Check([string]$Id, [bool]$Ok, [string]$What) {
  if ($Ok) { Write-Host "PASS $Id $What" } else { Write-Host "FAIL $Id $What"; $script:Failed = $true }
}

function IsTU-Rows([int]$Line) {
  $q = "select r.name_text from refs r join files f on f.id = r.file_id where r.kind = 'type_use' and f.path like '%GA_IsType.pas' and r.start_line = $Line"
  $j = & $exePath sql --query $q --db $db --json 2>$null | Out-String
  $o = $j | ConvertFrom-Json
  $names = @()
  foreach ($row in @($o.rows)) { $names += [string]$row[0] }
  return ,$names
}

try {
  & $exePath index $fx --db $db 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "index exit $LASTEXITCODE" }

  $l59 = IsTU-Rows 59
  $l98 = IsTU-Rows 98
  $l53 = IsTU-Rows 53
  Write-Host ("L59: " + ($l59 -join ',') + " | L98: " + ($l98 -join ',') + " | L53: " + ($l53 -join ','))
  IsTU-Check 'T1' ($l59 -contains 'Integer') 'L59 is TList<Integer> emits Integer'
  IsTU-Check 'T2' ($l98 -contains 'Integer') 'L98 is TList<Integer> emits Integer'
  IsTU-Check 'T3' (@($l53 | Where-Object { $_ -match 'TComponent$' }).Count -eq 0) 'L53 is System.Classes.TComponent emits no type_use (dotted form out)'
  IsTU-Check 'T4' (@($l59 | Where-Object { $_ -eq 'TList' }).Count -eq 1) 'L59 emits TList exactly once'

  $q = "select count(*) from refs r join files f on f.id = r.file_id where r.kind = 'type_use' and f.path like '%GA_IsType.pas'"
  $o = (& $exePath sql --query $q --db $db --json 2>$null | Out-String) | ConvertFrom-Json
  IsTU-Check 'P1' ([int]$o.rows[0][0] -gt 0) 'GA_IsType.pas has type_use refs at all (positive control)'
}
finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Verbose "temp dir left: $tmp" }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
