#Requires -Version 7
<#
  run_lsp_fix_code_action_guard.ps1 -- textDocument/codeAction "Fix: <rule>" quick-fixes
  (L-PROBLEMS-AUTOFIX) beside "Mark as reviewed": the existing autofixers of the rules on
  TLspCompletion's allowlist (mixed-case-hex, length-zero-compare, deprecated-rtl-function).

  The diagnostics are the ones the server itself published, sent back as context.diagnostics.
  The server runs with --full-rules, as the VS Code extension runs it: the plain server's
  subset does not publish length-zero-compare. One case pins that plain lsp offers a fix too.
  Contract pinned here:
    each allowlisted finding  -> one "Fix: <rule>" quickfix, on the requested line only;
    the bytes                 -> applying the action's edit to the file gives what
                                 `lint --in <file> --fix --fix-line L --fix-rule R --apply` writes;
    the action applied        -> the finding is gone on a re-lint;
    the BUFFER, not the disk  -> a didChange that moved the text: the edit targets the buffer's
                                 line; a buffer where the span no longer holds what the
                                 diagnostic described: no fix action (and no exception);
    a rule off the list       -> "Mark as reviewed" only (POSITIVE CONTROL: Mark as reviewed
                                 IS offered there, so an empty answer fails it);
    a risky fix               -> never offered, even when the client's diagnostic names it.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-fixca-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
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

function Probe(const S: string; P: PChar): Integer;

implementation

function Probe(const S: string; P: PChar): Integer;
var
  Str: string;
begin
  Result:= $Ff;
  Str:= S;
  if Length(Str) = 0 then Result:= 0;
  Str:= StrPas(P);
  if Str = S then Str:= Str;
end;

end.
'@
WriteAnsi $file $text
$db = Join-Path $WorkDir 'fx.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)
$uri = 'file:///' + ($file -replace '\\', '/')
$body = [IO.File]::ReadAllText($file)
function OpenFrame([string]$t) { Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$t } } } }
function ChangeFrame([string]$t) { Frame @{ jsonrpc='2.0'; method='textDocument/didChange'; params=@{ textDocument=@{ uri=$uri; version=2 }; contentChanges=@(,@{ text=$t }) } } }
function ActionFrame([int]$id, [int]$line, $diags) {
  Frame @{ jsonrpc='2.0'; id=$id; method='textDocument/codeAction'; params=@{
    textDocument=@{ uri=$uri }; range=@{ start=@{ line=$line; character=0 }; end=@{ line=$line; character=0 } }; context=@{ diagnostics=@($diags) } } }
}
# One whole stdio session; frames go in as one stream, the parsed output comes back.
function Session([string[]]$frames, [string[]]$extra = @('--full-rules')) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  foreach ($f in $frames) { $m += $f }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [IO.File]::WriteAllText($inF, $m, [Text.ASCIIEncoding]::new())
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $db) + $extra) -WorkingDirectory $WorkDir -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $res = @{ diags = @(); byId = @{} }
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($o['method'] -eq 'textDocument/publishDiagnostics' -and "$($o['params']['uri'])" -match 'uFx\.pas$') { $res.diags = @($o['params']['diagnostics']) }
    elseif ($o.ContainsKey('id') -and $o['id'] -gt 10) { $res.byId[[int]$o['id']] = $o }
  }
  return $res
}
function Titles($reply) { if (-not $reply -or $null -eq $reply['result']) { return @() } return @($reply['result'] | ForEach-Object { "$($_['title'])" }) }
function FixOf($reply, [string]$rule) { if (-not $reply -or $null -eq $reply['result']) { return $null } foreach ($a in $reply['result']) { if ($a['title'] -eq "Fix: $rule") { return $a } } return $null }
# Applies one LSP TextEdit to CRLF text.
function ApplyEdit([string]$t, $edit) {
  $ls = $t -split "`r`n"
  $ln = $edit['range']['start']['line']
  Check 'the edit stays on one line' ($edit['range']['end']['line'] -eq $ln)
  $from = $edit['range']['start']['character']; $to = $edit['range']['end']['character']
  $ls[$ln] = $ls[$ln].Substring(0, $from) + $edit['newText'] + $ls[$ln].Substring($to)
  return ($ls -join "`r`n")
}
function LineOf([string]$t, [string]$needle) { $ls = $t -split "`r`n"; for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains($needle)) { return $i } } throw "no line $needle" }

