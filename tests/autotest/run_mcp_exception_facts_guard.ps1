#Requires -Version 7
<#
  run_mcp_exception_facts_guard.ps1 -- MCP tool get_exception_facts (wave 148 lane D1P,
  spec docs\superpowers\specs\2026-11-07-editor-programme.md section P1).

  Checks (stdio `serve` session on tests\fixtures\raise-handle-types, indexed here):
    M1. tools/list carries get_exception_facts with a target / name schema, and the list grew
        by exactly one (18 tools).
    M2. tools/call {target: TypeFacts.Stamp} returns text byte-identical to
        `exception-facts --target TypeFacts.Stamp --json` (the one shared reader).
    M3. tools/call {name: ELocal} likewise equals `exception-facts --name ELocal --json`.
    M4. controls: neither selector, or both, is an error (not an empty answer); an unknown
        routine answers count 0; the M2 compare FAILS against the --name ELocal text.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-exc-$PID",
  [int]$ExpectedTools = 18
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
$FixtureDir = (Resolve-Path "$PSScriptRoot\..\fixtures\raise-handle-types").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null
Copy-Item (Join-Path $FixtureDir '*.pas'), (Join-Path $FixtureDir '*.dpr') $work
$db = Join-Path $WorkDir 'facts.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$cliT = ((& $Exe exception-facts --target TypeFacts.Stamp --db $db --json 2>$null) -join "`n").Trim()
$cliN = ((& $Exe exception-facts --name ELocal --db $db --json 2>$null) -join "`n").Trim()
Check 'control: the CLI answers (non-empty, count > 0)' (($cliT | ConvertFrom-Json).count -gt 0 -and ($cliN | ConvertFrom-Json).count -gt 0)

$req = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_exception_facts","arguments":{"target":"TypeFacts.Stamp"}}}',
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_exception_facts","arguments":{"name":"ELocal"}}}',
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_exception_facts","arguments":{}}}',
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_exception_facts","arguments":{"target":"A","name":"B"}}}',
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_exception_facts","arguments":{"target":"NoSuchRoutine"}}}'
) -join "`n"
$mcp = $req | & $Exe serve --db $db 2>$null | Out-String
$rep = @{}
foreach ($ln in ($mcp -split "`n")) { try { $o = $ln.Trim() | ConvertFrom-Json; if ($o.id) { $rep[[int]$o.id] = $o } } catch { } }
$tools = @($rep[2].result.tools)
$t = @($tools | Where-Object { $_.name -eq 'get_exception_facts' })
Check 'M1 tools/list carries get_exception_facts' ($t.Count -eq 1)
Check 'M1 schema names target and name' ($t.Count -eq 1 -and $null -ne $t[0].inputSchema.properties.target -and $null -ne $t[0].inputSchema.properties.name)
Check "M1 tool count is $ExpectedTools" ($tools.Count -eq $ExpectedTools) "count=$($tools.Count)"
function ToolText($r) { if ($null -eq $r -or $null -eq $r.result -or $null -eq $r.result.content) { return '' } return ([string]@($r.result.content)[0].text).Trim() }
$txtT = ToolText $rep[3]
$txtN = ToolText $rep[4]
Check 'M2 {target} == exception-facts --target --json' ($txtT -ne '' -and $txtT -ceq $cliT) "mcp=$txtT"
Check 'M3 {name} == exception-facts --name --json' ($txtN -ne '' -and $txtN -ceq $cliN) "mcp=$txtN"
Check 'M4 control: the target compare fails against the name text' (-not ($txtT -ceq $cliN))
Check 'M4 no selector is an error' ($null -ne $rep[5].error -or [bool]$rep[5].result.isError) ($rep[5] | ConvertTo-Json -Compress -Depth 5)
Check 'M4 both selectors is an error' ($null -ne $rep[6].error -or [bool]$rep[6].result.isError) ($rep[6] | ConvertTo-Json -Compress -Depth 5)
$empty = $null; try { $empty = (ToolText $rep[7]) | ConvertFrom-Json } catch { }
Check 'M4 unknown routine: count 0, not an error' ($null -ne $empty -and $empty.count -eq 0)

if ($script:Failed) { Write-Host 'run_mcp_exception_facts_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_mcp_exception_facts_guard: PASS' -ForegroundColor Green
exit 0
} finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
