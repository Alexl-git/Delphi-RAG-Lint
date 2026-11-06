<#
  run_rename_local_scope.ps1 -- E-RENAME-LOCAL-REFUSED (wave 146): a symbol declared inside a routine is proved inside
  that routine, in every form of the verb.

  A local's scope is its routine: no other unit can name it or capture the new name. 1.44.1 read every unit, so a
  same-named bare ref elsewhere refused the rename through --kind symbol and --qname (the IDE's form), and --apply
  wrote nothing after a preview that exited 0.

  POSITIVE CONTROLS: l4 and l8 (a real capture and an include inside the routine still refuse, so the scope did not
  blind the proof); l9 (a unit-level symbol still answers for the other unit's bare ref, so the scope is not blanket).
  RED on 1.44.1-alpha: l1 and l2 refuse on LsB, l5 misses the implementation header, l7 refuses shadowed-at-site.
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
function Reset-Fx {
  foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $Src $k), (Crlf $Files[$k]), $Ascii) }
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
} finally { Pop-Location }
Write-Host ("run_rename_local_scope: {0} pass, {1} fail" -f $script:Passed, $script:FailCount)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
