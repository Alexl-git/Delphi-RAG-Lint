<#
run_ancestry_routine_local.ps1 -- ResolveAncestry must never bind a heritage name to a
type declared INSIDE A ROUTINE of another scope.

FILED 2026-11-03 (docs\INBOX-yadf-false-positives-2026-11-03.md item 3): on YADFOT.sqlite
`TYadfOptionsFrame = class(TFrame)` had its ancestor bound to the record
YADF.Layout.ParseCaseArms.TFrame -- a type local to one procedure of another unit, which
is visible nowhere outside that procedure. The real ancestor (Vcl.Forms.TFrame) is in the
platform library, so the honest project-index answer is UNRESOLVED; the wrong binding made
dfm-property-not-declared report Left/Top/Width/Height/TabOrder as undeclared.

Checks:
  NEG  a class whose ancestor name matches only a routine-local record of another unit is
       left UNRESOLVED (ancestor_symbol_id NULL), not bound to the record.
  POS  a unit-level class ancestor in another unit still resolves (rule not switched off).
  POS  a routine-local class deriving from a routine-local class of the SAME routine still
       resolves (the local type IS visible there).
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($d){" -- $d"}else{''})); if(-not $ok){ $script:fail=$true } }
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$work = Join-Path C:\TEMP "draglint_ancloc_$PID"
if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
New-Item -ItemType Directory -Path $work | Out-Null
try {
  W (Join-Path $work 'uLocal.pas') @(
    'unit uLocal;','','interface','','type','  TBaseThing = class','  end;','',
    'procedure ParseArms;','procedure SameScope;','',
    'implementation','',
    'procedure ParseArms;','type','  TFrame = record','    Depth: Integer;','  end;',
    'var','  F: TFrame;','begin','  F.Depth := 0;','end;','',
    'procedure SameScope;','type','  TLocalBase = class','  end;','  TLocalDer = class(TLocalBase)','  end;',
    'begin','end;','','end.')
  W (Join-Path $work 'uFrm.pas') @(
    'unit uFrm;','','interface','','uses','  uLocal;','','type',
    '  TMyFrame = class(TFrame)','  end;','',
    '  TMyThing = class(TBaseThing)','  end;','',
    'implementation','','end.')

  $db = Join-Path $work 'fx.sqlite'
  & $exePath index $work --db $db --rebuild *> $null
  Check 'SANITY fixture indexed' (Test-Path $db) $db

  function AncOf([string]$cls) {
    $q = "SELECT COALESCE(ta.ancestor_symbol_id, 0), COALESCE(a.qualified_name, '') FROM type_ancestors ta " +
         "JOIN symbols s ON s.id = ta.symbol_id LEFT JOIN symbols a ON a.id = ta.ancestor_symbol_id " +
         "WHERE s.name = '$cls' AND ta.ordinal = 0"
    $j = (& $exePath sql --db $db --query $q --json 2>$null | Out-String) | ConvertFrom-Json
    if ($null -eq $j -or $null -eq $j.rows -or $j.rows.Count -eq 0) { return $null }
    return ,@($j.rows[0])
  }
  $fr = AncOf 'TMyFrame'; $th = AncOf 'TMyThing'; $ld = AncOf 'TLocalDer'
  Check 'SANITY type_ancestors rows exist for all three classes' (($null -ne $fr) -and ($null -ne $th) -and ($null -ne $ld)) "fr=$fr th=$th ld=$ld"
  if ($null -ne $fr) {
    Check 'NEG a heritage name matching only a ROUTINE-LOCAL record of another unit stays UNRESOLVED' `
          ([int64]$fr[0] -eq 0) "bound to id=$($fr[0]) '$($fr[1])'"
  }
  if ($null -ne $th) {
    Check 'POS a unit-level ancestor in another unit still resolves' (([int64]$th[0] -gt 0) -and ($th[1] -match 'TBaseThing$')) "id=$($th[0]) '$($th[1])'"
  }
  if ($null -ne $ld) {
    Check 'POS a local class deriving from a local class of the SAME routine still resolves' (([int64]$ld[0] -gt 0) -and ($ld[1] -match 'TLocalBase$')) "id=$($ld[0]) '$($ld[1])'"
  }
} finally {
  if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
if($fail){ Write-Host 'ANCESTRY ROUTINE-LOCAL GUARD: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'ANCESTRY ROUTINE-LOCAL GUARD: PASS' -ForegroundColor Green; exit 0 }
