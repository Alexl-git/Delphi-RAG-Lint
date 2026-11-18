<#
  run_v1511_DOCAPPLY_y10_shared_converge.ps1 -- autodoc of a `dl:shared` unit
  converges whichever project runs last (1.51.1 Y10, DOC-10 second cause).

  THE DEFECT THIS PINS:
    After the facts-cache fix (run_v1511_DOCAPPLY_y10_reindex_facts.ps1) the YADF
    copy still did not converge on ONE block: YADF.Options.SharedAppDataIniPath,
    whose harvested `// Shared per-user fallback path used by YADF.exe,
    YADFOT.bpl, and YADFSetup.exe ...` comment YADF and YADFOT promote to an
    auto <summary>, and YADFSetup removes again. DemoteForeignSummary demotes a
    summary whose first sentence names a FOREIGN symbol -- and "YADFSetup"
    resolves (to the program) only in YADFSetup's own index. On a shared unit
    the demotion's evidence depends on which project's index is asking, so the
    block flipped on every run. Ruling (lane default, OWNER-Q): on a `dl:shared`
    unit the demotion does not run; the harvested summary is kept by every
    project. An unmarked unit keeps the demotion (CONTROL).

  FIXTURE: ToolOne.dpr and ToolTwo.dpr both compile uShared.pas
  (`// dl:shared ToolOne, ToolTwo`); the comment above SharedPath's body opens
  "Path used by ToolOne.exe". Only ToolOne's index holds the symbol ToolOne.
  CASES
    * CONVERGE  ToolTwo, ToolOne, ToolTwo, ToolOne apply (--reindex); then both
                dry runs have nothing to document.
    * SUMMARY   the shared unit carries the harvested summary.
    * CONTROL   the same comment on an UNMARKED unit of ToolOne is still demoted
                (no <summary> written from it) -- the rule did not just vanish.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v1511-y10s-$PID")
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
function Write-Ascii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  $app = Join-Path $WorkDir 'app'
  New-Item -ItemType Directory (Join-Path $app '_D-RAG') -Force | Out-Null
  $body = @(
    'implementation',
    '// Path used by ToolOne.exe and the other tool when no local file is found.',
    'function {0}: string;',
    'begin',
    "  Result := 'x';",
    'end;',
    'end.')
  Write-Ascii (Join-Path $app 'uShared.pas') (@('unit uShared;   // dl:shared ToolOne, ToolTwo', 'interface',
    'function SharedPath: string;') + ($body -replace '\{0\}', 'SharedPath'))
  Write-Ascii (Join-Path $app 'uOwn.pas') (@('unit uOwn;', 'interface',
    'function OwnPath: string;') + ($body -replace '\{0\}', 'OwnPath'))
  Write-Ascii (Join-Path $app 'ToolOne.dpr') @('program ToolOne;', 'uses', "  uShared in 'uShared.pas',",
    "  uOwn in 'uOwn.pas';", 'begin', '  Writeln(SharedPath + OwnPath);', 'end.')
  Write-Ascii (Join-Path $app 'ToolTwo.dpr') @('program ToolTwo;', 'uses', "  uShared in 'uShared.pas';",
    'begin', '  Writeln(SharedPath);', 'end.')
  $shared = Join-Path $app 'uShared.pas'
  $own    = Join-Path $app 'uOwn.pas'
  $p = @{ ToolOne = (Join-Path $app 'ToolOne.dpr'); ToolTwo = (Join-Path $app 'ToolTwo.dpr') }
  $d = @{ ToolOne = (Join-Path $app '_D-RAG\ToolOne.sqlite'); ToolTwo = (Join-Path $app '_D-RAG\ToolTwo.sqlite') }
  foreach ($k in 'ToolOne', 'ToolTwo') {
    $null = & $Exe index --project $p[$k] --db $d[$k] 2>&1
    Check "setup: $k index built" ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  }
  foreach ($k in 'ToolTwo', 'ToolOne', 'ToolTwo', 'ToolOne') {
    $o = & $Exe document --project $p[$k] --db $d[$k] --apply --reindex --no-backup 2>&1 | Out-String
    Write-Host ("    apply {0}: {1}" -f $k, (($o -split "`r?`n" | Where-Object { $_ -match '^doc: \d' }) -join ' '))
  }
  foreach ($k in 'ToolOne', 'ToolTwo') { $null = & $Exe index --project $p[$k] --db $d[$k] 2>&1 }
  foreach ($k in 'ToolOne', 'ToolTwo') {
    $o = & $Exe document --project $p[$k] --db $d[$k] 2>&1 | Out-String
    Check "CONVERGE $k dry run has nothing to document" ($o -notmatch '(?m)^File:') (($o -split "`r?`n" | Where-Object { $_ -match '^doc: \d|^File:|^\s+(insert|delete)' } | Select-Object -First 4) -join ' ')
  }
  $st = [IO.File]::ReadAllText($shared)
  Check 'SUMMARY the shared unit carries the harvested summary' ($st -match '<summary><!-- drag-lint:auto sum -->Path used by ToolOne') ''
  $ot = [IO.File]::ReadAllText($own)
  Check 'CONTROL the unmarked unit still demotes it (no summary from the comment)' ($ot -notmatch '<summary>[^\r\n]*Path used by ToolOne') ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
