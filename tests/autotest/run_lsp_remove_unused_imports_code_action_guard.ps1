#Requires -Version 7
<#
  run_lsp_remove_unused_imports_code_action_guard.ps1 -- auto uses on save, the
  REMOVE half (plan docs\superpowers\plans\2026-10-29-auto-uses-on-save.md, Task 3).

  textDocument/codeAction with context.only = ['source.removeUnusedImports'] (what
  VS Code sends for editor.codeActionsOnSave) must return ONE source action that
  removes the dead imports -- but only behind the drop gate (D2): the buffer's
  hash equals the indexed hash AND the whole index is fresh. Otherwise the client
  would silently delete a unit the user has just started to use.

    P1  dead uDead, fresh index, buffer = disk -> exactly one source action; its
        applied edit equals `lint --fix --apply` output (byte for byte); the gate
        line on stderr reads buffer=True fresh=True.
    P2  same request WITHOUT `only` (light bulb) -> no source action, the
        "Remove unused unit" quickfix is offered and makes the same text.
    N1  buffer = disk + `  DeadProc;` (a ref into uDead, unsaved) -> NO source
        action; quickfix still present; gate line buffer=False.
    N2  index stale (a sibling unit touched after indexing) -> NO source action;
        quickfix still present; gate line fresh=False.
    N3  uDead has an initialization section -> still reported at INFO severity, but NO\r
        source action: the gate removes warning-level findings only.
    N4  uDead's uses clause holds a {$IFNDEF} -> NO source action; quickfix present.
    N5  uWidgets is used only by the sibling .dfm -> not reported, never removed,
        while a genuinely dead uDeadImport in the same clause IS removed.
  Every N case carries a positive-control half (the finding exists / the quickfix
  is offered), so a server that emits nothing at all cannot pass it.
  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-ruca-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$CRLF = [string][char]13 + [char]10
$KIND = 'source.removeUnusedImports'

function Emit([string]$Dir, [string]$Name, [string[]]$Lines) {
  [IO.File]::WriteAllText((Join-Path $Dir $Name), (($Lines -join $CRLF) + $CRLF), [Text.Encoding]::ASCII)
}
function New-Case([string]$Name) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d -Force | Out-Null
  return $d
}
function Index-Case([string]$Dir) {
  $db = Join-Path $Dir 'app.sqlite'
  & $Exe index $Dir --db $db 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }
  return $db
}
# The LSP diagnostics the client would hold: lint --json, mapped the way
# TLspCompletion.DiagnosticsFromLintJson maps it.
function Get-LintDiags([string]$Dir, [string]$Db, [string]$Unit) {
  $j = & $Exe lint (Join-Path $Dir $Unit) --db $Db --json --rule unused-unit-in-uses 2>$null
  $arr = @(($j -join "`n") | ConvertFrom-Json)
  return ,@($arr | Where-Object { $_.rule -eq 'unused-unit-in-uses' } | ForEach-Object {
    [ordered]@{
      range    = @{ start = @{ line = $_.start_line - 1; character = $_.start_col - 1 }
                    end   = @{ line = $_.end_line   - 1; character = $_.end_col   - 1 } }
      severity = $(if ($_.severity -eq 'info') { 3 } else { 2 }); source = 'drag-lint'; code = $_.rule; message = $_.message
    } })
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Read-Frames([string]$Out) {
  $res = @(); $i = 0
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
# One LSP session: open $Unit with $Text, ask codeAction over the whole file.
# Returns @{ All = every action (or $null when unanswered); Err = stderr text }.
function Invoke-CodeAction([string]$Dir, [string]$Db, [string]$Unit, [string]$Text, $Diags, [string[]]$Only) {
  $f = Join-Path $Dir $Unit
  $uri = 'file:///' + $f.Replace([string][char]92, '/')
  $ctx = @{ diagnostics = @($Diags) }
  if ($Only) { $ctx.only = @($Only) }
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$Text } } })
    (Frame @{ jsonrpc='2.0'; id=2; method='textDocument/codeAction'; params=@{
        textDocument=@{ uri=$uri }
        range=@{ start=@{ line=0; character=0 }; end=@{ line=200; character=0 } }
        context=$ctx } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $in = Join-Path $WorkDir "in-$tag.txt"; $so = Join-Path $WorkDir "out-$tag.txt"; $se = Join-Path $WorkDir "err-$tag.txt"
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = if (Test-Path $so) { [IO.File]::ReadAllText($so) } else { '' }
  $err = if (Test-Path $se) { [IO.File]::ReadAllText($se) } else { '' }
  $r = @(Read-Frames $out) | Where-Object { $_.id -eq 2 } | Select-Object -First 1
  $all = $null
  if ($r) { $all = @($r.result | Where-Object { $_ }) }
  return @{ All = $all; Err = $err }
}
function Source-Actions($R) { return ,@($R.All | Where-Object { $_.kind -eq $KIND }) }
function Remove-Quickfixes($R) { return ,@($R.All | Where-Object { ($_.kind -eq 'quickfix') -and ($_.title -match '^Remove unused unit') }) }
# Applies every TextEdit of an action (LSP line/character, 0-based) back to front.
function Apply-Action([string]$Text, $Action) {
  $tes = @($Action.edit.changes.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_ })
  $starts = @(0); for ($k = 0; $k -lt $Text.Length; $k++) { if ($Text[$k] -eq "`n") { $starts += ($k + 1) } }
  $off = { param($p) $starts[[int]$p.line] + [int]$p.character }
  foreach ($te in ($tes | Sort-Object { & $off $_.range.start } -Descending)) {
    $a = & $off $te.range.start; $b = & $off $te.range.end
    $Text = $Text.Substring(0, $a) + $te.newText + $Text.Substring($b)
  }
  return $Text
}

