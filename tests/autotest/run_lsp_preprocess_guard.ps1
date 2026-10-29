#Requires -Version 7
<#
  run_lsp_preprocess_guard.ps1 -- the LSP's publishDiagnostics must lint the
  PREPROCESSED text, exactly as `lint` does.

  THE DEFECT THIS PINS (owner report 2026-10-26, VS Code Problems window):
    `lint` enables the preprocessor (TAstParseCache.SetPreprocess, CLI.pas,
    platform built-ins when no .dproj is known); the `lsp` startup branch never
    did, so didOpen/didSave linted the RAW bytes. A routine with alternative
    bodies -- {$IFDEF MSWINDOWS} begin..end; {$ENDIF} {$IFDEF POSIX} begin..end;
    {$ENDIF}, the RTL's System.IOUtils.pas pattern -- parsed as two bodies and
    the second `end;` was published as parser-error (79 of them on IOUtils;
    0 from `lint`, 79 from `lint --no-preprocess`).

  THE SPEC IS PARITY plus fixed counts, per fixture:
    alt-bodies  two {$IFDEF} alternative bodies          -> 0 parser-error
    dead-error  garbage inside the INACTIVE POSIX branch -> 0 (preprocessed away)
    live-error  the same garbage in the ACTIVE branch    -> >= 1 (POSITIVE CONTROL:
                parser-error is still published -- the fix is preprocessing, not
                suppression)
  and the fixture is proved to need the preprocessor: `lint --no-preprocess`
  reports parser-error on alt-bodies. A finding AFTER the {$IFDEF} block keeps
  its line (the preprocessor is length-preserving).

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-pp-$PID"
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

# ---------- fixtures ----------
# Line 26 holds a with-statement AFTER the {$IFDEF} block: its line must survive.
function New-Fixture([string]$Name, [string]$WinBody, [string]$PosixBody) {
  $lines = @(
    'unit uPp;'                          # 1
    ''                                   # 2
    'interface'                          # 3
    ''                                   # 4
    'function CurDir: string;'           # 5
    'procedure Other(X: TObject);'       # 6
    ''                                   # 7
    'implementation'                     # 8
    ''                                   # 9
    'function CurDir: string;'           # 10
    '{$IFDEF MSWINDOWS}'                 # 11
    'begin'                              # 12
    $WinBody                             # 13
    'end;'                               # 14
    '{$ENDIF}'                           # 15
    '{$IFDEF POSIX}'                     # 16
    'begin'                              # 17
    $PosixBody                           # 18
    'end;'                               # 19
    '{$ENDIF}'                           # 20
    ''                                   # 21
    'procedure Other(X: TObject);'       # 22
    'begin'                              # 23
    '  X.Free;'                          # 24
    '  X := nil;'                        # 25
    '  with X do Free;'                  # 26
    'end;'                               # 27
    ''                                   # 28
    'end.'                               # 29
  )
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir 'uPp.pas'
  Write-Ascii $f (($lines -join "`r`n") + "`r`n")
  return $f
}
$Good    = "  Result := 'C:\';"
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
  Start-Process $Exe -ArgumentList 'lsp' -WorkingDirectory $dir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = if (Test-Path $so) { [System.IO.File]::ReadAllText($so) } else { '' }
  $pubs = @(@(Read-Frames $out) | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' })
  if ($pubs.Count -eq 0) { return ,@('NO-PUBLISH') }
  return ,@($pubs[-1].params.diagnostics | Where-Object { $_.code -eq $Rule } | ForEach-Object { [int]$_.range.start.line + 1 })
}
# `lint --json` is a bare array; the line field is start_line, the id is rule.
function CliLines([string]$PasFile, [string]$Rule, [string[]]$Extra = @()) {
  $raw = (& $Exe lint $PasFile --json @Extra 2>$null) -join "`n"
  $arr = @()
  if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}

$alt  = New-Fixture 'alt'  $Good $Good
$dead = New-Fixture 'dead' $Good $Garbage
$live = New-Fixture 'live' $Garbage $Good

Write-Host 'SETUP: the fixture needs the preprocessor' -ForegroundColor Cyan
$raw = CliLines $alt 'parser-error' @('--no-preprocess')
Check 'lint --no-preprocess reports parser-error on the alternative bodies' ($raw.Count -ge 1) ("cli=[" + ($raw -join ',') + "]")
$pre = CliLines $alt 'parser-error'
Check 'lint (preprocessed) reports none' ($pre.Count -eq 0) ("cli=[" + ($pre -join ',') + "]")

Write-Host ''
Write-Host 'LSP publishDiagnostics lints the preprocessed text' -ForegroundColor Cyan
foreach ($c in @(
    @{ Name = 'alt-bodies';                      File = $alt;  Zero = $true  },
    @{ Name = 'dead-error (inactive branch)';     File = $dead; Zero = $true  },
    @{ Name = 'live-error (POSITIVE CONTROL)';    File = $live; Zero = $false })) {
  $lsp = LspLines $c.File 'parser-error'
  $cli = CliLines $c.File 'parser-error'
  $d = "lsp=[" + ($lsp -join ',') + "] cli=[" + ($cli -join ',') + "]"
  $countOk = if ($c.Zero) { $lsp.Count -eq 0 } else { $lsp.Count -ge 1 -and $lsp -notcontains 'NO-PUBLISH' }
  Check "$($c.Name) : parser-error count" $countOk $d
  Check "$($c.Name) : parity with lint --json" (($lsp -join ',') -eq ($cli -join ',')) $d
}

Write-Host ''
Write-Host 'a finding after the {$IFDEF} block keeps its line' -ForegroundColor Cyan
$w = LspLines $alt 'with-statement'
Check 'with-statement published on line 26' (($w -join ',') -eq '26') ("lsp=[" + ($w -join ',') + "]")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
