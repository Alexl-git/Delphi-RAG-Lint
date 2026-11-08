<#
  run_autofix_quality.ps1 -- lint --fix --apply output must not need hand repair
  (docs\INBOX-autofix-output-quality.md, C10; seen on YADF with 1.39.2).

  Four sub-items, each driven through the real engine on a scratch copy:
    1. comma-first uses: a unit added by a fix follows the clause's own layout
       (`  , System.Math` on its own line before the lone `;`), never `System.Math,`.
    2. else-if ladder: ifthen-to-if-expression never joins a ladder onto one line
       (regression pin: the fixer declines a nested `if`; green on 1.43 and later).
    3. redundant parentheses: manual-inrange's InRange(..) drops the now-redundant
       outer pair, but keeps the parens of a call (`Check((a>=1) and (a<=9))`).
    4. .bak noise: --no-backup writes no .bak; the default still writes one.
  Each case has a positive control inside the run (the same engine, the other
  flag/shape) so a vacuous pass is impossible.

  -Exe defaults to the worktree build; pass the 1.43 engine to see RED.
#>
param(
  [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FAIL: engine not found: $Exe"; exit 2 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('autofixq-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$Enc = [Text.Encoding]::GetEncoding(1252)
$script:Pass = 0; $script:Fail = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS  $Name" }
  else { $script:Fail++; Write-Host "FAIL  $Name  $Detail" }
}
function Put([string]$Name, [string]$Text) {
  $p = Join-Path $Work $Name
  [IO.File]::WriteAllText($p, ($Text -replace "`r?`n", "`r`n"), $Enc)
  return $p
}
function Get-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $Enc) }
function Fix([string]$Path, [string]$Rules, [switch]$NoBackup) {
  $a = @('lint', '--in', $Path, '--fix', '--apply', '--enable', $Rules)
  if ($NoBackup) { $a += '--no-backup' }
  $out = & $Exe @a 2>&1 | Out-String
  return $out
}

