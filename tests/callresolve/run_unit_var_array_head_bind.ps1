<#
  run_unit_var_array_head_bind.ps1 -- item 4 (f), spec
  2026-10-28-untypable-receivers s.3 (f) / s.8 bullet 3. A selector chain whose
  HEAD is a unit-level var (`GagePort[DChan].StopGageLoop`, ~500 sites on ORM3
  CLIENT) read the var's type as an ID and dropped its declaration TEXT, so the
  `[..]` selector never saw `array [..] of T` and the call declined.

  CASES (fixture tests\callresolve\fixtures\unitvararr\uUnitVarArr.pas)
    U1 GArr[1].K   unit-level array var, element TLeaf -> TLeaf.K
    U2 GOne.K      unit-level var of TLeaf (control)   -> TLeaf.K
    U3 GArr.K      no selector on an array var          -> unbound
  CONTROL: no call edge anywhere lands on TOther.K.
  `sql --json` rows are POSITIONAL arrays: mapped onto columns[].name.
  Usage: pwsh -File tests\callresolve\run_unit_var_array_head_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:fail=$true} }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$fix     = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\unitvararr\uUnitVarArr.pas')).Path
$scratch = Join-Path C:\TEMP "draglint_unitvararr_$PID"
try {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
  $src = Join-Path $scratch 'src'; New-Item -ItemType Directory -Path $src -Force | Out-Null
  Copy-Item $fix $src -Force
  $db = Join-Path $scratch 'u.sqlite'
  function Q([string]$Query) {
    $raw = (& $exePath sql --db $db --json --limit 5000 --query $Query 2>$null) -join "`n"
    $b = $raw.IndexOf('{'); if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
    $o = $raw.Substring($b) | ConvertFrom-Json
    $names = @($o.columns | ForEach-Object { $_.name }); $out = @()
    foreach ($r in @($o.rows)) { $h = @{}; for ($i=0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }; $out += $h }
    return ,@($out)
  }
  Push-Location C:\TEMP
  try {
    & $exePath index $src --db $db 2>$null | Out-Null
    Check 'index built' ($LASTEXITCODE -eq 0)
    $rows = Q ("select r.receiver_text as rcv, s.qualified_name as target from refs r " +
               "left join call_edges e on e.ref_id = r.id left join symbols s on s.id = e.target_symbol_id " +
               "where r.kind = 'call' and r.name_text = 'K'")
    function T($rcv) { @($rows | Where-Object { $_.rcv -ceq $rcv }) }
    $u1 = @(T 'GArr[1]'); $u2 = @(T 'GOne'); $u3 = @(T 'GArr')
    Check 'U1 GArr[1].K -> TLeaf.K' (($u1.Count -eq 1) -and ($u1[0].target -ceq 'uUnitVarArr.TLeaf.K')) ("got=" + (($u1 | % { "'" + $_.target + "'" }) -join ','))
    Check 'U2 GOne.K -> TLeaf.K (control)' (($u2.Count -eq 1) -and ($u2[0].target -ceq 'uUnitVarArr.TLeaf.K')) ("got=" + (($u2 | % { "'" + $_.target + "'" }) -join ','))
    Check 'U3 GArr.K declines' (($u3.Count -eq 1) -and (-not $u3[0].target)) ("got=" + (($u3 | % { "'" + $_.target + "'" }) -join ','))
    Check 'CONTROL: nothing binds to TOther.K' (@($rows | Where-Object { $_.target -like '*TOther*' }).Count -eq 0)
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }