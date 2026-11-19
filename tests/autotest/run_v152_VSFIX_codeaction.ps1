#Requires -Version 7
<#
  run_v152_VSFIX_codeaction.ps1 -- 1.52 lane VSFIX: "Fix with drag-lint" code actions.
  Contract pinned here:
    initialize               -> codeActionKinds lists source.fixAll.drag-lint;
    a fixable finding hit    -> "Fix: <rule>" (kind quickfix, unchanged) PLUS
                                "drag-lint: fix all <rule> in file" (quickfix) when the file holds 2+ of that rule,
                                PLUS "drag-lint: fix all fixable in file" (kind source.fixAll.drag-lint);
    the fix-all edit         -> fixes EVERY fixable finding in the file (the client's context.diagnostics is
                                range-filtered, so the server recomputes file-wide);
    context.only source.fixAll, cursor on a line without a finding -> the fix-all source action is offered;
    POSITIVE CONTROLS        -> a single-instance rule gets no "fix all <rule>" title; a line without a
                                finding and no `only` gets no fix-all title;
    VS Code extension        -> package.json contributes.menus has editor/context + problems/context entries
                                whose commands are declared in contributes.commands.
  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-vsfix-ca-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src -Force | Out-Null
$file = Join-Path $src 'uFx.pas'
$text = @'
unit uFx;

interface

function Probe(const S: string): Integer;

implementation

function Probe(const S: string): Integer;
begin
  Result:= $Ff;
  if Length(S) = 0 then Result:= $aB;
end;

end.
'@
WriteAnsi $file $text
$db = Join-Path $WorkDir 'fx.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)
$uri = 'file:///' + ($file -replace '\\', '/')
$body = [IO.File]::ReadAllText($file)
function OpenFrame([string]$t) { Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$t } } } }
function ActionFrame([int]$id, [int]$line, $diags, $only = $null) {
  $ctx = @{ diagnostics = @($diags) }
  if ($only) { $ctx['only'] = @($only) }
  Frame @{ jsonrpc='2.0'; id=$id; method='textDocument/codeAction'; params=@{
    textDocument=@{ uri=$uri }; range=@{ start=@{ line=$line; character=0 }; end=@{ line=$line; character=0 } }; context=$ctx } }
}
function Session([string[]]$frames) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  foreach ($f in $frames) { $m += $f }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
  [IO.File]::WriteAllText($inF, $m, [Text.ASCIIEncoding]::new())
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db, '--full-rules') -WorkingDirectory $WorkDir -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $res = @{ diags = @(); byId = @{} }
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json -AsHashtable | ForEach-Object { $_ } } catch { continue }
    if ($o['method'] -eq 'textDocument/publishDiagnostics' -and "$($o['params']['uri'])" -match 'uFx\.pas$') { $res.diags = @($o['params']['diagnostics']) }
    elseif ($o.ContainsKey('id')) { $res.byId[[int]$o['id']] = $o }
  }
  return $res
}
function Titles($reply) { if (-not $reply -or $null -eq $reply['result']) { return @() } return @($reply['result'] | ForEach-Object { "$($_['title'])" }) }
function ActOf($reply, [string]$title) { if (-not $reply -or $null -eq $reply['result']) { return $null } foreach ($a in $reply['result']) { if ($a['title'] -eq $title) { return $a } } return $null }
function ApplyAll([string]$t, $edits) {
  $ls = $t -split "`r`n"
  foreach ($e in @($edits | Sort-Object { - $_['range']['start']['line'] }, { - $_['range']['start']['character'] })) {
    $ln = $e['range']['start']['line']
    $ls[$ln] = $ls[$ln].Substring(0, $e['range']['start']['character']) + $e['newText'] + $ls[$ln].Substring($e['range']['end']['character'])
  }
  return ($ls -join "`r`n")
}
function LineOf([string]$t, [string]$needle) { $ls = $t -split "`r`n"; for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains($needle)) { return $i } } throw "no line $needle" }

Write-Host ''
Write-Host 'run_v152_VSFIX_codeaction -- Fix with drag-lint: fix-all code actions + VS Code menus' -ForegroundColor Cyan

