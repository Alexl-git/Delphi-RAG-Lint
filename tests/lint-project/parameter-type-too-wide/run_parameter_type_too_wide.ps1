<#
  run_parameter_type_too_wide.ps1 -- the `parameter-type-too-wide` project rule (1.46 lane t4).

  The rule reports exactly the FIXES of `narrow-param --all --plan`, so the fixture is the narrow-param one
  (tests\fixtures\refactor\narrowparam): NpUse.pas marks each routine NARROW <type> / REFUSE <kind> / NONE.
  RUN 1 asks for the rule: exactly the NARROW lines fire, none of the REFUSE / NONE lines (the negative controls).
  RUN 2 is a plain lint-all: the rule ships OFF, so nothing. RUN 3 changes one routine's body so it needs the
  declared type: its finding disappears while the others stay (the finding follows the proof, not the signature).

  Usage: pwsh -File tests\lint-project\parameter-type-too-wide\run_parameter_type_too_wide.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$fx      = Join-Path $repo 'tests\fixtures\refactor\narrowparam'
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_ptw_$PID"
$Rule    = 'parameter-type-too-wide'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function RuleLines([string]$Db, [string[]]$Extra) {
  $raw = & $exePath lint-all --db $Db --library-db none --format json @Extra 2>$null
  return @((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*NpUse.pas' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function MarkerLines([string]$File, [string]$Pattern) {
  $n = 0; $out = @()
  foreach ($l in [IO.File]::ReadAllLines($File)) { $n++; if ($l -match $Pattern) { $out += $n } }
  return @($out)
}
try {
  $dir = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  Copy-Item $fx $dir -Recurse
  $use = Join-Path $dir 'NpUse.pas'
  $db  = Join-Path $scratch 'ptw.sqlite'
  & $exePath index --project (Join-Path $dir 'NarrowParam.dproj') --db $db --library-db none 2>&1 | Out-Null

  # positive-control: parameter-type-too-wide
  $want = @(MarkerLines $use '//\s*NARROW \w+\s*$')
  $other = @(MarkerLines $use '//\s*(REFUSE [a-z-]+|NONE)\s*$')
  Check 'C0 control: the fixture holds NARROW and non-NARROW routines' (($want.Count -ge 4) -and ($other.Count -ge 12)) "narrow=$($want.Count) other=$($other.Count)"
  $got = @(RuleLines $db @('--rule', $Rule))
  Check 'RUN 1 exactly the NARROW lines fire' (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
  Check 'RUN 1 no REFUSE / NONE line fires' (@($got | Where-Object { $other -contains $_ }).Count -eq 0) ''
  $raw = & $exePath lint-all --db $db --library-db none --format json --rule $Rule 2>$null
  $msg = @((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule } | Select-Object -First 1)
  Check 'RUN 1 the message names parameter and narrower type' (($msg.Count -eq 1) -and ($msg[0].message -match 'pP') -and ($msg[0].message -match '\bT(Base|Mid|Root)\b')) "$($msg[0].message)"

  $off = @(RuleLines $db @())
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  # RUN 3: ViaBase then also calls a TLeaf-only member -> the proof fails -> its finding goes, the rest stay.
  $t = [IO.File]::ReadAllText($use)
  $victim = $want[0]
  $lines = [IO.File]::ReadAllLines($use)
  Check 'C1 control: the victim is a declaration line' ($lines[$victim - 1] -match 'procedure \w+\(pP: TLeaf\)') $lines[$victim - 1]
  $name = [regex]::Match($lines[$victim - 1], 'procedure (\w+)\(').Groups[1].Value
  $body = [regex]::Match($t, "(?s)procedure THost\.$name\(pP: TLeaf\);\s*begin(.*?)end;")
  if ($body.Success) {
    $t2 = $t.Remove($body.Groups[1].Index, $body.Groups[1].Length).Insert($body.Groups[1].Index, "`r`n  pP.LeafOnly;`r`n")
    [IO.File]::WriteAllText($use, $t2, [Text.Encoding]::ASCII)
    & $exePath index --project (Join-Path $dir 'NarrowParam.dproj') --db $db --library-db none 2>&1 | Out-Null
    $after = @(RuleLines $db @('--rule', $Rule))
    $expect = @($want | Where-Object { $_ -ne $victim })
    Check 'RUN 3 a body that needs TLeaf: only its finding goes' (($after -join ',') -eq ($expect -join ',')) "got [$($after -join ',')] want [$($expect -join ',')]"
  } else {
    Check 'RUN 3 body of the victim found' $false $name
  }
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
