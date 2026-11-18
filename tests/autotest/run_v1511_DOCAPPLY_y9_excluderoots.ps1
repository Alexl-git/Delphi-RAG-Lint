<#
  run_v1511_DOCAPPLY_y9_excluderoots.ps1 -- `document --project` honours the
  project's "excludeRoots" however the project path is spelled (1.51.1 Y9,
  docs\INBOX-yadf-fp-hunt-151.md DOC-9).

  THE DEFECT THIS PINS:
    YADF declares { "ownRoots": [<repo>], "excludeRoots": [<repo>\vendor] }.
    `document --project YADF.dproj`, run from the YADF folder, listed and wrote
    vendor\DelphiAST\...\SimpleParser.Lexer.pas. The ownership filter loaded
    drag-lint-project.json from ExtractFilePath(<project path>) -- '' for a
    RELATIVE path -- so the declaration was inactive and every closure file
    counted as "ours". The same command with an absolute path skipped vendor.

  CASES
    * REL     relative --project from the project folder: vendor byte-identical,
              the skip is named on stderr.
    * ABS     absolute --project: same (regression guard for the old good path).
    * CONTROL the project's own unit IS documented (otherwise every
              "byte-identical" above would pass with the writer dead).
    * OPTIN   --document-third-party still documents the vendored unit: the
              escape hatch stays the opt-in.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v1511-y9-$PID")
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [IO.File]::WriteAllText($Path, $norm, [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  $app    = Join-Path $WorkDir 'app'
  $vendor = Join-Path $app 'vendor'
  $drag   = Join-Path $app '_D-RAG'
  foreach ($d in @($app, $vendor, $drag)) { New-Item -ItemType Directory $d -Force | Out-Null }

  Write-Ascii (Join-Path $vendor 'uVendor.pas') @'
unit uVendor;
interface
function VendorLen(const AName: string): Integer;
implementation
function VendorLen(const AName: string): Integer;
begin
  Result := Length(AName);
end;
end.
'@
  Write-Ascii (Join-Path $app 'uApp.pas') @'
unit uApp;
interface
uses uVendor;
function AppDo(const AName: string): Integer;
implementation
function AppDo(const AName: string): Integer;
begin
  Result := VendorLen(AName);
end;
end.
'@
  Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uApp in 'uApp.pas',
  uVendor in 'vendor\uVendor.pas';
begin
  Writeln(AppDo('x'));
end.
'@
  # The YADF shape: the project folder is the own root, vendor\ carved out.
  Write-Ascii (Join-Path $drag 'drag-lint-project.json') '{ "ownRoots": ["."], "excludeRoots": ["vendor"] }'

  $db    = Join-Path $drag 'app.sqlite'
  $vfile = Join-Path $vendor 'uVendor.pas'
  $afile = Join-Path $app 'uApp.pas'
  $null  = & $Exe index $app --db $db 2>&1
  Check 'setup: index built' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $q = & $Exe query --name VendorLen --db $db 2>&1 | Out-String
  Check 'setup: the vendored unit is indexed (exclusion is a real decision)' ($q -match 'VendorLen')
  $vBefore = [IO.File]::ReadAllText($vfile)
  $aBefore = [IO.File]::ReadAllText($afile)

  Write-Host 'REL: relative --project from the project folder' -ForegroundColor Cyan
  Push-Location $app
  try { $o = & $Exe document --project 'App.dpr' --db $db 2>&1 | Out-String } finally { Pop-Location }
  Check 'REL dry run does not list the vendored file' ($o -notmatch '(?m)^File:.*uVendor\.pas') (($o -split "`r?`n" | Where-Object { $_ -match '^File:.*uVendor' } | Select-Object -First 1))
  Check 'REL dry run names the skipped root' ($o -match 'skipped third-party root') ''
  Push-Location $app
  try { $o = & $Exe document --project 'App.dpr' --db $db --apply --no-backup 2>&1 | Out-String } finally { Pop-Location }
  Check 'REL --apply leaves the vendored file byte-identical' ([IO.File]::ReadAllText($vfile) -ceq $vBefore) ''

  Write-Host 'ABS: absolute --project' -ForegroundColor Cyan
  # Independent of REL: restore the vendored bytes first, so a REL failure is not counted twice.
  [IO.File]::WriteAllText($vfile, $vBefore, [Text.Encoding]::ASCII)
  $o = & $Exe document --project (Join-Path $app 'App.dpr') --db $db --apply --no-backup 2>&1 | Out-String
  Check 'ABS --apply leaves the vendored file byte-identical' ([IO.File]::ReadAllText($vfile) -ceq $vBefore) ''

  Write-Host 'CONTROL: the own unit IS documented' -ForegroundColor Cyan
  $aNow = [IO.File]::ReadAllText($afile)
  Check 'CONTROL uApp.pas received engine output' (($aNow -ne $aBefore) -and ($aNow -match 'drag-lint:auto')) ''

  Write-Host 'OPTIN: --document-third-party stays the opt-in' -ForegroundColor Cyan
  Push-Location $app
  try { $o = & $Exe document --project 'App.dpr' --db $db --document-third-party 2>&1 | Out-String } finally { Pop-Location }
  Check 'OPTIN dry run lists the vendored file' ($o -match '(?m)^File:.*uVendor\.pas') ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
