<#
  run_rules_fix_default_on.ps1 -- every autofix is ON by default (lane A7, 1.37.0).
  (Renamed from run_rules_fix_opt_in.ps1, which pinned the opposite contract.)

  THE CONTRACT THIS PINS
  * `rules --json`: `fix_opt_in` is still emitted (the IDE plugin reads it) but is
    false for every rule. The eight naming fixes are still `fixable`.
  * A batch `lint --fix --apply` with a --db renames with NO config key and NO
    --fix-naming flag (uOptIn: wrStr -> WrStr, declaration AND use).
  * `"autofix_off": ["const-casing"]` is the only brake: that rule is left alone.
  * `"autofix": [...]` is accepted and ignored (one stderr note names the new key).
  * `--fix-naming` is still ACCEPTED (a no-op) so the IDE's Fix all keeps working.
  * Safety nets that replace the gate (each has a positive control):
      - a rename whose symbol a BINARY .dfm references is skipped and counted
        `skipped (dfm-referenced): N` (a TEXT .dfm row is rewritten with the .pas);
      - a field-name-prefix finding whose name is read bare inside a `with` is
        skipped and counted `skipped (with-block): N`.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
function WriteAscii($path, $text) {
  [IO.File]::WriteAllText($path, (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
$ExeP = (Resolve-Path $Exe).Path

Write-Host '== rules --json: fix_opt_in is false everywhere ==' -ForegroundColor Cyan
$rules = @((& $ExeP rules --json 2>$null | ConvertFrom-Json).rules)
Check 'catalog read' ($rules.Count -gt 100) "rules=$($rules.Count)"
Check 'O1 every rule still carries the field' (@($rules | Where-Object { $null -eq $_.PSObject.Properties['fix_opt_in'] }).Count -eq 0) ''
Check 'O2 no rule is opt-in' (@($rules | Where-Object { $_.fix_opt_in -eq $true }).Count -eq 0) ''
$naming = @('const-casing','field-name-prefix','local-field-prefix','local-var-casing','method-pascalcase','param-name-prefix','property-accessor-name','type-name-prefix')
$fixable = @($rules | Where-Object { $_.fixable } | ForEach-Object { $_.id })
Check 'O3 CONTROL: the eight naming rules stay fixable' (@($naming | Where-Object { $fixable -notcontains $_ }).Count -eq 0) ''

$work = Join-Path ([IO.Path]::GetTempPath()) ("draglint-defon-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function NewProject($name, $files) {
  $dir = Join-Path $work $name
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $uses = @()
  foreach ($k in $files.Keys) {
    if ($k -match '\.pas$') { $uses += "  $([IO.Path]::GetFileNameWithoutExtension($k)) in '$k'" }
  }
  WriteAscii (Join-Path $dir "$name.dpr") ("program $name;`nuses`n" + ($uses -join ",`n") + ";`nbegin`nend.`n")
  foreach ($k in $files.Keys) {
    if ($files[$k] -is [byte[]]) { [IO.File]::WriteAllBytes((Join-Path $dir $k), $files[$k]) }
    else { WriteAscii (Join-Path $dir $k) $files[$k] }
  }
  & $ExeP index --project (Join-Path $dir "$name.dpr") --db (Join-Path $dir "$name.sqlite") 2>&1 | Out-Null
  return $dir
}
function Txt($p) { [IO.File]::ReadAllText($p) }
function Say($o, $re) { ($o -split "`r?`n" | Where-Object { $_ -match $re }) -join ' | ' }
try {
  # ---- D: batch fix, no opt-in anywhere ----
  $optIn = @'
unit uOptIn;

interface

const
  wrStr = 'x';

function Get: string;

implementation

function Get: string;
begin
  Result:= wrStr;
end;

end.
'@
  $d1 = NewProject 'OptIn' @{ 'uOptIn.pas' = $optIn }
  $u1 = Join-Path $d1 'uOptIn.pas'; $db1 = Join-Path $d1 'OptIn.sqlite'
  $o = (& $ExeP lint --file $u1 --db $db1 --fix --apply 2>&1 | Out-String)
  $a = Txt $u1
  Check 'D1 batch --fix --apply with a --db recases wrStr (decl AND use), no config, no flag' `
    (($a -cmatch '(?m)^\s*WrStr = ') -and ($a -cmatch 'Result:= WrStr;') -and ($a -cnotmatch '\bwrStr\b')) (Say $o 'autofix')
  Check 'D2 CONTROL: the old opt-out note is gone' ($o -notmatch 'NOT opted in')

  # ---- D3: autofix_off is the brake ----
  $d3 = NewProject 'OffCfg' @{ 'uOptIn.pas' = $optIn }
  $u3 = Join-Path $d3 'uOptIn.pas'; $db3 = Join-Path $d3 'OffCfg.sqlite'
  $cfg3 = Join-Path $d3 'drag-lint-lint.json'
  $pre3 = Txt $u3
  WriteAscii $cfg3 '{ "autofix_off": ["const-casing"] }'
  $o = (& $ExeP lint --file $u3 --db $db3 --config $cfg3 --fix --apply 2>&1 | Out-String)
  Check 'D3 "autofix_off": ["const-casing"] leaves wrStr alone' ((Txt $u3) -ceq $pre3) ''
  Check 'D3b ... and the file really still says wrStr' ((Txt $u3) -cmatch '\bwrStr\b') ''

  # ---- D4: legacy "autofix" key accepted and ignored; --fix-naming is a no-op ----
  $d4 = NewProject 'Legacy' @{ 'uOptIn.pas' = $optIn }
  $u4 = Join-Path $d4 'uOptIn.pas'; $db4 = Join-Path $d4 'Legacy.sqlite'
  $cfg4 = Join-Path $d4 'drag-lint-lint.json'
  WriteAscii $cfg4 '{ "autofix": ["method-pascalcase"] }'
  $o = (& $ExeP lint --file $u4 --db $db4 --config $cfg4 --fix --fix-naming --apply 2>&1 | Out-String)
  Check 'D4 legacy "autofix" does not gate: const-casing still applied' ((Txt $u4) -cmatch 'WrStr') ''
  Check 'D5 ... one stderr note names "autofix_off"' ($o -match '"autofix" no longer gates fixes' -and $o -match 'autofix_off') ''

  # ---- A: DFM-referenced symbols ----
  $form = @'
unit uForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TfrmMain = class(TForm)
    Button1: TButton;
  public
    procedure buttonClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmMain.buttonClick(Sender: TObject);
begin
  Tag:= 1;
end;

end.
'@
  $dfmText = "object frmMain: TfrmMain`n  Left = 0`n  object Button1: TButton`n    OnClick = buttonClick`n  end`nend`n"
  $d6 = NewProject 'FormText' @{ 'uForm.pas' = $form; 'uForm.dfm' = $dfmText }
  $o = (& $ExeP lint --file (Join-Path $d6 'uForm.pas') --db (Join-Path $d6 'FormText.sqlite') --fix --apply 2>&1 | Out-String)
  Check 'A1 text .dfm: the handler is renamed in the .pas AND the .dfm OnClick row (both change)' `
    (((Txt (Join-Path $d6 'uForm.pas')) -cmatch 'procedure ButtonClick') -and ((Txt (Join-Path $d6 'uForm.dfm')) -cmatch 'OnClick = ButtonClick')) (Say $o 'autofix')

  # binary .dfm: TPF0 header then the handler name as a length-prefixed string
  $bin = [byte[]]([Text.Encoding]::ASCII.GetBytes("TPF0") + [byte[]](0x08) + [Text.Encoding]::ASCII.GetBytes("TfrmMain") + [byte[]](0x00, 0x07) + [Text.Encoding]::ASCII.GetBytes("OnClick") + [byte[]](0x06, 0x0B) + [Text.Encoding]::ASCII.GetBytes("buttonClick") + [byte[]](0x00, 0x00))
  $d7 = NewProject 'FormBin' @{ 'uForm.pas' = $form; 'uForm.dfm' = $bin }
  $p7 = Join-Path $d7 'uForm.pas'; $b7 = Join-Path $d7 'uForm.dfm'
  $pre = Txt $p7; $hb = (Get-FileHash $b7).Hash
  $o = (& $ExeP lint --file $p7 --db (Join-Path $d7 'FormBin.sqlite') --fix --apply 2>&1 | Out-String)
  Check 'A2 binary .dfm referencing the handler: .pas AND .dfm are left unchanged' (((Txt $p7) -ceq $pre) -and ((Get-FileHash $b7).Hash -eq $hb)) ''
  Check 'A3 ... and the skip is counted: "skipped (dfm-referenced): 1"' ($o -match 'skipped \(dfm-referenced\): 1') (Say $o 'skipped|autofix')

  # ---- B: bare field read inside `with` ----
  $withU = @'
unit uWith;

interface

type
  TFoo = class
  private
    client: Integer;
    other: Integer;
  public
    function GetOther: Integer;
  end;

function Use(O: TFoo): Integer;

implementation

function TFoo.GetOther: Integer;
begin
  Result:= Self.other;
end;

function Use(O: TFoo): Integer;
begin
  with O do
    Result:= client + 1;
end;

end.
'@
  $d8 = NewProject 'WithRead' @{ 'uWith.pas' = $withU }
  $cfg8 = Join-Path $d8 'drag-lint-lint.json'
  WriteAscii $cfg8 '{ "naming": { "field_prefix": "F" } }'
  $u8 = Join-Path $d8 'uWith.pas'
  $o = (& $ExeP lint --file $u8 --db (Join-Path $d8 'WithRead.sqlite') --config $cfg8 --rule field-name-prefix --fix --apply 2>&1 | Out-String)
  $a = Txt $u8
  Check 'B1 the field read bare inside `with` is NOT renamed' (($a -cmatch '\bclient: Integer') -and ($a -cmatch 'Result:= client \+ 1')) ''
  Check 'B2 ... the skip is counted: "skipped (with-block): 1"' ($o -match 'skipped \(with-block\): 1') (Say $o 'skipped|autofix')
  Check 'B3 CONTROL: the field with no `with` read IS renamed' (($a -cmatch '\bFOther: Integer') -and ($a -cnotmatch '\bother: Integer')) ''

  # ---- U: a TEXT form beside the unit that is NOT the unit's own indexed form ----
  # (an inherited form / a form outside the .dproj). The engine cannot rewrite what it
  # does not index: renaming the .pas would leave its row stale (compiles, dies at load).
  $childDfm = "inherited frmChild: TfrmMain`n  Left = 0`n  object Button2: TButton`n    OnClick = buttonClick`n  end`nend`n"
  $d9 = NewProject 'FormUnidx' @{ 'uForm.pas' = $form; 'uForm.dfm' = $dfmText; 'uChild.dfm' = $childDfm }
  $p9 = Join-Path $d9 'uForm.pas'; $c9 = Join-Path $d9 'uChild.dfm'
  $pre9 = Txt $p9; $preC9 = Txt $c9; $preD9 = Txt (Join-Path $d9 'uForm.dfm')
  $o = (& $ExeP lint --file $p9 --db (Join-Path $d9 'FormUnidx.sqlite') --fix --apply 2>&1 | Out-String)
  Check 'U1 an unindexed text form names the handler: .pas, own .dfm and the other .dfm are all unchanged' `
    (((Txt $p9) -ceq $pre9) -and ((Txt $c9) -ceq $preC9) -and ((Txt (Join-Path $d9 'uForm.dfm')) -ceq $preD9)) (Say $o 'skipped|autofix')
  Check 'U2 ... and the skip is counted: "skipped (dfm-unindexed): 1"' ($o -match 'skipped \(dfm-unindexed\): 1') (Say $o 'skipped|autofix')
  $otherDfm = "inherited frmChild: TfrmMain`n  object Button2: TButton`n    OnClick = SomethingElse`n  end`nend`n"
  $d10 = NewProject 'FormUnidxCtl' @{ 'uForm.pas' = $form; 'uForm.dfm' = $dfmText; 'uChild.dfm' = $otherDfm }
  $o = (& $ExeP lint --file (Join-Path $d10 'uForm.pas') --db (Join-Path $d10 'FormUnidxCtl.sqlite') --fix --apply 2>&1 | Out-String)
  Check 'U3 CONTROL: a neighbouring form that does not name the handler does not block the rename' `
    (((Txt (Join-Path $d10 'uForm.pas')) -cmatch 'procedure ButtonClick') -and ((Txt (Join-Path $d10 'uForm.dfm')) -cmatch 'OnClick = ButtonClick') -and ($o -notmatch 'dfm-unindexed')) (Say $o 'skipped|autofix')

  # ---- C: a bare field read in the class's own method IS renamed; no review warning ----
  $bare = @'
unit uBare;

interface

type
  TFoo = class
  private
    client: Integer;
  public
    function Get: Integer;
  end;

implementation

function TFoo.Get: Integer;
begin
  Result:= client + 1;
end;

end.
'@
  $d11 = NewProject 'BareRead' @{ 'uBare.pas' = $bare }
  $cfg11 = Join-Path $d11 'drag-lint-lint.json'
  WriteAscii $cfg11 '{ "naming": { "field_prefix": "F" } }'
  $u11 = Join-Path $d11 'uBare.pas'
  $o = (& $ExeP lint --file $u11 --db (Join-Path $d11 'BareRead.sqlite') --config $cfg11 --rule field-name-prefix --fix --apply 2>&1 | Out-String)
  $a = Txt $u11
  Check 'C1 the bare read in the class''s own method is renamed with the declaration' (($a -cmatch '\bFClient: Integer') -and ($a -cmatch 'Result:= FClient \+ 1;')) (Say $o 'autofix')
  Check 'C2 ... and the stale "may leave a bare field read" warning is gone' ($o -notmatch 'bare field read')
  Check 'C3 CONTROL: the matcher sees that warning text when present' (('drag-lint: warning: field-name-prefix autofix may leave a bare field read') -match 'bare field read')

} finally {
  [IO.Directory]::Delete($work, $true)
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
