<#
  run_type_use_uses_order.ps1 -- 147 B4 residue / B5 tie-break (149 RB2 item 5): a type
  mention (refs.kind = 'type_use') whose name two USED units declare was 'ambiguous' and
  unbound. Delphi decides it by uses order: the unit listed LAST wins, and the
  implementation uses clause comes AFTER the interface one -- so in the implementation an
  implementation-uses unit shadows an interface-uses unit, while a mention in the interface
  section cannot see the implementation-uses unit at all.

  Pins (UA and UB both declare TPair):
    A1 uOne  `uses UA, UB` (one section), a local `P: TPair`          -> UB.TPair
    A2 uOne2 `uses UB, UA` (order reversed), same mention              -> UA.TPair
    A3 uSplit interface `uses UA`, implementation `uses UB`:
       the interface mention (a parameter type)                       -> UA.TPair
       the implementation mention (a local type)                      -> UB.TPair
  CONTROLS (green on both engines): A4 uSolo `uses UA` -> UA.TPair; A5 uOwn declares its own
  TPair and uses UA, UB -> uOwn.TPair (the unit's own type shadows every used one).
  POSITIVE CONTROL: on 1.48.0-alpha A1, A2 and the implementation half of A3 are RED.
  Run from any CWD, pwsh 7. Pass -Exe with the engine under test.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_type_use_order_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($dir,$name,$t){ [IO.File]::WriteAllText((Join-Path $dir $name), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

foreach ($u in 'UA','UB') {
  W $WorkDir "$u.pas" @"
unit $u;
interface
type
  TPair = record
    K: Integer;
  end;
implementation
end.
"@
}
function Consumer($name, $intfUses, $implUses) {
  $iu = if ($intfUses) { "uses $intfUses;`r`n" } else { '' }
  $mu = if ($implUses) { "uses $implUses;`r`n" } else { '' }
  W $WorkDir "$name.pas" @"
unit $name;
interface
$($iu)procedure GoIntf(const A: TPair);
procedure GoImpl;
implementation
$($mu)procedure GoIntf(const A: TPair);
begin
end;
procedure GoImpl;
var
  P: TPair;
begin
  P.K:= 1;
end;
end.
"@
}
Consumer 'uOne'   'UA, UB' ''
Consumer 'uOne2'  'UB, UA' ''
Consumer 'uSplit' 'UA'     'UB'
Consumer 'uSolo'  'UA'     ''
W $WorkDir 'uOwn.pas' @'
unit uOwn;
interface
uses UA, UB;
type
  TPair = record
    V: Integer;
  end;
procedure GoOwn;
implementation
procedure GoOwn;
var
  P: TPair;
begin
  P.V:= 1;
end;
end.
'@
W $WorkDir 'App.dpr' @'
program App;
uses
  UA in 'UA.pas',
  UB in 'UB.pas',
  uOne in 'uOne.pas',
  uOne2 in 'uOne2.pas',
  uSplit in 'uSplit.pas',
  uSolo in 'uSolo.pas',
  uOwn in 'uOwn.pas';
begin
end.
'@

$db = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V index built' (Test-Path $db) $db
$raw = & $exePath sql --db $db --json --limit 500 --query "SELECT f.path, r.start_line, coalesce(s.qualified_name,'') FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id WHERE r.kind = 'type_use' AND r.name_text = 'TPair' ORDER BY f.path, r.start_line" | Out-String
Pop-Location
$rows = foreach ($r in ($raw | ConvertFrom-Json).rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[0]); Line=[int]$r[1]; Target=[string]$r[2] } }
Check "V the TPair mentions were read ($(@($rows).Count))" (@($rows).Count -ge 9) $raw
function Mentions($file){ @($rows | Where-Object { $_.File -eq $file } | Sort-Object Line) }
function Impl($file){ (Mentions $file | Select-Object -Last 1) }
function Intf($file){ (Mentions $file | Select-Object -First 1) }

$m = Impl 'uOne';   Check "A1 uOne (uses UA, UB) local P: TPair -> UB.TPair (got '$($m.Target)')" ($m.Target -ceq 'UB.TPair')
$m = Impl 'uOne2';  Check "A2 uOne2 (uses UB, UA) local P: TPair -> UA.TPair (got '$($m.Target)')" ($m.Target -ceq 'UA.TPair')
$m = Intf 'uSplit'; Check "A3 uSplit interface mention (impl uses UB not visible yet) -> UA.TPair (got '$($m.Target)')" ($m.Target -ceq 'UA.TPair')
$m = Impl 'uSplit'; Check "A3 uSplit implementation mention (impl uses UB shadows UA) -> UB.TPair (got '$($m.Target)')" ($m.Target -ceq 'UB.TPair')
$m = Impl 'uSolo';  Check "A4 CONTROL uSolo (uses UA) -> UA.TPair (got '$($m.Target)')" ($m.Target -ceq 'UA.TPair')
$m = Impl 'uOwn';   Check "A5 CONTROL uOwn own TPair shadows UA / UB -> uOwn.TPair (got '$($m.Target)')" ($m.Target -ceq 'uOwn.TPair')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
