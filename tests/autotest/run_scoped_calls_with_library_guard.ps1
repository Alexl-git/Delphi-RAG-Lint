<#
  run_scoped_calls_with_library_guard.ps1 -- 149 IC: the calls pass may be SCOPED with a
  library extra store attached, exactly when the library is the one this DB was bound
  against and no declared type name moved; it must then write what the whole-DB pass writes.
  Spec: docs\superpowers\specs\2026-11-09-scoped-calls-with-library.md (option C).

  Fixture: lib\uLib.pas (TLibThing.Ping) indexed as the "library"; src\ = uCaller (X: TLibThing;
  X.Ping -- binds only through the library), uEdit (the file each arm rewrites), five fillers
  (keeps a 1-file delta under the 1-in-3 scoping limit).

    S1  unchanged library, comment edit       -> SCOPED, rows identical to a whole-DB run (A/B)
    S2  library re-indexed (indexed_at moves)  -> WHOLE, reason "the library changed"
    S3  run adds a type name                   -> WHOLE, reason "set of declared type names"
    S4  scoped pass WITHOUT the library, then  -> WHOLE, reason "the library changed"
        the library again (the history hole: external_stores is marked partial)

  POSITIVE CONTROLS: the whole-DB dump really holds the library binding of X.Ping (else the
  A/B compares nothing); S1 RED on the 1.48 engine (whole, "extra stores are attached").
  Run from a NEUTRAL CWD, pwsh 7.  -Exe defaults to the deployed engine, then the wt build.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n); if(-not $ok){ if($d){Write-Host "      $d"}; $script:fail=$true } }
if (-not $Exe) {
  $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
  if (-not (Test-Path $Exe)) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
}
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_scoped_lib_$PID"
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
function Write-Ascii($p,$t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), (New-Object Text.UTF8Encoding($false))) }
$lib = Join-Path $scratch 'lib'; $src = Join-Path $scratch 'src'
[IO.Directory]::CreateDirectory($lib) | Out-Null; [IO.Directory]::CreateDirectory($src) | Out-Null

$libText = @'
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
Write-Ascii (Join-Path $lib 'uLib.pas') $libText
Write-Ascii (Join-Path $src 'uCaller.pas') @'
unit uCaller;

interface

uses
  uLib;

procedure Go;

implementation

procedure Go;
var
  X: TLibThing;
begin
  X := TLibThing.Create;
  X.Ping;
end;

end.
'@
$editText = @'
unit uEdit;

interface

type
  TEditThing = class
  public
    procedure Bump;
  end;

procedure Touch;

implementation

procedure TEditThing.Bump;
begin
end;

procedure Touch;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uEdit.pas') $editText
# uUser is NEVER edited: its refs are typed through uEdit's class (whose symbol id moves on
# every re-emit) and its Bump calls are in the scoped NAME set while their receiver Thing is not.
Write-Ascii (Join-Path $src 'uUser.pas') @'
unit uUser;

interface

uses
  uEdit;

procedure UseIt;

implementation

procedure UseIt;
var
  Thing : TEditThing;
  Things: array of TEditThing;
begin
  Thing := TEditThing.Create;
  Thing.Bump;
  SetLength(Things, 1);
  Things[0] := Thing;
  Things[0].Bump;
  Thing.Free;
end;

