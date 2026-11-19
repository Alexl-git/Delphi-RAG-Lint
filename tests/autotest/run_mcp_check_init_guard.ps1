#Requires -Version 7
<#
  run_mcp_check_init_guard.ps1 -- MCP tool check_init (v152 lane HBMCP; plan lane MCP,
  check-init verbs: docs\superpowers\specs\2026-11-17-happens-before-design.md).

  Checks (stdio `serve --db` session on a tiny fixture indexed here):
    C6. (INT11, HBFIX H3) max_seconds is in the schema; {target, max_seconds: 0.000001} answers with
        budget.timed_out true (control: the plain {target} answer is not timed out); a negative
        max_seconds is an error, not unknown-tool.
    C1. tools/list carries check_init with a target / at / explain / max_routines schema and
        the tool is read-only by name (no write argument).
    C2. tools/call {target} returns text byte-identical to `check-init <target> --json`
        (one shared answer and one shared Render).
    C3. tools/call {at} (file:line[:col]) equals `check-init --at <at> --json`.
    C4. the answer parses as JSON and carries the verdict key with one of SET / NEVER-SET / MAY-BE-UNSET.
    C5. controls: neither target nor at is an error (not an empty answer); a malformed at is an
        error; the C2 compare FAILS against the --at text when the two documents differ
        (target vs a different target).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-check-init-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = $(& "$PSScriptRoot\lib\DefaultEngineExe.ps1") }
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
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null
$unit = @'
unit HbCfg;

interface

var
  GCount: Integer;
  GOther: string;

procedure Bump;

implementation

procedure Bump;
begin
  GCount:= GCount + 1;
end;

initialization
  GCount:= 0;

end.
'@
$pas = Join-Path $work 'HbCfg.pas'
[IO.File]::WriteAllText($pas, $unit, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'ci.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$at = "$pas`:15:3"
$cliT = ((& $Exe check-init HbCfg.GCount --db $db --json 2>$null) -join "`n").Trim()
$cliA = ((& $Exe check-init --at $at --db $db --json 2>$null) -join "`n").Trim()
$cliO = ((& $Exe check-init HbCfg.GOther --db $db --json 2>$null) -join "`n").Trim()
Check 'control: the CLI answers (non-empty JSON)' ($cliT -ne '' -and $cliA -ne '' -and $cliO -ne '')

function Q($o) { ($o | ConvertTo-Json -Compress -Depth 6) }
$req = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
  (Q @{ jsonrpc='2.0'; id=3; method='tools/call'; params=@{ name='check_init'; arguments=@{ target='HbCfg.GCount' } } }),
  (Q @{ jsonrpc='2.0'; id=4; method='tools/call'; params=@{ name='check_init'; arguments=@{ at=$at } } }),
  (Q @{ jsonrpc='2.0'; id=5; method='tools/call'; params=@{ name='check_init'; arguments=@{} } }),
  (Q @{ jsonrpc='2.0'; id=6; method='tools/call'; params=@{ name='check_init'; arguments=@{ at='nonsense' } } }),
  (Q @{ jsonrpc='2.0'; id=7; method='tools/call'; params=@{ name='check_init'; arguments=@{ target='HbCfg.GOther' } } }),
  (Q @{ jsonrpc='2.0'; id=8; method='tools/call'; params=@{ name='check_init'; arguments=@{ target='HbCfg.GCount'; max_seconds=0.000001 } } }),
  (Q @{ jsonrpc='2.0'; id=9; method='tools/call'; params=@{ name='check_init'; arguments=@{ target='HbCfg.GCount'; max_seconds=-1 } } })
) -join "`n"
$mcp = $req | & $Exe serve --db $db 2>$null | Out-String
$rep = @{}
foreach ($ln in ($mcp -split "`n")) { try { $o = $ln.Trim() | ConvertFrom-Json; if ($o.id) { $rep[[int]$o.id] = $o } } catch { } }
$tools = @($rep[2].result.tools)
$t = @($tools | Where-Object { $_.name -eq 'check_init' })
Check 'C1 tools/list carries check_init' ($t.Count -eq 1)
$props = if ($t.Count -eq 1) { @($t[0].inputSchema.properties.PSObject.Properties.Name) } else { @() }
Check 'C1 schema names target, at, explain, max_routines' (($props -contains 'target') -and ($props -contains 'at') -and ($props -contains 'explain') -and ($props -contains 'max_routines')) "props=$($props -join ',')"
function ToolText($r) { if ($null -eq $r -or $null -eq $r.result -or $null -eq $r.result.content) { return '' } return ([string]@($r.result.content)[0].text).Trim() }
$txtT = ToolText $rep[3]
$txtA = ToolText $rep[4]
$txtO = ToolText $rep[7]
# INT11: budget.ms is wall time (differs run to run since the solver landed); compare with it zeroed.
function NoMs([string]$s) { $s -replace '"ms":\d+', '"ms":0' }
Check 'C2 {target} == check-init <target> --json' ($txtT -ne '' -and (NoMs $txtT) -ceq (NoMs $cliT)) "mcp=$txtT"
Check 'C3 {at} == check-init --at --json' ($txtA -ne '' -and (NoMs $txtA) -ceq (NoMs $cliA)) "mcp=$txtA"
Check 'C2 second target == its CLI text' ($txtO -ne '' -and (NoMs $txtO) -ceq (NoMs $cliO))
$doc = $null; try { $doc = $txtT | ConvertFrom-Json } catch { }
Check 'C4 answer parses and verdict is one of the three literals' ($null -ne $doc -and @('SET','NEVER-SET','MAY-BE-UNSET') -contains $doc.verdict) "verdict=$($doc.verdict)"
Check 'C5 control: GCount text differs from GOther text, so the compare can fail' (-not ($txtT -ceq $txtO))
Check 'C5 no target and no at is an error (not unknown-tool -32601)' (($null -ne $rep[5].error -and $rep[5].error.code -ne -32601) -or [bool]$rep[5].result.isError) (Q $rep[5])
Check 'C5 malformed at is an error (not unknown-tool -32601)' (($null -ne $rep[6].error -and $rep[6].error.code -ne -32601) -or [bool]$rep[6].result.isError) (Q $rep[6])
Check 'C6 schema names max_seconds' ($props -contains 'max_seconds') "props=$($props -join ',')"
$docS = $null; try { $docS = (ToolText $rep[8]) | ConvertFrom-Json } catch { }
Check 'C6 {max_seconds: 0.000001} -> budget.timed_out' ($null -ne $docS -and $docS.budget.timed_out -eq $true) (ToolText $rep[8])
Check 'C6 control: plain {target} is not timed out' ($null -ne $doc -and $doc.budget.timed_out -ne $true)
Check 'C6 negative max_seconds is an error (not unknown-tool -32601)' (($null -ne $rep[9].error -and $rep[9].error.code -ne -32601) -or [bool]$rep[9].result.isError) (Q $rep[9])
} catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
finally { if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } } }
if ($script:Failed) { Write-Host 'run_mcp_check_init_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_mcp_check_init_guard: PASS' -ForegroundColor Green
exit 0
