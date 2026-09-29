<#
  run_doc_drift_fix_overloads.ps1 -- `lint-all --fix --apply` for doc-drift must
  never touch a line that is not a doc comment, and must repair each overload's
  OWN block.

  THE DEFECT (INBOX-2026-09-29-converter-to-engine-docdrift-fix-deletes-overload-
  decls). FixEditsForDocDrift walks symbol ROWS but re-resolved each one BY NAME
  (TDocumenter.ExistingDocFor / BuildFor take a qualified name and use the first
  row). Two overloads share one name, so both rows produced a delete+insert pair
  over overload 1's doc span; the second delete ran past the block and removed
  overload 1's DECLARATION LINE. On the convrules-editor: 9 declarations deleted
  (TEngineAdapter x6, ConvRules.Usage x3), none added back, doc blocks merged.
  The checker had the same by-name resolution, so overload 2's block was graded
  against overload 1's doc.

    Part A  document --unit --apply writes one block per overload (setup)
    Part B  both overloads' callees change -> doc-drift reports BOTH blocks
    Part C  --fix --apply: every non-/// line survives, byte-identical, in order
    Part D  each block names ITS OWN overload's facts ("Overload 1 of 2" above
            the first declaration, "Overload 2 of 2" above the second)
    Part E  a second lint-all reports no doc-drift -- repaired, not reshuffled

  Usage: pwsh -File tests\autodoc\run_doc_drift_fix_overloads.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

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

$W = Join-Path $env:TEMP "drag-lint-drift-overloads-$PID"
if (Test-Path $W) { Remove-Item -Recurse -Force -LiteralPath $W }
New-Item -ItemType Directory $W | Out-Null
$Pas = Join-Path $W 'uOvl.pas'
$Db  = Join-Path $W 'ovl.sqlite'

function Write-Ascii([string]$Path, [string]$Text) {
  $n = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $n, [System.Text.Encoding]::ASCII)
}
function Get-Findings {
  $raw = (& $Exe lint-all --db $Db --json 2>$null) -join "`n"
  $a = $raw.IndexOf('['); $b = $raw.LastIndexOf(']')
  if ($a -lt 0 -or $b -le $a) { return ,@() }
  return ,@(ConvertFrom-Json $raw.Substring($a, $b - $a + 1))
}
# Every line that is not a /// doc line, in order -- the invariant under test.
function CodeLines { @([IO.File]::ReadAllLines($Pas) | Where-Object { -not $_.TrimStart().StartsWith('///') }) }
function DocAbove([int]$DeclLine) {
  $ls = [IO.File]::ReadAllLines($Pas); $i = $DeclLine - 2; $acc = @()
  while ($i -ge 0 -and $ls[$i].TrimStart().StartsWith('///')) { $acc = ,$ls[$i] + $acc; $i-- }
  return ($acc -join "`n")
}
function DeclLines { @(Select-String -LiteralPath $Pas -Pattern '^\s*function Query\(' | ForEach-Object { $_.LineNumber }) }

# Two overloads of TOvl.Query, each with hand prose -- the TEngineAdapter shape.
Write-Ascii $Pas @'
unit uOvl;

interface

type
  TOvl = class
  public
    /// <summary>Asks by name.</summary>
    function Query(const AName: string): Integer; overload;
    /// <summary>Asks by name, reporting a code.</summary>
    /// <param name="ACode">0 ok; anything else is a failure.</param>
    function Query(const AName: string; out ACode: Integer): Integer; overload;
    function Alpha: Integer;
    function Beta: Integer;
    function Gamma: Integer;
    function Delta: Integer;
  end;

implementation

function TOvl.Alpha: Integer;
begin
  Result := 1;
end;

function TOvl.Beta: Integer;
begin
  Result := 2;
end;

function TOvl.Gamma: Integer;
begin
  Result := 3;
end;

function TOvl.Delta: Integer;
begin
  Result := 4;
end;

function TOvl.Query(const AName: string): Integer;
begin
  Result := Length(AName) + Alpha;
end;

