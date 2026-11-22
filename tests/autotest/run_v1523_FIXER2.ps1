<#
  run_v1523_FIXER2.ps1 -- two autofix defects the SLZ lint-to-zero lanes hit on DL's own source
  (C:\TEMP\claude\lanes\v1523\SLZ\RULE-FP.tsv, SLZ-S07 REPORT):
    A. multiple-statements-per-line --fix split a line only ONCE: `if C then begin A; B; end;` became
       `if C then begin A;` + `B; end;` (SLZ-S07 re-laid out 98 sites by script, f5f0165a2; SLZ-S04
       needed three passes). One pass must put every statement on its own line, begin/end laid out.
    B. pos-for-contains --fix rewrote the UNSAFE shapes (a variable needle, and Pos('', S) = 0 into
       `not S.Contains('')`, which is never True) and declined every literal needle whose haystack was
       a member or a call (all 55 sites in src\doc + src\report). Pos('', S) = 0 but S.Contains('')
       is True, so only a NON-EMPTY literal needle is the same test.
  Each fixture is the exact failing statement shape; the fixed unit must COMPILE (dcc32), the unsafe
  shapes must be left as written, and the rewritten lines are named exactly (a fixer switched off
  fails those positive checks).

  -Exe defaults to the worktree build; pass the 1.52.2 / d8ebefa10 engine to see RED.
#>
param(
  [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FAIL: engine not found: $Exe"; exit 2 }
$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
$HaveDcc = Test-Path -LiteralPath $Dcc
$Work = Join-Path ([IO.Path]::GetTempPath()) ('fixer2-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$Enc = [Text.Encoding]::GetEncoding(1252)
$script:Pass = 0; $script:Fail = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS  $Name" }
  else {
    $script:Fail++
    if ($Detail.Length -gt 400) { $Detail = $Detail.Substring(0, 400) + ' ...' }
    Write-Host "FAIL  $Name  $Detail"
  }
}
function Put([string]$Name, [string]$Text) {
  $p = Join-Path $Work $Name
  [IO.File]::WriteAllText($p, ($Text -replace "`r?`n", "`r`n"), $Enc)
  return $p
}
function Get-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $Enc) }
function Invoke-Engine([string[]]$Arguments) {
  return (& { $ErrorActionPreference = 'Continue'; & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } } | Out-String)
}
# compile the unit through a one-line program; returns the dcc error lines ('' = compiled or no dcc32)
function Compile([string]$UnitPath) {
  if (-not $HaveDcc) { return '' }
  $u = [IO.Path]::GetFileNameWithoutExtension($UnitPath)
  $dir = Split-Path -Parent $UnitPath
  $dpr = Join-Path $dir "P_$u.dpr"
  [IO.File]::WriteAllText($dpr, "program P_$u;`r`n{`$APPTYPE CONSOLE}`r`nuses $u in '$u.pas';`r`nbegin end.`r`n", $Enc)
  $out = & $Dcc -Q -B $dpr "-E$dir" "-N$dir" 2>&1 | ForEach-Object { "$_" }
  return (($out | Where-Object { $_ -match '(Error|Fatal)' }) -join ' | ')
}
# the exact line block ALines (joined with CRLF) is in AText
function Has-Block([string]$Text, [string[]]$Lines) { return $Text.Contains(($Lines -join "`r`n")) }

