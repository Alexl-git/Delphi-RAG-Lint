#Requires -Version 7
<#
  run_mcp_readonly_db_guard.ps1 -- the MCP server opens the index READ-ONLY (v152 lane MCPDESC,
  docs\INBOX-claude-mcp-integration-152.md section 1: "prove it opens DBs read-only").

  A `serve --db <db>` session calls EVERY tool that tools/list advertises (rename_symbol with
  dry_run, run_compile_check is skipped: it spawns a compiler and is documented as not read-only).
  Afterwards the DB file must be byte-identical (SHA-256), same length, same LastWriteTime, and no
  -wal / -shm / -journal sidecar may exist.

    R1. the session answers tools/list and calls >= 10 tools (coverage, no vacuous pass).
    R2. DB sha256 + length + mtime unchanged after the session.
    R3. no -wal / -shm / -journal sidecar next to the DB.
    R4. POSITIVE CONTROL: a deliberate one-byte write to a DB copy is detected by the same
        snapshot compare (so R2 can fail), and so is an mtime-only touch.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-readonly-$PID"
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
function Get-Snap($path) {
  $fi = [IO.FileInfo]::new($path)
  [pscustomobject]@{
    Hash  = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Len   = $fi.Length
    Ticks = $fi.LastWriteTimeUtc.Ticks
  }
}
function Test-SnapEqual($a, $b) { ($a.Hash -eq $b.Hash) -and ($a.Len -eq $b.Len) -and ($a.Ticks -eq $b.Ticks) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
$FixtureDir = (Resolve-Path "$PSScriptRoot\..\fixtures\raise-handle-types").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null
Copy-Item (Join-Path $FixtureDir '*.pas'), (Join-Path $FixtureDir '*.dpr') $work
$db = Join-Path $WorkDir 'ro.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
Start-Sleep -Milliseconds 1200   # make an accidental mtime bump distinguishable on coarse clocks

$before = Get-Snap $db

# Pass 1: list the tools.
$listReq = Join-Path $WorkDir 'list.jsonl'
[IO.File]::WriteAllText($listReq, ('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' + "`n" +
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' + "`n"), [Text.Encoding]::ASCII)
$out = (Get-Content $listReq | & $Exe serve --db $db 2>$null | Out-String)
$tools = @()
foreach ($ln in ($out -split "`n")) { try { $o = $ln.Trim() | ConvertFrom-Json; if ($o.id -eq 2) { $tools = @($o.result.tools) } } catch { } }
Check 'tools/list answers' ($tools.Count -gt 0) "count=$($tools.Count)"

# Pass 2: call every tool with arguments derived from its inputSchema.
$strVals = @{ target = 'TypeFacts.Stamp'; name = 'Stamp'; symbol = 'Stamp'; query = 'Stamp'; qname = 'TypeFacts.Stamp';
              path = $work; file = (Join-Path $work (Get-ChildItem $work -Filter *.pas | Select-Object -First 1).Name) }
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
$id = 100; $called = 0
foreach ($t in $tools) {
  if ($t.name -eq 'run_compile_check') { continue }   # spawns a compiler: documented as NOT read-only
  $callArgs = [ordered]@{}
  $props = $t.inputSchema.properties
  $req = @($t.inputSchema.required)
  if ($props) {
    foreach ($p in $props.PSObject.Properties) {
      $isReq = $req -contains $p.Name
      $ty = [string]$p.Value.type
      if ($p.Name -eq 'dry_run') { $callArgs[$p.Name] = $true; continue }
      if ($p.Name -eq 'db') { continue }
      if (-not $isReq) { continue }
      $callArgs[$p.Name] = switch ($ty) {
        'boolean' { $false } 'integer' { 1 } 'number' { 1 }
        default   { if ($strVals.ContainsKey($p.Name)) { $strVals[$p.Name] } else { 'Stamp' } }
      }
    }
  }
  if ($t.name -eq 'rename_symbol') { $callArgs['dry_run'] = $true; if (-not $callArgs.Contains('new_name')) { $callArgs['new_name'] = 'StampX' } }
  $id++; $called++
  $lines.Add((@{ jsonrpc = '2.0'; id = $id; method = 'tools/call'; params = @{ name = $t.name; arguments = $callArgs } } | ConvertTo-Json -Depth 6 -Compress))
}
Check 'R1 coverage: >= 10 tools called' ($called -ge 10) "called=$called"
$callReq = Join-Path $WorkDir 'calls.jsonl'
[IO.File]::WriteAllText($callReq, ($lines -join "`n") + "`n", [Text.Encoding]::ASCII)
$out2 = (Get-Content $callReq | & $Exe serve --db $db 2>$null | Out-String)
$answered = 0; $ok = 0
foreach ($ln in ($out2 -split "`n")) {
  try { $o = $ln.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -gt 100) { $answered++; if ($null -eq $o.error -and -not [bool]$o.result.isError) { $ok++ } }
}
Check 'R1 every call got an answer' ($answered -eq $called) "answered=$answered called=$called ok=$ok"
Check 'R1 at least 5 calls were real (non-error) answers' ($ok -ge 5) "ok=$ok"

$after = Get-Snap $db
Check 'R2 DB bytes unchanged' ($before.Hash -eq $after.Hash -and $before.Len -eq $after.Len)
Check 'R2 DB mtime unchanged' ($before.Ticks -eq $after.Ticks)
$side = @('-wal', '-shm', '-journal') | Where-Object { Test-Path -LiteralPath ($db + $_) }
Check 'R3 no -wal/-shm/-journal sidecar' (@($side).Count -eq 0) "found=$($side -join ',')"

# R4 positive control on a COPY: a deliberate write and an mtime-only touch must be detected.
$ctl = Join-Path $WorkDir 'control.sqlite'
Copy-Item $db $ctl
$c0 = Get-Snap $ctl
Check 'R4 control: identical copy compares equal' (Test-SnapEqual $c0 (Get-Snap $ctl))
$fs = [IO.File]::Open($ctl, 'Open', 'ReadWrite'); try { $fs.Seek(-1, 'End') | Out-Null; $b = $fs.ReadByte(); $fs.Seek(-1, 'End') | Out-Null; $fs.WriteByte(($b -bxor 0xFF)) } finally { $fs.Dispose() }
Check 'R4 control: a one-byte write is detected' (-not (Test-SnapEqual $c0 (Get-Snap $ctl)))
$ctl2 = Join-Path $WorkDir 'control2.sqlite'
Copy-Item $db $ctl2; $d0 = Get-Snap $ctl2
[IO.File]::SetLastWriteTimeUtc($ctl2, [DateTime]::UtcNow.AddMinutes(5))
Check 'R4 control: an mtime-only touch is detected' (-not (Test-SnapEqual $d0 (Get-Snap $ctl2)))
} catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
