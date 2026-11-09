<#
  run_scoped_calls_all_tables_guard.ps1 -- 150-RS2 (5) + (6): the calls pass, when it is
  SCOPED, writes exactly what the WHOLE pass writes -- compared on EVERY table of the index
  (IC's corpus method of 149, at fixture scale), not on a hand-picked dump.

  (5) A NO-WRITE run with a library attached (149 IC incidental): `index` forces the calls
      pass whenever --library-db is given, and with no file written ScopedResolveDeclineReason
      answered "no file writes" -> the WHOLE pass, every time, for nothing. Expected: the pass
      is SCOPED (0 changed files) when the library is the one the DB was bound against, and
      every table is identical to the DB before the run AND to a forced whole pass.
  (6) The other ON DELETE SET NULL columns (149 IC round 3, unguarded): re-emitting an edited
      unit gives its class a NEW id, so call_edges.receiver_type_symbol_id and
      member_accesses.receiver_type_symbol_id / accessor_symbol_id rows in UNEDITED files that
      named the old id go NULL. uUser (never edited) calls TEditThing's INHERITED members
      (Run, FCount, Count from uBase): their names are not in the scoped name set, so the
      scoped pass must still rewrite them. A 2-file change (uEdit + uOther), no library.

  CASES
    N1  no-write + library: the pass is SCOPED                               (RED on 1.49: WHOLE, "no file writes")
    N2  no-write + library: every table identical to the DB before the run   (identity)
    N3  no-write + library: every table identical to a forced WHOLE run      (identity)
    T1  2-file change, no library: the pass is SCOPED                        (CONTROL)
    T2  2-file change: every table of the scoped run == the whole run        (identity)
    T3  POSITIVE CONTROL: the whole run really holds a call edge in uUser whose receiver type is
        uEdit.TEditThing (else T2 compares nothing)
  Excluded from the dump (named, not hidden): table schema_meta (fingerprints, timings, run
  markers) and column files.parsed_at (the wall-clock time of the run's own parse).

  Run from a NEUTRAL CWD, pwsh 7. -Exe defaults to the deployed engine, then the wt build.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n); if(-not $ok){ if($d){Write-Host "      $d"}; $script:fail=$true } }