try {
  if (-not $HaveDcc) { Write-Host "NOTE: dcc32 not found, the compile checks pass vacuously: $Dcc" }

  # ---- A. multiple-statements-per-line: every statement in ONE pass -------------------------
  $a = @'
unit FxMsp;

interface

function Walk(const Lines: TArray<string>): Integer;

implementation

uses System.SysUtils;

function Walk(const Lines: TArray<string>): Integer;
var
  J: Integer;
  InFence: Boolean;
  S, T: string;
begin
  Result := 0; J := 0; InFence := True;
  while J < Length(Lines) do
  begin
    if Trim(Lines[J]) = '' then begin Inc(J); Continue; end;
    if Lines[J] = 'x' then begin InFence := False; Inc(J); Continue; end;
    Inc(Result); Inc(J);
  end;
  S := 'a;b'; T := S + '; end;'; // keep this note
  if InFence then Result := -Result else Result := Result + Length(T);
  if J > 0 then Inc(J) else Dec(J); Inc(J);
  if J > 1 then Inc(J) else begin Dec(J); Inc(J); end;
  if J = 0 then Inc(J)
  else begin Dec(J); Dec(J); end;
  try Inc(J); Inc(J); finally Dec(J); end;
end;

end.
'@
  $pa = Put 'FxMsp.pas' $a
  Check 'A: the fixture compiles before the fix' ((Compile $pa) -eq '')
  $oa = Invoke-Engine @('lint', '--in', $pa, '--fix', '--apply', '--no-backup', '--no-compile-gate', '--enable', 'multiple-statements-per-line', '--rule', 'multiple-statements-per-line')
  $ta = Get-Text $pa
  $err = Compile $pa
  Check 'A: the fixed unit compiles' ($err -eq '') $err
  Check 'A: three plain statements become three lines in one pass' (Has-Block $ta @('  Result := 0;', '  J := 0;', '  InFence := True;')) $ta
  Check 'A: `if C then begin A; B; end;` is laid out as a block in one pass' (Has-Block $ta @(
    "    if Trim(Lines[J]) = '' then", '    begin', '      Inc(J);', '      Continue;', '    end;')) $ta
  Check 'A: a three-statement block is laid out the same way' (Has-Block $ta @(
    "    if Lines[J] = 'x' then", '    begin', '      InFence := False;', '      Inc(J);', '      Continue;', '    end;')) $ta
  Check 'A: a `;` inside a string literal is not a statement end; the trailing comment stays on the last line' (Has-Block $ta @(
    "  S := 'a;b';", "  T := S + '; end;'; // keep this note")) $ta
  Check 'A: an if-else statement followed by another statement is split after the else arm' (Has-Block $ta @(
    '  if J > 0 then Inc(J) else Dec(J);', '  Inc(J);')) $ta
  Check 'A: `if C then A else begin B; C; end;` puts else / begin on their own lines (the SLZ-S07 shape)' (Has-Block $ta @(
    '  if J > 1 then Inc(J)', '  else', '  begin', '    Dec(J);', '    Inc(J);', '  end;')) $ta
  Check 'A: a line that opens with `else begin` is laid out the same way' (Has-Block $ta @(
    '  if J = 0 then Inc(J)', '  else', '  begin', '    Dec(J);', '    Dec(J);', '  end;')) $ta
  Check 'A decline: a try/finally line is left as written' ($ta.Contains('  try Inc(J); Inc(J); finally Dec(J); end;')) $ta
  $ra = Invoke-Engine @('lint', '--in', $pa, '--enable', 'multiple-statements-per-line', '--rule', 'multiple-statements-per-line')
  $left = @($ra -split "`r?`n" | Where-Object { $_ -match 'multiple-statements-per-line:' })
  $tryLine = [Array]::IndexOf(($ta -split "`r`n"), '  try Inc(J); Inc(J); finally Dec(J); end;') + 1
  Check 'A: one pass leaves only the declined try/finally line flagged' ($left.Count -eq 1 -and $left[0] -match ":$($tryLine):") ("try at $tryLine; " + ($left -join ' / '))

  # ---- B. pos-for-contains: fix the non-empty literal needle, keep the unsafe ones ---------
  $b = @'
unit FxPos;

interface

type
  TSym = record
    Directives: string;
    ToPath: string;
  end;

function Probe(const ASym: TSym; const S, Needle: string): Integer;

implementation

uses System.SysUtils;

function Probe(const ASym: TSym; const S, Needle: string): Integer;
begin
  Result := 0;
  if Pos('deprecated', ASym.Directives) > 0 then Inc(Result);
  if (Pos('.', ASym.ToPath) = 0) and (S <> '') then Inc(Result);
  if Pos('<summary', LowerCase(S)) > 0 then Inc(Result);
  if Pos(#10, S) > 0 then Inc(Result);
  if Pos('ab', S) <> 0 then Inc(Result);
  if Pos(Needle, S) > 0 then Inc(Result);
  if Pos('', S) = 0 then Inc(Result);
  if Pos('x', Copy(S, 1, 3)) > 0 then Inc(Result);
end;

end.
'@
  $bdir = Join-Path $Work 'pos'
  [IO.Directory]::CreateDirectory($bdir) | Out-Null
  $pb = Join-Path $bdir 'FxPos.pas'
  [IO.File]::WriteAllText($pb, ($b -replace "`r?`n", "`r`n"), $Enc)
  Check 'B: the fixture compiles before the fix' ((Compile $pb) -eq '')
  $db = Join-Path $Work 'pos.sqlite'
  Invoke-Engine @('index', $bdir, '--db', $db) | Out-Null
  $ob = Invoke-Engine @('lint', $pb, '--db', $db, '--fix', '--apply', '--no-backup', '--no-compile-gate', '--enable', 'pos-for-contains', '--rule', 'pos-for-contains')
  $tb = Get-Text $pb
  $err = Compile $pb
  Check 'B: the fixed unit compiles' ($err -eq '') $err
  Check 'B: literal needle, member haystack (> 0) -> Contains' ($tb.Contains("if ASym.Directives.Contains('deprecated') then")) $tb
  Check 'B: literal needle, member haystack (= 0) -> not Contains' ($tb.Contains("if (not ASym.ToPath.Contains('.')) and (S <> '') then")) $tb
  Check 'B: literal needle, LowerCase(..) haystack -> Contains' ($tb.Contains("if LowerCase(S).Contains('<summary') then")) $tb
  Check 'B: char literal needle, string haystack -> Contains' ($tb.Contains('if S.Contains(#10) then')) $tb
  Check 'B: literal needle, <> 0 -> Contains' ($tb.Contains("if S.Contains('ab') then")) $tb
  Check 'B decline: a variable needle is left as written (Pos('''', S) = 0 but Contains('''') is True)' ($tb.Contains('if Pos(Needle, S) > 0 then')) $tb
  Check 'B decline: an empty literal needle is left as written' ($tb.Contains("if Pos('', S) = 0 then")) $tb
  Check 'B decline: an unproven haystack (Copy) is left as written' ($tb.Contains("if Pos('x', Copy(S, 1, 3)) > 0 then")) $tb
  $rb = Invoke-Engine @('lint', $pb, '--db', $db, '--enable', 'pos-for-contains', '--rule', 'pos-for-contains')
  $leftB = @($rb -split "`r?`n" | Where-Object { $_ -match 'pos-for-contains:' })
  Check 'B: the declined sites are still reported (3)' ($leftB.Count -eq 3) ($leftB -join ' / ')
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { Write-Host "NOTE: could not remove $Work" }
}
Write-Host ''
Write-Host "run_v1523_FIXER2: $script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 }
exit 0
