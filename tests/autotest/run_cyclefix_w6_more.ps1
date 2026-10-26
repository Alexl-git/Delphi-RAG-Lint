<#
  run_cyclefix_w6_more.ps1 -- plan docs\superpowers\plans\2026-10-25-cycles-fix-refusal-recipes.md, lane CYCC: the
  W6 items run_cyclefix_w6_rest.ps1 left open. One fixture variant per case, each refused before the item, each with
  a CONTROL that stays refused.

  (C6) the declaration block header
    c6d an indented `var` header (`  var` / `    GTieC1: ...`) on tiebreak: mechanical. CONTROL: a header at the SAME
        indent as its declarations is still not recognised.
    c6e the same-line form `var GTieC1: Integer = 2;` on tiebreak: mechanical; the keyword stays (or goes with an
        emptied block), the declaration moves. CONTROL: `var X: Integer; GTieC1: ...` (two declarations on the
        keyword line) still refuses.

  (C2) duplicate-identifier on R2 (r2extend)
    c2d the leaf declares exactly the interface the plan emits: reused, nothing inserted; mechanical.
    c2e the leaf declares I<Class>Surface differently: IDemoGagePortSurface2 names the interface; mechanical.
    c2f the class declares `function GetLog: TStrings;` and `property Log ... read GetLog`: the getter is reused.
        CONTROLS: c2g the same GetLog but the property reads FLog; c2h GetLog with another signature -- both still
        refuse duplicate-identifier.
  Accepted cases are followed, re-indexed (no cycle left) and, with RAD Studio, built (dcc).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-w6m-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Only      = ''   # a regex over the section tags (c6, c2, c7i ...); '' = every section
)
function Want([string]$Tag) { return ($Only -eq '') -or ($Tag -match $Only) }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $Old = $Old -replace "`r?`n", "`r`n"
  if (-not $t.Contains($Old)) { throw "fixture edit: text not found in ${Path}: $Old" }
  Set-Text $Path $t.Replace($Old, ($New -replace "`r?`n", "`r`n"))
}

# Copies a fixture, applies pEdit (scriptblock taking the case root), indexes, plans cycle 1 against the library copy.
# Returns the dump fields, the plan text and the case root.
function Get-Plan([string]$Fixture, [string]$Dproj, [string]$Tag, [scriptblock]$Edit) {
  $root = Join-Path $WorkDir $Tag
  Copy-Tree (Join-Path $Fx $Fixture) $root
  if ($Edit) { & $Edit $root }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $null | & $Exe index --project (Join-Path $root $Dproj) --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  } finally { $env:DRAGLINT_TEST_DUMP_PLAN = $null }
  $verdict = ''; $refusals = ''
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $h = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $h[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($h['cycle'] -eq '1') { $verdict = $h['verdict']; $refusals = $h['refusals'] }
    }
  }
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o); Verdict = $verdict; Refusals = $refusals; Root = $root; Out = $o; Dproj = (Join-Path $root $Dproj) }
}
# Applies cycle 1 of a plan with the follower, re-indexes, returns the text `cycles` prints on the result.
function Invoke-FollowAndCycles($Pl, [string]$Tag) {
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $Pl.Out -Cycle 1 2>&1 | Out-String
  $db = Join-Path $WorkDir "after-$Tag.sqlite"
  $null | & $Exe index --project $Pl.Dproj --db $db *> (Join-Path $WorkDir "index-after-$Tag.log")
  $o = & $Exe cycles --db $db | Out-String
  return @{ Follow = $LASTEXITCODE; Text = $fo; Cycles = $o }
}
function Test-Mechanical( [string]$Tag, $Pl, [string]$Kind) {
  Check "$Tag m0 planned (exit 0)" ($Pl.Exit -eq 0) "exit=$($Pl.Exit)"
  Check "$Tag m1 no refused: $Kind" (-not $Pl.Text.Contains("refused: $Kind")) ([regex]::Match($Pl.Text, "(?m)^.*refused: $Kind.*$").Value)
  Check "$Tag m2 verdict mechanical" ($Pl.Verdict -eq 'mechanical') "[$($Pl.Verdict) / $($Pl.Refusals)]"
}
function Test-Refused([string]$Tag, $Pl, [string]$Kind) {
  Check "$Tag r0 planned (exit 0)" ($Pl.Exit -eq 0) "exit=$($Pl.Exit)"
  Check "$Tag r1 refused: $Kind" ($Pl.Text.Contains("refused: $Kind") -and (($Pl.Refusals -split ',') -contains $Kind)) "[$($Pl.Verdict) / $($Pl.Refusals)]"
}

