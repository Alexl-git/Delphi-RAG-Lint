<#
  run_public_field_records.ps1 -- public-field must not fire on a RECORD.

  THE DEFECT THIS PINS (owner report 2026-10-13, ORM3 COMMON\BASICS.PAS:226):
    TMousePos = record
      public
        X: integer;
        Y: integer;
    end;
  drew two "Public field on a class breaks encapsulation" findings. A record
  is a value type whose fields ARE its surface; the rule's own message says
  "on a class". The grammar parses both under one node, declClass, so the
  query has to tell them apart by the node's leading keyword. The sibling
  AST rule public-writable-field already excluded records the same way.

  THE CONTROLS:
    * a public field on a CLASS is still flagged (the fix must not silence it);
    * a public field on a legacy OBJECT type is still flagged (class-like);
    * a PACKED record is excluded too.

  -RulesDir defaults to the repo's rules\ folder, so the test pins the SOURCE
  rule, not whatever copy was last deployed beside the exe.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-pfrec-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== public-field: records are not classes ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe      = (Resolve-Path $Exe).Path
$RulesDir = (Resolve-Path $RulesDir).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fix = Join-Path $WorkDir 'uPfRec.pas'
$src = @'
unit uPfRec;

interface

type
  TPfRec = record
    public
      RecX: Integer;
  end;

  TPfPacked = packed record
  public
    PackedY: Integer;
  end;

  TPfClass = class
  public
    ClassZ: Integer;
  end;

  TPfObject = object
  public
    ObjectW: Integer;
  end;

implementation

end.
'@
[IO.File]::WriteAllText($fix, (($src -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)

$errFile = Join-Path $WorkDir 'stderr.txt'
$out = (& $Exe lint $fix --rule public-field --rules-dir $RulesDir 2>$errFile | Out-String) -replace "`r`n", "`n"
$hits = @($out -split "`n" | Where-Object { $_ -match 'public-field:' })
Write-Host ("  findings:`n    " + ($hits -join "`n    ")) -ForegroundColor DarkGray

# Lines in the fixture: RecX=8, PackedY=13, ClassZ=18, ObjectW=23.
Check 'R1 a public field on a RECORD is not flagged'        (@($hits -match '\.pas:8:').Count -eq 0)  ''
Check 'R2 a public field on a PACKED RECORD is not flagged' (@($hits -match '\.pas:13:').Count -eq 0) ''
Check 'R3 CONTROL: a public field on a CLASS is flagged'    (@($hits -match '\.pas:18:').Count -eq 1) ''
Check 'R4 CONTROL: a public field on an OBJECT is flagged'  (@($hits -match '\.pas:23:').Count -eq 1) ''
Check 'R5 exactly two findings'                             ($hits.Count -eq 2) ("count=" + $hits.Count)

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