$first = Session @(OpenFrame $body)
$codes = @($first.diags | ForEach-Object { "$($_['code'])" })
Write-Host "  published: $($codes -join ', ')"
$caps = $first.byId[1]['result']['capabilities']['codeActionProvider']['codeActionKinds']
Check 'initialize lists source.fixAll.drag-lint' (@($caps) -contains 'source.fixAll.drag-lint') ("kinds=$(@($caps) -join ',')")
$hexDiags = @($first.diags | Where-Object { $_['code'] -eq 'mixed-case-hex' })
Check 'fixture: two mixed-case-hex findings published' ($hexDiags.Count -eq 2) "count=$($hexDiags.Count)"
$hexLine = LineOf $body 'Result:= $Ff'
# The client range-filters context.diagnostics: send only the finding on the requested line.
$oneDiag = @($hexDiags | Where-Object { $_['range']['start']['line'] -eq $hexLine })
$r = Session @((OpenFrame $body), (ActionFrame 11 $hexLine $oneDiag))
$reply = $r.byId[11]
$ti = @(Titles $reply)
Write-Host "  titles: $($ti -join ' | ')"
Check 'Fix: mixed-case-hex still offered (unchanged title)' ($null -ne (ActOf $reply 'Fix: mixed-case-hex'))
$ruleAll = ActOf $reply 'drag-lint: fix all mixed-case-hex in file'
Check 'fix all <rule> in file offered (2 findings)' ($null -ne $ruleAll)
Check 'fix all <rule>: kind quickfix' ($ruleAll -and $ruleAll['kind'] -eq 'quickfix')
Check 'POSITIVE CONTROL: single-instance rule has no fix-all-rule title' (-not ($ti -contains 'drag-lint: fix all length-zero-compare in file'))
$all = ActOf $reply 'drag-lint: fix all fixable in file'
Check 'fix all fixable in file offered' ($null -ne $all)
Check 'fix all fixable: kind source.fixAll.drag-lint' ($all -and $all['kind'] -eq 'source.fixAll.drag-lint')
if ($all) {
  $edits = @($all['edit']['changes'][$uri])
  Check 'fix all fixable: edits cover every fixable finding (3)' ($edits.Count -eq 3) "edits=$($edits.Count)"
  $applied = ApplyAll $body $edits
  Check 'fix all fixable: both hex literals upper-cased' ($applied.Contains('$FF') -and $applied.Contains('$AB'))
  Check 'fix all fixable: length compare rewritten' ($applied.Contains("if S = ''"))
  if ($ruleAll) {
    $hexOnly = ApplyAll $body @($ruleAll['edit']['changes'][$uri])
    Check 'fix all <rule>: only that rule changed' ($hexOnly.Contains('$FF') -and $hexOnly.Contains('$AB') -and $hexOnly.Contains('Length(S) = 0'))
  }
  # Fixed means gone: re-lint of the applied text.
  $copy = Join-Path $WorkDir 'applied.pas'
  [IO.File]::WriteAllText($copy, $applied, [Text.ASCIIEncoding]::new())
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $relint = (& { $ErrorActionPreference = 'Continue'; & $Exe lint $copy --db $db --json 2>$null }) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }
  $ErrorActionPreference = $ea
  $gone = @($relint | Where-Object { $_.rule -in 'mixed-case-hex', 'length-zero-compare' }).Count
  Check 're-lint: the three findings are gone' ($gone -eq 0) "left=$gone"
}
# No finding on the requested line, no `only`: no fix-all title (control for the next case).
$quiet = LineOf $body 'begin'
$rq = Session @((OpenFrame $body), (ActionFrame 12 $quiet @()))
Check 'quiet line, no only: no fix-all action' (-not (@(Titles $rq.byId[12]) -match 'fix all'))
# context.only = source.fixAll on the same quiet line: the source action is offered.
$ro = Session @((OpenFrame $body), (ActionFrame 13 $quiet @() 'source.fixAll'))
$srcAct = ActOf $ro.byId[13] 'drag-lint: fix all fixable in file'
Check 'only=source.fixAll on a quiet line: fix-all source action offered' ($null -ne $srcAct) ("titles=$((@(Titles $ro.byId[13])) -join ' | ')")
Check 'only=source.fixAll: kind source.fixAll.drag-lint' ($srcAct -and $srcAct['kind'] -eq 'source.fixAll.drag-lint')

Write-Host ''
Write-Host '(extension) package.json contributes.menus' -ForegroundColor Cyan
$pkg = Get-Content (Join-Path $PSScriptRoot '..\..\editors\vscode\drag-lint\package.json') -Raw | ConvertFrom-Json | ForEach-Object { $_ }
$declared = @($pkg.contributes.commands | ForEach-Object { $_.command })
foreach ($menu in 'editor/context', 'problems/context') {
  $items = @($pkg.contributes.menus.$menu)
  Check "menus.$menu has a drag-lint fix entry" (@($items | Where-Object { $_.command -like 'dragLint.fix*' }).Count -ge 1)
  foreach ($it in $items) { Check "menus.$menu command $($it.command) is declared" ($declared -contains $it.command) }
}
$fixCmd = $pkg.contributes.commands | Where-Object { $_.command -eq 'dragLint.fixFinding' }
Check 'command title is "Fix with drag-lint"' ($fixCmd -and $fixCmd.title -eq 'Fix with drag-lint')
Check 'POSITIVE CONTROL: a command that is not declared fails the declared check' (-not ($declared -contains 'dragLint.noSuchCommand'))
$ext = Get-Content (Join-Path $PSScriptRoot '..\..\editors\vscode\drag-lint\extension.js') -Raw
Check 'extension.js registers both fix commands' ($ext.Contains("registerCommand('dragLint.fixFinding'") -and $ext.Contains("registerCommand('dragLint.fixAllInFile'"))

if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASSED' -ForegroundColor Green
