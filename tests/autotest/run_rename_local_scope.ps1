<#
  run_rename_local_scope.ps1 -- E-RENAME-LOCAL-REFUSED (wave 146): a symbol declared inside a routine is proved inside
  that routine, in every form of the verb.

  A local's scope is its routine: no other unit can name it or capture the new name. 1.44.1 read every unit, so a
  same-named bare ref elsewhere refused the rename through --kind symbol and --qname (the IDE's form), and --apply
  wrote nothing after a preview that exited 0.

  POSITIVE CONTROLS: l4 and l8 (a real capture and an include inside the routine still refuse, so the scope did not
  blind the proof); l9 (a unit-level symbol still answers for the other unit's bare ref, so the scope is not blanket).
  RED on 1.44.1-alpha: l1 and l2 refuse on LsB, l5 misses the implementation header, l7 refuses shadowed-at-site.

  E-SYNCFWD-HEADERS, the s cases: --kind param syncs the ONE header the routine implements. RED on 1.44.1-alpha: a sibling
  overload's headers get the edit and a class member's declaration does not, so the compile gate stops it at E2037.

  E-BUILDLOCAL-BYTES, the b cases: --kind param edits carry character columns on a non-ASCII line, in a UTF-8 and an ANSI
  file. RED on 1.44.1-alpha: byte columns, so StaleEditReason refuses the line as out of date.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-localscope-$PID"
)
$env:DRAGLINT_RENAME_TEST_UNGATED = '1' # the fixture does not compile; run_rename_precise.ps1 proves the gate
$ErrorActionPreference = 'Continue'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $Src | Out-Null
$Db = Join-Path $WorkDir 'fx.sqlite'
$Ascii = [Text.Encoding]::ASCII
function Crlf([string]$Body) { return ($Body -replace "`r`n", "`n" -replace "`n", "`r`n") }
$Files = @{}
$Files['LsA.pas'] = @'
unit LsA;

interface

type
  TA = class
  public
    Caption: Integer;
    Used: Integer;
    procedure Go(pX: Integer);
    procedure Capt;
    procedure WithInc;
  end;
  TB = class
  public
    procedure Go(pX: Integer);
  end;

var
  GlobalR: Integer;

implementation

procedure TA.Go(pX: Integer);
var
  R: Integer;
begin
  R:= pX;
  Inc(R);
  pX:= R;
end;

procedure TA.Capt;
var
  R: Integer;
begin
  R:= 1;
  Used:= R;
end;

procedure TA.WithInc;
var
  Q: Integer;
begin
  Q:= 1;
  {$I LsInc.inc}
end;

procedure TB.Go(pX: Integer);
begin
  pX:= 2;
end;

end.
'@
$Files['LsB.pas'] = @'
unit LsB;

interface

implementation

procedure Other;
begin
  R:= 1;
  pX:= 1;
  GlobalR:= 1;
  with Foo do
    ARect:= 2;
end;

end.
'@
$Files['LsInc.inc'] = "  Q:= 2;`r`n"
$Files['LsC.pas'] = @"
unit LsC;

interface

type
  TA = class
  public
    procedure Ov(pX: Integer); overload;
    procedure Ov(pX: string); overload;
    procedure Bare(pZ: Integer);
    procedure Def(pD: Integer = 0);
    procedure Grp(pG, pH: Integer);
  end;
  TB = class
  public
    procedure Ov(pX: Integer);
  end;

procedure Free1(pX: Integer); overload;
procedure Free1(pX: string); overload;

implementation

procedure TA.Ov(pX: Integer);
begin
  pX:= 1;
end;

procedure TA.Ov(pX: string);
begin
  pX:= '';
end;

procedure TA.Bare;
begin
  pZ:= 1;
end;

procedure TA.Def(pD: Integer);
begin
  pD:= 1;
end;

procedure TA.Grp(pG: Integer; pH: Integer);
begin
  pG:= pH;
end;

procedure TB.Ov(pX: Integer);
begin
  pX:= 2;
end;

procedure Free1(pX: Integer);
begin
  pX:= 3;
end;

procedure Free1(pX: string);
begin
  pX:= '';
end;

end.
"@
# ~ is one non-ASCII character: a byte column and a character column differ after it.
$Bytes = @"
unit NAME;

interface

implementation

type
  TP = record
    Z: Integer;
  end;

procedure Go;
var
  N: TP;
  {~} R: Integer;
begin
  {~} R:= 1; Inc(R);
  {~} with N do R:= 2;
end;

end.
"@
$Ansi = [Text.Encoding]::GetEncoding(1252)
$Umlaut = [string][char]0xFC
function Reset-Fx {
  foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $Src $k), (Crlf $Files[$k]), $Ascii) }
  [IO.File]::WriteAllText((Join-Path $Src 'LsE8.pas'), (Crlf ($Bytes -replace 'NAME', 'LsE8' -replace '~', $Umlaut)), [Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText((Join-Path $Src 'LsEA.pas'), (Crlf ($Bytes -replace 'NAME', 'LsEA' -replace '~', $Umlaut)), $Ansi)
}
function Param-Plan([string]$Unit, [int]$Line, [int]$Col, [string]$To) {
  $o = ($null | & $Exe rename --kind param --in (Join-Path $Src $Unit) --line $Line --col $Col --to $To --db $Db --plan --json 2>$null | Out-String)
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Raw = $o; Json = $j; Lines = @($j.edits | ForEach-Object { [int]$_.line }) }
}
function Line-Of([string]$Unit, [string]$Exact, [int]$Nth = 1) {
  $n = 0; $i = 0
  foreach ($l in ((Text-Of $Unit) -split "`r`n")) { $i++; if ($l -ceq $Exact) { $n++; if ($n -eq $Nth) { return $i } } }
  return 0
}
function Text-Of([string]$Name) { return [IO.File]::ReadAllText((Join-Path $Src $Name), $Ascii) }
function Run-Engine([string[]]$A) {
  $o = ($null | & $Exe @A 2>&1 | Out-String); return @{ Exit = $LASTEXITCODE; Out = $o }
}
function Plan-Symbol([string]$Q, [string]$To) {
  $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $Db --library-db none --plan --json 2>$null | Out-String)
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Raw = $o; Json = $j; Kinds = @($j.refusals | ForEach-Object { $_.kind }) }
}
Reset-Fx
Push-Location $WorkDir
try {
  $null | & $Exe index $Src --db $Db --library-db none *> "$Db.log"
  $A = Join-Path $Src 'LsA.pas'
  $LineR = 0; $i = 0; foreach ($l in ((Text-Of 'LsA.pas') -split "`r`n")) { $i++; if (($LineR -eq 0) -and ($l -match '^  R: Integer;')) { $LineR = $i } }

  Write-Host 'A local: the same answer in all three forms' -ForegroundColor Cyan
  $p = Plan-Symbol 'LsA.TA.Go.R' 'ARect'
  Check 'l1 --kind symbol: 4 edits, 0 undecided' ($p.Json -and @($p.Json.edits).Count -eq 4 -and @($p.Json.refusals).Count -eq 0) $p.Raw
  $r = Run-Engine @('rename', '--qname', 'LsA.TA.Go.R', '--to', 'ARect', '--db', $Db, '--library-db', 'none', '--dry-run')
  Check 'l2 --qname --dry-run: exit 0, 4 edits' ($r.Exit -eq 0 -and $r.Out -match 'Dry run: 4 edit') $r.Out
  Check 'l2 --qname --dry-run: no refusal notes' ($r.Out -notmatch 'note:') $r.Out
  $r = Run-Engine @('rename', '--kind', 'param', '--in', $A, '--line', "$LineR", '--col', '3', '--to', 'ARect', '--db', $Db, '--plan', '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'l3 --kind param: 4 edits, 0 undecided' ($j -and @($j.edits).Count -eq 4 -and @($j.refusals).Count -eq 0) $r.Out
  $r = Run-Engine @('rename', '--qname', 'LsA.TA.Go.R', '--to', 'ARect', '--db', $Db, '--library-db', 'none')
  Check 'l3b --qname applies, exit 0' ($r.Exit -eq 0) $r.Out
  Check 'l3b the routine renamed' ((Text-Of 'LsA.pas') -match 'ARect:= pX;\s+Inc\(ARect\);\s+pX:= ARect;') (Text-Of 'LsA.pas')
  Check 'l3b the other unit untouched' ((Text-Of 'LsB.pas') -ceq (Crlf $Files['LsB.pas']))
  Check 'l3b TA.Capt''s own R untouched' ((Text-Of 'LsA.pas') -match 'R:= 1;\s+Used:= R;') (Text-Of 'LsA.pas')
  Reset-Fx

  Write-Host 'Positive controls: the scope does not blind the proof' -ForegroundColor Cyan
  $p = Plan-Symbol 'LsA.TA.Capt.R' 'Used'
  Check 'l4 the routine already uses the new name: [capture-local]' ($p.Kinds -contains 'capture-local') $p.Raw
  $r = Run-Engine @('rename', '--qname', 'LsA.TA.Capt.R', '--to', 'Used', '--db', $Db, '--library-db', 'none')
  Check 'l4 apply refuses, exit 2, bytes same' ($r.Exit -eq 2 -and $r.Out -match 'refused \[capture-local\]' -and (Text-Of 'LsA.pas') -match 'R:= 1;\s+Used:= R;') $r.Out
  $p = Plan-Symbol 'LsA.TA.WithInc.Q' 'Qq'
  Check 'l8 an include inside the routine: [no-ref-occurrence]' ($p.Kinds -contains 'no-ref-occurrence') $p.Raw
  $p = Plan-Symbol 'LsA.GlobalR' 'GlobalS'
  Check 'l9 a unit-level symbol still answers for the other unit: [bare-unbound]' ($p.Kinds -contains 'bare-unbound') $p.Raw

  Write-Host 'A parameter: declaration, implementation header and body' -ForegroundColor Cyan
  $p = Plan-Symbol 'LsA.TA.Go.pX' 'ARect'
  $lines = @($p.Json.edits | ForEach-Object { [int]$_.line })
  $text = (Text-Of 'LsA.pas') -split "`r`n"
  $hdr = [array]::IndexOf($text, 'procedure TA.Go(pX: Integer);') + 1
  Check 'l5 the implementation header is an edit' ($lines -contains $hdr) $p.Raw
  Check 'l5 declaration + header + 2 body sites, 0 undecided' ($lines.Count -eq 4 -and @($p.Json.refusals).Count -eq 0) $p.Raw
  $tbHdr = [array]::IndexOf($text, 'procedure TB.Go(pX: Integer);') + 1
  Check 'l6 TB.Go''s header is not an edit' ($lines -notcontains $tbHdr) $p.Raw

  Write-Host 'A local hides a member it does not use' -ForegroundColor Cyan
  $p = Plan-Symbol 'LsA.TA.Go.R' 'Caption'
  Check 'l7 a field of the class named the new name, unused in the routine: 0 undecided' ($p.Json -and @($p.Json.refusals).Count -eq 0 -and @($p.Json.edits).Count -eq 4) $p.Raw

  Write-Host '--kind param: the one header the routine implements' -ForegroundColor Cyan
  $declInt = Line-Of 'LsC.pas' '    procedure Ov(pX: Integer); overload;'
  $declStr = Line-Of 'LsC.pas' '    procedure Ov(pX: string); overload;'
  $hdrInt  = Line-Of 'LsC.pas' 'procedure TA.Ov(pX: Integer);'
  $hdrStr  = Line-Of 'LsC.pas' 'procedure TA.Ov(pX: string);'
  $declTB  = Line-Of 'LsC.pas' '    procedure Ov(pX: Integer);'
  $hdrTB   = Line-Of 'LsC.pas' 'procedure TB.Ov(pX: Integer);'
  $q = Param-Plan 'LsC.pas' $hdrInt 17 'pQ'
  Check 's1 the method''s own declaration is an edit' ($q.Lines -contains $declInt) $q.Raw
  Check 's1 own header and body are edits' (($q.Lines -contains $hdrInt) -and ($q.Lines -contains ($hdrInt + 2))) $q.Raw
  Check 's1 the sibling overload is not touched' (($q.Lines -notcontains $declStr) -and ($q.Lines -notcontains $hdrStr)) $q.Raw
  Check 's1 another class''s method is not touched' (($q.Lines -notcontains $declTB) -and ($q.Lines -notcontains $hdrTB)) $q.Raw
  $declF1 = Line-Of 'LsC.pas' 'procedure Free1(pX: Integer); overload;'
  $declF2 = Line-Of 'LsC.pas' 'procedure Free1(pX: string); overload;'
  $hdrF1  = Line-Of 'LsC.pas' 'procedure Free1(pX: Integer);'
  $q = Param-Plan 'LsC.pas' $hdrF1 17 'pQ'
  Check 's2 a free routine: its own forward header, not the overload''s' (($q.Lines -contains $declF1) -and ($q.Lines -notcontains $declF2)) $q.Raw
  $q = Param-Plan 'LsC.pas' (Line-Of 'LsC.pas' 'procedure TA.Def(pD: Integer);') 18 'pQ'
  Check 's3 a default value only in the declaration still matches' ($q.Lines -contains (Line-Of 'LsC.pas' '    procedure Def(pD: Integer = 0);')) $q.Raw
  $q = Param-Plan 'LsC.pas' ((Line-Of 'LsC.pas' 'procedure TA.Bare;') + 2) 3 'pQ'
  Check 's4 an implementation header with no list still finds the declaration' ($q.Lines -contains (Line-Of 'LsC.pas' '    procedure Bare(pZ: Integer);')) $q.Raw
  $q = Param-Plan 'LsC.pas' (Line-Of 'LsC.pas' 'procedure TA.Grp(pG: Integer; pH: Integer);') 18 'pQ'
  Check 's5 grouped and ungrouped lists match' ($q.Lines -contains (Line-Of 'LsC.pas' '    procedure Grp(pG, pH: Integer);')) $q.Raw

  Write-Host '--kind param on a non-ASCII line: character columns' -ForegroundColor Cyan
  foreach ($u in @(@{ N = 'LsE8.pas'; Enc = [Text.Encoding]::UTF8 }, @{ N = 'LsEA.pas'; Enc = $Ansi })) {
    $f = Join-Path $Src $u.N
    $decl = 0; $i = 0
    foreach ($l in ([IO.File]::ReadAllText($f, $u.Enc) -split "`r`n")) { $i++; if ($l -match 'R: Integer;') { $decl = $i } }
    $q = Param-Plan $u.N $decl 7 'ARect'
    Check "b1 $($u.N) plan by character column: 4 edits, 0 undecided" ($q.Json -and @($q.Json.edits).Count -eq 4 -and @($q.Json.refusals).Count -eq 0) $q.Raw
    $cols = @($q.Json.edits | Where-Object { [int]$_.line -eq $decl } | ForEach-Object { [int]$_.col })
    Check "b1 $($u.N) the column is the character's" ($cols.Count -eq 1 -and $cols[0] -eq 7) $q.Raw
    $q2 = Param-Plan $u.N $decl 8 'ARect'
    Check "b2 $($u.N) the byte column finds it too (a lint finding's)" ($q2.Json -and @($q2.Json.edits).Count -eq 4) $q2.Raw
    $before = [IO.File]::ReadAllBytes($f)[0..2] -join ','
    $r = Run-Engine @('rename', '--kind', 'param', '--in', $f, '--line', "$decl", '--col', '7', '--to', 'ARect', '--db', $Db, '--apply')
    $after = [IO.File]::ReadAllText($f, $u.Enc)
    Check "b3 $($u.N) applies, exit 0" ($r.Exit -eq 0) $r.Out
    $mark = "{$Umlaut}"
    Check "b3 $($u.N) every site rewritten" ($after.Contains("$mark ARect: Integer;") -and $after.Contains("$mark ARect:= 1; Inc(ARect);") -and $after.Contains("$mark with N do ARect:= 2;")) $after
    Check "b3 $($u.N) encoding kept" ((([IO.File]::ReadAllBytes($f)[0..2]) -join ',') -eq $before)
  }
} finally { Pop-Location }
Write-Host ("run_rename_local_scope: {0} pass, {1} fail" -f $script:Passed, $script:FailCount)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
