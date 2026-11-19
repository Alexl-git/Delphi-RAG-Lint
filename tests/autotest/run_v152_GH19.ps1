<#
  run_v152_GH19.ps1 -- GitHub #19: `usages --width wide` was quadratic in the number of units using a
  type. The impact walk (ISymbolStore.FindTransitiveCallers) took every symbol whose line range holds
  a use as a "caller" -- including the PARAMETER `A` of `procedure Work1(A: TThing)` and the LOCAL `B`
  -- and the next level then joined every ref named A / B in the database to every such row.
  Fixture (the issue's generator, N = 20 units x 10 routines): count-based, no timing.
  1. wide impact depth 1 has no param / local "callers": callers <= 11 * N + 5 (was 13 * N + ...).
  2. depth 2 stays bounded (<= 11 * N + 5): it no longer walks every ref named A / B.
  3. control: narrow and wide report the same declarations / reads / calls totals.
  4. control: the impact rows are present (depth 1 > 0).
  pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [int]$N = 20)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh19_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
[IO.File]::WriteAllText((Join-Path $fx 'Thing.pas'), "unit Thing;`r`ninterface`r`ntype`r`n  TThing = class`r`n  private`r`n    FValue: Integer;`r`n  public`r`n    function Make: TThing;`r`n    procedure Run;`r`n    property Value: Integer read FValue write FValue;`r`n  end;`r`nimplementation`r`nfunction TThing.Make: TThing; begin Result := TThing.Create; end;`r`nprocedure TThing.Run; begin end;`r`nend.`r`n", [Text.Encoding]::ASCII)
for ($u = 1; $u -le $N; $u++) {
  $sb = [Text.StringBuilder]::new()
  [void]$sb.Append("unit User$u;`r`ninterface`r`nuses Thing;`r`n")
  for ($k = 1; $k -le 10; $k++) { [void]$sb.Append("procedure Work$k(A: TThing);`r`n") }
  [void]$sb.Append("implementation`r`n")
  for ($k = 1; $k -le 10; $k++) { [void]$sb.Append("procedure Work$k(A: TThing);`r`nvar`r`n  B: TThing;`r`nbegin`r`n  B := A.Make;`r`n  B.Value := A.Value + 1;`r`n  B.Run;`r`n  TThing(B).Run;`r`nend;`r`n") }
  [void]$sb.Append("end.`r`n")
  [IO.File]::WriteAllText((Join-Path $fx "User$u.pas"), $sb.ToString(), [Text.Encoding]::ASCII)
}
$db = Join-Path $work 'u.sqlite'
Push-Location $work
try {
  & { $ErrorActionPreference = 'Continue'; & $exe index $fx --db $db *> $null }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $wid = (& { $ErrorActionPreference = 'Continue'; & $exe usages --name TThing --width wide --depth 2 --format json --limit 50 --db $db 2>$null } | Out-String) | ConvertFrom-Json | ForEach-Object { $_ }
  $nar = (& { $ErrorActionPreference = 'Continue'; & $exe usages --name TThing --width narrow --format json --limit 50 --db $db 2>$null } | Out-String) | ConvertFrom-Json | ForEach-Object { $_ }
  $cap = 11 * $N + 5
  $d1 = @($wid.impact | Where-Object { $_.depth -eq 1 })[0].callers
  $d2 = @($wid.impact | Where-Object { $_.depth -eq 2 })
  $d2c = if ($d2.Count) { $d2[0].callers } else { 0 }
  Check "depth 1 callers <= $cap (no param / local callers)" ($d1 -le $cap) "depth 1 = $d1"
  Check "depth 2 callers <= $cap" ($d2c -le $cap) "depth 2 = $d2c"
  Check 'control: depth 1 > 0' ($d1 -gt 0) "depth 1 = $d1"
  $same = ($wid.totals.declarations -eq $nar.totals.declarations) -and ($wid.totals.reads -eq $nar.totals.reads) -and ($wid.totals.calls -eq $nar.totals.calls)
  Check 'control: narrow and wide agree on the row totals' $same ("wide " + ($wid.totals | ConvertTo-Json -Compress) + " narrow " + ($nar.totals | ConvertTo-Json -Compress))
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
