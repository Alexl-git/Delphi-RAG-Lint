<#
  run_proptree_progress.ps1 -- progress lines on STDERR for proptree and
  convert-scaffold, `--progress-interval S`, and the info capability keys
  (engine 1.20.6, task T2e).

  THE CONTRACT (owner decisions C and D, 2026-09-30):
    * `--progress-interval S` (S = decimal digits, >= 0) makes proptree and
      convert-scaffold write ONE JSON line to STDERR at most every S seconds
      while the tree is expanded and emitted:
        {"progress":{"elapsed_s":12.3,"verb":"proptree","class":"...","depth":2,
          "max_depth":5,"classes_done":41,"classes_queued":7,"nodes":3114}}
    * DEFAULT 0 = OFF. The editor merges stdout+stderr and slices the first
      '{' .. the last '}', so a default run must be byte-identical to
      `--progress-interval 0` with both streams merged (arm a is THE contract).
    * convert-apply / convert-validate never emit progress: the flag is
      REJECTED there as an unknown argument (exit 3), like every flag a verb
      does not take. Cancel = kill the process; the default write-back is
      kill-safe (each memoize is its own SQLite statement).
    * info --json capabilities: book_depth, progress_lines, lazy_validate are
      the JSON literal true (and apply_unit_rules still is).

  ARMS
    a  default run == --progress-interval 0 (2>&1 merged, byte-identical), no
       "progress" -- proptree and convert-scaffold on the fixture
    b  --progress-interval 1 on the real FireDAC TFDQuery --depth 4 (a SCRATCH
       library copy, -LibDb; skipped without it): >= 2 lines on STDERR, none on
       STDOUT, each exactly the keys above in that order, elapsed_s and
       classes_done non-decreasing, STDOUT still proptree/2 with the same node
       count as a run without the flag. THIS is the positive control for a.
    c  --progress-interval x / -1 / +3 / $A / 1.5 -> exit 2 naming the flag
    d  convert-apply / convert-validate --progress-interval 1 -> exit 3, no
       "progress"
    e  info --json: capabilities.book_depth / progress_lines / lazy_validate /
       apply_unit_rules are [bool] true
    f  kill-safety (-LibDb; copied into the work dir, never written in place):
       proptree --progress-interval 1 --depth 5 WITH write-back, killed after
       the first progress line; PRAGMA integrity_check = ok (python sqlite3);
       proptree --no-write-back on the copy still answers

  RED 2026-09-30, the pre-T2e build (2d7cf4f3 copy), with -LibDb: 16 PASS /
  22 FAIL -- the flag was an unknown argument everywhere (exit 3) and info had
  no new keys. The passes are the controls (a1/a3/a4/a6, d3), d1/d2 (the old
  engine rejected the flag on every verb), b3/b9, f2, and b4/b6, which are
  vacuous with zero progress lines -- b2 (>= 2 lines) is what guards them.
  GREEN 2026-09-30, the T2e build: 38 PASS / 0 FAIL (b: 127.6 s with the flag,
  125.2 s without, on a contended box).
  Run from a NEUTRAL CWD, pwsh 7. Every engine run passes an explicit --db.
    pwsh -File tests\autotest\run_proptree_progress.ps1 [-Exe <engine>] [-LibDb <scratch library-Win64.sqlite>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-progress-$PID",
  [string]$LibDb   = ''
)
try {
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else {
    $script:Fail++
    if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }
    $script:Failed = $true
  }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
