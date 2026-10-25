<#
  run_doc_drift_procedure_marker.ps1 -- a comment on a parameterless procedure's declaration line
  must not turn it into a "function" for doc-drift.

  A parameterless procedure has an EMPTY indexed Signature, so doc-drift's EffectiveSignature
  falls back to the raw declaration line (Doc.Drift ReadDeclLine). That read kept trailing
  comments, so `procedure Clean;  // dl:ok some-rule@hash` reached ParseReturnType, whose
  "text after the last ':' outside the parens" found the colon in `dl:ok` and reported
  "function returns a value but has no <returns> tag" on a procedure. H2 (c2d32c07) made
  `allow` write markers on declaration lines, which is how this surfaced ("after dl:ok").
  Facts.ReadDeclLine already strips comments (StripPasCommentsKeepLayout); Drift's own copy
  did not.

  Asserts, on a scratch fixture written here (lint-all, then lint <file>):
    A  no doc-drift on Clean   (procedure; `// dl:ok ...` marker on its declaration line)
    B  no doc-drift on Clean4  (procedure; `{ note: ... }` brace comment on its declaration line)
    C  CONTROL no doc-drift on Clean3 (procedure, no comment)
    D  POSITIVE CONTROL Val (a parameterless FUNCTION, same marker, no <returns>) still reports
       "returns a value but has no <returns>" -- the rule is live and the guard can fail.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-docdrift-procmarker-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$src = Join-Path $WorkDir 'procmark.pas'
$db  = Join-Path $WorkDir 'procmark.sqlite'
$lines = @(
  'unit procmark;', '', 'interface', '',
  '/// <summary>A parameterless procedure with a marker.</summary>',     # 5
  'procedure Clean;  // dl:ok unused-public-symbol',                    # 6
  '',                                                                   # 7
  '/// <summary>A parameterless procedure, no comment.</summary>',      # 8
  'procedure Clean3;',                                                  # 9
  '',                                                                   # 10
  '/// <summary>A parameterless procedure with a brace comment.</summary>', # 11
  'procedure Clean4; { note: keep }',                                   # 12
  '',                                                                   # 13
  '/// <summary>A parameterless function, no returns tag.</summary>',   # 14
  'function Val: Integer;  // dl:ok unused-public-symbol',              # 15
  '', 'implementation', '',
  'procedure Clean;', 'begin', '  Clean3;', 'end;', '',
  'procedure Clean3;', 'begin', '  Clean4;', 'end;', '',
  'procedure Clean4;', 'begin', '  Clean;', 'end;', '',
  'function Val: Integer;', 'begin', '  Result:= 1;', 'end;', '', 'end.')
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function DriftAt($rows, [int]$line) { @($rows | Where-Object { $_.rule -eq 'doc-drift' -and $_.start_line -eq $line }) }
function RowsOf([string]$o) { $r = @(); try { $r = @($o | ConvertFrom-Json) } catch { $r = @() }; return ,$r }

Push-Location $WorkDir
try {
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $la = (& $Exe lint-all --db $db --json --library-db none 2>$null | Out-String)
  $lo = (& $Exe lint $src --db $db --project-rules --format json --library-db none 2>$null | Out-String)
  foreach ($scope in @(@{ N = 'lint-all'; O = $la }, @{ N = 'lint'; O = $lo })) {
    $rows = RowsOf $scope.O
    $n = $scope.N
    Check "SANITY ${n}: JSON parsed to rows" ($rows.Count -ge 1) $scope.O
    Check "A ${n}: no doc-drift on procedure Clean (dl:ok on its decl line)" ((DriftAt $rows 5).Count -eq 0) (DriftAt $rows 5 | ConvertTo-Json -Compress)
    Check "B ${n}: no doc-drift on procedure Clean4 (brace comment with a colon)" ((DriftAt $rows 11).Count -eq 0) (DriftAt $rows 11 | ConvertTo-Json -Compress)
    Check "C ${n}: CONTROL no doc-drift on procedure Clean3" ((DriftAt $rows 8).Count -eq 0) (DriftAt $rows 8 | ConvertTo-Json -Compress)
    $pc = @(DriftAt $rows 14 | Where-Object { $_.message -match 'returns a value but has no <returns>' })
    Check "D ${n}: POSITIVE CONTROL function Val still reports missing <returns>" ($pc.Count -ge 1) $scope.O
  }
} finally {
  Pop-Location
}
Write-Host ("{0} PASS" -f $script:Passed)
if (-not $script:Failed -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
