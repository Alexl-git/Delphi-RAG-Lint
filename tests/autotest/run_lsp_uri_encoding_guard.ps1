#Requires -Version 7
<#
  run_lsp_uri_encoding_guard.ps1 -- E-LSP-URI-ENCODING: every file:/// URI the LSP server
  builds for a WorkspaceEdit key (TLspCompletion.BuildFixActions and its two siblings, the
  uses-on-save removal quickfix and source action in TLSPServer) is in the SAME form as the
  URI the client sent for that document, so the client applies the edit to the open buffer.
  Two client forms exist and both must round-trip:
    raw    file:///C:/dir/sp%20ace%23x/uFx.pas   (IDE plugin, guards: colon kept, drive as-is)
    vscode file:///c%3A/dir/sp%20ace%23x/uFx.pas (VS Code: drive lower-cased, colon as %3A)
  Contract: the "Fix: <rule>" edit, the "Remove unused unit" quickfix edit and the
  source.removeUnusedImports edit of a document opened as <uri> are keyed by exactly <uri>.
  POSITIVE CONTROL: the plain-path raw case is keyed by its URI (a harness that finds no key
  fails it); the special-path and vscode cases fail on an engine without the fix (148 LS RED:
  the vscode key came back as file:///C:/..., the removal keys as file:///.../sp ace#x/...).
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
$deadText = "unit uDead;`r`n`r`ninterface`r`n`r`nprocedure DeadProc;`r`n`r`nimplementation`r`n`r`nprocedure DeadProc;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
$mainText = "unit uMain;`r`n`r`ninterface`r`n`r`nuses`r`n  uDead;`r`n`r`nprocedure MainProc;`r`n`r`nimplementation`r`n`r`nprocedure MainProc;`r`nbegin`r`nend;`r`n`r`nend.`r`n"

function ClientUri([string]$path, [string]$style) {
  $p = $path.Replace('\', '/').Replace(' ', '%20').Replace('#', '%23')
  if ($style -eq 'vscode' -and $p -match '^([A-Za-z]):(.*)$') { $p = $Matches[1].ToLowerInvariant() + '%3A' + $Matches[2] }
  return 'file:///' + $p
}
function EditKeys([string]$outF, [int]$id) {
  $keys = @()
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($o.ContainsKey('id') -and $o['id'] -eq $id -and $o['result']) {
      foreach ($a in $o['result']) { if ($a['edit'] -and $a['edit']['changes']) { $keys += @($a['edit']['changes'].Keys) } }
    }
  }
  return ,$keys
}
function AllKeysAre([array]$keys, [string]$uri) {
  # every key, not any key: a second action keyed by another form still misses the buffer
  return ($keys.Count -ge 1) -and (@($keys | Where-Object { $_ -cne $uri }).Count -eq 0)
}
function RunLsp([string]$db, [string]$m, [string]$tag, [string[]]$extra) {
  $inF = Join-Path $WorkDir "in-$tag.txt"; $outF = Join-Path $WorkDir "out-$tag.txt"
  [IO.File]::WriteAllText($inF, $m, [Text.ASCIIEncoding]::new())
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $db) + $extra) -WorkingDirectory $WorkDir -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir "err-$tag.txt") -NoNewWindow -Wait | Out-Null
  return $outF
}
function RunCase([string]$dirName, [string]$style) {
  $src = Join-Path $WorkDir "$style-$dirName"
  New-Item -ItemType Directory $src -Force | Out-Null
  $file = Join-Path $src 'uFx.pas'
  WriteAnsi $file $text
  $db = Join-Path $WorkDir "$style-$($dirName -replace '[ #]', '_').sqlite"
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Exe index $src --db $db 2>&1 | Out-Null
  $ErrorActionPreference = $ea
  $uri = ClientUri $file $style
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } }
  $diag = @{ range=@{ start=@{ line=11; character=10 }; end=@{ line=11; character=13 } }; code='mixed-case-hex'; message='mixed-case hex'; severity=3; source='drag-lint' }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/codeAction'; params=@{ textDocument=@{ uri=$uri }
      range=@{ start=@{ line=11; character=0 }; end=@{ line=11; character=0 } }; context=@{ diagnostics=@($diag) } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $outF = RunLsp $db $m "fx-$style-$($dirName -replace '[ #]', '_')" @('--full-rules')
  return @{ uri = $uri; keys = (EditKeys $outF 11) }
}
# uses-on-save: the removal quickfix (light bulb, HandleCodeAction) and the
# source.removeUnusedImports action (BuildRemoveUnusedSourceAction) for uMain's dead uDead.
function RunUsesCase([string]$dirName, [string]$style) {
  $src = Join-Path $WorkDir "uses-$style-$dirName"
  New-Item -ItemType Directory $src -Force | Out-Null
  WriteAnsi (Join-Path $src 'uDead.pas') $deadText
  $file = Join-Path $src 'uMain.pas'
  WriteAnsi $file $mainText
  $db = Join-Path $WorkDir "uses-$style-$($dirName -replace '[ #]', '_').sqlite"
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Exe index $src --db $db 2>&1 | Out-Null
  $j = & $Exe lint $file --db $db --json --rule unused-unit-in-uses 2>$null
  $ErrorActionPreference = $ea
  $diags = @(@(($j -join "`n") | ConvertFrom-Json) | Where-Object { $_.rule -eq 'unused-unit-in-uses' } | ForEach-Object {
    @{ range = @{ start = @{ line = $_.start_line - 1; character = $_.start_col - 1 }; end = @{ line = $_.end_line - 1; character = $_.end_col - 1 } }
       severity = 2; source = 'drag-lint'; code = $_.rule; message = $_.message } })
  $uri = ClientUri $file $style
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$mainText } } }
  $rng = @{ start=@{ line=0; character=0 }; end=@{ line=200; character=0 } }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/codeAction'; params=@{ textDocument=@{ uri=$uri }; range=$rng; context=@{ diagnostics=$diags } } }
  $m += Frame @{ jsonrpc='2.0'; id=12; method='textDocument/codeAction'; params=@{ textDocument=@{ uri=$uri }; range=$rng; context=@{ diagnostics=$diags; only=@('source.removeUnusedImports') } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $outF = RunLsp $db $m "uses-$style-$($dirName -replace '[ #]', '_')" @()
  return @{ uri = $uri; diags = $diags.Count; quick = (EditKeys $outF 11); source = (EditKeys $outF 12) }
}

Write-Host ''
Write-Host 'run_lsp_uri_encoding_guard -- WorkspaceEdit URIs match the client URI' -ForegroundColor Cyan
New-Item -ItemType Directory $WorkDir -Force | Out-Null
foreach ($style in 'raw', 'vscode') {
  $plain = RunCase 'plain' $style
  Check "control: $style plain path -> an edit key exists" ($plain.keys.Count -ge 1) "keys=$($plain.keys -join ',')"
  Check "$style plain path -> every key equals client URI" (AllKeysAre $plain.keys $plain.uri) "uri=$($plain.uri) keys=$($plain.keys -join ',')"
  $odd = RunCase 'sp ace#x' $style
  Check "$style special path -> an edit key exists" ($odd.keys.Count -ge 1) "keys=$($odd.keys -join ',')"
  Check "$style special path (space, #) -> every key equals client URI" (AllKeysAre $odd.keys $odd.uri) "uri=$($odd.uri) keys=$($odd.keys -join ',')"
  $u = RunUsesCase 'sp ace#x' $style
  Check "control: $style uses case -> lint reports the dead unit" ($u.diags -ge 1) "diags=$($u.diags)"
  Check "$style uses quickfix -> an edit key exists" ($u.quick.Count -ge 1) "keys=$($u.quick -join ',')"
  Check "$style uses quickfix -> every key equals client URI" (AllKeysAre $u.quick $u.uri) "uri=$($u.uri) keys=$($u.quick -join ',')"
  Check "$style source.removeUnusedImports -> an edit key exists" ($u.source.Count -ge 1) "keys=$($u.source -join ',')"
  Check "$style source.removeUnusedImports -> every key equals client URI" (AllKeysAre $u.source $u.uri) "uri=$($u.uri) keys=$($u.source -join ',')"
}
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
