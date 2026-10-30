<#
  run_output_caps.ps1 -- outline --kind / --no-locals / --limit, usages --limit
  and query unit-usage --limit (Gitea #38).

  WHY. An agent asking about one large unit got 94,000 characters from
  `outline` (UConfig.pas: 1,587 rows, 701 local_var and 330 param), 144,000 from
  `usages --format json` and 27,000 from `query unit-usage`, with nothing to
  narrow them. The IDE reads outline and usages whole, so every option is
  opt-in: without one the output is unchanged.

  Checks:
    C1  outline (no option): local_var and param rows are still there
    C2  outline --no-locals: neither kind, the class and its method stay
    C3  outline --kind method: only method rows
    C4  outline --limit 2: two rows, then a line saying how many matched
    C5  outline --format json --limit 2: an array of two, the note on stderr
    C6  usages --json (no option): no "limit" / "totals" keys
    C7  usages --json --limit 1: each group at most one row, totals carry the full counts
    C8  query unit-usage (no option): every importer listed (the three units and P.dpr)
    C9  query unit-usage --limit 1: one importer, a note, the summary still counts all
    C10 query unit-usage --json --limit 1: an array of one, the note on stderr

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_caps_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uLib.pas') @'
unit uLib;

interface

type
  TBox = class
  public
    V: Integer;
    procedure Put(A, B: Integer);
  end;

var
  GBox: TBox;

implementation

procedure TBox.Put(A, B: Integer);
var
  Sum: Integer;
begin
  Sum:= A + B;
  V:= Sum;
end;

end.
'@
$users = @()
foreach ($n in 1..3) {
  $users += "uUser$n"
  Write-Ascii (Join-Path $src "uUser$n.pas") @"
unit uUser$n;

interface

procedure Run$n;

implementation

uses
  uLib;

procedure Run$n;
begin
  GBox.Put(GBox.V, $n);
end;

end.
"@
}
Write-Ascii (Join-Path $src 'P.dpr') @"
program P;

uses
  uLib, $($users -join ', ');

begin
end.
"@
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $src 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx
$lib = Join-Path $src 'uLib.pas'
$errF = Join-Path $WorkDir 'err.txt'
function Rows([string]$Text) { @($Text -split "`r?`n" | Where-Object { $_ -match '^[a-z_]+\s+\S+\s+\d+(\s|$)' }) }

# --- outline ---------------------------------------------------------------------
$o1 = & $exePath outline --file $lib --db $db 2>&1 | Out-String
Check 'C1 outline (no option): local_var and param rows are still there' (($o1 -match '(?m)^local_var') -and ($o1 -match '(?m)^param')) $o1

$o2 = & $exePath outline --file $lib --db $db --no-locals 2>&1 | Out-String
Check 'C2 outline --no-locals: neither kind, the class and its method stay' (($LASTEXITCODE -eq 0) -and ($o2 -notmatch '(?m)^(local_var|param)\b') -and ($o2 -match 'uLib\.TBox\b') -and ($o2 -match 'uLib\.TBox\.Put')) $o2

$o3 = & $exePath outline --file $lib --db $db --kind method 2>&1 | Out-String
$r3 = Rows $o3
Check 'C3 outline --kind method: only method rows' (($r3.Count -ge 1) -and (@($r3 | Where-Object { $_ -notmatch '^method\s' }).Count -eq 0)) $o3

$all = (Rows $o1).Count
$o4 = & $exePath outline --file $lib --db $db --limit 2 2>&1 | Out-String
Check 'C4 outline --limit 2: two rows, then how many matched' (((Rows $o4).Count -eq 2) -and ($o4 -match "first 2 of $all row\(s\)")) $o4

$o5 = & $exePath outline --file $lib --db $db --format json --limit 2 2>$errF | Out-String
$e5 = Get-Content $errF -Raw
$j5 = $null; try { $j5 = $o5 | ConvertFrom-Json } catch { }
Check 'C5 outline --format json --limit 2: an array of two, the note on stderr' (($null -ne $j5) -and (@($j5).Count -eq 2) -and ($e5 -match "first 2 of $all row\(s\)")) "stdout: $o5 | stderr: $e5"

# --- usages ----------------------------------------------------------------------
$u6 = & $exePath usages --name GBox --json --db $db 2>$null | Out-String
$j6 = $u6 | ConvertFrom-Json
$reads = @($j6.reads).Count
Check 'C6 usages --json (no option): no "limit" / "totals" keys' (($null -eq $j6.PSObject.Properties['limit']) -and ($null -eq $j6.PSObject.Properties['totals']) -and ($reads -ge 3)) "reads: $reads"

$u7 = & $exePath usages --name GBox --json --limit 1 --db $db 2>$null | Out-String
$j7 = $null; try { $j7 = $u7 | ConvertFrom-Json } catch { }
$groupsOk = $null -ne $j7
if ($groupsOk) { foreach ($g in 'declarations', 'reads', 'writes', 'calls', 'types', 'attributes', 'events') { if (@($j7.$g).Count -gt 1) { $groupsOk = $false } } }
Check 'C7 usages --json --limit 1: each group at most one row, totals carry the full counts' ($groupsOk -and ($j7.limit -eq 1) -and ($j7.totals.reads -eq $reads)) $u7

# --- query unit-usage --------------------------------------------------------------
$q8 = & $exePath query unit-usage --unit uLib --db $db 2>&1 | Out-String
Check 'C8 query unit-usage (no option): every importer listed' ((@($users | Where-Object { $q8 -match "$_\.pas" }).Count -eq 3) -and ($q8 -match '3 of 4 importing file')) $q8

$q9 = & $exePath query unit-usage --unit uLib --db $db --limit 1 2>&1 | Out-String
Check 'C9 query unit-usage --limit 1: one importer, a note, the summary still counts all' ((@($q9 -split "`r?`n" | Where-Object { $_ -match '^\s+\S+\.(pas|dpr)\s+uses\(' }).Count -eq 1) -and ($q9 -match 'first 1 of 4 importing file') -and ($q9 -match '3 of 4 importing file\(s\) reference it')) $q9

$q10 = & $exePath query unit-usage --unit uLib --db $db --json --limit 1 2>$errF | Out-String
$e10 = Get-Content $errF -Raw
$j10 = $null; try { $j10 = $q10 | ConvertFrom-Json } catch { }
Check 'C10 query unit-usage --json --limit 1: an array of one, the note on stderr' (($null -ne $j10) -and (@($j10).Count -eq 1) -and ($e10 -match 'first 1 of 4 importing file')) "stdout: $q10 | stderr: $e10"
}
finally {
  $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
