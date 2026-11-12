<#
  run_doc_drift_attr_and_orphan_152b.ps1 -- 152b DOC: two INBOX notes.

  1. INBOX-attribute-arg-doc-drift: `[Test] [Ignore('text')]` above a parameterless method
     put the attribute on the symbol's first line, so doc-drift's declaration-line fallback
     read the attribute argument as a signature parameter. Doc.Drift.ReadDeclLine now skips
     leading attribute groups / attribute-only lines.
  2. INBOX-doc-orphan-param-whitespace-and-false-stale: `document --apply` must keep the
     bytes of a tag that names several real params (`S, WordDelims`) or a `var`-prefixed
     real param, and must not mark them stale; a true orphan is still marked and keeps its
     bytes.

  Asserts (fixture written here; pwsh 7, any cwd):
    A  attribute case: 0 doc-drift findings (lint-all and lint <file>)
    A+ POSITIVE CONTROL: a parameterless method with a REAL missing-param twin still reports
       (`Real(AValue: Integer)` with no <param> tag -> doc-drift names AValue)
    B  document --apply: the `S, WordDelims` and `var Pos` tags are byte-identical, 0 markers
    C  CONTROL: the true orphan `AViewInfo` tag IS marked and keeps its bytes
    D  a second --apply makes 0 edits (idempotent)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc152b-$PID"
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
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 152b INT2: tree-build default, no machine drag-lint.json
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$src = Join-Path $WorkDir 'doc152b.pas'
$db  = Join-Path $WorkDir 'doc152b.sqlite'
$lines = @(
  'unit doc152b;', '', 'interface', '', 'type', '  TFx = class', '  public',
  '    /// <summary>Attribute argument is not a parameter.</summary>',                 # 8
  "    [Test] [Ignore('awaits Task 4 reader (doc section 8)')]",                        # 9
  '    procedure StoredLayout;',                                                        # 10
  '',
  '    /// <summary>Real param, no tag: control.</summary>',                            # 12
  "    [Test] [Ignore('x')]",
  '    procedure Real(AValue: Integer);',
  '  end;', '',
  '/// <summary>Position of a word.</summary>',
  '/// <param name="N"> (cardinal) </param>',
  '/// <param name="S, WordDelims"> (string) </param>',
  '/// <param name="var Pos"> (cardinal) </param>',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Boolean;', '',
  '/// <summary>Cell value.</summary>',
  '/// <param name="AView"> (view) </param>',
  '/// <param name="AViewInfo"> (gone) </param>',
  'function CellValueToDouble(AView: Integer): Double;', '',
  'implementation', '',
  'procedure TFx.StoredLayout;', 'begin', 'end;', '',
  'procedure TFx.Real(AValue: Integer);', 'begin', 'end;', '',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Boolean;', 'begin', '  Result:= True;', 'end;', '',
  'function CellValueToDouble(AView: Integer): Double;', 'begin', '  Result:= 0;', 'end;', '', 'end.')
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

function DriftAt($rows, [int]$line) { @($rows | Where-Object { $_.rule -eq 'doc-drift' -and $_.start_line -eq $line }) }
function RowsOf([string]$o) { $r = @(); try { $r = @($o | ConvertFrom-Json) } catch { $r = @() }; return ,$r }
function TagLines([string]$path, [string[]]$names) {
  @([IO.File]::ReadAllLines($path) | Where-Object { $l = $_; @($names | Where-Object { $l.Contains('<param name="' + $_ + '"') }).Count -gt 0 })
}

Push-Location $WorkDir
try {
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $la = (& $Exe lint-all --db $db --json --library-db none 2>$null | Out-String)
  $lo = (& $Exe lint $src --db $db --project-rules --format json --library-db none 2>$null | Out-String)
  foreach ($scope in @(@{ N = 'lint-all'; O = $la }, @{ N = 'lint'; O = $lo })) {
    $rows = RowsOf $scope.O
    $n = $scope.N
    Check "SANITY ${n}: JSON parsed to rows" ($rows.Count -ge 1) $scope.O
    $a = @(DriftAt $rows 8)
    Check "A ${n}: attribute argument is not a param (no doc-drift on StoredLayout)" ($a.Count -eq 0) ($a | ConvertTo-Json -Compress)
    $pc = @(DriftAt $rows 12 | Where-Object { $_.message -match 'AValue' })
    Check "A+ ${n}: POSITIVE CONTROL Real(AValue) still reports the missing <param>" ($pc.Count -ge 1) $scope.O
  }

  # --- orphan path -------------------------------------------------------
  $before = TagLines $src @('S, WordDelims', 'var Pos', 'AViewInfo')
  Check 'SANITY: fixture has the 3 tags' ($before.Count -eq 3) ($before -join '|')
  & $Exe document --unit $src --apply --db $db --library-db none 2>&1 | Out-Null
  $after = TagLines $src @('S, WordDelims', 'var Pos', 'AViewInfo')
  $text = [IO.File]::ReadAllText($src)
  $keep = @($after | Where-Object { $_.Contains('S, WordDelims') -or $_.Contains('var Pos') })
  Check 'B: multi-name and var-prefixed tags keep their bytes' (($keep -contains $before[0]) -and ($keep -contains $before[1])) ($after -join '|')
  Check 'B: they are not marked stale' (@($keep | Where-Object { $_ -match 'no longer exists' }).Count -eq 0) ($keep -join '|')
  Check 'B: no duplicate auto tag for S / WordDelims / Pos' (([regex]::Matches($text, '<param name="(S|WordDelims|Pos)"')).Count -eq 0) $text
  $orph = @($after | Where-Object { $_.Contains('AViewInfo') })
  Check 'C: CONTROL true orphan AViewInfo is marked' ($orph.Count -eq 1 -and $orph[0] -match 'param no longer exists') ($orph -join '|')
  Check 'C: ...and keeps its bytes before the marker' ($orph.Count -eq 1 -and $orph[0].StartsWith($before[2])) ($orph -join '|')
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $h1 = (Get-FileHash $src).Hash
  & $Exe document --unit $src --apply --db $db --library-db none 2>&1 | Out-Null
  Check 'D: second --apply is idempotent (file unchanged)' ((Get-FileHash $src).Hash -eq $h1)
} finally {
  Pop-Location
}
Write-Host ("{0} PASS" -f $script:Passed)
if (-not $script:Failed -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
