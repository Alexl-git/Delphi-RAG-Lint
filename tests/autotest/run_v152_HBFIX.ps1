<#
  run_v152_HBFIX.ps1 -- check-init fixes from the HBMEASURE soak (lane HBFIX, 1.52).

  Source: docs\superpowers\specs\2026-11-17-happens-before-measurements.md (lane HBMEASURE), findings
  F1 (property writes), F2 / F4 (DFM-streamed fields, same-method write), F3 (wall-clock cap), F5
  (vacuous SET on zero uses). Fixtures tests\fixtures\happens-before\fields-property, fields-samewrite,
  fields-dfm, each indexed into a private DB; answers from `check-init --json` of -Exe.

    H1  a field written only through a `write FField` property is a writer (never NEVER-SET):
        TItem (outside `Item.Number:= 5`) MAY; TSelfProp (constructor `Number:= 1`) SET.
        Twins that must not move: TSelfSet SET / TCondSet MAY (setter methods), TNamed MAY,
        TUnwritten and TReadOnly NEVER-SET. An unresolved `B.Side:= ..` (B's type not inferred) is a
        soft writer: TSideHolder MAY, never NEVER-SET. A read through a `read FField` property is a
        use (TItem's `Writeln(Item.Number)`, TReadOnly's `Writeln(Ro)`).
    H2  a counting DFM-stream writer stands for the inherited form constructor: edtName SET; the
        non-streamed twin FCount stays MAY. A same-method Self write before the read stays SET while
        a read through ANOTHER object after a Self write is MAY (was a wrong SET).
    F5  zero judged uses: SET carries the limit no-judged-use and says so in the summary.
    H3  --max-seconds: a cap that has already run out answers MAY-BE-UNSET with reason budget, limit
        stopped-after, budget.timed_out; the same target uncapped stays SET; bad values exit 2.

  Parameters: -Exe (engine; default the worktree's src\cli\Win64\Debug\drag-lint.exe), -Repo, -WorkDir.
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-hbfix-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
Write-Host '== v152 HBFIX: check-init property writes, DFM fields, foreign reads, zero uses, time cap ==' -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\happens-before'

# Uses: '<file>#<marker>=<VERDICT>|<reasons -like pattern>'. Extra: Args (more CLI flags), Limit /
# NoLimit / Summary (-like patterns), Writer (a source text whose line must be a counting writer),
# TimedOut ($true / $false asserted on budget.timed_out when present in the case).
$Cases = @(
  # H1: direct write-field property
  @{ Name = 'H1 outside property write is a writer'; Fix = 'fields-property'; Target = 'fpProps.TItem.FNumber'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Writer = 'FieldsProperty.dpr#Item.Number:= 5'; Uses = @('fpProps.pas#USE-ITEM=MAY-BE-UNSET|*no-declared-ctor*',
       'FieldsProperty.dpr#USE-ITEM-PROP=MAY-BE-UNSET|*no-declared-ctor*receiver-unproven*',
       'FieldsProperty.dpr#USE-ITEM-FMT=MAY-BE-UNSET|*no-declared-ctor*receiver-unproven*') }
  @{ Name = 'H1 Self property write in ctor SET';   Fix = 'fields-property'; Target = 'fpProps.TSelfProp.FNumber'; Verdict = 'SET'; Exit = 0;
     Writer = 'fpProps.pas#  Number:= 1;'; Uses = @('fpProps.pas#USE-SELFPROP=SET|') }
  @{ Name = 'H1 twin setter always SET';            Fix = 'fields-property'; Target = 'fpProps.TSelfSet.FName';    Verdict = 'SET'; Exit = 0;
     Uses = @('fpProps.pas#USE-SELFSET=SET|') }
  @{ Name = 'H1 twin setter conditional MAY';       Fix = 'fields-property'; Target = 'fpProps.TCondSet.FName';    Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @('fpProps.pas#USE-CONDSET=MAY-BE-UNSET|*ctor-misses-field*') }
  @{ Name = 'H1 twin setter outside MAY';           Fix = 'fields-property'; Target = 'fpProps.TNamed.FName';      Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @('fpProps.pas#USE-NAMED=MAY-BE-UNSET|*no-declared-ctor*') }
  @{ Name = 'H1 twin property never written';       Fix = 'fields-property'; Target = 'fpProps.TUnwritten.FNever'; Verdict = 'NEVER-SET'; Exit = 1;
     Uses = @('fpProps.pas#USE-UNWRITTEN=NEVER-SET|') }
  @{ Name = 'H1 twin read-only property';           Fix = 'fields-property'; Target = 'fpProps.TReadOnly.FRo';     Verdict = 'NEVER-SET'; Exit = 1;
     Uses = @('fpProps.pas#USE-READONLY=NEVER-SET|', 'fpProps.pas#USE-READONLY-PROP=NEVER-SET|') }
  @{ Name = 'H1 unresolved receiver property write'; Fix = 'fields-property'; Target = 'fpProps.TSideHolder.FSide'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @('fpProps.pas#USE-SIDE=MAY-BE-UNSET|*soft-writer*') }
  # F4 / receiver soundness
  @{ Name = 'same-method write; foreign read MAY';  Fix = 'fields-samewrite'; Target = 'fsRun.TRun.FSecs'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @('fsRun.pas#USE-SAME=SET|', 'fsRun.pas#USE-PEEK=MAY-BE-UNSET|*ctor-misses-field*',
              'fsRun.pas#USE-COND=MAY-BE-UNSET|*ctor-misses-field*', 'fsRun.pas#USE-OTHER=MAY-BE-UNSET|*receiver-unproven*') }
  # F5: zero judged uses
  @{ Name = 'F5 unit var never read';               Fix = 'fields-samewrite'; Target = 'fsRun.GUnread'; Verdict = 'SET'; Exit = 0;
     Limit = 'no-judged-use'; Summary = '*no judged use*'; Uses = @() }
  # H2: DFM-streamed component fields
  @{ Name = 'H2 streamed component SET';            Fix = 'fields-dfm'; Target = 'fdForm.TDfmForm.edtName'; Verdict = 'SET'; Exit = 0;
     NoLimit = 'no-judged-use'; Uses = @('fdForm.pas#USE-EDT=SET|') }
  @{ Name = 'H2 streamed, never read';              Fix = 'fields-dfm'; Target = 'fdForm.TDfmForm.lblIdle'; Verdict = 'SET'; Exit = 0;
     Limit = 'no-judged-use'; Summary = '*no judged use*'; Uses = @() }
  @{ Name = 'H2 twin not streamed MAY';             Fix = 'fields-dfm'; Target = 'fdForm.TDfmForm.FCount'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Uses = @('fdForm.pas#USE-COUNT=MAY-BE-UNSET|*no-declared-ctor*') }
  # H3: wall-clock cap
  @{ Name = 'H3 cap ran out -> MAY budget';         Fix = 'fields-property'; Target = 'fpProps.TSelfSet.FName'; Verdict = 'MAY-BE-UNSET'; Exit = 1;
     Args = @('--max-seconds', '0.0001'); Limit = 'stopped-after *'; Summary = '*stopped after*'; TimedOut = $true;
     Uses = @('fpProps.pas#USE-SELFSET=MAY-BE-UNSET|*budget*') }
  @{ Name = 'H3 no cap (0) stays SET';              Fix = 'fields-property'; Target = 'fpProps.TSelfSet.FName'; Verdict = 'SET'; Exit = 0;
     Args = @('--max-seconds', '0'); NoLimit = 'stopped-after *'; TimedOut = $false;
     Uses = @('fpProps.pas#USE-SELFSET=SET|') }
)

function LineOf([string]$Dir, [string]$Spec, [switch]$Marker) {
  $file, $text = $Spec -split '#', 2
  $pat = if ($Marker) { '// ' + [regex]::Escape($text) + '(\s|$)' } else { [regex]::Escape($text) }
  $m = @(Select-String -LiteralPath (Join-Path $Dir $file) -Pattern $pat)
  if ($m.Count -ne 1) { throw "'$text' in $file found $($m.Count) times" }
  return @{ File = $file; Line = [int]$m[0].LineNumber }
}

function Compare-Case($Case, $Json, [string]$Dir) {
  $bad = @()
  if ($null -eq $Json) { return ,@('no JSON answer') }
  if ($Json.verdict -cne $Case.Verdict) { $bad += "verdict expected $($Case.Verdict) got $($Json.verdict) [$($Json.summary)]" }
  if ($Case.Limit -and -not (@(@($Json.limits) | Where-Object { $_ -like $Case.Limit }).Count -ge 1)) { $bad += "limits lack $($Case.Limit): [$(@($Json.limits) -join ',')]" }
  if ($Case.NoLimit -and (@(@($Json.limits) | Where-Object { $_ -like $Case.NoLimit }).Count -ge 1)) { $bad += "limits hold $($Case.NoLimit)" }
  if ($Case.Summary -and -not ($Json.summary -like $Case.Summary)) { $bad += "summary [$($Json.summary)]" }
  if ($Case.ContainsKey('TimedOut')) {
    $got = [bool]$Json.budget.timed_out
    if ($got -ne $Case.TimedOut) { $bad += "budget.timed_out expected $($Case.TimedOut) got $got" }
    if ($Case.TimedOut -and -not $Json.budget.exhausted) { $bad += 'budget.exhausted is false on a timed-out answer' }
  }
  if ($Case.Writer) {
    $w = LineOf $Dir $Case.Writer
    $hit = @(@($Json.writers) | Where-Object { ((Split-Path $_.file -Leaf) -ieq $w.File) -and ([int]$_.line -eq $w.Line) -and $_.counts })
    if ($hit.Count -ne 1) { $bad += "writer $($Case.Writer) (line $($w.Line)): $($hit.Count) counting writer rows" }
  }
  if (@($Json.uses).Count -ne $Case.Uses.Count) { $bad += "uses expected $($Case.Uses.Count) got $(@($Json.uses).Count)" }
  foreach ($u in $Case.Uses) {
    if ($u -notmatch '^([^=]+)=([^|]+)\|(.*)$') { $bad += "bad expectation $u"; continue }
    $loc = LineOf $Dir $Matches[1] -Marker; $verdict = $Matches[2]; $reasons = $Matches[3]
    $hit = @(@($Json.uses) | Where-Object { ((Split-Path $_.file -Leaf) -ieq $loc.File) -and ([int]$_.line -eq $loc.Line) })
    if ($hit.Count -ne 1) { $bad += "$($Matches[1]) (line $($loc.Line)): $($hit.Count) judged uses"; continue }
    $h = $hit[0]
    $gotR = (@($h.reasons) -join ',')
    if ($h.verdict -cne $verdict) { $bad += "$u verdict got $($h.verdict) [$gotR] $($h.why)" }
    elseif (-not ($gotR -like $reasons)) { $bad += "$u reasons got [$gotR]" }
  }
  return ,$bad
}

try {
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  $dbs = @{}; $dirsOf = @{}
  foreach ($fx in @($Cases | ForEach-Object { $_.Fix } | Sort-Object -Unique)) {
    $d = Join-Path $WorkDir "fx\$fx"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Copy-Item -Path (Join-Path $FixRoot "$fx\*") -Destination $d -Force
    $db = Join-Path $WorkDir "$fx.sqlite"
    $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db 2>&1 | ForEach-Object { "$_" } }
    Check "index $fx (exit 0)" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
    $dbs[$fx] = $db; $dirsOf[$fx] = $d
  }
  $first = $null
  foreach ($c in $Cases) {
    $extra = if ($c.Args) { $c.Args } else { @() }
    $raw = & { $ErrorActionPreference = 'Continue'; & $Exe check-init $c.Target --db $dbs[$c.Fix] --json @extra 2>$null }
    $code = $LASTEXITCODE
    $json = $null
    try { $json = ((@($raw) -join "`n").Trim()) | ConvertFrom-Json } catch { $json = $null }
    if ($null -eq $first) { $first = @{ Case = $c; Json = $json } }
    $mis = Compare-Case $c $json $dirsOf[$c.Fix]
    foreach ($m in $mis) { Write-Host "      $m" -ForegroundColor DarkRed }
    Check "$($c.Name): $($c.Target)" ($mis.Count -eq 0) "mismatches=$($mis.Count)"
    Check "$($c.Name): exit $($c.Exit)" ($code -eq $c.Exit) "exit=$code"
  }
  # --max-seconds usage errors: exit 2, nothing on stdout
  foreach ($bad in 'abc', '-1') {
    $out = & { $ErrorActionPreference = 'Continue'; & $Exe check-init fpProps.TSelfSet.FName --db $dbs['fields-property'] --json --max-seconds $bad 2>$null }
    Check "H3 --max-seconds $bad is a usage error" (($LASTEXITCODE -eq 2) -and ([string]::IsNullOrWhiteSpace((@($out) -join '')))) "exit=$LASTEXITCODE"
  }
  # --help names the flag on the check-init line
  $help = (& { $ErrorActionPreference = 'Continue'; & $Exe --help 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  $ciLine = @($help -split "`n" | Where-Object { $_ -match 'check-init' -and $_ -match '--max-routines' })
  Check 'H3 --help lists --max-seconds on the check-init line' (@($ciLine | Where-Object { $_ -match '--max-seconds' }).Count -ge 1) "lines=$($ciLine.Count)"
  # Comparator control: a flipped verdict is reported.
  $flip = @{} + $first.Case
  $flip.Verdict = if ($first.Case.Verdict -eq 'SET') { 'MAY-BE-UNSET' } else { 'SET' }
  $fm = Compare-Case $flip $first.Json $dirsOf[$first.Case.Fix]
  Check 'comparator control: a flipped verdict is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"

  Write-Host ("v152 HBFIX: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
  if ($script:Failed) { Write-Host 'V152 HBFIX: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'V152 HBFIX: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