Write-Host ''
Write-Host 'run_lsp_fix_code_action_guard -- Fix: <rule> quick-fixes beside Mark as reviewed' -ForegroundColor Cyan

$first = Session @(OpenFrame $body)
$codes = @($first.diags | ForEach-Object { "$($_['code'])" })
Write-Host "  published: $($codes -join ', ')"
$cases = @(
  @{ rule = 'mixed-case-hex';          needle = 'Result:= $Ff';     want = '$FF' },
  @{ rule = 'length-zero-compare';     needle = 'if Length(Str) = 0'; want = "if Str = ''" },
  @{ rule = 'deprecated-rtl-function'; needle = 'StrPas(P)';        want = 'Str:= string(P)' })
foreach ($c in $cases) {
  $line = LineOf $body $c.needle
  $diag = @($first.diags | Where-Object { $_['code'] -eq $c.rule })
  Check "$($c.rule): the server publishes it" ($diag.Count -eq 1) "count=$($diag.Count)"
  if ($diag.Count -ne 1) { continue }
  $r = Session @((OpenFrame $body), (ActionFrame 11 $line $first.diags))
  $reply = $r.byId[11]
  $act = FixOf $reply $c.rule
  Check "$($c.rule): a Fix action is offered" ($null -ne $act) ("titles=$((Titles $reply) -join ' | ')")
  Check "$($c.rule): Mark as reviewed still there" ((Titles $reply) -contains "Mark as reviewed: $($c.rule)")
  if ($null -eq $act) { continue }
  Check "$($c.rule): kind quickfix" ($act['kind'] -eq 'quickfix')
  $edits = $act['edit']['changes'][$uri]
  Check "$($c.rule): one edit, on the document's URI" (@($edits).Count -eq 1)
  $applied = ApplyEdit $body @($edits)[0]
  Check "$($c.rule): the edit does the job" ($applied.Contains($c.want)) ($applied -split "`r`n")[$line]
  # The bytes: what the batch fixer writes for this one finding.
  $cli = Join-Path $WorkDir "cli-$($c.rule)"
  New-Item -ItemType Directory $cli -Force | Out-Null
  $copy = Join-Path $cli 'uFx.pas'
  [IO.File]::WriteAllText($copy, $body, [Text.ASCIIEncoding]::new())
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $Exe lint --in $copy --db $db --fix --fix-line ($line + 1) --fix-rule $c.rule --apply --no-backup 2>&1 | Out-Null
  $ErrorActionPreference = $ea
  $cliText = [IO.File]::ReadAllText($copy)
  Check "$($c.rule): byte-identical to lint --fix --apply" ($cliText -ceq $applied) ("cli=[$(($cliText -split "`r`n")[$line])] lsp=[$(($applied -split "`r`n")[$line])]")
  # Fixed means gone ($copy holds the fixed bytes: the check above).
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $relint = (& $Exe lint $copy --db $db --json 2>$null) -join "`n" | ConvertFrom-Json
  $ErrorActionPreference = $ea
  Check "$($c.rule): re-lint sees it gone, and still sees the others" ((@($relint | Where-Object { $_.rule -eq $c.rule }).Count -eq 0) -and (@($relint).Count -ge 1)) ("rules=$(@($relint | ForEach-Object { $_.rule }) -join ',')")
}

