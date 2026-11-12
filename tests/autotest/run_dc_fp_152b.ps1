<#
  run_dc_fp_152b.ps1 -- wave 152b lane DC: three lint false positives from the
  ORM3 lint-all of 2026-11-09 (docs\INBOX-default-encoding-io-name-match-and-
  out-arg-writes.md, docs\INBOX-referenced-never-set-cast-write.md).

    A  default-encoding-io matched the callee text by SUBSTRING, so
       `SetCurrentStreamWriter(nil)` ("...tStreamWriter") fired. The callee is
       now matched by its dotted name SEGMENTS.
    B  read-never-assigned did not count a field passed to an out / var formal
       of a PROCEDURAL-type callee (a parameter typed `reference to
       function(out ..)`, a field typed `procedure(var ..) of object`).
    C  referenced-never-set did not credit `TGreet(LOld).FReplaced := True`,
       a write through a hard cast to the field's class, from another class's
       method in the same unit.

  Fixtures: tests\fixtures\dc-fp-152b\{dei,rna,rns}. Each fixture line carries
  a TRIGGER-* marker (must fire) or a CONTROL-* marker (must stay silent).
  Positive controls (the rules still fire): a real TStreamWriter.Create /
  TStreamReader.Create / LoadFromFile without an encoding; a field passed by
  VALUE to the same procedural callee; a field only read; a field written only
  through a cast to ANOTHER class.

  On the base engine (1.50.0-alpha) the CONTROL lines of A, B and C fire: RED.

  Usage: pwsh -File tests\autotest\run_dc_fp_152b.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dc-fp-152b-$PID"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$Fix = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\dc-fp-152b')).Path
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function Get-Markers([string]$Path) {
  $map = @{}
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    $n++
    if ($l -match '//\s*((TRIGGER|CONTROL)-[A-Z]+)') { $map[$Matches[1]] = $n }
  }
  return $map
}
function Get-Lines([string[]]$Raw, [string]$Leaf, [string]$Rule) {
  $lines = @()
  foreach ($r in $Raw) {
    if ($r -match ('\\' + [regex]::Escape($Leaf) + ':(\d+):\d+\s+\[\w+\]\s+' + [regex]::Escape($Rule) + ':')) { $lines += [int]$Matches[1] }
  }
  return ,@($lines)
}
function Assert-Markers([string]$Tag, [string]$Path, [int[]]$Hits) {
  $m = Get-Markers $Path
  if ($m.Count -eq 0) { Check "$Tag fixture has markers" $false $Path; return }
  foreach ($k in ($m.Keys | Sort-Object)) {
    $line = $m[$k]
    $fired = $Hits -contains $line
    if ($k -like 'TRIGGER-*') { Check "$Tag $k fires" $fired "line=$line" }
    else { Check "$Tag $k stays silent" (-not $fired) "line=$line" }
  }
}

try {
  [IO.Directory]::CreateDirectory($WorkDir) | Out-Null
  Push-Location $WorkDir   # lint-all writes its report into cwd

  Write-Host 'A  default-encoding-io: name segments, not a substring' -ForegroundColor Cyan
  $dei = Join-Path $Fix 'dei\dcdei.pas'
  $raw = @(& $Exe lint $dei --rule default-encoding-io 2>&1 | ForEach-Object { "$_" })
  Assert-Markers 'A' $dei (Get-Lines $raw 'dcdei.pas' 'default-encoding-io')

  Write-Host 'B  read-never-assigned: out / var formal of a procedural-type callee' -ForegroundColor Cyan
  $rnaSrc = Join-Path $WorkDir 'rna'
  [IO.Directory]::CreateDirectory($rnaSrc) | Out-Null
  $rna = Join-Path $Fix 'rna\uDcRna.pas'
  [IO.File]::Copy($rna, (Join-Path $rnaSrc 'uDcRna.pas'), $true)
  $db = Join-Path $WorkDir 'rna.sqlite'
  & $Exe index $rnaSrc --db $db 2>&1 | Out-Null
  Check 'B index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $raw = @(& $Exe lint-all --db $db --rule read-never-assigned 2>&1 | ForEach-Object { "$_" })
  $hits = Get-Lines $raw 'uDcRna.pas' 'read-never-assigned'
  Check 'B lint-all produced findings (rule ran)' ($hits.Count -gt 0) "count=$($hits.Count)"
  Assert-Markers 'B' $rna $hits

  Write-Host 'C  referenced-never-set: write through a hard cast' -ForegroundColor Cyan
  $rns = Join-Path $Fix 'rns\dcrns.pas'
  $raw = @(& $Exe lint $rns --rule referenced-never-set 2>&1 | ForEach-Object { "$_" })
  Assert-Markers 'C' $rns (Get-Lines $raw 'dcrns.pas' 'referenced-never-set')
}
finally {
  Pop-Location
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
