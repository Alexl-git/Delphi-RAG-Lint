# v1512-CHARTZOOM: every `ask` page that embeds a chart SVG zooms and pans (fit-to-width start, wheel at the
# cursor, drag, Fit / 100% / + / -, key 0), draglint:// clicks survive a drag, and the steps the trace STOPS at
# (plus "dangling:" notes) are drawn in their own colour with a legend and a jump from the END TRACE count.
# The page is static HTML + inline JS, so the checks read the generated index.html; a positive control pins that
# the page really embeds the chart. Offline: no http(s) reference may appear in the page script.
param([string] $Exe = '',
      [string] $Dot = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) {'PASS'} else {'FAIL'}), $Name, $Detail) -ForegroundColor $(if ($Ok) {'Green'} else {'Red'})
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP ('draglint_chartzoom_' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory $work | Out-Null
  Copy-Item "$PSScriptRoot\..\fixtures\compare-verb\*" $work -Recurse
  $proj = "$work\Cmp.dproj"; $db = "$work\cmp.sqlite"
  function Run([string[]]$ArgList) {
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    $psi.Environment['DRAGLINT_ASK_REPORT'] = "$work\no-such-Ask-Report.ps1"
    $psi.Environment['DRAGLINT_DOT'] = $Dot
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Out = $o.Result; Err = $e.Result }
  }
  $null = Run @('index','--project',$proj,'--db',$db)
  Check 'fixture indexed' (Test-Path $db)
  if (-not (Test-Path $Dot)) { Write-Host "  [FAIL] no dot.exe at $Dot" -ForegroundColor Red; exit 1 }
  $r = Run @('ask','who-writes','--target','Unit1.TFoo.FName','--project',$proj,'--db',$db,'--plain','--out-root',"$work\out")
  Check 'ask who-writes exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) err=$($r.Err)"
  $page = Get-ChildItem "$work\out" -Recurse -Filter index.html | Select-Object -First 1
  Check 'page written' ($null -ne $page)
  $h = [IO.File]::ReadAllText($page.FullName)
  Check 'POSITIVE CONTROL: page embeds the chart svg and its draglint links' (($h -match '<svg ') -and ($h -match 'draglint://open'))
  Check 'zoom toolbar: Fit / 100% / + / - buttons' (($h -match 'data-zoom="fit"') -and ($h -match 'data-zoom="100"') -and ($h -match 'data-zoom="in"') -and ($h -match 'data-zoom="out"'))
  Check 'wheel zoom at the cursor' ($h -match "addEventListener\('wheel'")
  Check 'drag pans' (($h -match 'mousedown') -and ($h -match 'mousemove'))
  Check 'a drag does not fire a click (capture-phase swallow)' (($h -match 'moved') -and ($h -match "(?s)addEventListener\('click',\s*function\s*\(ev\)\s*\{\s*if \(moved\)"))
  Check 'key 0 = fit' ($h -match "'0'")
  Check 'opens fit-to-width' ($h -match 'fitWidth')
  Check 'unresolved legend text' ($h -match 'unresolved: the trace stops here')
  Check 'unresolved node/edge/line styling' (($h -match '\.unres\b') -and ($h -match 'unres-edge') -and ($h -match 'unres-line'))
  Check 'END TRACE unresolved count jumps' ($h -match 'unres-jump')
  Check 'stays offline (no http(s) src/href/import in the page script)' ($h -notmatch '(?s)<script>.*https?://.*</script>')
  $code = ([regex]::Matches($h, '(?s)<(script|style)>.*?</\1>') | ForEach-Object { $_.Value }) -join ''
  Check '7-bit ASCII page script and style (the shipped source)' (-not ($code -cmatch '[^\x00-\x7F]'))
  # the script must parse: extract it and run node --check when node exists
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    $m = [regex]::Matches($h, '(?s)<script>(.*?)</script>')
    $js = ($m | ForEach-Object { $_.Groups[1].Value }) -join "`n"
    $f = "$work\page.js"; [IO.File]::WriteAllText($f, $js)
    $o = & { $ErrorActionPreference = 'Continue'; & node --check $f 2>&1 | ForEach-Object { "$_" } }
    Check 'page script parses (node --check)' ($LASTEXITCODE -eq 0) "$o"
  } else { Write-Host '  [SKIP] node not on PATH: script syntax check' -ForegroundColor Yellow }
} finally { if (Test-Path $work) { [IO.Directory]::Delete($work, $true) } }
if ($script:Failed) { Write-Host 'FAIL run_v1512_chartzoom' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_v1512_chartzoom' -ForegroundColor Green