try {
  # ---- 1. comma-first uses -------------------------------------------------
  $cf = @'
unit CF;

interface

uses
  System.SysUtils
  , System.Classes
  ;

function Chk(Cp: Integer): Boolean;

implementation

function Chk(Cp: Integer): Boolean;
begin
  Result:= (Cp >= 1) and (Cp <= 9);
end;

end.
'@
  $p = Put 'CF.pas' $cf
  Fix $p 'manual-inrange' | Out-Null
  $t = Get-Text $p
  Check 'comma-first: the new unit is added on its own comma-first line' ($t -match "(?m)^\s*, System\.Math\r?\n\s*;") $t
  Check 'comma-first: no trailing-comma entry' (-not ($t -match 'System\.Math,')) $t
  # positive control: a conventional (comma-last) clause still gets the plain entry
  $cl = $cf -replace '(?s)uses.*?;\r?\n', "uses`n  System.SysUtils,`n  System.Classes;`n"
  $p2 = Put 'CL.pas' ($cl -replace 'unit CF', 'unit CL')
  Fix $p2 'manual-inrange' | Out-Null
  $t2 = Get-Text $p2
  Check 'comma-last control: the new unit is still added and the file changed' (($t2 -match 'System\.Math') -and ($t2 -match 'InRange\(')) $t2

  # ---- 2. else-if ladder stays one arm per line ---------------------------------
  $lad = @'
unit LD;

interface

function Pick(A, B, C: Boolean): Integer;

implementation

function Pick(A, B, C: Boolean): Integer;
begin
  if A then
    Result:= 1
  else if B then
    Result:= 2
  else if C then
    Result:= 3
  else
    Result:= 4;
end;

end.
'@
  $p3 = Put 'LD.pas' $lad
  Fix $p3 'ifthen-to-if-expression' | Out-Null
  $t3 = Get-Text $p3
  $long = ($t3 -split "`r?`n" | Where-Object { $_.Length -gt 60 }).Count
  Check 'ladder: no joined long line' ($long -eq 0) $t3
  Check 'ladder: the else-if arms are still one per line' (([regex]::Matches($t3, '(?m)^\s*else if ')).Count -ge 1) $t3

  # ---- 3. redundant parentheses ----------------------------------------------
  $pr = @'
unit PR;

interface

function Chk(Cp: Integer): Boolean;
function Wrap(X: Boolean): Boolean;

implementation

function Wrap(X: Boolean): Boolean;
begin
  Result:= X;
end;

function Chk(Cp: Integer): Boolean;
begin
  Result:= ((Cp >= $D800) and (Cp <= $DFFF));
  Result:= Wrap((Cp >= 1) and (Cp <= 9));
  Result:= Wrap(((Cp >= 2) and (Cp <= 8)));
  if ((Cp >= 3) and (Cp <= 7)) then Result:= True;
end;

end.
'@
  $p4 = Put 'PR.pas' $pr
  Fix $p4 'manual-inrange' | Out-Null
  $t4 = Get-Text $p4
  Check 'parens: the redundant outer pair after := is dropped' ($t4 -match 'Result:= InRange\(Cp, \$D800, \$DFFF\);') $t4
  Check 'parens: the call parentheses are kept' ($t4 -match 'Result:= Wrap\(InRange\(Cp, 1, 9\)\);') $t4
  Check 'parens: a doubled pair inside a call collapses to the call pair' ($t4 -match 'Result:= Wrap\(InRange\(Cp, 2, 8\)\);') $t4
  Check 'parens: the pair after if is dropped' ($t4 -match 'if InRange\(Cp, 3, 7\) then') $t4

  # ---- 4. --no-backup on lint --fix --apply ----------------------------------
  $nb = $cf -replace 'unit CF', 'unit NB'
  $p5 = Put 'NB.pas' $nb
  Fix $p5 'manual-inrange' -NoBackup | Out-Null
  Check 'no-backup: the file was fixed' ((Get-Text $p5) -match 'InRange\(') ''
  Check 'no-backup: no .bak written' (-not (Test-Path -LiteralPath ($p5 + '.bak'))) ''
  $p6 = Put 'BK.pas' ($cf -replace 'unit CF', 'unit BK')
  Fix $p6 'manual-inrange' | Out-Null
  Check 'no-backup control: the default still writes the .bak' (Test-Path -LiteralPath ($p6 + '.bak')) ''
  # ---- 5. unused-local keeps every dl: anchor (D7) ----------------------------
  # Shapes: `//` trailing, brace trailing, `var // dl:bk` on the keyword line, an
  # own-line anchor; plus a plain non-dl trailing comment that must still go.
  $bk = @"
unit BM;

interface

procedure Foo;

implementation

procedure Foo;
var
  A, B: Integer; // dl:bk anchor-a
  D: Integer; { dl:bk anchor-d }
  G: Integer; // plain-gone
  C: Integer;
begin
  C:= 1;
  if C = 1 then C:= 2;
end;

procedure Baz;
var // dl:bk anchor-v
  E: Integer;
begin
end;

end.
"@
  $p7 = Put 'BM.pas' $bk
  Fix $p7 'unused-local' -NoBackup | Out-Null
  $t7 = Get-Text $p7
  Check 'bookmark: the // anchor survives' ($t7 -match 'dl:bk anchor-a') $t7
  Check 'bookmark: the brace anchor survives' ($t7 -match 'dl:bk anchor-d') $t7
  Check 'bookmark: the var-keyword-line anchor survives' ($t7 -match 'dl:bk anchor-v') $t7
  # positive control: the dead declarations really went, and a plain comment went with its line
  Check 'bookmark control: dead declarations removed' (-not ($t7 -match '(?m)^\s*(A, B|D|G|E): Integer')) $t7
  Check 'bookmark control: a plain trailing comment is still deleted' (-not ($t7 -match 'plain-gone')) $t7
}
finally {
  [IO.Directory]::Delete($Work, $true)
}
Write-Host ("autofix quality: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