$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { $RsVars = $null }

# msbuild of pRoot\pDproj (Win64 Debug) after a follow: one check, BUILD_EXITCODE=0 and no error E / fatal F.
function Test-Builds([string]$Root, [string]$Dproj, [string]$Tag) {
  $bat = Join-Path $WorkDir "build-$Tag.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f (Join-Path $Root $Dproj), $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  Check "$Tag the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" (($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0)) ($errors -join ' | ')
}
# Mechanical, followed, no cycle left, and (with RAD Studio) the followed copy compiles.
function Test-Accepted([string]$Tag, $Pl, [string]$Kind) {
  Test-Mechanical $Tag $Pl $Kind
  $run = Invoke-FollowAndCycles $Pl $Tag
  Check "$Tag followed (exit 0) and no cycle remains" (($run.Follow -eq 0) -and $run.Cycles.Contains('No circular unit dependencies found.')) ($run.Text.Trim() -replace "`r?`n", ' | ')
  if ($RsVars) { Test-Builds $Pl.Root (Split-Path $Pl.Dproj -Leaf) $Tag }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  # every candidate edge of tiebreak moves a global out of a `type` / `var` block, so each unit gets the same header
  # shape -- whichever edge the planner picks meets it.
  $tieUnits = 'TieA.pas', 'TieB.pas', 'TieC.pas'
  $indentAll = { param($r, [string]$HeaderPad, [string]$DeclPad)
    foreach ($u in $tieUnits) {
      $f = Join-Path $r $u; $t = [IO.File]::ReadAllText($f)
      $t = [regex]::Replace($t, '(?m)^(type|var)\r\n((?:  .*\r\n)+)', {
          param($m) $HeaderPad + $m.Groups[1].Value + "`r`n" + (($m.Groups[2].Value -split "`r`n" | Where-Object { $_ -ne '' } |
            ForEach-Object { $DeclPad + $_ }) -join "`r`n") + "`r`n" })
      Set-Text $f $t } }
  $sameLineAll = { param($r, [string]$Lead)
    foreach ($u in $tieUnits) {
      $f = Join-Path $r $u; $t = [IO.File]::ReadAllText($f)
      $t = [regex]::Replace($t, '(?m)^(type|var)\r\n  ///.*\r\n  (\w+)', {
          param($m) $m.Groups[1].Value + ' ' + ($Lead -f $m.Groups[2].Value) + $m.Groups[2].Value })
      Set-Text $f $t } }

  if (Want 'c6') {
  Write-Host '== (c6d) an indented type / var header' -ForegroundColor Cyan
  $c6d = Get-Plan 'tiebreak' 'TieBreak.dproj' 'c6d-indent' { param($r) & $indentAll $r '  ' '  ' }
  Test-Accepted 'c6d-indent' $c6d 'manual-edit'
  Check 'c6d-indent the plan names no unrecognised block' (-not $c6d.Text.Contains('was not recognised')) ''
  $c6dBad = Get-Plan 'tiebreak' 'TieBreak.dproj' 'c6d-same' { param($r) & $indentAll $r '  ' '' }
  Check 'c6d-same (header at the declarations'' indent) still not recognised' ($c6dBad.Verdict -ne 'mechanical' -and $c6dBad.Text.Contains('was not recognised')) "[$($c6dBad.Verdict) / $($c6dBad.Refusals)]"

  Write-Host '== (c6e) the same-line form `var X: T = v;` / `type TX = ...`' -ForegroundColor Cyan
  $c6e = Get-Plan 'tiebreak' 'TieBreak.dproj' 'c6e-sameline' { param($r) & $sameLineAll $r '' }
  Test-Accepted 'c6e-sameline' $c6e 'manual-edit'
  Check 'c6e-sameline the leaf declares the moved global under its own keyword line' ($c6e.Text -match '(?m)^(var|type)\r?\n  (GTie\w+: Integer = \d;|TTieARec = record)') ''
  $left = (Get-ChildItem $c6e.Root -Filter 'Tie?.pas' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
  Check 'c6e-sameline no unit keeps an emptied keyword line' (-not ($left -match '(?m)^(var|type)\s*\r?\n\s*\r?\n(/// <summary>Prints|procedure)')) ''
  $c6eKeep = Get-Plan 'tiebreak' 'TieBreak.dproj' 'c6e-keep' { param($r)
    & $sameLineAll $r ''
    foreach ($u in $tieUnits) {
      $f = Join-Path $r $u; $t = [IO.File]::ReadAllText($f)
      $stay = "  /// <summary>Stays.</summary>`r`n  G$($u.Substring(0, 4))Stay: Integer = 4;`r`n`r`n"
      Set-Text $f ([regex]::new('(?m)^(?=/// <summary>Prints)').Replace($t, $stay, 1)) } }
  Test-Accepted 'c6e-keep' $c6eKeep 'manual-edit'
  $kept = (Get-ChildItem $c6eKeep.Root -Filter 'Tie?.pas' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
  Check 'c6e-keep a keyword line stays above the global that remains' ($kept -match '(?m)^var\r?\n(\s*\r?\n)?  /// <summary>Stays.</summary>') ''
  $c6eBad = Get-Plan 'tiebreak' 'TieBreak.dproj' 'c6e-two' { param($r) & $sameLineAll $r '{0}X: Integer; ' }
  Check 'c6e-two (two declarations on the keyword line) still refused' ($c6eBad.Verdict -ne 'mechanical' -and $c6eBad.Text.Contains('was not recognised')) "[$($c6eBad.Verdict) / $($c6eBad.Refusals)]"
  }
  if (Want 'c2') {
  Write-Host '== (c2d) R2: the leaf already declares the very interface the plan emits' -ForegroundColor Cyan
  $clean = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2-clean' $null
  $iface = [regex]::Match($clean.Text, '(?ms)^  IDemoGagePortSurface = interface\r?\n.*?^  end;').Value
  Check 'c2-clean the plan emits IDemoGagePortSurface (the text c2d copies)' ($iface -ne '') ''
  $c2d = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2d-same' { param($r)
    $f = Join-Path $r 'DemoGagePort.Untangle.pas'
    Edit-File $f "interface`n`ntype" "interface`n`nuses`n  System.Classes;`n`ntype"
    Edit-File $f '  TDemoGageUnit = (guMillimetre, guInch);' ("  TDemoGageUnit = (guMillimetre, guInch);`n`n  /// <summary>Declared already.</summary>`n" + $iface) }
  Test-Accepted 'c2d-same' $c2d 'duplicate-identifier'
  Check 'c2d-same the plan says the interface is reused' $c2d.Text.Contains('already declares the interface `IDemoGagePortSurface`') ''
  $leafD = [IO.File]::ReadAllText((Join-Path $c2d.Root 'DemoGagePort.Untangle.pas'))
  Check 'c2d-same the leaf still declares it exactly once' ([regex]::Matches($leafD, 'IDemoGagePortSurface = interface').Count -eq 1) ''

  Write-Host '== (c2e) R2: the leaf declares I<Class>Surface differently -> the lowest free suffix' -ForegroundColor Cyan
  $c2e = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2e-diff' { param($r)
    Edit-File (Join-Path $r 'DemoGagePort.Untangle.pas') '  TDemoGageUnit = (guMillimetre, guInch);' "  TDemoGageUnit = (guMillimetre, guInch);`n`n  /// <summary>Another interface of that name.</summary>`n  IDemoGagePortSurface = interface`n  end;" }
  Test-Accepted 'c2e-diff' $c2e 'duplicate-identifier'
  $gpE = [IO.File]::ReadAllText((Join-Path $c2e.Root 'DemoGagePort.pas'))
  $uiE = [IO.File]::ReadAllText((Join-Path $c2e.Root 'DemoUIConnect.pas'))
  Check 'c2e-diff IDemoGagePortSurface2 is declared, implemented and cast to' ($c2e.Text.Contains('  IDemoGagePortSurface2 = interface') -and
    $gpE.Contains('class(TComponent, IDemoGagePortSurface2)') -and $uiE.Contains('as IDemoGagePortSurface2')) ''

  Write-Host '== (c2f) R2: the class has Get<M> already, exactly `function GetLog: TStrings;`, read by the property' -ForegroundColor Cyan
  $getLog = { param($r, [string]$Decl, [string]$Prop)
    $g = Join-Path $r 'DemoGagePort.pas'
    Edit-File $g '    FLastGage: Integer;' "    FLastGage: Integer;`n    $Decl"
    Edit-File $g '    property Log: TStrings read FLog;' "    property Log: TStrings read $Prop;"
    Edit-File $g "constructor TDemoGagePort.Create(pOwner: TComponent);" ("function TDemoGagePort." + ($Decl -replace '^function ', '') + "`nbegin`n  Result := FLog;`nend;`n`nconstructor TDemoGagePort.Create(pOwner: TComponent);") }
  $c2f = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2f-getter' { param($r) & $getLog $r 'function GetLog: TStrings;' 'GetLog' }
  Test-Accepted 'c2f-getter' $c2f 'duplicate-identifier'
  $gpF = [IO.File]::ReadAllText((Join-Path $c2f.Root 'DemoGagePort.pas'))
  Check 'c2f-getter the class keeps ONE GetLog (declaration and body), GetLastGage is added' (([regex]::Matches($gpF, '(?m)^\s*function (TDemoGagePort\.)?GetLog\b').Count -eq 2) -and
    $gpF.Contains('function TDemoGagePort.GetLastGage: Integer;')) ''
  $c2g = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2g-notread' { param($r) & $getLog $r 'function GetLog: TStrings;' 'FLog' }
  Test-Refused 'c2g-notread (the property reads FLog, not GetLog)' $c2g 'duplicate-identifier'
  $c2h = Get-Plan 'r2extend' 'R2Extend.dproj' 'c2h-sig' { param($r) & $getLog $r 'function GetLog(pIndex: Integer = 0): TStrings;' 'FLog' }
  Test-Refused 'c2h-sig (another signature)' $c2h 'duplicate-identifier'
  }
  if (Want 'c7i') {
  Write-Host '== (c7i) member-unsupported: an indexed property read through the interface' -ForegroundColor Cyan
  $indexed = { param($r, [string]$PropTail, [string]$Use)
    $g = Join-Path $r 'DemoGagePort.pas'
    Edit-File $g '    FLastGage: Integer;' "    FLastGage: Integer;`n    function GetLine(pIndex: Integer): string;"
    Edit-File $g '    property LastGage: Integer read FLastGage;' "    property LastGage: Integer read FLastGage;`n    /// <summary>One log line.</summary>`n    property Lines[pIndex: Integer]: string read GetLine$PropTail;"
    Edit-File $g "constructor TDemoGagePort.Create(pOwner: TComponent);" "function TDemoGagePort.GetLine(pIndex: Integer): string;`nbegin`n  Result := FLog[pIndex];`nend;`n`nconstructor TDemoGagePort.Create(pOwner: TComponent);"
    Edit-File (Join-Path $r 'DemoUIConnect.pas') "    Log.Add(Format('gage now %d', [LastGage]));" "    Log.Add(Format('gage now %d', [LastGage]));`n$Use" }
  $c7i = Get-Plan 'r2extend' 'R2Extend.dproj' 'c7i-indexed' { param($r) & $indexed $r '' "    Log.Add('first ' + Lines[0]);" }
  Test-Accepted 'c7i-indexed' $c7i 'member-unsupported'
  Check 'c7i-indexed the interface declares the indexed property and its getter verbatim' ($c7i.Text.Contains('    function GetLines(pIndex: Integer): string;') -and
    $c7i.Text.Contains('    property Lines[pIndex: Integer]: string read GetLines;') -and $c7i.Text.Contains('  Result := Lines[pIndex];')) ''
  $c7iDef = Get-Plan 'r2extend' 'R2Extend.dproj' 'c7i-default' { param($r) & $indexed $r '; default' "    Log.Add('first ' + Lines[0]);" }
  Test-Refused 'c7i-default (a default array property)' $c7iDef 'member-unsupported'
  $c7iW = Get-Plan 'r2extend' 'R2Extend.dproj' 'c7i-write' { param($r)
    & $indexed $r '' "    Log.Add('first ' + Lines[0]);"
    $g = Join-Path $r 'DemoGagePort.pas'
    Edit-File $g "    function GetLine(pIndex: Integer): string;" "    function GetLine(pIndex: Integer): string;`n    procedure SetLine(pIndex: Integer; const pValue: string);"
    Edit-File $g "string read GetLine;" "string read GetLine write SetLine;"
    Edit-File $g "constructor TDemoGagePort.Create(pOwner: TComponent);" "procedure TDemoGagePort.SetLine(pIndex: Integer; const pValue: string);`nbegin`n  FLog[pIndex] := pValue;`nend;`n`nconstructor TDemoGagePort.Create(pOwner: TComponent);"
    Edit-File (Join-Path $r 'DemoUIConnect.pas') "    Log.Add('first ' + Lines[0]);" "    Lines[0] := 'x';" }
  Check 'c7i-write (a write to the indexed property) is never mechanical' ($c7iW.Verdict -ne 'mechanical') "[$($c7iW.Verdict) / $($c7iW.Refusals)]"
  }
  if (Want 'lbl') {
  Write-Host '== (lbl) a refusal is labelled with the kind of the symbol it names, not of the first need' -ForegroundColor Cyan
  $lbl = Get-Plan 'sigincyclelabel' 'R1Extend.dproj' 'lbl-record' $null
  Test-Refused 'lbl-record' $lbl 'signature-in-cycle'
  Check 'lbl-record the refusal names `TR1TitleKind` (record), not (var)' ($lbl.Text.Contains('`TR1TitleKind` (record): refused: signature-in-cycle') -and
    -not $lbl.Text.Contains('`TR1TitleKind` (var)')) ([regex]::Match($lbl.Text, '(?m)^.*refused: signature-in-cycle.*$').Value) }
  if (Want 'b4f') {
  Write-Host '== (b4f) Part B: a class handed over through a base class (implementation edge)' -ForegroundColor Cyan
  $b4f = Get-Plan 'b4fbase' 'B4fBase.dproj' 'b4f-base' $null
  Test-Accepted 'b4f-base' $b4f 'base-class'
  Check 'b4f-base TBfShapeBase carries Name; `is` and `(X as ...)` switch to it' ($b4f.Text.Contains('TBfShape = class(TBfShapeBase)') -and
    $b4f.Text.Contains('if pShape is TBfShapeBase then') -and $b4f.Text.Contains('(pShape as TBfShapeBase).Name')) ''
  $b4fCast = Get-Plan 'b4fbase' 'B4fBase.dproj' 'b4f-cast' { param($r)
    Edit-File (Join-Path $r 'BfCanvas.pas') "    Writeln('paint ', (pShape as TBfShape).Name, ' style ', pStyle);" "    Writeln('paint ', TBfShape(pShape).Name, ' style ', pStyle);" }
  Check 'b4f-cast (a hard cast) refused, naming the site BfCanvas.pas:31' (($b4fCast.Verdict -ne 'mechanical') -and
    $b4fCast.Text.Contains('through a base class: `TBfShape` (class): refused: base-class -- `BfCanvas.pas:31`')) "[$($b4fCast.Verdict) / $($b4fCast.Refusals)]"
 }
  if (Want 'na') {
  Write-Host '== (na) non-ascii-text: a new unit holding cp1252 text copied from the sources compiles (UTF-8 + BOM)' -ForegroundColor Cyan
  $naRoot = Join-Path $WorkDir 'na-tie'
  Copy-Tree (Join-Path $Fx 'tiebreak') $naRoot
  foreach ($u in 'TieA.pas', 'TieB.pas', 'TieC.pas') {
    $f = Join-Path $naRoot $u
    $b = [IO.File]::ReadAllBytes($f); $s = [Text.Encoding]::GetEncoding(28591).GetString($b)
    [IO.File]::WriteAllBytes($f, [Text.Encoding]::GetEncoding(28591).GetBytes($s.Replace('<summary>Read', "<summary>Gr$([char]0xF6)$([char]0xDF)e: read"))) }
  $naDb = Join-Path $WorkDir 'na.sqlite'
  $null | & $Exe index --project (Join-Path $naRoot 'TieBreak.dproj') --db $naDb *> (Join-Path $WorkDir 'index-na.log')
  $naOut = & $Exe cycles --fix --project (Join-Path $naRoot 'TieBreak.dproj') --db $naDb --library-db none --format json 2>&1 | Out-String
  $naCode = $LASTEXITCODE
  Check 'na the dry run (it BUILDS the shadow tree) is exit 0 with no non-ascii-text refusal' (($naCode -eq 0) -and -not $naOut.Contains('non-ascii-text')) ("exit=$naCode " + ($naOut.Trim() -replace "`r?`n", ' '))
 }
  if ((Want 'rsv') -and $RsVars) {
  Write-Host '== (rsv) no-compiler: --rsvars names the Studio build environment the registry / BDS does not' -ForegroundColor Cyan
  $rsRoot = Join-Path $WorkDir 'rsv-tie'
  Copy-Tree (Join-Path $Fx 'tiebreak') $rsRoot
  $rsDb = Join-Path $WorkDir 'rsv.sqlite'
  $null | & $Exe index --project (Join-Path $rsRoot 'TieBreak.dproj') --db $rsDb *> (Join-Path $WorkDir 'index-rsv.log')
  $fixArgs = @('cycles', '--fix', '--project', (Join-Path $rsRoot 'TieBreak.dproj'), '--db', $rsDb, '--library-db', 'none', '--format', 'json')
  $savedBds = $env:BDS
  try {
    $env:BDS = Join-Path $WorkDir 'no-studio-here'   # TStudioEnv takes the root from BDS first: a root without rsvars.bat
    $o0 = & $Exe @fixArgs 2>&1 | Out-String; $c0 = $LASTEXITCODE
    Check 'rsv-control without --rsvars: refused no-compiler' ($o0.Contains('no-compiler')) "exit=$c0"
    $o1 = & $Exe @fixArgs --rsvars $RsVars 2>&1 | Out-String; $c1 = $LASTEXITCODE
    Check 'rsv with --rsvars <real rsvars.bat>: exit 0, built, no no-compiler refusal' (($c1 -eq 0) -and -not $o1.Contains('no-compiler')) "exit=$c1"
    $o2 = & $Exe @fixArgs --rsvars (Join-Path $WorkDir 'missing\rsvars.bat') 2>&1 | Out-String; $c2 = $LASTEXITCODE
    Check 'rsv-missing --rsvars <no such file>: exit 2, named' (($c2 -eq 2) -and $o2.Contains('--rsvars: no such file')) "exit=$c2"
  } finally { $env:BDS = $savedBds }
  }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
