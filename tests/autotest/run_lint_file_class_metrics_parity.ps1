<#
  run_lint_file_class_metrics_parity.ps1 -- single-file lint scoping, step 2
  (docs\superpowers\plans\2026-10-14-single-file-lint-scoping-step2.md).

  TClassMetrics.Run used to compute every metric for every class in the index
  -- including ComputeAllFanIn (6.3 s on ORM3) for fan-in / instability, two
  rules that ship OFF and whose findings the final filter then dropped -- and
  `lint <file>` kept one file's answers. It now (a) visits only the file's
  classes when linting one file and (b) skips a metric the verb's own filter
  would drop. Both are only acceptable if the answers do not move:

  P1  PARITY, FULL TUPLES, EVERY FILE, defaults: class-metric findings from
      `lint <file>` equal lint-all's for that file.
  P1b the same with `--enable fan-in` -- the CONFIG opt-in path must reach the
      skip predicate, or an enabled rule silently reports nothing.
  P2  POSITIVE CONTROLS: deep-inheritance and too-many-children fire on
      defaults (too-many-children across files: the children live in uKids);
      fan-in fires under --enable. Without these P1 compares empty sets.
  P3  SCOPE IS REAL: DRAGLINT_PROFILE `per-class loop N class(es)` is the
      file's own class count per file, and every class for lint-all.
  P3b SKIP IS REAL: `ComputeAllFanIn skipped` on defaults; NOT skipped when
      fan-in is enabled.
  P4  --rule fan-in (OFF by default) still computes and reports it.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_file_class_metrics_$PID"
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

# uBase: TBase, and a TD0..TD8 chain -> deep-inheritance (DIT > 6) on TD7/TD8.
$chain = (1..8 | ForEach-Object { "  TD$($_) = class(TD$($_ - 1))`n  end;" }) -join "`n"
Write-Ascii (Join-Path $proj 'uBase.pas') @"
unit uBase;

interface

type
  TBase = class
  end;

  TD0 = class
  end;
$chain

implementation

end.
"@

# uKids: eleven direct subclasses of TBase IN ANOTHER UNIT -> too-many-children
# (NOC > 10) on TBase, which only a whole-store inventory can see.
$kids = (1..11 | ForEach-Object { "  TK$($_) = class(TBase)`n  end;" }) -join "`n"
Write-Ascii (Join-Path $proj 'uKids.pas') @"
unit uKids;

interface

uses
  uBase;

type
$kids

implementation

end.
"@

Write-Ascii (Join-Path $proj 'uHub.pas') @'
unit uHub;

interface

type
  THub = class
  end;

implementation

end.
'@

# uUsers: 21 classes each holding a THub -> fan-in 21 (> 20) on THub when enabled.
$users = (1..21 | ForEach-Object { "  TU$($_) = class`n  public`n    F: THub;`n  end;" }) -join "`n"
Write-Ascii (Join-Path $proj 'uUsers.pas') @"
unit uUsers;

interface

uses
  uHub;

type
$users

implementation

end.
"@

# uEmpty: no classes at all -> the per-class loop visits 0.
Write-Ascii (Join-Path $proj 'uEmpty.pas') @'
unit uEmpty;

interface

function Nothing: Integer;

implementation

function Nothing: Integer;
begin
  Result:= 0;
end;

end.
'@

$db  = Join-Path $WorkDir 'cm.sqlite'
$idx = & $exePath index $proj --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

$CM = @('too-many-children','deep-inheritance','high-response','high-coupling','low-cohesion',
        'middle-man','fan-out','fan-in','instability','feature-envy')
$FILES = [ordered]@{ 'uBase.pas' = 10; 'uKids.pas' = 11; 'uHub.pas' = 1; 'uUsers.pas' = 21; 'uEmpty.pas' = 0 }

function Rows($json) { @(if ($json.Trim()) { $json | ConvertFrom-Json } else { @() }) }
function CmTuples($rows, $fileAbs) {
  @($rows | Where-Object { $CM -contains $_.rule -and
                           $_.file_path.ToLowerInvariant() -eq $fileAbs.ToLowerInvariant() } |
           ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.rule, $_.severity, $_.start_line, $_.start_col, $_.message } |
           Sort-Object)
}
function ProfInt($text, $pattern) { if ($text -match $pattern) { [int]$Matches[1] } else { -1 } }

