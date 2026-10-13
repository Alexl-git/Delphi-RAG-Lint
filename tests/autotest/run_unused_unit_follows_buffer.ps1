<#
  run_unused_unit_follows_buffer.ps1 -- in a single-file lint of an EDITOR
  BUFFER, unused-unit-in-uses must answer for the buffer's uses clause, not
  the indexed one.

  THE DEFECT THIS PINS (owner report 2026-10-13, ORM3 COMMON\BASICS.PAS):
  DXFConv, sgConsts and bcParser were commented out of the uses clause, the
  unit was saved, and the Diagnostics panel kept reporting all three as dead
  imports. The rule reads the uses list (and the refs) from the INDEX, so in
  `lint <buffer> --stand-in-for <file> --db <db>` -- the IDE's live lint --
  it described the file as it was at the last reindex: an import the user had
  already removed, at the line it used to occupy.

  THE FIX: after the index-wide pass, each unused-unit-in-uses finding is
  checked against the uses clause READ FROM THE BUFFER. Not there any more ->
  dropped; there -> re-anchored to the buffer's line.

  THE CONTROLS:
    * an unused import still in the buffer IS still reported (the fix must not
      silence the rule);
    * when the buffer moves it, the finding follows to the buffer's line.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-uubuf-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== unused-unit-in-uses follows the BUFFER in a single-file lint ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null
function W([string]$Path, [string]$t) {
  [IO.File]::WriteAllText($Path, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
W (Join-Path $src 'uUbDeadA.pas') "unit uUbDeadA;`ninterface`ntype`n  TUbA = class`n  end;`nimplementation`nend.`n"
W (Join-Path $src 'uUbDeadB.pas') "unit uUbDeadB;`ninterface`ntype`n  TUbB = class`n  end;`nimplementation`nend.`n"
$mainText = @'
unit uUbMain;

interface

uses
  uUbDeadA,
  uUbDeadB;

type
  TUbMain = class
  end;

implementation

end.
'@
$main = Join-Path $src 'uUbMain.pas'
W $main $mainText
W (Join-Path $src 'App.dpr') "program App;`nuses`n  uUbMain in 'uUbMain.pas',`n  uUbDeadA in 'uUbDeadA.pas',`n  uUbDeadB in 'uUbDeadB.pas';`nbegin`nend.`n"
$db = Join-Path $WorkDir 'ub.sqlite'
& $Exe index --project (Join-Path $src 'App.dpr') --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db) ''

function UnusedIn([string]$Buffer) {
  $raw = & $Exe lint $Buffer --stand-in-for $main --db $db --rule unused-unit-in-uses --json 2>$null | Out-String
  $i = $raw.IndexOf('[')
  if ($i -lt 0) { return @() }
  @(($raw.Substring($i) | ConvertFrom-Json) | Where-Object { $_.rule -eq 'unused-unit-in-uses' } |
    ForEach-Object { [pscustomobject]@{ Unit = ($_.message -replace "^Unit '([^']+)'.*", '$1'); Line = [int]$_.start_line } })
}

# PREMISE: on the unedited buffer both imports are dead, from the index.
$base = UnusedIn $main
Check 'P1 premise: both unused imports are reported for the unedited unit' `
  ((@($base | Where-Object Unit -eq 'uUbDeadA').Count -eq 1) -and (@($base | Where-Object Unit -eq 'uUbDeadB').Count -eq 1)) `
  "got: $(@($base | ForEach-Object { "$($_.Unit)@$($_.Line)" }) -join ', ')"

# THE DEFECT: the buffer comments uUbDeadA out; the index still lists it.
$buf1 = Join-Path $WorkDir 'drag-lint-live-1.pas'
W $buf1 ($mainText -replace '  uUbDeadA,', '  //uUbDeadA,')
$r1 = UnusedIn $buf1
Check 'B1 an import commented out in the BUFFER is not reported (index still lists it)' `
  (@($r1 | Where-Object Unit -eq 'uUbDeadA').Count -eq 0) "got: $(@($r1 | ForEach-Object { "$($_.Unit)@$($_.Line)" }) -join ', ')"
Check 'B2 CONTROL: the import still in the buffer IS reported' (@($r1 | Where-Object Unit -eq 'uUbDeadB').Count -eq 1) ''

# THE LINE: the buffer pushes the uses clause down three lines.
$buf2 = Join-Path $WorkDir 'drag-lint-live-2.pas'
W $buf2 ($mainText -replace 'interface', "interface`n`n// added`n")
$r2 = UnusedIn $buf2
$b = @($r2 | Where-Object Unit -eq 'uUbDeadB')
Check 'L1 the finding follows the BUFFER line, not the indexed one' (($b.Count -eq 1) -and ($b[0].Line -eq 10)) "got line: $($b.Line) (indexed: 7)"

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
