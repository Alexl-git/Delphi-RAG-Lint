<#
  run_hover_implementors.ps1 --
  Hovering an INTERFACE METHOD must name the methods that answer it (1.44 C22).

  THE STATE IT REPLACES. `hover --qname IWorker.Work` showed signature, doc and
  facts but never the implementing methods, although `implementors` and the LSP
  implementation request answer it from the same index (ImplementingMethodsOf).
  run_hover_interface_implementors.ps1 covers the TYPE-level line; this guard
  covers the MEMBER-level line, in plain, md and json.

  POSITIVE CONTROL. The same fixture's class method TWorkerAlpha.Work and a
  plain method must NOT carry the line (a guard that passes with the feature
  switched on everywhere proves nothing), and the fixture index must really hold
  the answering methods (V2).

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(& "$PSScriptRoot\lib\DefaultEngineExe.ps1"),
  [string]$WorkDir = "C:\TEMP\draglint_hover_implm_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uFixM.pas') @"
unit uFixM;

interface

type
  IWorker = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Work: Integer;
  end;

  TWorkerAlpha = class(TInterfacedObject, IWorker)
  public
    function Work: Integer;
    procedure Plain;
  end;

  TWorkerBeta = class(TInterfacedObject, IWorker)
  public
    function Work: Integer;
  end;

implementation

function TWorkerAlpha.Work: Integer;
begin
  Result := 1;
end;

procedure TWorkerAlpha.Plain;
begin
end;

function TWorkerBeta.Work: Integer;
begin
  Result := 2;
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Hover([string]$QName, [string]$Fmt) {
  return ((& $exePath hover --qname $QName --db $db --format $Fmt 2>$null) -join "`r`n")
}

$impl = ((& $exePath implementors --target 'IWorker.Work' --db $db 2>$null) -join ' ')
Check 'V2 POSITIVE CONTROL implementors answers TWorkerAlpha.Work for IWorker.Work' `
      ($impl -match 'TWorkerAlpha') $impl

foreach ($fmt in 'plain','md','json') {
  $h = Hover 'uFixM.IWorker.Work' $fmt
  Check "C22 [$fmt] interface method hover has an 'Implemented by' line" ($h -match 'Implemented by') $h
  Check "C22 [$fmt] it names TWorkerAlpha.Work" ($h -match 'TWorkerAlpha\.Work') $h
  Check "C22 [$fmt] it names TWorkerBeta.Work" ($h -match 'TWorkerBeta\.Work') $h
}

# NEGATIVE CONTROLS: the line belongs to interface methods only.
foreach ($q in 'uFixM.TWorkerAlpha.Work','uFixM.TWorkerAlpha.Plain') {
  foreach ($fmt in 'plain','md','json') {
    $h = Hover $q $fmt
    Check "C22 [$fmt] $q is a class method: no 'Implemented by' member line" (($h -match 'Work|Plain') -and ($h -notmatch 'Implemented by')) $h
  }
}
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