$env:DRAGLINT_PROFILE = '1'
foreach ($mode in @(@{ Name = 'defaults'; Args = @() }, @{ Name = '--enable fan-in'; Args = @('--enable','fan-in') })) {
  $tag     = $mode.Name
  $allErr  = Join-Path $WorkDir 'all.err'
  $allRows = Rows (& $exePath lint-all --db $db --rules-dir $rules --json @($mode.Args) 2>$allErr | Out-String)
  $allProf = Get-Content $allErr -Raw
  $allIds  = @($allRows | Where-Object { $CM -contains $_.rule } | ForEach-Object { $_.rule } | Sort-Object -Unique)

  if ($tag -eq 'defaults') {
    Check "P2  CONTROL [$tag]: lint-all reports deep-inheritance"  ($allIds -contains 'deep-inheritance')  "fixture TD0..TD8 should exceed DIT 6"
    Check "P2  CONTROL [$tag]: lint-all reports too-many-children (children in another unit)" ($allIds -contains 'too-many-children') "uKids holds 11 subclasses of TBase"
    Check "P2  CONTROL [$tag]: fan-in is NOT reported (it ships OFF)" ($allIds -notcontains 'fan-in') "if it is, the OFF list changed and P3b is measuring something else"
    Check "P3b [$tag]: lint-all skips ComputeAllFanIn" ($allProf -match 'ComputeAllFanIn\s+skipped') "profile: no 'ComputeAllFanIn skipped' line"
  } else {
    Check "P2  CONTROL [$tag]: lint-all reports fan-in on THub" ($allIds -contains 'fan-in') "uUsers holds 21 classes coupled to THub"
    Check "P3b [$tag]: lint-all does NOT skip ComputeAllFanIn when fan-in is enabled" ($allProf -notmatch 'ComputeAllFanIn\s+skipped') "the enable must reach the skip predicate"
  }
  $allN = ProfInt $allProf 'per-class loop\s+(\d+) class\(es\)'
  Check "P3  [$tag]: lint-all's per-class loop visits every class (43)" ($allN -eq 43) "visited: $allN (-1 = profile line absent)"

  foreach ($leaf in $FILES.Keys) {
    $abs     = Join-Path $proj $leaf
    $oneErr  = Join-Path $WorkDir 'one.err'
    $oneRows = Rows (& $exePath lint $abs --db $db --rules-dir $rules --json @($mode.Args) 2>$oneErr | Out-String)
    $oneProf = Get-Content $oneErr -Raw
    $want    = @(CmTuples $allRows $abs)
    $got     = @(CmTuples $oneRows $abs)
    $diff    = @(Compare-Object $want $got)
    Check "P1  [$tag] $leaf -- class-metric findings == lint-all's, full tuples ($($want.Count))" `
          ($diff.Count -eq 0) `
          ("lint-all only: " + (($diff | Where-Object SideIndicator -eq '<=').InputObject -join ' ; ') +
           " || per-file only: " + (($diff | Where-Object SideIndicator -eq '=>').InputObject -join ' ; '))
    $n = ProfInt $oneProf 'per-class loop\s+(\d+) class\(es\)'
    Check "P3  [$tag] $leaf -- per-class loop visits only this file's classes ($($FILES[$leaf]))" `
          ($n -eq $FILES[$leaf]) "visited: $n (-1 = profile line absent)"
  }
}
$env:DRAGLINT_PROFILE = $null

$hubAbs  = Join-Path $proj 'uHub.pas'
$ruleRows = Rows (& $exePath lint $hubAbs --db $db --rules-dir $rules --rule fan-in --json 2>$null | Out-String)
$ruleGot  = @(CmTuples $ruleRows $hubAbs)
Check 'P4  --rule fan-in (OFF by default) still computes it: THub reported, Ca 21' `
      (($ruleGot.Count -eq 1) -and ($ruleGot[0] -match 'THub is referenced by 21 other classes')) `
      ("got: " + ($ruleGot -join ' ; '))

# M: A MARKER ON A METRIC THE FILTER DROPS MUST STILL BE ACCOUNTED FOR.
# ApplyLineMarkers runs BEFORE the config filter on purpose, so a fan-in finding
# (fan-in ships OFF) used to satisfy `dl:ok fan-in` and was then dropped. A skip
# that ignored markers turned that marker into a review-marker-unused hint
# telling the reader to delete a review that is doing its job (whole-branch
# review, 2026-10-14). Same fixture, one marker added on THub's declaration line.
Write-Ascii (Join-Path $proj 'uHub.pas') @'
unit uHub;

interface

type
  THub = class // dl:ok fan-in@a95e -- hub by design, referenced everywhere
  end;

implementation

end.
'@
$idx2 = & $exePath index $proj --db $db 2>&1 | Out-String
Check 'SANITY: marker fixture re-indexed' ($LASTEXITCODE -eq 0) $idx2

function UnusedOnHub($rows) { @($rows | Where-Object { $_.rule -like 'review-marker-*' -and $_.file_path -like '*uHub.pas' } |
                                ForEach-Object { '{0}:{1} {2}' -f $_.rule, $_.start_line, $_.message }) }
$env:DRAGLINT_PROFILE = '1'
$mAllErr  = Join-Path $WorkDir 'mall.err'
$mAllRows = Rows (& $exePath lint-all --db $db --rules-dir $rules --json 2>$mAllErr | Out-String)
$mOneErr  = Join-Path $WorkDir 'mone.err'
$mOneRows = Rows (& $exePath lint $hubAbs --db $db --rules-dir $rules --json 2>$mOneErr | Out-String)
$env:DRAGLINT_PROFILE = $null
$ua = @(UnusedOnHub $mAllRows | Where-Object { $_ -like 'review-marker-unused*' -or $_ -like 'review-marker-stale*' })
$uo = @(UnusedOnHub $mOneRows | Where-Object { $_ -like 'review-marker-unused*' -or $_ -like 'review-marker-stale*' })
Check 'M1  lint-all: `dl:ok fan-in` on THub is NOT reported unused/stale on defaults' ($ua.Count -eq 0) ($ua -join ' ; ')
Check 'M2  lint uHub.pas: the same marker is NOT reported unused/stale' ($uo.Count -eq 0) ($uo -join ' ; ')
Check 'M3  the marker pins the metric: neither verb skips ComputeAllFanIn' `
      (((Get-Content $mAllErr -Raw) -notmatch 'ComputeAllFanIn\s+skipped') -and ((Get-Content $mOneErr -Raw) -notmatch 'ComputeAllFanIn\s+skipped')) `
      "a marked rule must be computed even though the final filter drops it"
Check 'M3b CONTROL: fan-in itself is still NOT reported (the filter still drops it)' `
      (@($mAllRows | Where-Object { $_.rule -eq 'fan-in' }).Count -eq 0) "pinning a rule for its marker must not turn it on"

Write-Host ''
if ($fail) { Write-Host 'run_lint_file_class_metrics_parity: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_file_class_metrics_parity: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:DRAGLINT_PROFILE = $null
  foreach ($d23 in @("C:\TEMP\draglint_file_class_metrics_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
