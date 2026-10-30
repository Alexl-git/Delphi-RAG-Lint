<#
  run_type_prefix_exception_no_db.ps1 -- type-name-prefix must recognise an
  exception class when the index cannot see its ancestry (Gitea drag-lint#3).

  THE DEFECT. NamingChecks decided "exception class" ONLY through
  AStore.IsDescendantOf(..., 'Exception'). With no store -- every `lint <file>`
  without --db, the IDE gutter -- or with an ancestor outside the index
  (EAbort, no RTL index), the class was taken for an ordinary one: every
  exception was told to start with "T", and a badly named exception was told
  "T" instead of "E". The fallback reads the first ancestor as written.

  WHAT THIS ASSERTS (lint without --db unless stated)
    1. EFooError = class(Exception), EBarError = class(EFooError),
       EAbortLike = class(EAbort), EQual = class(System.SysUtils.Exception):
       no finding                                                    <- THE FIX
    2. BadExc = class(Exception): asked for the "E" prefix, not "T"   <- THE FIX
    3. CONTROL: Widget = class(TObject) and EWidget = class(TObject)
       still asked for "T" (an E-name does not make a class an exception)
    4. EX = class(Engine): NO verdict store-free. Engine is outside the
       index, so the origin is unknown and the rule stays silent rather than
       guess a letter from a name (main d5c20ad3, three-valued class origin;
       docs\INBOX-type-name-prefix-exception-ancestry.md). Check 3 is the
       live control that the rule is still on.
    5. CONTROL: with --db the same fixture gives the same answers
    6. with --db: TEdiReader = class(EDIParser), EDIParser = class(TObject):
       no finding; EdiWriter on the same chain asked for "T", not "E"

  RED-CHECK: against the pre-fix build 1, 2 and 5 FAIL -- 5 because EAbort is
  RTL and not in the fixture's index, so even WITH --db EAbortLike was told
  "T"; 3 passes on both builds.
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

$work = Join-Path C:\TEMP "draglint_excprefix_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Exc.dpr') @'
program Exc;

uses
  UExc in 'UExc.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UExc.pas') @'
unit UExc;

interface

uses
  System.SysUtils;

type
  EFooError = class(Exception);
  EBarError = class(EFooError);
  EAbortLike = class(EAbort);
  EQual = class(System.SysUtils.Exception);
  BadExc = class(Exception);
  Widget = class(TObject);
  EWidget = class(TObject);
  EX = class(Engine);
  EDIParser = class(TObject);
  TEdiReader = class(EDIParser);
  EdiWriter = class(EDIParser);

implementation

end.
'@
$unit = Join-Path $dir 'UExc.pas'

function Findings([string[]]$Extra) {
  $out = (& $Exe lint $unit --rule type-name-prefix @Extra 2>$null) -join "`n"
  return @($out -split "`n" | Where-Object { $_ -match 'type-name-prefix' })
}
# The comma keeps a one-element result an array (PowerShell unrolls it otherwise).
function About($hits, [string]$name) { return ,@($hits | Where-Object { $_ -match "`"$name`"" }) }

Write-Host ''
Write-Host '=== no --db ===' -ForegroundColor Cyan
$h = Findings @()
$h | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
$excFp = @(foreach ($n in 'EFooError','EBarError','EAbortLike','EQual') { About $h $n | ForEach-Object { $_ } })
Check '1. exception classes with an E name: no finding' ($excFp.Count -eq 0) ($excFp -join ' | ')
$bad = About $h 'BadExc'
Check '2. BadExc = class(Exception) is asked for "E"' (($bad.Count -eq 1) -and ($bad[0] -match 'Exception class "BadExc" should start with the "E" prefix')) ($bad -join ' | ')
$w = About $h 'Widget'; $ew = About $h 'EWidget'
Check '3. CONTROL: Widget and EWidget (class(TObject)) still asked for "T"' `
  (($w.Count -ge 1) -and ($w[0] -match '"T" prefix') -and ($ew.Count -eq 1) -and ($ew[0] -match '"T" prefix')) "w=$($w -join ' | ') ew=$($ew -join ' | ')"
$ex = About $h 'EX'
Check '4. EX = class(Engine): unknown origin store-free, no verdict (d5c20ad3)' ($ex.Count -eq 0) ($ex -join ' | ')

Write-Host ''
Write-Host '=== with --db (CONTROL) ===' -ForegroundColor Cyan
$db = Join-Path $work 'e.sqlite'
& $Exe index --project (Join-Path $dir 'Exc.dpr') --db $db *> $null
$hd = Findings @('--db', $db)
$hd | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
$excDb = @(foreach ($n in 'EFooError','EBarError','EAbortLike','EQual') { About $hd $n | ForEach-Object { $_ } })
$badDb = About $hd 'BadExc'
Check '5. CONTROL: with --db the same answers' `
  (($excDb.Count -eq 0) -and ($badDb.Count -eq 1) -and ($badDb[0] -match '"E" prefix') -and ((About $hd 'EWidget').Count -eq 1)) "exc=$($excDb -join ' | ') bad=$($badDb -join ' | ')"

# 6. The store PROVES EDIParser is a plain class (an E-style NAME, TObject
#    ancestry): a descendant is never taken for an exception by its ancestor's
#    written name. TEdiReader is correct as written; EdiWriter is asked for "T",
#    not "E" -- the positive control that the rule still fires on this chain.
$rd = About $hd 'TEdiReader'; $wr = About $hd 'EdiWriter'
Check '6. with --db: class(EDIParser) where EDIParser = class(TObject) is a plain class' `
  (($rd.Count -eq 0) -and ($wr.Count -eq 1) -and ($wr[0] -match '"T" prefix')) "reader=$($rd -join ' | ') writer=$($wr -join ' | ')"
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_excprefix_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
