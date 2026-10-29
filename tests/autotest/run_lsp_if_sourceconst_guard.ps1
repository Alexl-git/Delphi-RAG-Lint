<#
  run_lsp_if_sourceconst_guard.ps1 -- the LSP lint path must evaluate {$IF <expr>}
  conditions that name SOURCE-DECLARED constants, exactly as `lint` does. Lane INC3
  gave the lint verb the IF symbol table (InstallPPUnitSource); ConfigureLspLint
  never installed it, so didOpen linted with the unknown name = False and
  published the inactive branch's parser-error.

  Fixtures (untyped const Ver = 3 in a USED project unit uConsts, indexed into a fixture DB; the IF is {$IF Ver >= 2}, TRUE):
    dead-error  garbage in the {$ELSE} (inactive) branch -> 0 parser-error
    live-error  garbage in the {$IF} (active) branch     -> >= 1 (POSITIVE CONTROL:
                parser-error is still published; the fix evaluates, it does not suppress)
  SETUP proves `lint --db` resolves the const (the same-file case already worked in LSP). Parity with `lint --json`.
  Run from any CWD, pwsh 7.
#>
#Requires -Version 7
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-ifc-$PID"
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
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null

function New-Fixture([string]$Name, [string]$IfBody, [string]$ElseBody) {
  $lines = @(
    'unit uIfc;'
    ''
    'interface'
    ''
    'function Pick: Integer;'
    ''
    'implementation'
    ''
    'uses uConsts;'
    ''
    'function Pick: Integer;'
    'begin'
    '{$IF Ver >= 2}'
    $IfBody
    '{$ELSE}'
    $ElseBody
    '{$ENDIF}'
    'end;'
    ''
    'end.'
  )
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir 'uIfc.pas'
  Write-Ascii $f (($lines -join "`r`n") + "`r`n")
  $cl = @('unit uConsts;', 'interface', 'const', '  Ver = 3;', 'implementation', 'end.')
  Write-Ascii (Join-Path $dir 'uConsts.pas') (($cl -join "`r`n") + "`r`n")
  & $Exe index $dir --db (Join-Path $dir 'fx.sqlite') *> $null
  return $f
}
$Good    = '  Result := 1;'
$Garbage = '  Result := := ) ;'

# ---------- LSP plumbing (batch stdin, as run_lsp_dlok_filtering_guard) ----------
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Read-Frames([string]$Out) {
  $res = @()
  $i = 0
  while ($true) {
    $m = [regex]::Match($Out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $i + $m.Index + $m.Length
    $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $Out.Length) { break }
    $res += ($Out.Substring($start, $len) | ConvertFrom-Json)
    $i = $start + $len
  }
  return $res
}
# Lines (1-based) of the LAST publishDiagnostics for the file, for one rule.
function LspLines([string]$PasFile, [string]$Rule) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($PasFile)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $dir = Split-Path $PasFile
  $in = Join-Path $dir 'lsp-in.txt'; $so = Join-Path $dir 'lsp-out.txt'; $se = Join-Path $dir 'lsp-err.txt'
  [System.IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList 'lsp','--db',(Join-Path $dir 'fx.sqlite') -WorkingDirectory $dir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = if (Test-Path $so) { [System.IO.File]::ReadAllText($so) } else { '' }
  $pubs = @(@(Read-Frames $out) | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' })
  if ($pubs.Count -eq 0) { return ,@('NO-PUBLISH') }
  return ,@($pubs[-1].params.diagnostics | Where-Object { $_.code -eq $Rule } | ForEach-Object { [int]$_.range.start.line + 1 })
}
# `lint --json` is a bare array; the line field is start_line, the id is rule.
function CliLines([string]$PasFile, [string]$Rule, [string[]]$Extra = @()) {
  $raw = (& $Exe lint $PasFile --json --db (Join-Path (Split-Path $PasFile) 'fx.sqlite') @Extra 2>$null) -join "`n"
  $arr = @()
  if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}

$dead = New-Fixture 'dead' $Good $Garbage
$live = New-Fixture 'live' $Garbage $Good

Write-Host 'SETUP: lint resolves the source const' -ForegroundColor Cyan
$cliDead = CliLines $dead 'parser-error'
Check 'lint reports no parser-error on the dead-branch fixture' ($cliDead.Count -eq 0) ("cli=[" + ($cliDead -join ',') + "]")

Write-Host ''
Write-Host 'LSP publishDiagnostics evaluates {$IF Ver >= 2}' -ForegroundColor Cyan
foreach ($c in @(
    @{ Name = 'dead-error (inactive ELSE)';    File = $dead; Zero = $true  },
    @{ Name = 'live-error (POSITIVE CONTROL)'; File = $live; Zero = $false })) {
  $lsp = LspLines $c.File 'parser-error'
  $cli = CliLines $c.File 'parser-error'
  $d = "lsp=[" + ($lsp -join ',') + "] cli=[" + ($cli -join ',') + "]"
  $countOk = if ($c.Zero) { $lsp.Count -eq 0 } else { $lsp.Count -ge 1 -and $lsp -notcontains 'NO-PUBLISH' }
  Check "$($c.Name) : parser-error count" $countOk $d
  Check "$($c.Name) : parity with lint --json" (($lsp -join ',') -eq ($cli -join ',')) $d
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