function TOvl.Query(const AName: string; out ACode: Integer): Integer;
begin
  ACode := Beta;
  Result := Length(AName);
end;

end.
'@

Push-Location $W
try {
  & $Exe index $W --db $Db 2>$null | Out-Null

  # ---- Part A: one managed block per overload --------------------------------
  & $Exe document --unit $Pas --db $Db --apply --no-backup 2>$null | Out-Null
  $d = DeclLines
  Check 'A: two Query declarations after document' ($d.Count -eq 2) "decls=$($d -join ',')"
  Check 'A: overload 1 has its own managed block' ((DocAbove $d[0]) -match 'Overload 1 of 2')
  Check 'A: overload 2 has its own managed block' ((DocAbove $d[1]) -match 'Overload 2 of 2')

  # ---- Part B: both overloads' callees change --------------------------------
  $src = [IO.File]::ReadAllText($Pas)
  $src = $src.Replace('Result := Length(AName) + Alpha;', 'Result := Length(AName) + Gamma;')
  $src = $src.Replace('ACode := Beta;', 'ACode := Delta;')
  Write-Ascii $Pas $src
  & $Exe index $W --db $Db 2>$null | Out-Null
  $codeBefore = CodeLines
  $f = Get-Findings
  $drift = @($f | Where-Object { $_.rule -eq 'doc-drift' })
  Check 'B: doc-drift reports stale blocks' ($drift.Count -ge 2) ("lines=" + (($drift | ForEach-Object { $_.start_line }) -join ','))

  # ---- Part C: the invariant -------------------------------------------------
  & $Exe lint-all --db $Db --fix --apply --no-backup 2>$null | Out-Null
  $codeAfter = CodeLines
  $same = ($codeBefore.Count -eq $codeAfter.Count) -and (@(Compare-Object $codeBefore $codeAfter -SyncWindow 0).Count -eq 0)
  Check 'C: --fix left every non-/// line intact and in order' $same `
    ("before=$($codeBefore.Count) after=$($codeAfter.Count); missing: " + ((@(Compare-Object $codeBefore $codeAfter) | Where-Object SideIndicator -eq '<=' | ForEach-Object { $_.InputObject.Trim() }) -join ' | '))
  $d = DeclLines
  Check 'C: both overload declarations survive' ($d.Count -eq 2) "decls=$($d -join ',')"

  # ---- Part D: each block is its own overload's ------------------------------
  if ($d.Count -eq 2) {
    $b1 = DocAbove $d[0]; $b2 = DocAbove $d[1]
    Check 'D: block 1 says Overload 1 of 2 and calls Gamma' (($b1 -match 'Overload 1 of 2') -and ($b1 -match 'Calls:[^<]*Gamma')) "block1=[$($b1 -replace '\s+',' ')]"
    Check 'D: block 2 says Overload 2 of 2 and calls Delta' (($b2 -match 'Overload 2 of 2') -and ($b2 -match 'Calls:[^<]*Delta')) "block2=[$($b2 -replace '\s+',' ')]"
    Check 'D: hand prose kept -- overload 2 still documents ACode' ($b2 -match 'anything else is a failure')
    Check 'D: exactly one managed block above each declaration' `
      ((([regex]::Matches($b1, 'drag-lint:auto BEGIN')).Count -eq 1) -and (([regex]::Matches($b2, 'drag-lint:auto BEGIN')).Count -eq 1))
  }

  # ---- Part E: repaired, not reshuffled --------------------------------------
  & $Exe index $W --db $Db 2>$null | Out-Null
  $f2 = Get-Findings
  $drift2 = @($f2 | Where-Object { $_.rule -eq 'doc-drift' })
  Check 'E: a second lint-all reports no doc-drift' ($drift2.Count -eq 0) ("left: " + (($drift2 | ForEach-Object { "$($_.start_line): $($_.message)" }) -join ' | '))
} finally {
  Pop-Location
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0

} finally {
  if ($W -and (Test-Path -LiteralPath $W)) { Remove-Item -LiteralPath $W -Recurse -Force -ErrorAction SilentlyContinue }
}