$deadUnit  = @('unit uDead;', 'interface', 'procedure DeadProc;', 'implementation', 'procedure DeadProc;', 'begin', 'end;', 'end.')
$otherUnit = @('unit uOther;', 'interface', 'procedure OtherProc;', 'implementation', 'procedure OtherProc;', 'begin', 'end;', 'end.')
$hostUnit  = @('unit uHost;', 'interface', 'implementation', 'uses', '  uDead,', '  uOther;', 'procedure Run;', 'begin', '  OtherProc;', 'end;', 'end.')

Push-Location C:\TEMP
try {
  Write-Host 'source.removeUnusedImports behind the drop gate' -ForegroundColor Cyan
  # ---- P1 / P2 / N1 / N2: one fixture, the index built once --------------------
  $a = New-Case 'a'
  Emit $a 'uDead.pas' $deadUnit; Emit $a 'uOther.pas' $otherUnit; Emit $a 'uHost.pas' $hostUnit
  $dbA = Index-Case $a
  $hostPath = Join-Path $a 'uHost.pas'
  $disk = [IO.File]::ReadAllText($hostPath)
  $diags = Get-LintDiags $a $dbA 'uHost.pas'
  Check 'P1 POSITIVE CONTROL: lint reports uDead as unused' (@($diags | Where-Object { $_.message -match "'uDead'" }).Count -eq 1) ("n=" + $diags.Count)

  $p1 = Invoke-CodeAction $a $dbA 'uHost.pas' $disk $diags @($KIND)
  $src = Source-Actions $p1
  Check 'P1 fresh index, buffer = disk -> exactly one source.removeUnusedImports' ($src.Count -eq 1) ("n=" + $src.Count)
  Check 'P1 gate line on stderr: buffer=True fresh=True' ($p1.Err -match 'uses-on-save: drop gate buffer=True fresh=True directive=False') ''
  $applied = $null
  if ($src.Count -eq 1) {
    $applied = Apply-Action $disk $src[0]
    Check 'P1 the edit removes uDead and keeps uOther' ((-not $applied.Contains('uDead')) -and $applied.Contains('uOther;')) ($applied -replace "`r`n", '\n')
    # parity: the same fixture through `lint --fix --apply` in its own directory
    $a2 = New-Case 'a2'
    Emit $a2 'uDead.pas' $deadUnit; Emit $a2 'uOther.pas' $otherUnit; Emit $a2 'uHost.pas' $hostUnit
    $dbA2 = Index-Case $a2
    & $Exe lint (Join-Path $a2 'uHost.pas') --db $dbA2 --fix --apply --no-backup --rule unused-unit-in-uses 2>&1 | Out-Null
    $fixed = [IO.File]::ReadAllText((Join-Path $a2 'uHost.pas'))
    Check 'P1 POSITIVE CONTROL: lint --fix changed the file' ($fixed -ne $disk) ''
    Check 'P1 applied edit equals lint --fix output byte for byte' ($applied -ceq $fixed) ($fixed -replace "`r`n", '\n')
  }

  $p2 = Invoke-CodeAction $a $dbA 'uHost.pas' $disk $diags $null
  $q2 = Remove-Quickfixes $p2
  Check 'P2 light bulb (no only) -> no source action' (($null -ne $p2.All) -and ((Source-Actions $p2).Count -eq 0)) ''
  Check 'P2 light bulb offers the Remove unused unit quickfix' ($q2.Count -eq 1) ("n=" + $q2.Count)
  if (($q2.Count -eq 1) -and $applied) { Check 'P2 quickfix makes the same text' ((Apply-Action $disk $q2[0]) -ceq $applied) '' }

  $typed = $disk.Replace("  OtherProc;$CRLF", "  OtherProc;$CRLF  DeadProc;$CRLF")
  Check 'N1 fixture: the buffer differs from disk' ($typed -ne $disk) ''
  $n1 = Invoke-CodeAction $a $dbA 'uHost.pas' $typed $diags @($KIND)
  Check 'N1 buffer newer than index (DeadProc just typed) -> NO source action' (($null -ne $n1.All) -and ((Source-Actions $n1).Count -eq 0)) ''
  Check 'N1 POSITIVE CONTROL: the quickfix is still offered' ((Remove-Quickfixes $n1).Count -eq 1) ''
  Check 'N1 gate line: buffer=False' ($n1.Err -match 'drop gate buffer=False') ''

  (Get-Item (Join-Path $a 'uOther.pas')).LastWriteTime = (Get-Date).AddMinutes(5)
  $n2 = Invoke-CodeAction $a $dbA 'uHost.pas' $disk $diags @($KIND)
  Check 'N2 stale index (sibling touched) -> NO source action' (($null -ne $n2.All) -and ((Source-Actions $n2).Count -eq 0)) ''
  Check 'N2 POSITIVE CONTROL: the quickfix is still offered' ((Remove-Quickfixes $n2).Count -eq 1) ''
  Check 'N2 gate line: buffer=True fresh=False' ($n2.Err -match 'drop gate buffer=True fresh=False') ''

  # ---- N3: an initialization section ------------------------------------------
  $c = New-Case 'c'
  Emit $c 'uDead.pas' @('unit uDead;', 'interface', 'procedure DeadProc;', 'implementation', 'procedure DeadProc;', 'begin', 'end;',
                        'initialization', '  DeadProc;', 'end.')
  Emit $c 'uOther.pas' $otherUnit; Emit $c 'uHost.pas' $hostUnit
  $dbC = Index-Case $c
  $diagsC = Get-LintDiags $c $dbC 'uHost.pas'
  $n3 = Invoke-CodeAction $c $dbC 'uHost.pas' ([IO.File]::ReadAllText((Join-Path $c 'uHost.pas'))) $diagsC @($KIND)
  Check 'N3 POSITIVE CONTROL: uDead is still reported, at INFO severity (L-RULE 734663bb)' (@($diagsC | Where-Object { ($_.message -match "'uDead'") -and ($_.severity -eq 3) }).Count -eq 1) ("n=" + $diagsC.Count)
  Check 'N3 no warning-level finding for the init-section unit' (@($diagsC | Where-Object { ($_.message -match "'uDead'") -and ($_.severity -eq 2) }).Count -eq 0) ''
  Check 'N3 initialization section -> NO source action' (($null -ne $n3.All) -and ((Source-Actions $n3).Count -eq 0)) ''
  Check 'N3 POSITIVE CONTROL: the gate was open (so only the exclusion stopped it)' ($n3.Err -match 'drop gate buffer=True fresh=True') ''

  # ---- N4: a directive inside the uses clause ---------------------------------
  $d = New-Case 'd'
  Emit $d 'uDead.pas' $deadUnit; Emit $d 'uOther.pas' $otherUnit
  Emit $d 'uHost.pas' @('unit uHost;', 'interface', 'implementation', 'uses', '  {$IFNDEF DL_NEVER_DEFINED}', '  uDead,', '  {$ENDIF}',
                        '  uOther;', 'procedure Run;', 'begin', '  OtherProc;', 'end;', 'end.')
  $dbD = Index-Case $d
  $diagsD = Get-LintDiags $d $dbD 'uHost.pas'
  Check 'N4 POSITIVE CONTROL: lint reports uDead inside the {$IFNDEF}' (@($diagsD | Where-Object { $_.message -match "'uDead'" }).Count -eq 1) ("n=" + $diagsD.Count)
  $n4 = Invoke-CodeAction $d $dbD 'uHost.pas' ([IO.File]::ReadAllText((Join-Path $d 'uHost.pas'))) $diagsD @($KIND)
  Check 'N4 {$ directive in the uses clause -> NO source action' (($null -ne $n4.All) -and ((Source-Actions $n4).Count -eq 0)) ''
  Check 'N4 POSITIVE CONTROL: the quickfix is still offered' ((Remove-Quickfixes $n4).Count -eq 1) ''
  Check 'N4 gate line: directive=True' ($n4.Err -match 'drop gate buffer=True fresh=True directive=True') ''

  # ---- N5: a unit used only by the sibling .dfm (B6) --------------------------
  $e = New-Case 'e'
  Emit $e 'uWidgets.pas' @('unit uWidgets;', 'interface', 'type', '  TMyWidget = class', '  end;', 'implementation', 'end.')
  Emit $e 'uDeadImport.pas' @('unit uDeadImport;', 'interface', 'procedure Nothing;', 'implementation', 'procedure Nothing;', 'begin', 'end;', 'end.')
  Emit $e 'uMainForm.pas' @('unit uMainForm;', 'interface', 'uses', '  uWidgets,', '  uDeadImport;', 'type', '  TfrmMain = class', '  end;',
                            'implementation', 'end.')
  Emit $e 'uMainForm.dfm' @('object frmMain: TfrmMain', '  Left = 0', '  object Widget1: TMyWidget', '    Left = 8', '  end', 'end')
  $dbE = Index-Case $e
  $diagsE = Get-LintDiags $e $dbE 'uMainForm.pas'
  Check 'N5 uWidgets (used by the .dfm only) is not reported' (@($diagsE | Where-Object { $_.message -match "'uWidgets'" }).Count -eq 0) ''
  Check 'N5 POSITIVE CONTROL: uDeadImport in the same clause IS reported' (@($diagsE | Where-Object { $_.message -match "'uDeadImport'" }).Count -eq 1) ("n=" + $diagsE.Count)
  $formText = [IO.File]::ReadAllText((Join-Path $e 'uMainForm.pas'))
  $n5 = Invoke-CodeAction $e $dbE 'uMainForm.pas' $formText $diagsE @($KIND)
  $src5 = Source-Actions $n5
  Check 'N5 POSITIVE CONTROL: one source action (for uDeadImport)' ($src5.Count -eq 1) ("n=" + $src5.Count)
  if ($src5.Count -eq 1) {
    $t5 = Apply-Action $formText $src5[0]
    Check 'N5 the source action keeps uWidgets and drops uDeadImport' ($t5.Contains('uWidgets;') -and (-not $t5.Contains('uDeadImport'))) ($t5 -replace "`r`n", '\n')
  }
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
