<#
  run_context_overload_bodies.ps1 -- `context` on an overloaded routine must
  carry the body of EVERY overload and say there are several (Gitea
  drag-lint#18).

  THE DEFECT. The bundle resolved the qname to one symbol per overload and
  sliced only Syms[0]. On ProjectA `context --task "modify
  UFSummaryReport.TSummaryPrint.ImportItems"` showed the 6-line wrapper overload and
  left out the overload it delegates to, where the work is -- with nothing in
  the bundle saying another body existed. `context` is the verb a session runs
  BEFORE editing a routine, so the edit was planned against half of it.

  WHAT THIS ASSERTS
    1. markdown: the impl slice holds BOTH overload bodies          <- THE FIX
    2. markdown: the header says the name covers 2 routines         <- THE FIX
    3. json: "overloads":2                                          <- THE FIX
    4. CONTROL: a unique routine's bundle has its body, no OVERLOADED line,
       and "overloads":1
    5. CONTROL: the wrapper body comes before the worker body (source order)

  RED-CHECK: against the pre-fix build 1, 2 and 3 FAIL (only the first body;
  no header line; no "overloads" key), and 4 fails only on the new key; 5
  passes on both builds (trivially pre-fix, since only one body is there).
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

$work = Join-Path C:\TEMP "draglint_ctxovl_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Ovl.dpr') @'
program Ovl;

uses
  UOvl in 'UOvl.pas';

begin
end.
'@
# The wrapper overload comes first, as in ImportItems: a short body that
# delegates to the overload doing the work.
Write-Ascii (Join-Path $dir 'UOvl.pas') @'
unit UOvl;

interface

type
  TWorker = class
  public
    function Run(const A: string): Integer; overload;
    function Run(const A: string; B: Integer): Integer; overload;
    function Single(X: Integer): Integer;
  end;

implementation

function TWorker.Run(const A: string): Integer;
begin
  Result := Run(A, 1); { WRAPPER_BODY_MARK }
end;

function TWorker.Run(const A: string; B: Integer): Integer;
begin
  Result := Length(A) * B; { WORKER_BODY_MARK }
end;

function TWorker.Single(X: Integer): Integer;
begin
  Result := X + 1; { SINGLE_BODY_MARK }
end;

end.
'@
$db = Join-Path $work 'o.sqlite'
& $Exe index --project (Join-Path $dir 'Ovl.dpr') --db $db *> $null
Check 'seed: index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host ''
Write-Host '=== overloaded routine ===' -ForegroundColor Cyan
$md = (& $Exe context --task 'modify UOvl.TWorker.Run' --db $db --format markdown 2>$null) -join "`n"
Write-Host $md -ForegroundColor DarkGray
Check '1. the impl slice holds both overload bodies' `
  (($md -match 'WRAPPER_BODY_MARK') -and ($md -match 'WORKER_BODY_MARK')) ''
Check '2. the header says the name covers 2 routines' `
  ($md -match '(?m)^> OVERLOADED: `UOvl\.TWorker\.Run` names 2 routines') ''
$js = (& $Exe context --task 'modify UOvl.TWorker.Run' --db $db --format json 2>$null) -join "`n"
Check '3. json carries "overloads":2' ($js -match '"overloads":2') "json=$js"
$iW = $md.IndexOf('WRAPPER_BODY_MARK'); $iK = $md.IndexOf('WORKER_BODY_MARK')
Check '5. CONTROL: bodies in source order (wrapper first)' (($iW -ge 0) -and (($iK -lt 0) -or ($iW -lt $iK))) "wrapper=$iW worker=$iK"

Write-Host ''
Write-Host '=== unique routine (CONTROL) ===' -ForegroundColor Cyan
$md1 = (& $Exe context --task 'modify UOvl.TWorker.Single' --db $db --format markdown 2>$null) -join "`n"
$js1 = (& $Exe context --task 'modify UOvl.TWorker.Single' --db $db --format json 2>$null) -join "`n"
Check '4. CONTROL: unique routine -- body present, no OVERLOADED line, "overloads":1' `
  (($md1 -match 'SINGLE_BODY_MARK') -and -not ($md1 -match 'OVERLOADED') -and -not ($md1 -match 'WORKER_BODY_MARK') -and ($js1 -match '"overloads":1')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_ctxovl_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
