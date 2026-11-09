<#
  run_rf_lint_false_positives.ps1 -- wave 148 lane RF: lint-rule false positives.

  Each section drives the real engine on a small fixture and asserts BOTH the fixed
  false positive (the finding is gone) AND a positive control (the genuine shape
  still fires), so the guard cannot pass with the rule off.

    1. for-bound-modified-in-body: a `with` in the body is not a modification of the
       loop variable (uStyles.pas:506); a real assignment inside a with still fires.
    2. concat-in-loop: `var Total := 0.0` / `var Cnt := 0` sums are arithmetic; an
       inline `var Acc := ''` string accumulation still fires.
    3. unused-unit-in-uses: a unit needed only for an inline property accessor
       (FireDAC.Stan.Param, H2443) is kept; a genuinely unused unit still fires.
       Needs the Win64 platform library DB; reported SKIP when it is absent.
    4. compiler-magic-comments: the message names the ENotImplemented raise form.
    5. shared-marker-legacy-shape: multi-word prose after the tag does not fire; the
       legacy shape still does.
    6. unsafe-typecast-without-is: a lower-case-prefixed class name (TcxButton,
       TfrmMain) is a class; Trim / Try* are not casts.
    7. nonminimal-bool: the `not in` form is named in the message (FIXED earlier,
       860aeccaa; pinned here).

  Run under pwsh 7. Exit 0 = all pass, 1 = a check failed, 2 = setup problem.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$Work = Join-Path ([IO.Path]::GetTempPath()) ('rf_fp_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Work) | Out-Null
function Put($name, $text) {
  $p = Join-Path $Work $name
  [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  return $p
}
# Lines of `lint` output for a rule, as 'line' numbers.
function Hits($file, $rule, [string[]]$extra = @()) {
  $out = & $Exe lint $file --enable $rule @extra 2>&1 | Out-String
  $rx = [regex]::Matches($out, '(?m)^.*?:(\d+):\d+\s+\[\w+\]\s+' + [regex]::Escape($rule) + ':')
  return @($rx | ForEach-Object { [int]$_.Groups[1].Value }), $out
}
try {
  # ---- 1. for-bound-modified-in-body ---------------------------------------
  Write-Host '1. for-bound-modified-in-body'
  $f = Put 'forwith.pas' @'
unit forwith;
interface
implementation
procedure NoHit(Mgr: TObject);
var
  i: Integer;
begin
  for i := Mgr.Count - 1 downto 0 do
  begin
    with Mgr.Styles[i].PrinterPage do
    begin
      PageFooter.Clear;
    end;
  end;
end;
procedure Hit(Mgr: TObject);
var
  i: Integer;
begin
  for i := 0 to 9 do
  begin
    with Mgr do
      i := 5;
  end;
end;
end.
'@
  $h, $o = Hits $f 'for-bound-modified-in-body'
  Check '1a with-body that never names the loop var: no finding (line 8)' ($h -notcontains 8) "hits=$($h -join ',')"
  Check '1b POSITIVE CONTROL: assignment to the loop var inside a with still fires (line 19)' ($h -contains 20) "hits=$($h -join ',')"

  # ---- 2. concat-in-loop -----------------------------------------------------
  Write-Host '2. concat-in-loop'
  $f = Put 'concat.pas' @'
unit concat;
interface
implementation
procedure P(Items: TObject);
begin
  var Total := 0.0;
  var Cnt := 0;
  var Neg := -1;
  var Acc := '';
  for var X in Items do
  begin
    Total := Total + X.Price;
    Cnt := Cnt + X.Qty;
    Neg := Neg + X.Qty;
    Acc := Acc + X.Name;
  end;
end;
end.
'@
  $h, $o = Hits $f 'concat-in-loop'
  Check '2a inferred Double sum: no finding (line 12)' ($h -notcontains 12) "hits=$($h -join ',')"
  Check '2b inferred Integer sum: no finding (line 13)' ($h -notcontains 13) "hits=$($h -join ',')"
  Check '2c inferred negative Integer sum: no finding (line 14)' ($h -notcontains 14) "hits=$($h -join ',')"
  Check '2d POSITIVE CONTROL: inferred string accumulation still fires (line 15)' ($h -contains 15) "hits=$($h -join ',')"

  # ---- 4. compiler-magic-comments message ----------------------------------------
  Write-Host '4. compiler-magic-comments'
  $f = Put 'magic.pas' @'
unit magic;
interface
implementation
procedure Stub;
begin
  raise ENotImplemented.CreateFmt('no %s', ['x']);
end;
procedure Todo;
begin
  // TODO: finish
end;
end.
'@
  $h, $o = Hits $f 'compiler-magic-comments'
  Check '4a POSITIVE CONTROL: raise ENotImplemented (line 6) and TODO comment (line 10) both fire' (($h -contains 6) -and ($h -contains 10)) "hits=$($h -join ',')"
  Check '4b message names the raise form, not only a comment' ($o -match 'raise ENotImplemented') ''

  # 4c-4f (RT-7, wave 150): a `raise ENotImplemented` that is the body of a VIRTUAL / OVERRIDE
  # method is the abstract-stub idiom (the subclass must override), not an unfinished marker.
  # The declaration (with its directive) lives in the class body, the rule sees only the body.
  $f = Put 'magic2.pas' @'
unit magic2;
interface
type
  TBase = class
    procedure NonVirt;
    procedure Virt; virtual;
    function Ovr: Integer; virtual;
  end;
  TDer = class(TBase)
    function Ovr: Integer; override;
  end;
implementation
procedure TBase.NonVirt;
begin
  raise ENotImplemented.Create('nonvirt');
end;
procedure TBase.Virt;
begin
  raise ENotImplemented.Create('virt');
end;
function TBase.Ovr: Integer;
begin
  raise ENotImplemented.Create('ovr');
end;
function TDer.Ovr: Integer;
begin
  raise ENotImplemented.Create('ovr2');
end;
end.
'@
  $h, $o = Hits $f 'compiler-magic-comments'
  Check '4c POSITIVE CONTROL: raise ENotImplemented in a NON-virtual method (line 15) still fires' ($h -contains 15) "hits=$($h -join ',')"
  Check '4d raise ENotImplemented in a virtual method (line 19) is exempt' ($h -notcontains 19) "hits=$($h -join ',')"
  Check '4e raise ENotImplemented in a virtual method with a result (line 23) is exempt' ($h -notcontains 23) "hits=$($h -join ',')"
  Check '4f raise ENotImplemented in an override method (line 27) is exempt' ($h -notcontains 27) "hits=$($h -join ',')"

  # ---- 5. shared-marker-legacy-shape --------------------------------------------
  Write-Host '5. shared-marker-legacy-shape'
  $f = Put 'shared.pas' @'
unit uSharedLegacy;   // dl:shared A, B // note
interface
const
  Legacy = 1;   // note // dl:shared A
  Good1  = 3;   // dl:shared A, B // note
  Prose2 = 5;   // see // dl:shared below for details
  Prose3 = 6;   // see // dl:shared A, B for details
implementation
end.
'@
  $h, $o = Hits $f 'shared-marker-legacy-shape'
  Check '5a POSITIVE CONTROL: legacy shape (line 4) fires' ($h -contains 4) "hits=$($h -join ',')"
  Check '5b multi-word prose after the tag (line 6) does not fire' ($h -notcontains 6) "hits=$($h -join ',')"
  Check '5c tag-first marker (line 1, 5) does not fire' (($h -notcontains 1) -and ($h -notcontains 5)) "hits=$($h -join ',')"
  Check '5d prose "A, B for details" (line 7) does not fire' ($h -notcontains 7) "hits=$($h -join ',')"

  # ---- 6. unsafe-typecast-without-is ------------------------------------------------
  Write-Host '6. unsafe-typecast-without-is'
  $f = Put 'tc.pas' @'
unit tc;
interface
implementation
procedure Handle(Sender: TObject; G: TcxGrid);
begin
  TcxButton(Sender).Caption := 'a';
  TfrmMain(Sender).Caption := 'b';
  Trim(Sender);
  TryFoo(Sender);
  TcxGrid(G).Name := 'c';
end;
end.
'@
  $h, $o = Hits $f 'unsafe-typecast-without-is'
  Check '6a TcxButton(Sender) fires (line 6)' ($h -contains 6) "hits=$($h -join ',')"
  Check '6b TfrmMain(Sender) fires (line 7)' ($h -contains 7) "hits=$($h -join ',')"
  Check '6c Trim / TryFoo are not casts (lines 8, 9)' (($h -notcontains 8) -and ($h -notcontains 9)) "hits=$($h -join ',')"
  Check '6d same-type cast TcxGrid(G) does not fire (line 10)' ($h -notcontains 10) "hits=$($h -join ',')"

  # ---- 7. nonminimal-bool message -------------------------------------------------------
  Write-Host '7. nonminimal-bool'
  $f = Put 'nmb.pas' @'
unit nmb;
interface
implementation
function F(A: Integer; S: TIntSet): Boolean;
begin
  Result := not (A in S);
end;
end.
'@
  $h, $o = Hits $f 'nonminimal-bool'
  Check '7a POSITIVE CONTROL: not (A in S) fires (line 6)' ($h -contains 6) "hits=$($h -join ',')"
  Check '7b message says "not in"' ($o -match 'A not in S') ''

  # ---- 3. unused-unit-in-uses ---------------------------------------------------------------
  Write-Host '3. unused-unit-in-uses'
  if (-not (Test-Path $LibraryDb)) {
    Write-Host "  [SKIP] library DB absent: $LibraryDb"
  } else {
    $proj = Join-Path $Work 'uu'
    [IO.Directory]::CreateDirectory($proj) | Out-Null
    $src = @'
unit uu;

interface

uses
  FireDAC.Comp.Client, FireDAC.Stan.Param, System.IniFiles;

procedure SetIt(Q: TFDQuery);

implementation

procedure SetIt(Q: TFDQuery);
begin
  Q.ParamByName('A').AsInteger := 5;
end;

end.
'@
    [IO.File]::WriteAllText((Join-Path $proj 'uu.pas'), ($src -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    $db = Join-Path $Work 'uu.sqlite'
    & $Exe index $proj --db $db 2>&1 | Out-Null
    Push-Location $Work
    try {
      $out = & $Exe lint-all --db $db --library-db $LibraryDb --enable unused-unit-in-uses 2>&1 | Out-String
    } finally { Pop-Location }
    Check '3a FireDAC.Stan.Param (inline AsInteger setter) is NOT reported' ($out -notmatch "Unit 'FireDAC.Stan.Param'") ''
    Check '3b POSITIVE CONTROL: unused System.IniFiles IS reported' ($out -match "Unit 'System.IniFiles'") ''
  }
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
