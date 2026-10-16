<#
  run_find_callees_overloads.ps1 -- find-callees on an overloaded name must say
  which overload each call leaves from and which overload it reaches (Gitea
  drag-lint#12).

  THE DEFECT. The callees of every overload of the qname were unioned and each
  line carried only the target qname. A wrapper overload calling its sibling
  therefore listed the routine as a callee of ITSELF, `[certain]`, which reads
  as recursion; on ProjectA `UFSummaryReport.TSummaryPrint.ImportItems` did exactly
  that. The index was right -- the edge goes from one overload's symbol to the
  other's -- only the output dropped the distinction.

  WHAT THIS ASSERTS
    1. text: one header per source overload, with its signature     <- THE FIX
    2. text: OnlyFirst is listed under the first overload, OnlySecond under
       the second                                                   <- THE FIX
    3. text: the call to the sibling names the TARGET overload      <- THE FIX
    4. json: from_signature on every edge; target_signature on the edge to
       the overloaded target                                        <- THE FIX
    5. CONTROL: a unique routine calling unique targets prints exactly
       "  <qname>  [certain]" lines -- no header, no suffix, no new JSON keys

  RED-CHECK: against the pre-fix build 1-4 FAIL; 5 passes on both builds.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

$work = Join-Path C:\TEMP "draglint_fcovl_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Over.dpr') @'
program Over;

uses
  uOver in 'uOver.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'uOver.pas') @'
unit uOver;

interface

type
  TWorker = class
  public
    procedure OnlyFirst;
    procedure OnlySecond;
    procedure Plain;
    procedure Run(const A: string); overload;
    procedure Run(const A: string; B: Integer); overload;
  end;

implementation

procedure TWorker.OnlyFirst;
begin
end;

procedure TWorker.OnlySecond;
begin
end;

procedure TWorker.Plain;
begin
  OnlyFirst;
  OnlySecond;
end;

procedure TWorker.Run(const A: string);
begin
  OnlyFirst;
  Run(A, 1);
end;

procedure TWorker.Run(const A: string; B: Integer);
begin
  OnlySecond;
end;

end.
'@
$db = Join-Path $work 'o.sqlite'
& $Exe index --project (Join-Path $dir 'Over.dpr') --db $db *> $null
Check 'seed: index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host ''
Write-Host '=== overloaded source: uOver.TWorker.Run ===' -ForegroundColor Cyan
$txt = @(& $Exe find-callees --qname uOver.TWorker.Run --db $db 2>$null)
Write-Host ($txt -join "`n") -ForegroundColor DarkGray
$h1 = -1; $h2 = -1
for ($i = 0; $i -lt $txt.Count; $i++) {
  if ($txt[$i] -match '^uOver\.TWorker\.Run\s+.*\(const A: string\)' -and $txt[$i] -notmatch 'B: Integer') { $h1 = $i }
  if ($txt[$i] -match '^uOver\.TWorker\.Run\s+.*B: Integer') { $h2 = $i }
}
Check '1. one header per overload, each with its signature' (($h1 -ge 0) -and ($h2 -ge 0)) "h1=$h1 h2=$h2"
function Under([int]$from, [string]$rx) {
  if ($from -lt 0) { return $false }
  for ($k = $from + 1; $k -lt $txt.Count; $k++) {
    if ($txt[$k] -match '^\S') { return $false }   # next header
    if ($txt[$k] -match $rx) { return $true }
  }
  return $false
}
Check '2. OnlyFirst under the 1st overload, OnlySecond under the 2nd' `
  ((Under $h1 'OnlyFirst') -and (Under $h2 'OnlySecond') -and -not (Under $h1 'OnlySecond') -and -not (Under $h2 'OnlyFirst')) ''
$sib = @($txt | Where-Object { $_ -match '^\s+uOver\.TWorker\.Run\s+\[' })
Check '3. the call to the sibling names the target overload' `
  (($sib.Count -eq 1) -and ($sib[0] -match '-> overload .*B: Integer')) "line=$($sib -join ' | ')"

$js = (& $Exe find-callees --qname uOver.TWorker.Run --db $db --json 2>$null) -join "`n"
$arr = @($js | ConvertFrom-Json)
$allFrom = @($arr | Where-Object { -not $_.from_signature }).Count -eq 0
$toSib = @($arr | Where-Object { $_.target_qname -eq 'uOver.TWorker.Run' })
Check '4. json: from_signature everywhere; target_signature on the sibling call' `
  ($allFrom -and ($arr.Count -ge 3) -and ($toSib.Count -eq 1) -and ($toSib[0].target_signature -match 'B: Integer')) "n=$($arr.Count)"

Write-Host ''
Write-Host '=== CONTROL: unique routine, unique targets ===' -ForegroundColor Cyan
$plain = @(& $Exe find-callees --qname uOver.TWorker.Plain --db $db 2>$null | Where-Object { $_ -ne '' })
$pj = (& $Exe find-callees --qname uOver.TWorker.Plain --db $db --json 2>$null) -join "`n"
# Since Gitea drag-lint#37 every line also carries `at <site>  -> <callee location>`;
# what this CONTROL guards is unchanged: one line per edge, no overload annotation.
$shapeOk = (@($plain | Where-Object { $_ -notmatch '^  uOver\.TWorker\.Only(First|Second)  \[certain\]  at \S+:\d+  -> \S+:\d+$' }).Count -eq 0) -and ($plain.Count -eq 2)
Check '5. CONTROL: plain "  <qname>  [certain]  at <site>  -> <where>" lines and no overload JSON keys' `
  ($shapeOk -and -not ($pj -match 'from_signature|target_signature')) "lines=$($plain -join ' | ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_fcovl_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
