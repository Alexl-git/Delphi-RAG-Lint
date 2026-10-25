<#
  run_cyclefix_refusal_line.ps1 -- `cycles --fix` names a refused symbol at its DECLARATION line.

  On a copy of docs\examples\circular-uses-demo (plus a minimal Demo.dpr / Demo.dproj this
  runner writes, since --fix needs --project), `cycles --fix --no-compile` refuses TOrder
  (kind base-class). Since owner ruling D1 (2026-10-25) the shipped demo's field switches to the
  base class, so the copy passes FOrders to Copy() -- a use that keeps the refusal. The refusal line used to say `Orders.pas:6` -- the first line of TOrder's
  /// doc-comment (the MOVE range start) -- while `cycles --plan`, outline and query all say
  line 10, the `TOrder = class` header.

  (a) text refusal line names Orders.pas:<decl line>
  (b) --format json refusal `line` equals <decl line>
  Positive controls: <decl line> is read from the SOURCE (the line holding `TOrder = class`),
  the doc-comment start is a different line (so (a)/(b) can fail), and `cycles --plan`
  on the same index names the same line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-refline-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-Engine([string[]]$Arguments, [string]$Tag) {
  $o = Join-Path $WorkDir "$Tag.out"; $e = Join-Path $WorkDir "$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList $Arguments -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $root = Join-Path $WorkDir 'demo'
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'docs\examples\circular-uses-demo') -Filter *.pas |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
  $cu = Join-Path $root 'Customers.pas'
  $cuText = [IO.File]::ReadAllText($cu)
  Check 'ctl0 the copy can be edited to keep the refusal' ($cuText.Contains('Result := Length(FOrders);'))
  [IO.File]::WriteAllText($cu, $cuText.Replace('Result := Length(FOrders);', 'Result := Length(Copy(FOrders));'))
  [IO.File]::WriteAllText((Join-Path $root 'Demo.dpr'),
    "program Demo;`r`n`r`nuses`r`n  Customers in 'Customers.pas',`r`n  Orders in 'Orders.pas';`r`n`r`nbegin`r`nend.`r`n")
  [IO.File]::WriteAllText((Join-Path $root 'Demo.dproj'),
    "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n" +
    "  <PropertyGroup><MainSource>Demo.dpr</MainSource></PropertyGroup>`r`n" +
    "  <ItemGroup>`r`n    <DelphiCompile Include=`"Demo.dpr`"><MainSource>MainSource</MainSource></DelphiCompile>`r`n" +
    "    <DCCReference Include=`"Customers.pas`"/>`r`n    <DCCReference Include=`"Orders.pas`"/>`r`n  </ItemGroup>`r`n</Project>`r`n")
  $proj = Join-Path $root 'Demo.dproj'
  $db   = Join-Path $WorkDir 'demo.sqlite'

  # Positive control: the declaration line comes from the source, not from the engine.
  $src  = [IO.File]::ReadAllLines((Join-Path $root 'Orders.pas'))
  $decl = 0; $doc = 0
  for ($k = 0; $k -lt $src.Count; $k++) {
    if ($decl -eq 0 -and $src[$k] -match '^\s*TOrder\s*=\s*class\b') { $decl = $k + 1 }
  }
  for ($k = $decl - 2; $k -ge 0 -and $src[$k] -match '^\s*///'; $k--) { $doc = $k + 1 }
  Check 'ctl1 TOrder header found in Orders.pas' ($decl -gt 0) "decl=$decl"
  Check 'ctl2 TOrder has a doc-comment that starts on another line' ($doc -gt 0 -and $doc -ne $decl) "doc=$doc"

  $ix = Invoke-Engine @('index', '--project', ('"' + $proj + '"'), '--db', ('"' + $db + '"')) 'index'
  Check 'demo indexed' ($ix.Exit -eq 0) "exit=$($ix.Exit)"

  $pl = Invoke-Engine @('cycles', '--db', ('"' + $db + '"'), '--plan', '--format', 'text') 'plan'
  Check "ctl3 cycles --plan names TOrder at Orders.pas line $decl" ($pl.Out.Contains("``TOrder`` (class, ``Orders.pas`` line $decl)"))

  $tx = Invoke-Engine @('cycles', '--fix', '--project', ('"' + $proj + '"'), '--db', ('"' + $db + '"'), '--no-compile') 'fix-text'
  $line = @($tx.Out -split "`r?`n" | Where-Object { $_ -match '^\s+- base-class: TOrder ' })
  Check 'a0 text output has the TOrder base-class refusal line' ($line.Count -eq 1) ($tx.Out.Trim() -replace "`r?`n", ' | ')
  if ($line.Count -eq 1) {
    Check "a1 refusal line names Orders.pas:$decl (the declaration)" ($line[0] -match ('Orders\.pas:' + $decl + ' -- ')) $line[0]
    Check "a2 refusal line does not name the doc-comment line $doc" ($line[0] -notmatch ('Orders\.pas:' + $doc + ' -- ')) ''
  }

  $js = Invoke-Engine @('cycles', '--fix', '--project', ('"' + $proj + '"'), '--db', ('"' + $db + '"'), '--no-compile', '--format', 'json') 'fix-json'
  $refs = @()
  try { $doc1 = $js.Out | ConvertFrom-Json; $refs = @($doc1.cycles | ForEach-Object { $_.refusals } | Where-Object { $_.symbol -eq 'TOrder' }) } catch { }
  Check 'b0 json has one TOrder refusal' ($refs.Count -eq 1) ''
  if ($refs.Count -eq 1) { Check "b1 json refusal line = $decl" ([int]$refs[0].line -eq $decl) "line=$($refs[0].line)" }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
