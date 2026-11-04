<#
  run_stage_engine_scope_guard.ps1 -- STAGE-UNKARG.
  build\stage-engine.ps1 splats $StandDownScope into the engine's stand-down verb. An unwrapped
  one-element `if` result is a scalar string, and splatting a string passes it character by
  character: the engine saw "-" ("Unknown argument: -"). This guard evaluates the real
  assignment line with the default ('--all') scope and checks it splats as ONE argument; the
  positive control evaluates the retired form and must fail the same check.
#>
$ErrorActionPreference = 'Stop'
$fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { Write-Host "PASS $n" } else { Write-Host "FAIL $n $d"; $script:fail++ } }
function Get-SplatArgs([string]$line) {
  $StandDownDb = ''
  Invoke-Expression $line
  $got = & { $args } @StandDownScope
  return ,@($got)
}
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\build\stage-engine.ps1')
$line = @($src | Where-Object { $_ -match '^\$StandDownScope\s*=' })
Check 'one assignment line' ($line.Count -eq 1) "found $($line.Count)"
$a = Get-SplatArgs $line[0]
Check 'default scope splats as one argument --all' (($a.Count -eq 1) -and ($a[0] -eq '--all')) ($a -join '|')
$old = '$StandDownScope = if ($StandDownDb) { @(''--db'', $StandDownDb) } else { @(''--all'') }'
$b = Get-SplatArgs $old
Check 'POSITIVE CONTROL: retired form splats char by char' ($b.Count -gt 1) ($b -join '|')
if ($fail) { exit 1 }
