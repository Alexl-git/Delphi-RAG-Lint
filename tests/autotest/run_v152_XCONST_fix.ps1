<#
  run_v152_XCONST_fix.ps1 -- 1.52 lane XCONST (ruling B4 part 2, PLAN D6): the MANUAL "extract constant" fix.

  `lint --fix --fix-rule <id> --fix-line <n> [--col <c>] [--name <ident>] [--apply]` on a literal flagged by
  magic-literal / large-magic-number / case-magic-numbers, or on ANY number / string literal through the
  on-demand rule extract-constant (the IDE's "Extract Constant (literal at cursor)"), declares ONE named constant
  in the unit and replaces every occurrence of that literal token, except inside other const declarations,
  attributes, uses clauses, and contexts of a different declared TYPE -- those are left and listed on stderr.

  Fixture: tests\fixtures\refactor\gatefix (GfDemo.dproj) with GfUnit.pas REPLACED by the unit below, written per
  case into a temp copy (nothing under tests\fixtures is edited).
    a  number, --name, --apply, --compile-gate: 2 occurrences replaced, the Double and the Word case-label
       occurrences left and listed, the const decl left, const placed in the implementation, project builds.
    b  string through extract-constant + --col, --apply, --compile-gate: 3 occurrences replaced, project builds.
    c  no --name: the plan proposes cCount5000 and shows it; preview writes nothing.
    d  name clash: --name Count is REFUSED, bytes identical. Positive control = a (a fresh name applies).
    e  interface placement: a literal used in an interface default parameter goes into the interface section.
    f  manual only: a batch --fix (no --fix-rule) writes nothing for these rules and says so; control = a.
    g  catalog: rules --json lists extract-constant (OFF by default) and the four ids as fixable + manual only.
  Needs dcc for a / b / e: SKIPs those builds when rsvars.bat is missing. RED: run against the 1.51.x engine.
#>
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Continue'  # the engine's stderr banner must not terminate; every call is checked by exit code
$script:Failed = $false
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$HaveDcc = Test-Path $Rsvars
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\gatefix").Path
$Tmp = Join-Path $env:TEMP ('xconst_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

$UnitText = @'
unit GfUnit;

interface

procedure RunAll;
procedure Take(A: Integer = 4242);

implementation

uses
  System.SysUtils;

const
  cOther = 5000;

var
  Count: Integer;
  Ratio: Double;
  Wide : Word;
  Title: string;

procedure Take(A: Integer);
begin
  Count:= A + 4242; { xc-iface }
end;

procedure RunAll;
begin
  Count:= 5000; { xc-num }
  if Count > 5000 then Count:= 0; { xc-num2 }
  Ratio:= 5000; { xc-double }
  Wide:= 7;
  case Wide of
    5000: Count:= 1; { xc-word }
  end;
  Title:= 'hello big world'; { xc-str }
  if Title = 'hello big world' then Writeln(Title);
  Writeln('hello big world' + 'x');
  Writeln(Count, Ratio, cOther);
  Take;
end;

end.
'@ -replace "`r?`n", "`r`n"

function New-Case([string]$Tag) {
  $d = Join-Path $Tmp $Tag
  Copy-Item $Fx $d -Recurse
  [IO.File]::WriteAllText((Join-Path $d 'GfUnit.pas'), $UnitText, [Text.Encoding]::ASCII)
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'GfDemo.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'GfDemo.dproj'); Unit = (Join-Path $d 'GfUnit.pas') }
}
function LineNo([string]$Marker) {
  $ls = $UnitText -split "`r`n"
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains($Marker)) { return $i + 1 } }
  throw "marker $Marker not found"
}
function Fix($C, [string]$Rule, [int]$Line, [string[]]$Extra) {
  $a = @('lint', '--in', $C.Unit, '--db', $C.Db, '--enable', $Rule, '--fix', '--fix-rule', $Rule, '--fix-line', "$Line", '--no-backup', '--rsvars', $Rsvars) + $Extra
  $out = & $Exe @a 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Hash($p) { return (Get-FileHash $p -Algorithm SHA1).Hash }
function Lines($p) { return [IO.File]::ReadAllLines($p) }
function MarkLine($p, [string]$m) { foreach ($l in (Lines $p)) { if ($l.Contains($m)) { return $l.Trim() } }; return '' }
function CountOf($p, [string]$s) { return ([regex]::Matches([IO.File]::ReadAllText($p), [regex]::Escape($s))).Count }
function Build($C) {
  if (-not $HaveDcc) { Write-Host '  skip build (no rsvars.bat)' -ForegroundColor Yellow; return 0 }
  $bat = Join-Path $C.Dir 'b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /D `"$($C.Dir)`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal GfDemo.dproj`r`n", [Text.Encoding]::ASCII)
  $p = Start-Process -Wait -PassThru -NoNewWindow -FilePath cmd.exe -ArgumentList '/c', $bat -RedirectStandardOutput (Join-Path $C.Dir 'b.out')
  return $p.ExitCode
}
$Gate = if ($HaveDcc) { @('--compile-gate') } else { @('--no-compile-gate') }
$LNum = LineNo 'xc-num'; $LNum2 = LineNo 'xc-num2'; $LDbl = LineNo 'xc-double'; $LWord = LineNo 'xc-word'
$LStr = LineNo 'xc-str'; $LIface = LineNo 'xc-iface'
try {
  # a: number literal, explicit name, applied through the compile gate
  $A = New-Case 'a'
  $r = Fix $A 'magic-literal' $LNum (@('--name', 'cMaxCount', '--apply', '--project', $A.Proj) + $Gate)
  Write-Host ($r.Out.Trim() -split "`r?`n" | Select-String 'extract-constant' | Out-String)
  Check 'a1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'a2 one const declared' ((CountOf $A.Unit 'cMaxCount = 5000;') -eq 1) ([IO.File]::ReadAllText($A.Unit))
  Check 'a3 target line uses the const' ((MarkLine $A.Unit 'xc-num }') -like 'Count:= cMaxCount;*') (MarkLine $A.Unit 'xc-num }')
  Check 'a4 second occurrence replaced' ((MarkLine $A.Unit 'xc-num2') -like 'if Count > cMaxCount then*') (MarkLine $A.Unit 'xc-num2')
  Check 'a5 Double context left' ((MarkLine $A.Unit 'xc-double') -like 'Ratio:= 5000;*') (MarkLine $A.Unit 'xc-double')
  Check 'a6 Word case label left' ((MarkLine $A.Unit 'xc-word') -like '5000: Count:= 1;*') (MarkLine $A.Unit 'xc-word')
  Check 'a7 const decl left' ((CountOf $A.Unit 'cOther = 5000;') -eq 1)
  Check 'a8 N replaced reported' ($r.Out -match 'cMaxCount = 5000 .*2 occurrence\(s\) replaced, 3 left') $r.Out
  Check 'a9 Double occurrence listed' ($r.Out -match "left .*GfUnit\.pas:$($LDbl):\d+ .*Double") $r.Out
  Check 'a10 Word occurrence listed' ($r.Out -match "left .*GfUnit\.pas:$($LWord):\d+ .*Word") $r.Out
  $ls = Lines $A.Unit
  $impl = [array]::IndexOf($ls, 'implementation'); $decl = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match '^\s*cMaxCount = 5000;') { $decl = $i } }
  Check 'a11 placed in the implementation' (($impl -ge 0) -and ($decl -gt $impl)) "impl=$impl decl=$decl"
  Check 'a12 no gate refusal' ($r.Out -cnotmatch 'REFUSED') $r.Out
  Check 'a13 written project builds' ((Build $A) -eq 0)

  # b: string literal through the on-demand rule extract-constant, caret column given
  $B = New-Case 'b'
  $col = (($UnitText -split "`r`n")[$LStr - 1]).IndexOf("'") + 1
  $r = Fix $B 'extract-constant' $LStr (@('--col', "$col", '--name', 'sGreeting', '--apply', '--project', $B.Proj) + $Gate)
  Write-Host ($r.Out.Trim() -split "`r?`n" | Select-String 'extract-constant' | Out-String)
  Check 'b1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  # positive-control: extract-constant
  Check 'b2 one const declared' ((CountOf $B.Unit "sGreeting = 'hello big world';") -eq 1) ([IO.File]::ReadAllText($B.Unit))
  Check 'b3 every occurrence replaced' ((CountOf $B.Unit "'hello big world'") -eq 1) ([IO.File]::ReadAllText($B.Unit))
  Check 'b4 3 replaced reported' ($r.Out -match '3 occurrence\(s\) replaced') $r.Out
  Check 'b5 written project builds' ((Build $B) -eq 0)

  # c: no --name -- the plan proposes a name and shows it; a preview writes nothing
  $Cc = New-Case 'c'; $hc = Hash $Cc.Unit
  $r = Fix $Cc 'magic-literal' $LNum @()
  Check 'c1 proposal shown' ($r.Out -match 'name cCount5000 = 5000 \(proposed') $r.Out
  Check 'c2 plan shows the const line' ($r.Out -match 'cCount5000 = 5000;') $r.Out
  Check 'c3 preview wrote nothing' ((Hash $Cc.Unit) -eq $hc)

  # d: a name that clashes with an identifier of the unit is refused
  $D = New-Case 'd'; $hd = Hash $D.Unit
  $r = Fix $D 'magic-literal' $LNum @('--name', 'Count', '--apply')
  Check 'd1 clash REFUSED' ($r.Out -match "extract-constant: REFUSED .*'Count'.*clashes") $r.Out
  Check 'd2 bytes identical' ((Hash $D.Unit) -eq $hd)

  # e: an occurrence in the interface (default parameter) puts the const in the interface
  $E = New-Case 'e'
  $r = Fix $E 'magic-literal' $LIface (@('--name', 'cDefaultTake', '--apply', '--project', $E.Proj) + $Gate)
  Check 'e1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  $ls = Lines $E.Unit
  $iface = [array]::IndexOf($ls, 'interface'); $impl = [array]::IndexOf($ls, 'implementation'); $decl = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match '^\s*cDefaultTake = 4242;') { $decl = $i } }
  Check 'e2 placed in the interface' (($decl -gt $iface) -and ($decl -lt $impl)) "iface=$iface decl=$decl impl=$impl"
  Check 'e3 default parameter replaced' ((CountOf $E.Unit 'A: Integer = cDefaultTake') -eq 1) ([IO.File]::ReadAllText($E.Unit))
  Check 'e4 written project builds' ((Build $E) -eq 0)

  # f: manual only -- a batch --fix (no --fix-rule) leaves the file alone and says why
  $F = New-Case 'f'; $hf = Hash $F.Unit
  $r = & $Exe lint --in $F.Unit --db $F.Db --enable magic-literal --fix --apply --no-backup --no-compile-gate 2>&1 | Out-String
  Check 'f1 batch withholds the manual fix' ($r -match 'manual only fix.*magic-literal') $r
  Check 'f2 batch wrote no constant' ((CountOf $F.Unit 'cCount5000') -eq 0)

  # g: catalog
  $j = (& $Exe rules --json 2>$null | Out-String | ConvertFrom-Json).rules
  $xc = $j | Where-Object { $_.id -eq 'extract-constant' }
  Check 'g1 extract-constant declared' ($null -ne $xc)
  Check 'g2 extract-constant OFF by default' (($null -ne $xc) -and (-not $xc.default_enabled))
  foreach ($id in 'extract-constant', 'magic-literal', 'large-magic-number', 'case-magic-numbers') {
    $row = $j | Where-Object { $_.id -eq $id }
    Check "g3 $id fixable + manual only" (($null -ne $row) -and $row.fixable -and $row.fix_manual_only) ($row | ConvertTo-Json -Compress)
  }
  # g4 positive control for g3: a rule without this fix is not reported fixable
  $ctl = $j | Where-Object { $_.id -eq 'address-of-local-returned' }
  Check 'g4 control: unrelated rule not manual only' (($null -ne $ctl) -and (-not $ctl.fix_manual_only))
}
finally { try { [IO.Directory]::Delete($Tmp, $true) } catch { } }
if ($script:Failed) { Write-Host "run_v152_XCONST_fix: FAILED ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_XCONST_fix: PASS ($script:Passed checks)"
