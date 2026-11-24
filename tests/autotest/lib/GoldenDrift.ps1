<#
  GoldenDrift.ps1 -- v154 TT-GOLDEN. ONE known-drift exception file format shared by every golden runner
  (run_fieldrepo_ormgen_golden.ps1, run_fieldrepo_paramarray_golden.ps1). Dot-source it.

  File format (tests\fieldrepo\<name>-golden-known-drift.txt), ASCII, one entry per line:
    # comment / blank line          ignored
    <key>  <reason>                 an entry of kind '' (a unit, or unit:class for the param-array golden)
    @<kind> <key>  <reason>         an entry of a named kind (ormgen uses @region <id> <the one change>)
  The reason is REQUIRED (a drift nobody can explain is not an exception); a key may occur once per kind.
  Keys compare case-insensitively.

  Rule (the same for every runner): a difference that is NOT listed = FAIL (NEW); a listed drift that no
  longer happens = FAIL (STALE, delete the line). Compare-GoldenDrift returns both sets; Test-GoldenDriftControl
  is the positive control every runner runs first: it proves both failure directions can fire.
#>

function Read-GoldenDrift {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  $entries = New-Object System.Collections.Generic.List[object]
  $errors = New-Object System.Collections.Generic.List[string]
  $seen = @{}
  $n = 0
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    $n++
    if ($line -match '^\s*(#|$)') { continue }
    $m = [regex]::Match($line, '^(?:@(?<kind>\w+)\s+)?(?<key>\S+)(?:\s+(?<reason>\S.*?))?\s*$')
    if (-not $m.Success) { $errors.Add("line ${n}: unreadable"); continue }
    $kind = $m.Groups['kind'].Value.ToLower()
    $key = $m.Groups['key'].Value.ToUpper()
    $reason = $m.Groups['reason'].Value
    if ($reason -eq '') { $errors.Add("line ${n}: '$key' has no reason"); continue }
    if ($seen.ContainsKey("$kind|$key")) { $errors.Add("line ${n}: duplicate '$key'"); continue }
    $seen["$kind|$key"] = $true
    $entries.Add([pscustomobject]@{ Kind = $kind; Key = $key; Reason = $reason; Line = $n })
  }
  return [pscustomobject]@{ Entries = $entries.ToArray(); Errors = $errors.ToArray() }
}

function Get-GoldenDriftKeys {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Drift, [string]$Kind = '')
  return @($Drift.Entries | Where-Object { $_.Kind -eq $Kind.ToLower() } | ForEach-Object { $_.Key })
}

function Compare-GoldenDrift {
  [CmdletBinding()]
  param([string[]]$Listed = @(), [string[]]$Actual = @())
  $l = @($Listed | ForEach-Object { $_.ToUpper() } | Sort-Object -Unique)
  $a = @($Actual | ForEach-Object { $_.ToUpper() } | Sort-Object -Unique)
  return [pscustomobject]@{
    New   = @($a | Where-Object { $l -notcontains $_ })
    Stale = @($l | Where-Object { $a -notcontains $_ })
  }
}

# Positive control: returns $true only when the comparison FAILS where it must and passes where it must.
function Test-GoldenDriftControl {
  [CmdletBinding()]
  param()
  $same = Compare-GoldenDrift -Listed @('a', 'B') -Actual @('A', 'b')
  $unl = Compare-GoldenDrift -Listed @('A') -Actual @('A', 'X')
  $stl = Compare-GoldenDrift -Listed @('A', 'Y') -Actual @('A')
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("golden-drift-control-$PID.txt")
  try {
    [IO.File]::WriteAllText($tmp, "# c`r`nu1 why`r`n@region 2 the change`r`nbad`r`nu1 again`r`n")
    $d = Read-GoldenDrift -Path $tmp
  } finally { [IO.File]::Delete($tmp) }
  return ($same.New.Count -eq 0 -and $same.Stale.Count -eq 0 -and
          $unl.New.Count -eq 1 -and $unl.New[0] -eq 'X' -and $unl.Stale.Count -eq 0 -and
          $stl.Stale.Count -eq 1 -and $stl.Stale[0] -eq 'Y' -and $stl.New.Count -eq 0 -and
          $d.Entries.Count -eq 2 -and $d.Errors.Count -eq 2 -and
          (Get-GoldenDriftKeys $d 'region') -contains '2' -and (Get-GoldenDriftKeys $d) -contains 'U1')
}
