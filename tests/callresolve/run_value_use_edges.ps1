<#
  run_value_use_edges.ps1 -- 147 B1 leftover (149 RB2 item 4): a property or field use is a
  member_accesses row (mode read / write); a bound VALUE -- a unit-level var, a const, a
  class var, an enum value -- was identity only (refs.symbol_id, no row), so every consumer
  that reads use edges (cycles plan, charts, usages) saw no use of it.

  THE FIX: TCallResolver.ValueUseEdge; Storage ResolveValueReadRefs / ResolveEnumValueRefs
  (reads) and ResolveWriteEdge (writes) record the row for a unit- or class-level var / const
  or an enum value. A routine-local const, a local and a parameter stay identity only.

  Pins (uUser reads / writes uVals' values):
    A1 GCount (unit var)     read -> member_accesses read,  receiver type NULL
    A2 GCount (unit var)     write -> member_accesses write
    A3 MAX_N (unit const)    read -> read
    A4 vkTwo (enum value)    read -> read, receiver type = uVals.TValKind
    A5 TBox.Shared (class var, bare inside TBox) write -> write, receiver type = uVals.TBox
  CONTROLS (green on both engines): A6 LOCAL_C (routine-local const) read is bound but has NO
  row; A7 L (local var) write has NO row; A8 every pinned site is still bound (refs.symbol_id).
  POSITIVE CONTROL: on 1.48.0-alpha A1-A5 are RED (no rows), A6-A8 green.
  Run from any CWD, pwsh 7. Pass -Exe with the engine under test.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_value_use_$PID"
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

W $WorkDir 'uVals.pas' @'
unit uVals;
interface
type
  TValKind = (vkOne, vkTwo);
  TBox = class
  public
    class var Shared: Integer;
    procedure Bump;
  end;
const
  MAX_N = 10;
var
  GCount: Integer;
implementation
procedure TBox.Bump;
begin
  Shared:= 1; // A5
end;
end.
'@
W $WorkDir 'uUser.pas' @'
unit uUser;
interface
procedure Go;
implementation
uses uVals;
procedure Go;
const
  LOCAL_C = 3;
var
  L: Integer;
  K: TValKind;
begin
  L:= GCount; // A1
  GCount:= 2; // A2
  L:= MAX_N; // A3
  K:= vkTwo; // A4
  L:= LOCAL_C; // A6
  L:= 5; // A7
  if K = vkOne then L:= L + 1;
end;
end.
'@
W $WorkDir 'App.dpr' @'
program App;
uses
  uVals in 'uVals.pas',
  uUser in 'uUser.pas';
begin
end.
'@

$db = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V index built' (Test-Path $db) $db
$raw = & $exePath sql --db $db --json --limit 500 --query "SELECT f.path, r.start_line, r.kind, r.name_text, CASE WHEN r.symbol_id IS NULL THEN 0 ELSE 1 END, coalesce(m.mode,''), coalesce(t.qualified_name,'') FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN member_accesses m ON m.ref_id = r.id LEFT JOIN symbols t ON t.id = m.receiver_type_symbol_id WHERE r.kind IN ('read','write') ORDER BY f.path, r.start_line" | Out-String
Pop-Location
$rows = foreach ($r in ($raw | ConvertFrom-Json).rows) { [pscustomobject]@{ File=[IO.Path]::GetFileNameWithoutExtension([string]$r[0]); Line=[int]$r[1]; Kind=[string]$r[2]; Name=[string]$r[3]; Bound=[int]$r[4]; Mode=[string]$r[5]; Rcv=[string]$r[6] } }
Check "V read/write refs were read ($(@($rows).Count))" (@($rows).Count -ge 7) $raw
function MarkLine($file,$tag){ $m=@(Select-String -LiteralPath (Join-Path $WorkDir "$file.pas") -SimpleMatch -Pattern "// $tag"); if($m.Count -ne 1){ throw "marker $tag x$($m.Count)" }; [int]$m[0].LineNumber }
function Site($file,$tag,$name,$kind){ $ln = MarkLine $file $tag; @($rows | Where-Object { $_.File -eq $file -and $_.Line -eq $ln -and $_.Name -eq $name -and $_.Kind -eq $kind }) | Select-Object -First 1 }
function Desc($s){ if($null -eq $s){ '<no ref>' } else { "bound=$($s.Bound) mode='$($s.Mode)' rcv='$($s.Rcv)'" } }

$s = Site 'uUser' 'A1' 'GCount' 'read';  Check "A1 GCount read -> member_accesses read, no receiver ($(Desc $s))" ($null -ne $s -and $s.Mode -eq 'read' -and $s.Rcv -eq '')
$s = Site 'uUser' 'A2' 'GCount' 'write'; Check "A2 GCount write -> member_accesses write ($(Desc $s))" ($null -ne $s -and $s.Mode -eq 'write')
$s = Site 'uUser' 'A3' 'MAX_N' 'read';   Check "A3 MAX_N read -> member_accesses read ($(Desc $s))" ($null -ne $s -and $s.Mode -eq 'read')
$s = Site 'uUser' 'A4' 'vkTwo' 'read';   Check "A4 vkTwo read -> read, receiver uVals.TValKind ($(Desc $s))" ($null -ne $s -and $s.Mode -eq 'read' -and $s.Rcv -ceq 'uVals.TValKind')
$s = Site 'uVals' 'A5' 'Shared' 'write'; Check "A5 class var Shared write -> write, receiver uVals.TBox ($(Desc $s))" ($null -ne $s -and $s.Mode -eq 'write' -and $s.Rcv -ceq 'uVals.TBox')
$s = Site 'uUser' 'A6' 'LOCAL_C' 'read'; Check "A6 CONTROL routine-local const read is bound, NO row ($(Desc $s))" ($null -ne $s -and $s.Bound -eq 1 -and $s.Mode -eq '')
$s = Site 'uUser' 'A7' 'L' 'write';      Check "A7 CONTROL local var write has NO row ($(Desc $s))" ($null -ne $s -and $s.Mode -eq '')
$all = @(foreach ($p in @(@('uUser','A1','GCount','read'),@('uUser','A2','GCount','write'),@('uUser','A3','MAX_N','read'),@('uUser','A4','vkTwo','read'),@('uVals','A5','Shared','write'))) { Site $p[0] $p[1] $p[2] $p[3] })
Check "A8 CONTROL the five pinned sites are bound (refs.symbol_id)" ((@($all | Where-Object { $_ -and $_.Bound -eq 1 })).Count -eq 5) (($all | ForEach-Object { Desc $_ }) -join '; ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