Write-Host ''
Write-Host '(plain) the server without --full-rules offers the fix for what it publishes' -ForegroundColor Cyan
$plain = Session @(OpenFrame $body) @()
$plainHex = @($plain.diags | Where-Object { $_['code'] -eq 'mixed-case-hex' })
Check 'plain lsp publishes mixed-case-hex' ($plainHex.Count -eq 1) "count=$($plainHex.Count)"
$rp = Session @((OpenFrame $body), (ActionFrame 17 (LineOf $body 'Result:= $Ff') $plain.diags)) @()
Check 'plain lsp offers Fix: mixed-case-hex' ($null -ne (FixOf $rp.byId[17] 'mixed-case-hex')) ("titles=$((Titles $rp.byId[17]) -join ' | ')")

Write-Host ''
Write-Host '(buffer) the edit follows the buffer, and a stale span declines' -ForegroundColor Cyan
$hexDiag = @($first.diags | Where-Object { $_['code'] -eq 'mixed-case-hex' })
if ($hexDiag.Count -eq 1) {
  $line = LineOf $body 'Result:= $Ff'
  # The same line in the buffer holds other text: the diagnostic is stale.
  $staleBody = $body.Replace('Result:= $Ff', 'Result:= 255')
  $rs = Session @((OpenFrame $staleBody), (ActionFrame 12 $line $hexDiag))
  Check 'stale span: no Fix action' ($null -eq (FixOf $rs.byId[12] 'mixed-case-hex')) ("titles=$((Titles $rs.byId[12]) -join ' | ')")
  Check 'stale span: answered, no error' ($rs.byId.ContainsKey(12) -and -not $rs.byId[12].ContainsKey('error'))
  # The file on disk still has the literal, the unsaved buffer spells it another way.
  $otherBody = $body.Replace('Result:= $Ff', 'Result:= $fF')
  $ro = Session @((OpenFrame $otherBody), (ActionFrame 13 $line $hexDiag))
  $acto = FixOf $ro.byId[13] 'mixed-case-hex'
  Check 'the buffer is what the edit reads' ($acto -and @($acto['edit']['changes'][$uri])[0]['newText'] -ceq '$FF') ("titles=$((Titles $ro.byId[13]) -join ' | ')")
  # The requested range decides.
  $rr = Session @((OpenFrame $body), (ActionFrame 14 ($line + 1) $hexDiag))
  Check 'another line requested: no Fix action for this finding' ($null -eq (FixOf $rr.byId[14] 'mixed-case-hex'))
}

Write-Host ''
Write-Host '(allowlist) a rule off the list keeps Mark as reviewed only; a risky fix is never offered' -ForegroundColor Cyan
$line = LineOf $body 'if Str = S then Str:= Str'
$selfDiag = @{ range=@{ start=@{ line=$line; character=2 }; end=@{ line=$line; character=20 } }; severity=2; source='drag-lint'; code='self-assignment'; message='self' }
$riskyDiag = @{ range=@{ start=@{ line=$line; character=2 }; end=@{ line=$line; character=20 } }; severity=2; source='drag-lint'; code='bare-except'; message='risky' }
$ra = Session @((OpenFrame $body), (ActionFrame 15 $line @($selfDiag, $riskyDiag)))
$ta = Titles $ra.byId[15]
Check 'POSITIVE CONTROL: Mark as reviewed offered for the unlisted rule' ($ta -contains 'Mark as reviewed: self-assignment') ("titles=$($ta -join ' | ')")
Check 'no Fix action for a rule off the list' (-not ($ta -contains 'Fix: self-assignment'))
Check 'no Fix action for a risky fix' (-not ($ta -contains 'Fix: bare-except'))
$foreign = @{ range=@{ start=@{ line=$line; character=2 }; end=@{ line=$line; character=20 } }; severity=2; source='DelphiLSP'; code='mixed-case-hex'; message='not ours' }
$rf = Session @((OpenFrame $body), (ActionFrame 16 $line @(,$foreign)))
Check 'a diagnostic another server published: no Fix action' (-not ((Titles $rf.byId[16]) -contains 'Fix: mixed-case-hex'))

Write-Host ''
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