Write-Host ("engine : {0}" -f $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Run([string[]]$A) {
  $o = (& $Exe @A 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
# Separate raw streams, as bytes on disk (a 10 MB stdout is not pushed through
# the PowerShell pipeline).
function RunSplit([string]$Tag, [string[]]$A) {
  $so = P "$Tag.out"; $se = P "$Tag.err"
  $p = Start-Process -FilePath $Exe -ArgumentList $A -NoNewWindow -PassThru `
    -RedirectStandardOutput $so -RedirectStandardError $se
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; OutFile = $so; ErrFile = $se }
}
$KEYS = 'elapsed_s,verb,class,depth,max_depth,classes_done,classes_queued,nodes'

# ---- fixture ----------------------------------------------------------------
$fx = P 'fx'
New-Item -ItemType Directory $fx | Out-Null
Write-Ascii (Join-Path $fx 'ProgFix.pas') @'
unit ProgFix;

interface

uses
  Classes;

type
  TInner = class(TPersistent)
  private
    FV: Integer;
  published
    property V: Integer read FV write FV;
  end;

  TMid = class(TPersistent)
  private
    FInner: TInner;
    FW: Integer;
  published
    property Inner: TInner read FInner write FInner;
    property W: Integer read FW write FW;
  end;

  TProgA = class(TComponent)
  private
    FMid: TMid;
  published
    property Mid: TMid read FMid write FMid;
  end;

  TProgB = class(TComponent)
  private
    FMid: TMid;
  published
    property Mid: TMid read FMid write FMid;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $fx 'ProgForm.pas') @'
unit ProgForm;

interface

uses
  Classes, ProgFix;

type
  TProgForm = class(TForm)
    a1: TProgA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (Join-Path $fx 'ProgForm.dfm') @'
object ProgForm: TProgForm
  object a1: TProgA
  end
end
'@
$db = P 'fx.sqlite'
$idx = & $Exe index $fx --db $db 2>&1
Check 'fx the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
$book = P 'b.rules'
Write-Ascii $book "#convert ProgFix.TProgA -> ProgFix.TProgB, ProgFix`n#link Mid.W <- Mid.W`n"

$pt = @('proptree', '--qname', 'ProgFix.TProgA', '--no-write-back', '--json', '--db', $db)
$sc = @('convert-scaffold', '--from', 'ProgFix.TProgA', '--to', 'ProgFix.TProgB', '--db', $db)

# ---- a: default = OFF, byte-identical with the streams merged ---------------
Write-Host ''
Write-Host 'a  default run == --progress-interval 0 (stdout+stderr merged)' -ForegroundColor Cyan
$d = Run $pt
$z = Run ($pt + @('--progress-interval', '0'))
Check 'a1 proptree default: exit 0, JSON parsed' (($d.Code -eq 0) -and ($null -ne (Json $d.Out))) "exit=$($d.Code) $($d.Out)"
Check 'a2 proptree --progress-interval 0: exit 0, byte-identical to the default' (($z.Code -eq 0) -and ($z.Out -ceq $d.Out)) "exit=$($z.Code) $($z.Out)"
Check 'a3 proptree default carries no progress line' (-not ($d.Out -match '"progress"')) $d.Out
$d = Run $sc
$z = Run ($sc + @('--progress-interval', '0'))
Check 'a4 convert-scaffold default: exit 0, a #link emitted' (($d.Code -eq 0) -and ($d.Out -match '#link Mid\.W <- Mid\.W')) "exit=$($d.Code) $($d.Out)"
Check 'a5 convert-scaffold --progress-interval 0: exit 0, byte-identical to the default' (($z.Code -eq 0) -and ($z.Out -ceq $d.Out)) "exit=$($z.Code) $($z.Out)"
Check 'a6 convert-scaffold default carries no progress line' (-not ($d.Out -match '"progress"')) $d.Out
$z = Run ($pt + @('--progress-interval', '5'))
Check 'a7 a run shorter than the interval prints nothing extra (stdout+stderr == default)' `
  (($z.Code -eq 0) -and ($z.Out -ceq (Run $pt).Out)) "exit=$($z.Code) $($z.Out)"

# ---- c: usage ------------------------------------------------------------------
Write-Host ''
Write-Host 'c  --progress-interval that is not decimal digits -> exit 2' -ForegroundColor Cyan
foreach ($v in @('x', '-1', '+3', '$A', '1.5')) {
  $r = Run ($pt + @('--progress-interval', $v))
  Check "c1 proptree --progress-interval $v -> exit 2 naming the flag" (($r.Code -eq 2) -and ($r.Out -match '--progress-interval')) "exit=$($r.Code) $($r.Out)"
  $r = Run ($sc + @('--progress-interval', $v))
  Check "c2 convert-scaffold --progress-interval $v -> exit 2 naming the flag" (($r.Code -eq 2) -and ($r.Out -match '--progress-interval')) "exit=$($r.Code) $($r.Out)"
}

# ---- d: the conversion verbs reject the flag -------------------------------------
Write-Host ''
Write-Host 'd  convert-apply / convert-validate reject --progress-interval (exit 3)' -ForegroundColor Cyan
$r = Run @('convert-apply', '--unit', (Join-Path $fx 'ProgForm.pas'), '--rules', $book, '--db', $db, '--progress-interval', '1')
Check 'd1 convert-apply --progress-interval 1 -> exit 3, unknown argument, no progress' `
  (($r.Code -eq 3) -and ($r.Out -match 'Unknown argument: --progress-interval') -and -not ($r.Out -match '"progress"')) "exit=$($r.Code) $($r.Out)"
$r = Run @('convert-validate', '--rules', $book, '--db', $db, '--progress-interval', '1')
Check 'd2 convert-validate --progress-interval 1 -> exit 3, unknown argument, no progress' `
  (($r.Code -eq 3) -and ($r.Out -match 'Unknown argument: --progress-interval') -and -not ($r.Out -match '"progress"')) "exit=$($r.Code) $($r.Out)"
$r = Run @('convert-validate', '--rules', $book, '--db', $db)
Check 'd3 CONTROL convert-validate without the flag -> exit 0' ($r.Code -eq 0) "exit=$($r.Code) $($r.Out)"

# ---- e: info capabilities --------------------------------------------------------
Write-Host ''
Write-Host 'e  info --json advertises the capabilities as JSON true' -ForegroundColor Cyan
$r = Run @('info', '--json')
$j = Json $r.Out
Check 'e0 info --json: exit 0, JSON parsed' (($r.Code -eq 0) -and ($null -ne $j)) $r.Out
foreach ($k in @('book_depth', 'progress_lines', 'lazy_validate', 'apply_unit_rules')) {
  $v = if ($j) { $j.capabilities.$k } else { $null }
  Check "e1 capabilities.$k is [bool] true" (($v -is [bool]) -and ($v -eq $true)) "value=$v type=$(if ($null -ne $v) { $v.GetType().Name })"
}

# ---- b / f: the real library (scratch copy) -----------------------------------------
$Q = 'FireDAC.Comp.Client.TFDQuery'
if (($LibDb -eq '') -or -not (Test-Path $LibDb)) {
  Write-Host ''
  Write-Host "b/f SKIPPED: no -LibDb scratch library copy ('$LibDb')" -ForegroundColor Yellow
} else {
  Write-Host ''
  Write-Host "b  --progress-interval 1 on $Q --depth 4 ($LibDb)" -ForegroundColor Cyan
  $base = @('proptree', '--qname', $Q, '--depth', '4', '--refs-as-leaves', '--no-write-back', '--json', '--db', $LibDb)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $w = RunSplit 'b-with' ($base + @('--progress-interval', '1'))
  $tWith = $sw.Elapsed.TotalSeconds
  $sw.Restart()
  $n = RunSplit 'b-without' $base
  $tWithout = $sw.Elapsed.TotalSeconds
  Write-Host ("      wall: with {0:N1} s, without {1:N1} s" -f $tWith, $tWithout) -ForegroundColor DarkGray
  $errLines = @(Get-Content -LiteralPath $w.ErrFile | Where-Object { $_ -match '"progress"' })
  $outText  = [IO.File]::ReadAllText($w.OutFile)
  Check 'b1 exit 0 with and without the flag' (($w.Code -eq 0) -and ($n.Code -eq 0)) "with=$($w.Code) without=$($n.Code)"
  Check 'b2 >= 2 progress lines on STDERR' ($errLines.Count -ge 2) "count=$($errLines.Count)"
  Check 'b3 no progress line on STDOUT' (-not ($outText -match '"progress"')) ''
  $parsed = @()
  $shapeOk = $true; $bad = ''
  foreach ($l in $errLines) {
    try { $o = $l | ConvertFrom-Json } catch { $o = $null }
    if (($null -eq $o) -or (@($o.PSObject.Properties.Name) -join ',') -ne 'progress' -or
        ((@($o.progress.PSObject.Properties.Name) -join ',') -ne $KEYS)) { $shapeOk = $false; $bad = $l; break }
    $parsed += $o.progress
  }
  Check 'b4 every progress line is one JSON object with exactly the documented keys, in order' ($shapeOk -and ($parsed.Count -eq $errLines.Count)) $bad
  Check 'b5 every progress line is 7-bit ASCII' (-not (($errLines -join '') -match '[^\x20-\x7E]')) ''
  $mono = $true
  for ($i = 1; $i -lt $parsed.Count; $i++) {
    if (($parsed[$i].elapsed_s -lt $parsed[$i-1].elapsed_s) -or ($parsed[$i].classes_done -lt $parsed[$i-1].classes_done) -or
        ($parsed[$i].nodes -lt $parsed[$i-1].nodes)) { $mono = $false }
  }
  Check 'b6 elapsed_s, classes_done and nodes are non-decreasing' $mono (($parsed | ForEach-Object { "$($_.elapsed_s)/$($_.classes_done)/$($_.nodes)" }) -join ' ')
  $first = if ($parsed.Count -gt 0) { $parsed[0] } else { $null }
  Check 'b7 verb=proptree, class=the qname, max_depth=4, 0 <= depth <= 4' `
    (($null -ne $first) -and ($first.verb -eq 'proptree') -and ($first.class -eq $Q) -and ($first.max_depth -eq 4) -and
     (@($parsed | Where-Object { ($_.depth -lt 0) -or ($_.depth -gt 4) }).Count -eq 0)) ($errLines -join ' | ')
  $jw = Json $outText
  $jn = Json ([IO.File]::ReadAllText($n.OutFile))
  $cw = if ($jw) { @($jw.properties).Count } else { -1 }
  $cn = if ($jn) { @($jn.properties).Count } else { -2 }
  Check 'b8 STDOUT is still proptree/2 with the same node count as without the flag' `
    (($null -ne $jw) -and ($jw.schema -eq 'proptree/2') -and ($cw -eq $cn) -and ($cw -gt 0)) "with=$cw without=$cn"
  $noErr = @(Get-Content -LiteralPath $n.ErrFile | Where-Object { $_ -match '"progress"' })
  Check 'b9 without the flag: no progress line on STDERR' ($noErr.Count -eq 0) "count=$($noErr.Count)"

  Write-Host ''
  Write-Host 'f  kill-safety of the default write-back (a COPY of the library)' -ForegroundColor Cyan
  $copy = P 'kill.sqlite'
  Copy-Item -LiteralPath $LibDb -Destination $copy
  $kso = P 'f.out'; $kse = P 'f.err'
  $ka = @('proptree', '--qname', $Q, '--depth', '5', '--refs-as-leaves', '--json', '--progress-interval', '1', '--db', $copy)
  $kp = Start-Process -FilePath $Exe -ArgumentList $ka -NoNewWindow -PassThru -RedirectStandardOutput $kso -RedirectStandardError $kse
  $sawLine = $false
  $deadline = (Get-Date).AddSeconds(180)
  while (-not $kp.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    # The engine holds the file open for writing: File.ReadAllText throws a
    # sharing violation here (which read as "no line yet"), so share ReadWrite.
    $t = try {
      $fs = [IO.File]::Open($kse, 'Open', 'Read', 'ReadWrite')
      try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    } catch { '' }
    if ($t -match '"progress"') { $sawLine = $true; break }
  }
  $wasRunning = -not $kp.HasExited
  if ($wasRunning) { $kp.Kill(); $kp.WaitForExit() }
  Check 'f1 a progress line arrived while the default (write-back) run was live, and it was killed' ($sawLine -and $wasRunning) "saw=$sawLine running=$wasRunning"
  $py = Get-Command python -ErrorAction SilentlyContinue
  if ($null -eq $py) {
    Check 'f2 python is available for PRAGMA integrity_check' $false 'python not found'
  } else {
    $ic = (& $py.Source -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('PRAGMA integrity_check').fetchone()[0])" $copy 2>&1) -join ' '
    Check 'f2 PRAGMA integrity_check on the killed copy = ok' ($ic.Trim() -eq 'ok') $ic
  }
  # stdout alone: this library copy prints a stale-resolver note on stderr, and
  # merged (2>&1) it can land INSIDE the JSON body.
  $r = RunSplit 'f3' @('proptree', '--qname', $Q, '--depth', '1', '--refs-as-leaves', '--no-write-back', '--json', '--db', $copy)
  $j = Json ([IO.File]::ReadAllText($r.OutFile))
  Check 'f3 proptree --no-write-back on the killed copy still answers' (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.properties).Count -gt 0)) "exit=$($r.Code)"
}

Write-Host ''
Write-Host ("{0} PASS / {1} FAIL" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; $rc = 1 } else { Write-Host 'PASS' -ForegroundColor Green; $rc = 0 }
} finally {
  try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
exit $rc
