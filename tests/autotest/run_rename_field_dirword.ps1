<#
  run_rename_field_dirword.ps1 -- GAP-RENAME-FIELD (1.40): a record field whose
  name is a directive word (Platform) parses, is indexed, and can be renamed.

  THE DEFECT (stats\draglint-gaps.log 2026-10-28, src\core\DRagLint.Project.ContextFile.pas
  before d3436f47): 'Project, Platform, Config: string;' and a field list STARTING
  with Platform gave 6 parser-error + 2 syntax-error, the record was absent from
  the index and `rename --kind symbol --name ..TLibraryDefault.Platform` computed
  no edits. Fixed by grammar tree-sitter-delphi13 v1.4.0 (1.39.2: directive words
  parse as names); the source was renamed to PlatformName as a workaround.

  ASSERTS: no parser-error / syntax-error on the fixture; both records and every
  field (Platform first, middle) are symbols; the rename plans the declaration edit.
  POSITIVE CONTROL: a broken twin fixture DOES raise parser-error/syntax-error, so a
  zero above is a real zero (the rules fire), and the CONTROL field names of a plain
  list are found (the symbol query reads rows).

  Usage: pwsh -File tests/autotest/run_rename_field_dirword.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-renamefield-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Get-ParseFindings([string]$Dir, [string]$File, [string]$Db) {
  Push-Location $Dir
  try {
    $raw = & $Exe lint $File --db $Db --json 2>$null | Out-String
  } finally { Pop-Location }
  $rows = @()
  try { $rows = @($raw | ConvertFrom-Json) } catch {}
  return @($rows | Where-Object { $_.rule -in 'parser-error', 'syntax-error' })
}

try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $good = Join-Path $WorkDir 'good'; $bad = Join-Path $WorkDir 'bad'
  [void][IO.Directory]::CreateDirectory($good); [void][IO.Directory]::CreateDirectory($bad)
  $src = @'
unit FieldDirWord;

interface

type
  TProjectContext = record
    Schema: Integer;
    Project, Platform, Config: string;
    Alpha, Beta: Integer;
  end;

  TLibraryDefault = record
    Platform, LibraryDb: string;
  end;

function DefaultPlatform(const pDef: TLibraryDefault): string;

implementation

function DefaultPlatform(const pDef: TLibraryDefault): string;
begin
  Result:= pDef.Platform;
end;

end.
'@
  # The broken twin: a missing ':' type separator -- a real syntax error.
  $broken = $src -replace 'Alpha, Beta: Integer;', 'Alpha, Beta Integer;'
  [IO.File]::WriteAllText((Join-Path $good 'FieldDirWord.pas'), ($src -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $bad 'FieldDirWord.pas'), ($broken -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)

  $gdb = Join-Path $good 'g.sqlite'; $bdb = Join-Path $bad 'b.sqlite'
  foreach ($p in @(@($good, $gdb), @($bad, $bdb))) {
    Push-Location $p[0]
    try { $null = & $Exe index $p[0] --db $p[1] --library-db none --rule-cache-warm off 2>&1 } finally { Pop-Location }
    Check "index exits 0 ($([IO.Path]::GetFileName($p[0])))" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  }

  # POSITIVE CONTROL: the parse rules fire on a real syntax error.
  $badHits = Get-ParseFindings $bad (Join-Path $bad 'FieldDirWord.pas') $bdb
  Check 'CONTROL broken twin raises parser-error/syntax-error' ($badHits.Count -gt 0) "count=$($badHits.Count)"

  $goodHits = Get-ParseFindings $good (Join-Path $good 'FieldDirWord.pas') $gdb
  Check 'ASSERT no parser-error/syntax-error with a field named Platform' ($goodHits.Count -eq 0) `
    ("count={0} {1}" -f $goodHits.Count, (($goodHits | ForEach-Object { "L$($_.start_line)" }) -join ','))

  Push-Location $good
  try {
    $j = & $Exe sql --db $gdb --query "SELECT name, kind, start_line FROM symbols WHERE kind IN ('record','field')" --json 2>$null | Out-String
  } finally { Pop-Location }
  $rows = @()
  try { $rows = @(($j | ConvertFrom-Json).rows) } catch {}
  function HasSym([string]$n, [string]$k, [int]$line = 0) {
    return [bool]($rows | Where-Object { ([string]$_[0] -ceq $n) -and ([string]$_[1] -eq $k) -and (($line -eq 0) -or ([int]$_[2] -eq $line)) })
  }
  Check 'CONTROL plain field list: Alpha, Beta' ((HasSym 'Alpha' 'field') -and (HasSym 'Beta' 'field'))
  Check 'ASSERT record TProjectContext indexed' (HasSym 'TProjectContext' 'record')
  Check 'ASSERT record TLibraryDefault indexed' (HasSym 'TLibraryDefault' 'record')
  foreach ($f in 'Project', 'Config', 'LibraryDb') { Check "ASSERT field $f" (HasSym $f 'field') }
  Check 'ASSERT field Platform in the MIDDLE of a list (L8)' (HasSym 'Platform' 'field' 8)
  Check 'ASSERT field Platform STARTING a list (L13)' (HasSym 'Platform' 'field' 13)

  Push-Location $good
  try {
    $plan = & $Exe rename --kind symbol --name FieldDirWord.TLibraryDefault.Platform --to PlatformName --db $gdb 2>&1 | Out-String
  } finally { Pop-Location }
  Check 'ASSERT rename plans the declaration edit (L13)' ($plan -match 'L13:C5\s+Platform -> PlatformName') ($plan.Trim() -replace "`r?`n", ' | ')
  Check 'ASSERT rename plans the use site (L22)' ($plan -match 'L22:C\d+\s+Platform -> PlatformName')
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