if (-not $Exe) {
  $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
  if (-not (Test-Path $Exe)) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
}
$exePath = (Resolve-Path $Exe).Path
$scratch = if ($WorkDir) { $WorkDir } else { Join-Path C:\TEMP "draglint_scoped_all_$PID" }
if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
function Write-Ascii($p,$t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
$lib = Join-Path $scratch 'lib'; $src = Join-Path $scratch 'src'
[IO.Directory]::CreateDirectory($lib) | Out-Null; [IO.Directory]::CreateDirectory($src) | Out-Null

Write-Ascii (Join-Path $lib 'uLib.pas') @'
unit uLib;

interface

type
  TLibThing = class
  public
    procedure Ping;
  end;

implementation

procedure TLibThing.Ping;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uBase.pas') @'
unit uBase;

interface

type
  TBase = class
  public
    FCount: Integer;
    procedure Run;
    function GetCount: Integer;
    property Count: Integer read GetCount;
  end;

implementation

procedure TBase.Run;
begin
end;

function TBase.GetCount: Integer;
begin
  Result := FCount;
end;

end.
'@
$editText = @'
unit uEdit;

interface

uses
  uBase;

type
  TEditThing = class(TBase)
  public
    procedure Bump;
  end;

implementation

procedure TEditThing.Bump;
begin
end;

end.
'@
$otherText = @'
unit uOther;

interface

type
  TOther = class
  public
    procedure Go;
  end;

implementation

procedure TOther.Go;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uEdit.pas') $editText
Write-Ascii (Join-Path $src 'uOther.pas') $otherText
# uUser is NEVER edited: its sites reach TEditThing's INHERITED members, whose names the
# 2-file change does not put in the scoped name set.
Write-Ascii (Join-Path $src 'uUser.pas') @'
unit uUser;

interface

uses
  uLib, uBase, uEdit, uOther;

procedure UseIt;

implementation

procedure UseIt;
var
  Thing: TEditThing;
  O    : TOther;
  L    : TLibThing;
  N    : Integer;
begin
  Thing := TEditThing.Create;
  Thing.Run;
  Thing.Bump;
  N := Thing.Count;
  Thing.FCount := N;
  O := TOther.Create;
  O.Go;
  L := TLibThing.Create;
  L.Ping;
end;

end.
'@
foreach ($n in 1..6) {
  Write-Ascii (Join-Path $src "uFill$n.pas") @"
unit uFill$n;

interface

type
  TFill$n = class
  public
    procedure Work$n;
  end;

implementation

procedure TFill$n.Work$n;
begin
end;

procedure Drive$n;
var
  F: TFill$n;
begin
  F := TFill$n.Create;
  F.Work$n;
end;

end.
"@
}

function Sql([string]$Db, [string]$Q) {
  $j = & $exePath sql --query $Q --db $Db --json --limit 1000000 2>$null | Out-String
  if ($j.IndexOf('{') -lt 0) { return $null }
  return ($j.Substring($j.IndexOf('{')) | ConvertFrom-Json)
}
# Every table but schema_meta, every column, rows sorted: the IC cmpdb method in PowerShell.
function Dump-All([string]$Db) {
  $t = Sql $Db "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'schema_meta' ORDER BY name"
  $out = [ordered]@{}
  foreach ($row in $t.rows) {
    $name = [string]$row[0]
    # files.parsed_at is the wall-clock time of the run's own parse -- the one volatile column.
    $d = Sql $Db "SELECT * FROM [$name]"
    $skip = if ($name -eq 'files') { [array]::IndexOf(@($d.columns | ForEach-Object { $_.name }), 'parsed_at') } else { -1 }
    $lines = @($d.rows | ForEach-Object { $k = 0; ($_ | ForEach-Object { $v = if ($k -eq $skip) { '<volatile>' } elseif ($null -eq $_) { '<null>' } else { [string]$_ }; $k++; $v }) -join '|' }) | Sort-Object
    $out[$name] = ($lines -join "`n") -replace [regex]::Escape($scratch), '<S>'
  }
  return $out
}
function Compare-All([string]$Tag, $A, $B, [string]$AName, [string]$BName) {
  $diff = @()
  foreach ($k in $A.Keys) { if (-not $B.Contains($k) -or ($A[$k] -cne $B[$k])) { $diff += $k } }
  foreach ($k in $B.Keys) { if (-not $A.Contains($k)) { $diff += $k } }
  Check "${Tag}: all $($A.Count) tables identical ($AName == $BName)" ($diff.Count -eq 0) ("differ: " + ($diff -join ', '))
  foreach ($k in ($diff | Select-Object -First 4)) {
    $x = $A[$k] -split "`n"; $y = $B[$k] -split "`n"
    $y | Where-Object { $x -notcontains $_ } | Select-Object -First 4 | ForEach-Object { Write-Host "      $k $BName-only: $_" }
    $x | Where-Object { $y -notcontains $_ } | Select-Object -First 4 | ForEach-Object { Write-Host "      $k $AName-only: $_" }
  }
}
function Lane-Index([string]$Db, [bool]$WithLib, [bool]$Whole) {
  [Environment]::SetEnvironmentVariable('DRAGLINT_NO_SCOPED_RESOLVE', $(if ($Whole) { '1' } else { $null }))
  try {
    if ($WithLib) { return (& $exePath index $src --db $Db --library-db $libDb 2>&1 | Out-String) }
    return (& $exePath index $src --db $Db 2>&1 | Out-String)
  } finally { [Environment]::SetEnvironmentVariable('DRAGLINT_NO_SCOPED_RESOLVE', $null) }
}
function CallsLines([string]$O) { return (($O -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join ' / ') }

$libDb = Join-Path $scratch 'lib.sqlite'
Push-Location C:\TEMP
try {
  & $exePath index $lib --db $libDb 2>&1 | Out-Null

  # ---- (5) no-write run with the library ----
  $nb = Join-Path $scratch 'n-base.sqlite'
  $null = Lane-Index $nb $true $false
  $null = Lane-Index $nb $true $false   # settle: the second run is the steady state a user sees
  $n1 = Join-Path $scratch 'n1.sqlite'; $nw = Join-Path $scratch 'nw.sqlite'
  Copy-Item $nb $n1; Copy-Item $nb $nw
  $dBefore = Dump-All $nb
  $oN1 = Lane-Index $n1 $true $false
  $null = Lane-Index $nw $true $true
  Check 'N1: no-write run with the library takes the SCOPED pass' ($oN1 -match 'starting SCOPED pass') (CallsLines $oN1)
  $dN1 = Dump-All $n1
  Compare-All 'N2' $dN1 $dBefore 'after' 'before'
  Compare-All 'N3' $dN1 (Dump-All $nw) 'scoped' 'whole'

  # ---- (6) 2-file change, no library: SET NULL receiver / accessor columns ----
  $tb = Join-Path $scratch 't-base.sqlite'
  $null = Lane-Index $tb $false $false
  $t1 = Join-Path $scratch 't1.sqlite'; $tw = Join-Path $scratch 'tw.sqlite'
  Copy-Item $tb $t1; Copy-Item $tb $tw
  Write-Ascii (Join-Path $src 'uEdit.pas') ($editText + "{ t1 }`n")
  Write-Ascii (Join-Path $src 'uOther.pas') ($otherText + "{ t1 }`n")
  $oT1 = Lane-Index $t1 $false $false
  $null = Lane-Index $tw $false $true
  Check 'T1 CONTROL: the 2-file change takes the SCOPED pass' ($oT1 -match 'starting SCOPED pass') (CallsLines $oT1)
  $dTW = Dump-All $tw
  $pc = Sql $tw ("SELECT count(*) FROM call_edges ce JOIN refs r ON r.id = ce.ref_id JOIN files f ON f.id = r.file_id " +
                 "JOIN symbols t ON t.id = ce.receiver_type_symbol_id WHERE f.path LIKE '%uUser.pas' AND t.qualified_name = 'uEdit.TEditThing'")
  Check 'T3 POSITIVE CONTROL: the whole run holds uUser call edges whose receiver type is uEdit.TEditThing' ([int]$pc.rows[0][0] -ge 2) "count=$($pc.rows[0][0])"
  Compare-All 'T2' (Dump-All $t1) $dTW 'scoped' 'whole'
} finally { Pop-Location }
} finally {
  if ((-not $WorkDir) -and (Test-Path -LiteralPath $scratch)) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
