#Requires -Version 7
<#
  run_lsp_uri_encoding_guard.ps1 -- E-LSP-URI-ENCODING: the file:/// URIs TLspCompletion builds
  (BuildFixActions' WorkspaceEdit key, and its two siblings) are percent-encoded the way the
  client's are, so a path with a space or '#' keys the SAME document the client opened.
  Contract: the "Fix: <rule>" edit of a document opened as
  file:///<dir>/sp%20ace%23x/uFx.pas is keyed by exactly that URI.
  POSITIVE CONTROL: the same document in a plain directory is keyed by its URI (a harness that
  finds no key would fail it), and the special-path case fails on an engine without the fix.
  Run from any CWD, pwsh 7. -Exe defaults to the repo build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-uri-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$text = "unit uFx;`r`n`r`ninterface`r`n`r`nfunction Probe: Integer;`r`n`r`nimplementation`r`n`r`nfunction Probe: Integer;`r`nbegin`r`n  Result:= `$Ff;`r`nend;`r`n`r`nend.`r`n"

function ClientUri([string]$path) {
  $p = $path.Replace('\', '/').Replace(' ', '%20').Replace('#', '%23')
  return 'file:///' + $p
}
function RunCase([string]$dirName) {
  $src = Join-Path $WorkDir $dirName
  New-Item -ItemType Directory $src -Force | Out-Null
  $file = Join-Path $src 'uFx.pas'
  WriteAnsi $file $text
  $db = Join-Path $WorkDir "$($dirName -replace '[ #]', '_').sqlite"
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Exe index $src --db $db 2>&1 | Out-Null
  $ErrorActionPreference = $ea
  $uri = ClientUri $file
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } }
  $diag = @{ range=@{ start=@{ line=11; character=10 }; end=@{ line=11; character=13 } }; code='mixed-case-hex'; message='mixed-case hex'; severity=3; source='drag-lint' }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/codeAction'; params=@{ textDocument=@{ uri=$uri }
      range=@{ start=@{ line=11; character=0 }; end=@{ line=11; character=0 } }; context=@{ diagnostics=@($diag) } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF = Join-Path $WorkDir "in-$PID.txt"; $outF = Join-Path $WorkDir "out-$PID.txt"
  [IO.File]::WriteAllText($inF, $m, [Text.ASCIIEncoding]::new())
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db, '--full-rules') -WorkingDirectory $WorkDir -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $keys = @()
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($o.ContainsKey('id') -and $o['id'] -eq 11 -and $o['result']) {
      foreach ($a in $o['result']) { if ($a['edit'] -and $a['edit']['changes']) { $keys += @($a['edit']['changes'].Keys) } }
    }
  }
  return @{ uri = $uri; keys = $keys }
}

Write-Host ''
Write-Host 'run_lsp_uri_encoding_guard -- WorkspaceEdit URIs match the client URI' -ForegroundColor Cyan
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$plain = RunCase 'plain'
Check 'control: plain path -> an edit key exists' ($plain.keys.Count -ge 1) "keys=$($plain.keys -join ',')"
Check 'control: plain path -> key equals client URI' ($plain.keys -contains $plain.uri) "uri=$($plain.uri) keys=$($plain.keys -join ',')"
$odd = RunCase 'sp ace#x'
Check 'special path -> an edit key exists' ($odd.keys.Count -ge 1) "keys=$($odd.keys -join ',')"
Check 'special path (space, #) -> key equals client URI' ($odd.keys -contains $odd.uri) "uri=$($odd.uri) keys=$($odd.keys -join ',')"
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
