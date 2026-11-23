#Requires -Version 7
<#
  run_v153_SETTINGS_VSCODE.ps1 -- lane v153 SETTINGS-VSCODE: "drag-lint: Project Settings..." in the
  VS Code extension, a UI over the CLI `settings` verb (docs\superpowers\specs\2026-11-20-settings-store-design.md
  section 8, V1-V6). The argv comes from editors\vscode\drag-lint\lib\projectsettings.js (via node) and is run
  against the real engine on a temp project; no VS Code is started.
    E1 buildSetArgs lint.profile=strict (project scope): exit 0, `settings get` says strict.
    E2 same with local=true: exit 0, the local file exists, list --json source is 'local'.
    E3 buildUnsetArgs local: exit 0; again: exit 1 and describeResult ok=true (nothing to do is not an error).
    E4 buildSetArgs taint.envSource=maybe: exit 2, describeResult ok=false with a message.
    E5 parseList on the real `settings list --json`: 9 rows, keys in the spec section 4 order.
    E6 a non-settable row (popupForms) is flagged settable=false and choicesFor gives [] (nothing to edit).
    N1 every editors\vscode\drag-lint\test\*.test.js passes under node.
    C1 package.json declares dragLint.projectSettings and extension.js registers it.
  Exit 0 on full pass, 1 on any failure, 2 when the harness cannot start.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-vsset-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$vsDir = Join-Path $root 'editors\vscode\drag-lint'
$lib = (Join-Path $vsDir 'lib\projectsettings.js').Replace([string][char]92, '/')

# Run `node -e <js>` with the lib path in $env:PS_LIB and extra data in $env:PS_ARG; returns stdout.
function NodeEval($js, $arg = '') {
  $env:PS_LIB = $lib; $env:PS_ARG = $arg
  $o = & node -e $js 2>&1
  if ($LASTEXITCODE -ne 0) { throw "node failed: $o" }
  return ($o -join "`n")
}
function ArgvFor($call) {
  $js = "const ps=require(process.env.PS_LIB);const project=process.env.PS_ARG;process.stdout.write(JSON.stringify($call));"
  return @((NodeEval $js $script:Project) | ConvertFrom-Json)
}
function Run($argv) {
  $out = & $Exe @argv 2>$null
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}
function Describe($stdout, $code) {
  $env:PS_ARG = $stdout
  $js = "const ps=require(process.env.PS_LIB);process.stdout.write(JSON.stringify(ps.describeResult(process.env.PS_ARG,$code)));"
  return (NodeEval $js $stdout) | ConvertFrom-Json
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory "$WorkDir\P\_D-RAG" | Out-Null
  $WorkDir = (Resolve-Path $WorkDir).Path
  $script:Project = "$WorkDir\P\App.dproj"
  [IO.File]::WriteAllText($script:Project, "<Project/>`r`n", (New-Object Text.ASCIIEncoding))
  $local = "$WorkDir\P\_D-RAG\drag-lint-project.local.json"

  $a = ArgvFor "ps.buildSetArgs({key:'lint.profile',value:'strict',local:false,project})"
  $r = Run $a
  $g = Run @('settings', 'get', 'lint.profile', '--project', $script:Project, '--json')
  $gv = try { ($g.Out | ConvertFrom-Json).value } catch { '' }
  Check 'E1 set lint.profile strict (project scope) -> exit 0, get = strict' ($r.Code -eq 0 -and $gv -eq 'strict') "code=$($r.Code) get=$($g.Out)"

  $a = ArgvFor "ps.buildSetArgs({key:'lint.profile',value:'fast',local:true,project})"
  $r = Run $a
  $l = Run @('settings', 'list', '--project', $script:Project, '--json')
  $row = try { ($l.Out | ConvertFrom-Json).settings | Where-Object key -eq 'lint.profile' } catch { $null }
  Check 'E2 set --local -> exit 0, local file exists, source = local' ($r.Code -eq 0 -and (Test-Path $local) -and $row.source -eq 'local' -and $row.value -eq 'fast') "code=$($r.Code) row=$($row | ConvertTo-Json -Compress)"

  $a = ArgvFor "ps.buildUnsetArgs({key:'lint.profile',local:true,project})"
  $r1 = Run $a
  $r2 = Run $a
  $d2 = Describe $r2.Out $r2.Code
  Check 'E3 unset --local: exit 0, again exit 1 and describeResult ok' ($r1.Code -eq 0 -and $r2.Code -eq 1 -and $d2.ok -eq $true -and $d2.message) "codes=$($r1.Code),$($r2.Code) out=$($r2.Out)"

  $a = ArgvFor "ps.buildSetArgs({key:'taint.envSource',value:'maybe',local:false,project})"
  $r = Run $a
  $d = Describe $r.Out $r.Code
  Check 'E4 bad bool -> exit 2, describeResult ok=false with a message' ($r.Code -eq 2 -and $d.ok -eq $false -and $d.message) "code=$($r.Code) out=$($r.Out)"

  $l = Run @('settings', 'list', '--project', $script:Project, '--json')
  $env:PS_ARG = $l.Out
  $pl = (NodeEval "const ps=require(process.env.PS_LIB);process.stdout.write(JSON.stringify(ps.parseList(process.env.PS_ARG)));" $l.Out) | ConvertFrom-Json
  $want = 'ownRoots,excludeRoots,reportsDir,fieldRepository,popupForms,checkInit,lint.config,lint.profile,taint.envSource'
  $got = ($pl.rows | ForEach-Object { $_.key }) -join ','
  Check 'E5 parseList on real list --json: 9 rows in spec order' ($pl.rows.Count -eq 9 -and $got -eq $want -and $pl.error -eq '') "got=$got err=$($pl.error)"

  $pf = $pl.rows | Where-Object key -eq 'popupForms'
  $ch = (NodeEval "const ps=require(process.env.PS_LIB);process.stdout.write(JSON.stringify(ps.choicesFor(JSON.parse(process.env.PS_ARG))));" ($pf | ConvertTo-Json -Compress -Depth 5))
  Check 'E6 popupForms is read-only and offers no editor' ($pf.settable -eq $false -and $ch -eq '[]') "settable=$($pf.settable) choices=$ch"

  $bad = @()
  foreach ($t in Get-ChildItem (Join-Path $vsDir 'test\*.test.js')) { & node $t.FullName *> $null; if ($LASTEXITCODE -ne 0) { $bad += $t.Name } }
  Check 'N1 every node test passes' ($bad.Count -eq 0) ($bad -join ',')

  $pkg = [IO.File]::ReadAllText((Join-Path $vsDir 'package.json'))
  $ext = [IO.File]::ReadAllText((Join-Path $vsDir 'extension.js'))
  Check 'C1 command declared in package.json and registered in extension.js' (($pkg -match '"command":\s*"dragLint\.projectSettings"') -and ($ext -match "registerCommand\('dragLint\.projectSettings'")) ''
}
catch {
  Check "runner: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" $false
}
finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("run_v153_SETTINGS_VSCODE: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'run_v153_SETTINGS_VSCODE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v153_SETTINGS_VSCODE: PASS' -ForegroundColor Green
