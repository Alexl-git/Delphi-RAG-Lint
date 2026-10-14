<#
  run_lint_file_scoped_loop_parity.ps1 -- single-file lint scoping, step 1
  (docs\superpowers\plans\2026-10-14-single-file-lint-scoping-step1.md).

  `lint <file> --db` used to run TProjectLintRules' per-file loop over EVERY
  file in the index and then keep this file's findings -- 7.6 s of a 36.5 s
  run on ORM3 BASICS.PAS for unused-unit-in-uses alone. It now visits one
  file. That is only acceptable if the answer for that file is unchanged, so:

  P1  PARITY, FULL TUPLES, EVERY FILE: for each fixture file, the loop rules'
      findings from `lint <file>` equal lint-all's for that file on
      rule|severity|line|col|message -- not just rule ids.
  P2  POSITIVE CONTROL: lint-all reports each of the four loop rules at least
      once, or P1 compares empty sets and proves nothing.
  P3  SCOPE IS REAL: under DRAGLINT_PROFILE the single-file run's loop visits
      exactly 1 file and lint-all's visits them all. Without this, P1 passes
      against the old whole-store code too.
  P4  --rule composes with the scoping.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_file_scoped_loop_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory -Path $proj -Force | Out-Null

# uLib: PublicNeverCalled -> unused-public-symbol; TKeeper.FNeverRead -> unused-private-member.
Write-Ascii (Join-Path $proj 'uLib.pas') @'
unit uLib;

interface

type
  TKeeper = class
  private
    FNeverRead: Integer;
    FUsed: Integer;
  public
    function Value: Integer;
  end;

procedure PublicNeverCalled;
function Used: Integer;

implementation

function TKeeper.Value: Integer;
begin
  Result:= FUsed;
end;

procedure PublicNeverCalled;
begin
end;

function Used: Integer;
begin
  Result:= 1;
end;

end.
'@

# uGod: TGod has 21 methods and 16 fields -> god-class.
$fields  = (1..16 | ForEach-Object { "    F$($_): Integer;" }) -join "`n"
$decls   = (1..21 | ForEach-Object { "    procedure M$($_);" }) -join "`n"
$bodies  = (1..21 | ForEach-Object { "procedure TGod.M$($_);`nbegin`nend;`n" }) -join "`n"
Write-Ascii (Join-Path $proj 'uGod.pas') @"
unit uGod;

interface

type
  TGod = class
  public
$fields
$decls
  end;

implementation

$bodies
end.
"@

# uMain: imports uGod and never references it -> unused-unit-in-uses (uGod only;
# uLib IS used -- the negative control inside the same uses clause).
Write-Ascii (Join-Path $proj 'uMain.pas') @'
unit uMain;

interface

uses
  uLib, uGod;

function Twice: Integer;

implementation

function Twice: Integer;
begin
  Result:= Used + Used;
end;

end.
'@

# uUser: uses uLib through TKeeper.Value -- no loop finding expected.
Write-Ascii (Join-Path $proj 'uUser.pas') @'
unit uUser;

interface

uses
  uLib;

function ReadIt(const pK: TKeeper): Integer;

implementation

function ReadIt(const pK: TKeeper): Integer;
begin
  Result:= pK.Value;
end;

end.
'@

# Proj.dpr: a program's uses clause is an inclusion list -> never unused-unit-in-uses.
Write-Ascii (Join-Path $proj 'Proj.dpr') @'
program Proj;

uses
  uLib, uGod, uMain, uUser;

begin
end.
'@

$db  = Join-Path $WorkDir 'loop.sqlite'
$idx = & $exePath index $proj --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

$LOOP = @('unused-unit-in-uses','god-class','unused-public-symbol','unused-private-member')

function LoopTuples($json, $fileAbs) {
  $rows = @(if ($json.Trim()) { $json | ConvertFrom-Json } else { @() })
  @($rows | Where-Object { $LOOP -contains $_.rule -and
                           $_.file_path.ToLowerInvariant() -eq $fileAbs.ToLowerInvariant() } |
           ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.rule, $_.severity, $_.start_line, $_.start_col, $_.message } |
           Sort-Object)
}

$env:DRAGLINT_PROFILE = '1'
$allErr  = Join-Path $WorkDir 'all.err'
$allJson = & $exePath lint-all --db $db --rules-dir $rules --json 2>$allErr | Out-String
$allProf = Get-Content $allErr -Raw

$allRules = @(($allJson | ConvertFrom-Json) | Where-Object { $LOOP -contains $_.rule } | ForEach-Object { $_.rule } | Sort-Object -Unique)
foreach ($r in $LOOP) {
  Check "P2  CONTROL: lint-all reports $r on the fixture" ($allRules -contains $r) `
        "if lint-all does not report it, P1 compares empty sets for it and proves nothing"
}

foreach ($leaf in @('uLib.pas','uGod.pas','uMain.pas','uUser.pas','Proj.dpr')) {
  $abs      = Join-Path $proj $leaf
  $fileJson = & $exePath lint $abs --db $db --rules-dir $rules --json 2>$null | Out-String
  $want     = @(LoopTuples $allJson  $abs)
  $got      = @(LoopTuples $fileJson $abs)
  $diff     = @(Compare-Object $want $got)
  Check "P1  $leaf -- per-file loop findings == lint-all's, full tuples ($($want.Count))" `
        ($diff.Count -eq 0) `
        ("lint-all only: " + (($diff | Where-Object SideIndicator -eq '<=').InputObject -join ' ; ') +
         " || per-file only: " + (($diff | Where-Object SideIndicator -eq '=>').InputObject -join ' ; '))
}

$mainAbs  = Join-Path $proj 'uMain.pas'
$oneErr   = Join-Path $WorkDir 'one.err'
& $exePath lint $mainAbs --db $db --rules-dir $rules --json 2>$oneErr | Out-Null
$oneProf  = Get-Content $oneErr -Raw
$oneN = if ($oneProf -match 'per-file loop\s+(\d+) file\(s\)') { [int]$Matches[1] } else { -1 }
$allN = if ($allProf -match 'per-file loop\s+(\d+) file\(s\)') { [int]$Matches[1] } else { -1 }
Check 'P3  single-file lint visits exactly 1 file in the per-file loop' ($oneN -eq 1) "visited: $oneN (-1 = profile line absent)"
Check 'P3b CONTROL: lint-all still visits every file' ($allN -ge 5) "visited: $allN (fixture has 5 files)"
Remove-Item Env:\DRAGLINT_PROFILE

$ruleJson = & $exePath lint $mainAbs --db $db --rules-dir $rules --rule unused-unit-in-uses --json 2>$null | Out-String
$ruleGot  = @(LoopTuples $ruleJson $mainAbs)
$ruleWant = @(LoopTuples $allJson $mainAbs | Where-Object { $_ -like 'unused-unit-in-uses|*' })
Check 'P4  --rule unused-unit-in-uses composes with the scoping (uGod only, not uLib)' `
      (($ruleWant.Count -eq 1) -and ($ruleWant[0] -match "'uGod'") -and (@(Compare-Object $ruleWant $ruleGot).Count -eq 0)) `
      ("want: " + ($ruleWant -join ' ; ') + " || got: " + ($ruleGot -join ' ; '))

Write-Host ''
if ($fail) { Write-Host 'run_lint_file_scoped_loop_parity: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_file_scoped_loop_parity: PASS' -ForegroundColor Green
exit 0
} finally {
  Remove-Item Env:\DRAGLINT_PROFILE -ErrorAction SilentlyContinue
  foreach ($d23 in @("C:\TEMP\draglint_file_scoped_loop_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
