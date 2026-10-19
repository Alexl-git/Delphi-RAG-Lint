<#
  run_doc_body_call_site_label.ps1 -- wave 1.31.6 lane B: 'declaration' shown as
  a CALLER name in a "Called from:" list.

  ROOT CAUSE: TDocFactsBuilder.Build.ToFactRef (DRagLint.Doc.Facts.pas) renders
  every caller row with an EMPTY EnclosingQName as 'declaration' (PHASE C B11).
  That is right for a declaration-position mention of a TYPE (a field type, a
  parameter type), but a CALL with no enclosing routine is a call from a
  program's main block (.dpr) or from a unit's initialization / finalization
  section -- not a declaration at all. The live symptom on drag-lint itself:
  DRagLint.CLI.Run read 'Called from: declaration (drag-lint.dpr)'.

  Fixture: uBody.pas declares Ping (a routine) and TRec (a record). Ping is
  called from UsePing (a real routine), from uBody's initialization section,
  and from app.dpr's main block. TRec is used only in declaration position
  (a unit-scope var).

  Asserts:
    1. Ping's "Called from:" names UsePing (positive control: the line exists
       and is read).
    2. ... names 'main block (app.dpr)' for the .dpr call.
    3. ... names 'initialization/finalization (uBody.pas)' for the unit call.
    4. ... does NOT name 'declaration' (the defect; RED before the fix).
    5. TRec's "Used by:" still names 'declaration' (B11 is kept for a type --
       positive control that the fix did not just delete the word).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-body-call-site-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-BlockAbove([string[]]$Lines, [string]$DeclPattern) {
  $idx = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $DeclPattern) { $idx = $i; break } }
  if ($idx -lt 1) { return '' }
  $bl = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($Lines[$i] -notmatch '^\s*///') { break }
    $bl.Insert(0, $Lines[$i])
  }
  return [string]::Join("`n", $bl.ToArray())
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$dir = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null

Write-Ascii (Join-Path $dir 'uBody.pas') @'
unit uBody;
interface
type
  TRec = record
    A: Integer;
  end;
procedure Ping;
procedure UsePing;
implementation
var
  GRec: TRec;
procedure Ping;
begin
end;
procedure UsePing;
begin
  Ping;
end;
initialization
  Ping;
end.
'@
Write-Ascii (Join-Path $dir 'app.dpr') @'
program app;
uses
  uBody in 'uBody.pas';
begin
  Ping;
end.
'@
$file = Join-Path $dir 'uBody.pas'
$db   = Join-Path $dir 'fx.sqlite'

& $Exe index $dir --db $db 2>&1 | Out-Null
Push-Location $dir
try {
  & $Exe document --qname uBody.Ping --db $db --apply --no-backup 2>&1 | Out-Null
  $ec1 = $LASTEXITCODE
  & $Exe document --qname uBody.TRec --db $db --apply --no-backup 2>&1 | Out-Null
  $ec2 = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'document Ping / TRec exit 0' (($ec1 -eq 0) -and ($ec2 -eq 0)) "ec=$ec1/$ec2"

$lines = [IO.File]::ReadAllLines($file)
$ping  = Get-BlockAbove $lines '^\s*procedure\s+Ping;'
$rec   = Get-BlockAbove $lines '^\s*TRec\s*=\s*record'
$called = ([regex]::Match($ping, 'Called from:[^\r\n]*')).Value
$used   = ([regex]::Match($rec,  'Used by:[^\r\n]*')).Value

Write-Host 'Ping: a call with no enclosing routine is not a declaration' -ForegroundColor Cyan
Check 'Called from: names UsePing (positive control)' ($called -match '\bUsePing\b') $called
Check 'Called from: names main block (app.dpr)' ($called -match 'main block \(app\.dpr\)') $called
Check 'Called from: names initialization/finalization (uBody.pas)' `
  ($called -match 'initialization/finalization \(uBody\.pas\)') $called
Check 'Called from: does NOT name declaration' (-not ($called -match '\bdeclaration\b')) $called
Write-Host 'TRec: a declaration-position use still reads declaration (B11 kept)' -ForegroundColor Cyan
Check 'Used by: names declaration (uBody.pas)' ($used -match 'declaration \(uBody\.pas\)') $used

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-doc-body-call-site-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
