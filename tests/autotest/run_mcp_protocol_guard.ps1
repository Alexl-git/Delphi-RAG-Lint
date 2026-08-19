<#
  run_mcp_protocol_guard.ps1 -- every JSON-RPC method a real MCP client issues
  must get a SPEC-SHAPED result back, and the server must report its true
  version.

  THE DEFECTS THIS PINS (found 2026-08-18 while wiring drag-lint into KAI, the
  RAD Studio 13 AI plugin):

  1. `resources/list` ANSWERED WITH THE WRONG KEY. `prompts/list` and
     `resources/list` shared one branch that always replied
     `{"prompts": []}`. A client calling resources/list therefore got a
     SUCCESS whose payload had no `resources` member at all. This is worse
     than an unimplemented method: -32601 is spec-legal and every client
     tolerates it, whereas a malformed success walks straight into
     `result.resources.length` and takes the client down. Strings extracted
     from Kai370.bpl prove KAI's client implements resources/list,
     resources/templates/list and resources/read.

  2. `resources/templates/list` and `resources/read` returned
     -32601 method-not-found. Legal, but since we already claim to answer
     resources/list it is friendlier and more correct to answer all three
     consistently: empty collections, and a resource-not-found error
     (-32002, the MCP convention) for a read of a URI we do not serve.

  3. serverInfo.version WAS THE STRING LITERAL '0.31.0-alpha' -- roughly forty
     releases behind the real product version. DRAGLINT_VERSION exists
     precisely to stop this; its own doc-comment in DRagLint.Core.Model.pas
     names the LSP and the CLI as the two consumers and the MCP server was
     simply missed. The unit ALREADY has DRagLint.Core.Model in its uses
     clause, so this was never a dependency problem.

  POSITIVE CONTROL: run this against a build made before the fix. Checks
  1, 5, 6 and 7 must FAIL. A guard that has never been seen red proves
  nothing -- see the repo's standing rule on positive controls.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Source  = "$PSScriptRoot\..\..\src\mcp\DRagLint.MCP.Server.pas",
  [string]$Model   = "$PSScriptRoot\..\..\src\core\DRagLint.Core.Model.pas",
  # NOT $Db: CmdletBinding aliases -Debug to 'db', and the collision is a
  # MetadataError at parse time, not a runtime surprise.
  [string]$DbPath  = "$PSScriptRoot\..\calls.sqlite",
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-protocol-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function HasProp($obj, $name) {
  if ($null -eq $obj) { return $false }
  return ($obj.PSObject.Properties.Name -contains $name)
}

if (-not (Test-Path $Exe))    { Write-Host "FATAL: exe not found: $Exe"    -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Source)) { Write-Host "FATAL: source not found: $Source" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Model))  { Write-Host "FATAL: source not found: $Model"  -ForegroundColor Red; exit 2 }
if (-not (Test-Path $DbPath)) { Write-Host "FATAL: test db not found: $DbPath" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$DbPath = (Resolve-Path $DbPath).Path

# The expected version is READ FROM THE SOURCE, never hardcoded here. A literal
# in this file would have to be edited on every release, and the release that
# forgot would silently re-open defect 3.
$verLine = Select-String -Path $Model -Pattern "^\s*DRAGLINT_VERSION\s*=\s*'([^']+)'" | Select-Object -First 1
Check 'read DRAGLINT_VERSION out of Core.Model' ($null -ne $verLine)
if ($null -eq $verLine) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$expectVer = $verLine.Matches[0].Groups[1].Value
Write-Host ("  (expecting serverInfo.version = {0})" -f $expectVer) -ForegroundColor DarkGray

# ---------- behavioural: one session, every method KAI is known to issue ----------
Write-Host ''
Write-Host 'BEHAVIOURAL: all eight client methods get a spec-shaped answer' -ForegroundColor Cyan
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$reqFile = Join-Path $WorkDir 'req.jsonl'
$lines = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"guard","version":"1"}}}'
  '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  '{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}'
  '{"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}'
  '{"jsonrpc":"2.0","id":5,"method":"resources/list","params":{}}'
  '{"jsonrpc":"2.0","id":6,"method":"resources/templates/list","params":{}}'
  '{"jsonrpc":"2.0","id":7,"method":"resources/read","params":{"uri":"file:///nope"}}'
)
[System.IO.File]::WriteAllText($reqFile, ($lines -join "`n") + "`n", [System.Text.Encoding]::ASCII)