end.
'@
foreach ($n in 1..5) {
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

{ a LOCAL call edge per filler: CallEdgesNeedRebuild declines a DB with no edges at all }
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

$libDb = Join-Path $scratch 'lib.sqlite'
# Everything the resolve pass writes that a library can influence, keyed by position, not id.
$dumpSql = @'
SELECT 'REF|' || f.path || '|' || r.start_line || '|' || r.start_col || '|' || r.name_text || '|' ||
       COALESCE(r.external_target,'') || '|' || COALESCE(r.receiver_text,'') || '|' ||
       COALESCE(ts.qualified_name,'') || '|' || COALESCE(e.confidence,'') || '|' || COALESCE(es.qualified_name,'')
FROM refs r JOIN files f ON f.id = r.file_id
LEFT JOIN symbols ts ON ts.id = r.symbol_id
LEFT JOIN call_edges e ON e.ref_id = r.id
LEFT JOIN symbols es ON es.id = e.target_symbol_id
ORDER BY f.path, r.start_line, r.start_col, r.name_text, 1
'@
function Lane-Dump([string]$Db) {
  $j = & $exePath sql --query $dumpSql --db $Db --json --limit 1000000 2>$null | Out-String
  $o = $j.Substring($j.IndexOf('{')) | ConvertFrom-Json
  return (@($o.rows | ForEach-Object { [string]$_[0] }) -join "`n") -replace [regex]::Escape($scratch), '<S>'
}
# The three derived tables the calls pass rewrites per ref (round 3: the scoped pass left
# ref_types / ref_element_types ids NULL and dropped ref_receivers rows outside the edited file).
$derivedSql = @'
SELECT 'RT|' || f.path || '|' || r.start_line || '|' || r.start_col || '|' || r.name_text || '|' ||
       COALESCE(ts.qualified_name,'<null>') || '|' || t.type_qname || '|' || t.via
FROM ref_types t JOIN refs r ON r.id = t.ref_id JOIN files f ON f.id = r.file_id
LEFT JOIN symbols ts ON ts.id = t.type_symbol_id
UNION ALL
SELECT 'ET|' || f.path || '|' || r.start_line || '|' || r.start_col || '|' || r.name_text || '|' ||
       COALESCE(ts.qualified_name,'<null>') || '|' || t.type_qname
FROM ref_element_types t JOIN refs r ON r.id = t.ref_id JOIN files f ON f.id = r.file_id
LEFT JOIN symbols ts ON ts.id = t.type_symbol_id
UNION ALL
SELECT 'RR|' || f.path || '|' || r.start_line || '|' || r.start_col || '|' || r.name_text || '|' ||
       q.start_line || '|' || q.start_col || '|' || q.name_text
FROM ref_receivers x JOIN refs r ON r.id = x.ref_id JOIN refs q ON q.id = x.receiver_ref_id
JOIN files f ON f.id = r.file_id
ORDER BY 1
'@
function Lane-DumpDerived([string]$Db) {
  $j = & $exePath sql --query $derivedSql --db $Db --json --limit 1000000 2>$null | Out-String
  $o = $j.Substring($j.IndexOf('{')) | ConvertFrom-Json
  return (@($o.rows | ForEach-Object { [string]$_[0] }) -join "`n") -replace [regex]::Escape($scratch), '<S>'
}
function Lane-CompareDerived([string]$Tag, [string]$Scoped, [string]$Whole) {
  Check "${Tag}: scoped ref_types / ref_element_types / ref_receivers IDENTICAL to the whole-DB rows" ($Scoped -ceq $Whole) ''
  if ($Scoped -cne $Whole) {
    $a = $Scoped -split "`n"; $b = $Whole -split "`n"
    $b | Where-Object { $a -notcontains $_ } | Select-Object -First 8 | ForEach-Object { Write-Host "      whole-only: $_" }
    $a | Where-Object { $b -notcontains $_ } | Select-Object -First 8 | ForEach-Object { Write-Host "      scoped-only: $_" }
  }
}
function Lane-Index([string]$Db, [bool]$WithLib, [bool]$Whole) {
  [Environment]::SetEnvironmentVariable('DRAGLINT_NO_SCOPED_RESOLVE', $(if ($Whole) { '1' } else { $null }))
  try {
    if ($WithLib) { return (& $exePath index $src --db $Db --library-db $libDb 2>&1 | Out-String) }
    return (& $exePath index $src --db $Db 2>&1 | Out-String)
  } finally { [Environment]::SetEnvironmentVariable('DRAGLINT_NO_SCOPED_RESOLVE', $null) }
}
function Lane-Touch([string]$Tag) { Write-Ascii (Join-Path $src 'uEdit.pas') ($editText + "{ $Tag }`n") }

Push-Location C:\TEMP
try {
  & $exePath index $lib --db $libDb 2>&1 | Out-Null
  $base = Join-Path $scratch 'base.sqlite'
  $o0 = Lane-Index $base $true $false
  Check 'SETUP: the first run with the library binds it (library: + resolve ran)' ($o0 -match 'library-db') $o0

  # ---- S1: unchanged library, comment edit -> SCOPED and identical to WHOLE ----
  $s1 = Join-Path $scratch 's1.sqlite'; $w1 = Join-Path $scratch 'w1.sqlite'
  Copy-Item $base $s1; Copy-Item $base $w1
  Lane-Touch 's1'
  $oS1 = Lane-Index $s1 $true $false
  $oW1 = Lane-Index $w1 $true $true
  Check 'S1: unchanged library + comment edit takes the SCOPED pass' ($oS1 -match 'starting SCOPED pass') (($oS1 -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")
  Check 'S1 CONTROL: the A side really ran WHOLE' ($oW1 -match 'WHOLE-DB pass') ''
  $dS1 = Lane-Dump $s1; $dW1 = Lane-Dump $w1
  Check 'S1 POSITIVE CONTROL: the whole-DB dump holds the library binding of X.Ping' `
        (($dW1 -split "`n") | Where-Object { $_ -match 'uCaller\.pas\|\d+\|\d+\|Ping\|[^|]*TLibThing' }) `
        ((($dW1 -split "`n") | Where-Object { $_ -match 'uCaller' }) -join "`n")
  Check 'S1: scoped rows IDENTICAL to the whole-DB rows' ($dS1 -ceq $dW1) "scoped=$($dS1.Length) whole=$($dW1.Length)"
  if ($dS1 -cne $dW1) {
    $a = $dS1 -split "`n"; $b = $dW1 -split "`n"
    $b | Where-Object { $a -notcontains $_ } | Select-Object -First 8 | ForEach-Object { Write-Host "      whole-only: $_" }
    $a | Where-Object { $b -notcontains $_ } | Select-Object -First 8 | ForEach-Object { Write-Host "      scoped-only: $_" }
  }
  $xS1 = Lane-DumpDerived $s1; $xW1 = Lane-DumpDerived $w1
  $xW1Lines = $xW1 -split "`n"
  Check 'S1 POSITIVE CONTROL: the whole-DB ref_types type uUser.Thing by the LIVE TEditThing id' `
        ([bool]($xW1Lines | Where-Object { $_ -match '^RT\|<S>\\src\\uUser\.pas\|\d+\|\d+\|Thing\|uEdit\.TEditThing\|' })) `
        (($xW1Lines | Where-Object { $_ -match 'uUser' }) -join "`n")
  Check 'S1 POSITIVE CONTROL: the whole-DB ref_receivers join uUser Bump to its receiver Thing' `
        ([bool]($xW1Lines | Where-Object { $_ -match '^RR\|<S>\\src\\uUser\.pas\|\d+\|\d+\|Bump\|\d+\|\d+\|Thing$' })) ''
  Lane-CompareDerived 'S1' $xS1 $xW1

  # ---- S5: the same identity WITHOUT a library (the scoped no-store pass, pre-149 behaviour) ----
  $b5 = Join-Path $scratch 'b5.sqlite'
  $null = Lane-Index $b5 $false $false
  $s5 = Join-Path $scratch 's5.sqlite'; $w5 = Join-Path $scratch 'w5.sqlite'
  Copy-Item $b5 $s5; Copy-Item $b5 $w5
  Lane-Touch 's5'
  $oS5 = Lane-Index $s5 $false $false
  $null = Lane-Index $w5 $false $true
  Check 'S5 CONTROL: the no-library run took the SCOPED pass' ($oS5 -match 'starting SCOPED pass') (($oS5 -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")
  Lane-CompareDerived 'S5' (Lane-DumpDerived $s5) (Lane-DumpDerived $w5)

  # ---- S2: the library is re-indexed -> WHOLE (positive control of the identity test) ----
  $s2 = Join-Path $scratch 's2.sqlite'; Copy-Item $s1 $s2
  Start-Sleep -Seconds 2   # indexed_at_unix has 1-second resolution
  Write-Ascii (Join-Path $lib 'uLib.pas') ($libText + "{ re-indexed }`n")
  & $exePath index $lib --db $libDb 2>&1 | Out-Null
  Lane-Touch 's2'
  $oS2 = Lane-Index $s2 $true $false
  Check 'S2: a re-indexed library sends the pass WHOLE, naming the library change' `
        (($oS2 -match 'WHOLE-DB pass') -and ($oS2 -match 'the library changed since')) (($oS2 -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")

  # ---- S3: the run adds a declared type name -> WHOLE on the type-name gate ----
  $s3 = Join-Path $scratch 's3.sqlite'; Copy-Item $s2 $s3
  $e3 = ($editText -replace "`r`n","`n").Replace("procedure Touch;`n`nimplementation", "procedure Touch;`n`ntype`n  TNewThing = class`n  end;`n`nimplementation")
  Check 'S3 CONTROL: the edit really declares a new type' ($e3 -match 'TNewThing') ''
  Write-Ascii (Join-Path $src 'uEdit.pas') $e3
  $oS3 = Lane-Index $s3 $true $false
  Check 'S3: a run that adds a type name goes WHOLE on the type-name gate' `
        (($oS3 -match 'WHOLE-DB pass') -and ($oS3 -match 'changed the set of declared type names')) (($oS3 -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")

  # ---- S4: the history hole -- a scoped pass without the library, then the library again ----
  $s4 = Join-Path $scratch 's4.sqlite'; Copy-Item $s3 $s4
  Lane-Touch 's4a'
  $oS4a = Lane-Index $s4 $false $false
  Check 'S4 CONTROL: the no-library run took the SCOPED pass' ($oS4a -match 'starting SCOPED pass') (($oS4a -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")
  Lane-Touch 's4b'
  $oS4b = Lane-Index $s4 $true $false
  Check 'S4: after a scoped no-library pass, the next library run goes WHOLE (external_stores partial)' `
        (($oS4b -match 'WHOLE-DB pass') -and ($oS4b -match 'the library changed since')) (($oS4b -split "`n" | Select-String 'calls +(starting|\.\.\. whole)') -join "`n")
} finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
