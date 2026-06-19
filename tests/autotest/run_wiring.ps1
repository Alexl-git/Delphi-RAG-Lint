# drag-lint wiring (framework-aware edges) smoke test
#
# Verifies Spring4D DI edges + DFM event-wiring edges end-to-end:
#   index fixtures -> `drag-lint wiring` queries -> assert expected output.
#
# Exit code: 0 on full pass, non-zero on first failure.
#
# Usage:
#   pwsh -File tests/autotest/run_wiring.ps1
#   pwsh -File tests/autotest/run_wiring.ps1 -Exe path\to\drag-lint.exe
#
# Banner-robust: the global C:\Projects\.drag-lint.json prints a
# "(loaded defaults from ...)" line that we strip before asserting.

[CmdletBinding()]
param(
  [string] $Exe = "$PSScriptRoot\..\..\src\cli\Win32\Debug\drag-lint.exe",
  [string] $FixtureDir = "$PSScriptRoot\..\fixtures"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok) {
  $status = if ($Ok) { 'PASS' } else { 'FAIL'; $script:Failed = $true }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $status, $Name) -ForegroundColor $color
}

function Run([string[]]$DragArgs) {
  # invoke the exe, drop the defaults banner, return joined stdout
  (& $Exe @DragArgs 2>$null | Where-Object { $_ -notmatch 'loaded defaults' }) -join "`n"
}

if (-not (Test-Path $Exe)) { Write-Host "exe not found: $Exe" -ForegroundColor Red; exit 2 }

$db = Join-Path $env:TEMP ("wiring_smoke_" + [guid]::NewGuid().ToString('N') + ".sqlite")

Write-Host "== drag-lint wiring smoke ==" -ForegroundColor Cyan
Write-Host "  exe: $Exe"

# Index fixtures (one file per call - multi-file index is a no-op).
foreach ($f in 'di_edges.pas','dfm_wiring.pas','dfm_wiring.dfm') {
  Run @('index', (Join-Path $FixtureDir $f), '--db', $db) | Out-Null
}

# --- Spring4D DI ---
$o = Run @('wiring','--qname','ImcSTATIONS','--db',$db,'--format','json')
Check 'DI: ImcSTATIONS implemented by TmcSTATIONS' ($o -match '"impl"\s*:\s*"TmcSTATIONS"')
Check 'DI: lifetime singleton'                     ($o -match '"lifetime"\s*:\s*"singleton"')
Check 'DI: resolve-site captured'                  ($o -match '"resolved_at"\s*:\s*\[\s*\{')

$o = Run @('wiring','--qname','IDataService<ImcCAUSFAIL>','--db',$db,'--format','json')
Check 'DI: nested-generic interface binding'       ($o -match 'TDataService_CAUSFAIL_SERVER')
Check 'DI: singleton-per-thread lifetime'          ($o -match 'singleton-per-thread')

$o = Run @('wiring','--coverage','--db',$db,'--format','json')
Check 'DI: unresolved RegisterInstance flagged'    ($o -match '"method"\s*:\s*"RegisterInstance"')

# --- DFM event wiring ---
$o = Run @('wiring','--qname','TfrmWire','--db',$db,'--format','json')
Check 'DFM: TfrmWire.Button1Click event handler'   ($o -match '"handler"\s*:\s*"Button1Click"')

# --- MCP get_wiring (stdio JSON-RPC round-trip; same builder as the CLI) ---
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$call = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_wiring","arguments":{"qname":"ImcSTATIONS"}}}'
$mcp  = "$init`n$call" | & $Exe serve --db $db 2>$null | Out-String
Check 'MCP: get_wiring returns TmcSTATIONS'         ($mcp -match 'TmcSTATIONS')

Write-Host ""
if ($script:Failed) { Write-Host "WIRING SMOKE: FAIL" -ForegroundColor Red; exit 1 }
Write-Host "WIRING SMOKE: PASS" -ForegroundColor Green
exit 0