$so = Join-Path $WorkDir 'out.txt'
$se = Join-Path $WorkDir 'err.txt'
$p = Start-Process $Exe -ArgumentList 'serve','--db',$DbPath -WorkingDirectory $WorkDir `
       -RedirectStandardInput $reqFile -RedirectStandardOutput $so -RedirectStandardError $se `
       -NoNewWindow -Wait -PassThru
Check 'serve exited cleanly' ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"

$resp = @{}
foreach ($ln in (Get-Content $so)) {
  $t = $ln.Trim()
  if ($t -eq '') { continue }
  try { $o = $t | ConvertFrom-Json } catch { continue }
  if (HasProp $o 'id') { $resp[[string]$o.id] = $o }
}
Check 'got a reply for every request that carried an id' ($resp.Count -eq 7) "replies=$($resp.Count)"

# --- initialize ---
$i = $resp['1']
Check 'initialize replied'                    ($null -ne $i)
Check 'initialize declares the tools capability' (HasProp $i.result.capabilities 'tools')
Check 'serverInfo.name is drag-lint'          ($i.result.serverInfo.name -eq 'drag-lint') "got=$($i.result.serverInfo.name)"
Check 'serverInfo.version matches DRAGLINT_VERSION' ($i.result.serverInfo.version -eq $expectVer) `
  "got=$($i.result.serverInfo.version) expected=$expectVer"

# --- ping ---
Check 'ping returns a result (not an error)' ((HasProp $resp['2'] 'result') -and -not (HasProp $resp['2'] 'error'))

# --- tools/list ---
$tools = $resp['3'].result.tools
Check 'tools/list returns a non-empty tools array' ($tools -and $tools.Count -gt 0) "count=$($tools.Count)"
$badTool = @($tools | Where-Object { -not (HasProp $_ 'name') -or -not (HasProp $_ 'description') -or -not (HasProp $_ 'inputSchema') })
Check 'every tool is self-describing (name+description+inputSchema)' ($badTool.Count -eq 0) `
  ("malformed=" + (($badTool | ForEach-Object { $_.name }) -join ','))

# --- prompts/list ---
Check 'prompts/list returns a prompts array' (HasProp $resp['4'].result 'prompts')

# --- resources/list : DEFECT 1 ---
$r5 = $resp['5']
$r5keys = if ($r5.result) { ($r5.result.PSObject.Properties.Name) -join ',' } else { '<no result>' }
Check 'resources/list returns a resources array' (HasProp $r5.result 'resources') "keys=$r5keys"
Check 'resources/list does NOT answer with a prompts key' (-not (HasProp $r5.result 'prompts'))

# --- resources/templates/list : DEFECT 2a ---
$r6 = $resp['6']
Check 'resources/templates/list is not method-not-found' ($r6.error.code -ne -32601) "code=$($r6.error.code)"
Check 'resources/templates/list returns a resourceTemplates array' (HasProp $r6.result 'resourceTemplates')

# --- resources/read : DEFECT 2b ---
$r7 = $resp['7']
Check 'resources/read is not method-not-found' ($r7.error.code -ne -32601) "code=$($r7.error.code)"
Check 'resources/read reports resource-not-found (-32002)' ($r7.error.code -eq -32002) "code=$($r7.error.code)"

# ---------- static: the version must not be a literal again ----------
Write-Host ''
Write-Host 'STATIC: serverInfo.version is a constant, not a literal' -ForegroundColor Cyan
$src = Get-Content $Source -Raw
$initBody = [regex]::Match($src, "procedure TMCPServer\.HandleInitialize.*?\r?\nend;", 'Singleline').Value
Check 'located HandleInitialize' ($initBody -ne '')
Check 'HandleInitialize references DRAGLINT_VERSION' ($initBody -match 'DRAGLINT_VERSION')
Check 'HandleInitialize hardcodes no x.y.z version string' `
  (-not ($initBody -match "'\d+\.\d+\.\d+[^']*'")) `
  ([regex]::Match($initBody, "'\d+\.\d+\.\d+[^']*'").Value)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
