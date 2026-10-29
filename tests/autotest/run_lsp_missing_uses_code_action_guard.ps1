#Requires -Version 7
<#
  run_lsp_missing_uses_code_action_guard.ps1 -- textDocument/codeAction quick-fix for
  rule `unit-missing-from-uses`. The LSP publishes the finding with data.fixes; the
  codeAction handler turns each into a quickfix whose WorkspaceEdit inserts the unit
  in the RIGHT uses section:
    * name used only in the implementation -> implementation clause (created)
    * name used as a type in the interface -> interface clause (extended)
  Applying the returned edit to the buffer must yield the same text as `lint --fix`.
  POSITIVE CONTROL: a unit that already uses uCsLog yields NO action (a handler that
  offers an action for every file would fail it).
  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-muca-$PID"
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
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src -Force | Out-Null
function Emit([string]$name, [string]$text) {
  [IO.File]::WriteAllText((Join-Path $src $name), (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
Emit 'uCsLog.pas' @'
unit uCsLog;
interface
type
  TCsLogger = class
  public
    procedure Send(const S: string);
  end;
var
  CsSite: TCsLogger;
implementation
procedure TCsLogger.Send(const S: string);
begin
end;
end.
'@
Emit 'System.pas' @'
unit System;
interface
implementation
end.
'@
Emit 'uHelper.pas' @'
unit uHelper;
interface
implementation
end.
'@
Emit 'uImplUse.pas' @'
unit uImplUse;
interface
procedure DoIt;
implementation
procedure DoIt;
begin
  CsSite.Send('x');
end;
end.
'@
Emit 'uIntfUse.pas' @'
unit uIntfUse;
interface
uses
  uHelper;
type
  TFoo = class
    F: TCsLogger;
  end;
implementation
end.
'@
Emit 'uAlready.pas' @'
unit uAlready;
interface
implementation
uses uCsLog;
procedure P;
begin
  CsSite.Send('x');
end;
end.
'@

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
# Returns the quickfix actions for the whole file (codeAction id=2). The full
# reply, the initialize result and the published diagnostics land in
# $script:LastAll / $script:LastInit / $script:LastDiags.
function Get-Actions([string]$Unit, [string]$Dir = $src, [string]$Db = $db) {
  $f = Join-Path $Dir $Unit
  $uri = 'file:///' + $f.Replace([string][char]92, '/')
  $text = [IO.File]::ReadAllText($f)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
    (Frame @{ jsonrpc='2.0'; id=2; method='textDocument/codeAction'; params=@{
        textDocument=@{ uri=$uri }
        range=@{ start=@{ line=0; character=0 }; end=@{ line=50; character=0 } }
        context=@{ diagnostics=@() } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $in = Join-Path $WorkDir "in-$Unit.txt"; $so = Join-Path $WorkDir "out-$Unit.txt"; $se = Join-Path $WorkDir "err-$Unit.txt"
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = if (Test-Path $so) { [IO.File]::ReadAllText($so) } else { '' }
  $frames = @(Read-Frames $out)
  $script:LastInit = $frames | Where-Object { $_.id -eq 1 } | Select-Object -First 1
  $script:LastDiags = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' } |
    ForEach-Object { $_.params.diagnostics } | Where-Object { $_ })
  $r = $frames | Where-Object { $_.id -eq 2 } | Select-Object -First 1
  $script:LastAll = $null
  if ($r) { $script:LastAll = @($r.result | Where-Object { $_ }) }
  if (-not $r) { return $null }
  return ,@($r.result | Where-Object { $_.kind -eq 'quickfix' -and $_.edit })
}
# Applies the first TextEdit of an action to $Text (LSP line/character, 0-based).
function Apply-Edit([string]$Text, $Action) {
  $te = @($Action.edit.changes.PSObject.Properties | ForEach-Object { $_.Value })[0][0]
  $lines = [regex]::Split($Text, '(?<=\n)')
  $off = 0
  for ($i = 0; $i -lt [int]$te.range.start.line; $i++) { $off += $lines[$i].Length }
  $off += [int]$te.range.start.character
  return $Text.Substring(0, $off) + $te.newText + $Text.Substring($off)
}

$db = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
try {
  & $Exe index $src --db $db 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

  Write-Host 'codeAction quick-fix for unit-missing-from-uses' -ForegroundColor Cyan
  $impl = Get-Actions 'uImplUse.pas'
  Check 'implementation-only use: exactly one quickfix' (($null -ne $impl) -and ($impl.Count -eq 1)) ("n=" + @($impl).Count)
  if ($impl -and $impl.Count -ge 1) {
    Check 'action title names the unit' ($impl[0].title -match 'uCsLog') $impl[0].title
    $txt = Apply-Edit ([IO.File]::ReadAllText((Join-Path $src 'uImplUse.pas'))) $impl[0]
    Check 'edit creates the IMPLEMENTATION uses clause' ($txt.Contains("implementation`r`n`r`nuses`r`n  uCsLog;`r`nprocedure DoIt;")) ($txt -replace "`r`n", '\n')
    Check 'edit is 7-bit ASCII + CRLF' ((-not ($txt -match "[^\x00-\x7F]")) -and (-not ($txt -match "[^\r]\n"))) ''
  }
  $intf = Get-Actions 'uIntfUse.pas'
  Check 'interface type use: exactly one quickfix' (($null -ne $intf) -and ($intf.Count -eq 1)) ("n=" + @($intf).Count)
  if ($intf -and $intf.Count -ge 1) {
    $txt = Apply-Edit ([IO.File]::ReadAllText((Join-Path $src 'uIntfUse.pas'))) $intf[0]
    Check 'edit extends the INTERFACE uses clause' ($txt.Contains("uses`r`n  uHelper,`r`n  uCsLog;")) ($txt -replace "`r`n", '\n')
    Check 'interface edit lands before the implementation keyword' ($txt.IndexOf('uCsLog') -lt $txt.IndexOf('implementation')) ''
  }
  $none = Get-Actions 'uAlready.pas'
  Check 'POSITIVE CONTROL: unit already used -> no action' (($null -ne $none) -and ($none.Count -eq 0)) ("n=" + @($none).Count)

  Write-Host 'source.addMissingImports (auto uses on save)' -ForegroundColor Cyan
  # S1: the single unambiguous fix is re-emitted under the on-save kind, same edit.
  $impl = Get-Actions 'uImplUse.pas'
  $kinds = @($script:LastInit.result.capabilities.codeActionProvider.codeActionKinds)
  Check 'initialize advertises quickfix + both on-save kinds' (($kinds -contains 'quickfix') -and
    ($kinds -contains 'source.addMissingImports') -and ($kinds -contains 'source.removeUnusedImports')) ($kinds -join ',')
  $srcAdd = @($script:LastAll | Where-Object { $_.kind -eq 'source.addMissingImports' })
  Check 'S1 single resolution -> exactly one source.addMissingImports' ($srcAdd.Count -eq 1) ("n=" + $srcAdd.Count)
  if (($srcAdd.Count -eq 1) -and $impl -and ($impl.Count -ge 1)) {
    $qe  = $impl[0].edit   | ConvertTo-Json -Depth 20 -Compress
    $sae = $srcAdd[0].edit | ConvertTo-Json -Depth 20 -Compress
    Check 'S1 source edit equals the quickfix edit' ($qe -eq $sae) $sae
    Check 'S1 source action carries its diagnostic' (@($srcAdd[0].diagnostics | Where-Object { $_.code -eq 'unit-missing-from-uses' }).Count -eq 1) ''
  }
  $null = Get-Actions 'uAlready.pas'
  Check 'S1 POSITIVE CONTROL: unit already used -> no source action' (($null -ne $script:LastAll) -and
    (@($script:LastAll | Where-Object { "$($_.kind)".StartsWith('source') }).Count -eq 0)) ''

  # S2 (NEGATIVE): two units declare CsSite -> never a silent source.* edit.
  # Own index: a second CsSite in $src would make uImplUse ambiguous too.
  $src2 = Join-Path $WorkDir 'src2'
  New-Item -ItemType Directory $src2 -Force | Out-Null
  foreach ($n in 'uCsLog.pas', 'System.pas') { Copy-Item (Join-Path $src $n) (Join-Path $src2 $n) }
  $crlf = [string][char]13 + [char]10
  [IO.File]::WriteAllText((Join-Path $src2 'uCsLog2.pas'),
    ((@('unit uCsLog2;', 'interface', 'var', '  CsSite: Integer;', 'implementation', 'end.') -join $crlf) + $crlf), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $src2 'uAmbig.pas'),
    ((@('unit uAmbig;', 'interface', 'procedure DoIt;', 'implementation', 'procedure DoIt;', 'begin',
        "  CsSite.Send('x');", 'end;', 'end.') -join $crlf) + $crlf), [Text.Encoding]::ASCII)
  $db2 = Join-Path $WorkDir 'app2.sqlite'
  & $Exe index $src2 --db $db2 2>&1 | Out-Null
  $null = Get-Actions 'uAmbig.pas' $src2 $db2
  $ambDiag = @($script:LastDiags | Where-Object { ($_.code -eq 'unit-missing-from-uses') -and ($_.message -match 'uCsLog2') })
  Check 'P0 POSITIVE CONTROL: the ambiguous finding is published (names uCsLog2)' ($ambDiag.Count -ge 1) ("n=" + $ambDiag.Count)
  Check 'P0 POSITIVE CONTROL: the codeAction request was answered' ($null -ne $script:LastAll) ''
  Check 'S2 ambiguous resolution -> ZERO source.* actions' (($null -ne $script:LastAll) -and
    (@($script:LastAll | Where-Object { "$($_.kind)".StartsWith('source') }).Count -eq 0)) ''
} finally { Pop-Location }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
