#Requires -Version 7
<#
  run_lsp_hover_exceptions_guard.ps1 -- the exception fact in the editor (wave 148 lane D1P,
  spec docs\superpowers\specs\2026-11-07-editor-programme.md section P1; owner ruling D1:
  DEFAULT ON, `lsp --no-exception-facts` is the way back).

  Checks (stdio LSP session on an indexed fixture):
    H1. textDocument/hover on a routine that raises: one 'Raises:' line naming each type once,
        with how it is known (EFoo bound, EArgumentException spelled), in source order.
        No-doc path ('Analysis facts:') AND doc path (a routine with a /// summary).
    H2. draglint/hoverBundle (the IDE popup's request): the same line in markdown AND in
        model facts.
    H3. a routine with no raise sites: no 'Raises:' line (negative).
    L1. textDocument/codeLens: 'raises 2 types' on Risky's declaration line,
        'raises 1 type, handles 2 types' on Safe's, nothing exception-shaped on Plain's;
        the caller lenses are still there.
    O1. `lsp --no-exception-facts`: hover still answers, no 'Raises:' line, and the ON markdown
        minus its 'Raises:' line equals the OFF markdown byte for byte; no exception lens,
        caller lenses unchanged.
  Positive control: H1/H2/L1 fail on an engine without the surfaces (1.46.0-alpha) and with
  the switch off (O1 runs the same session with the switch and asserts the inverse).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-exc-$PID"
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$WorkDir = (Resolve-Path $WorkDir).Path
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uExc.pas'
WriteAnsi $file @'
unit uExc;

interface

uses System.SysUtils;

type
  EFoo = class(Exception);

  TWorker = class
  public
    procedure Risky;
    /// <summary>Calls Risky and absorbs what it may raise.</summary>
    procedure Safe;
    procedure Plain;
  end;

implementation

procedure TWorker.Risky;
begin
  if Now < 0 then raise EFoo.Create('a');
  raise EArgumentException.Create('b');
end;

procedure TWorker.Safe;
begin
  try
    Risky;
  except
    on E: EFoo do raise;
    on EConvertError do ;
  end;
end;

procedure TWorker.Plain;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'exc.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}
function PosOf([string]$pattern, [string]$word) {
  $l = LineOf $pattern
  return @{ line = $l; character = $lines[$l].IndexOf($word) + 1 }
}
$uri = 'file:///' + ($file -replace '\\', '/')
$pRisky = PosOf '^procedure TWorker\.Risky;' 'Risky'
$pSafe  = PosOf '^procedure TWorker\.Safe;'  'Safe'
$pPlain = PosOf '^procedure TWorker\.Plain;' 'Plain'

function Session([string[]]$Extra, [string]$Tag) {
  $td = @{ uri = $uri }
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=$td; position=$pRisky } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='textDocument/hover'; params=@{ textDocument=$td; position=$pSafe } }
  $m += Frame @{ jsonrpc='2.0'; id=4; method='textDocument/hover'; params=@{ textDocument=$td; position=$pPlain } }
  $m += Frame @{ jsonrpc='2.0'; id=5; method='draglint/hoverBundle'; params=@{ textDocument=$td; position=$pRisky } }
  $m += Frame @{ jsonrpc='2.0'; id=6; method='textDocument/codeLens'; params=@{ textDocument=$td } }
  $m += Frame @{ jsonrpc='2.0'; id=9; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir "in-$Tag.txt"
  $outF = Join-Path $WorkDir "out-$Tag.txt"
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $db) + $Extra) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir "err-$Tag.txt") -NoNewWindow -Wait | Out-Null
  $r = @{}
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.id) { $r[[int]$o.id] = $o }
  }
  return $r
}
function HoverMd($resp) { if ($null -eq $resp -or $null -eq $resp.result) { return '' } return [string]$resp.result.contents.value }
function RaisesLines([string]$md) { return @(($md -split "`n") | Where-Object { $_ -match 'Raises:' }) }

# ---------------- ON (default) ----------------
$on = Session @() 'on'
$mdRisky = HoverMd $on[2]; $mdSafe = HoverMd $on[3]; $mdPlain = HoverMd $on[4]
$rl = RaisesLines $mdRisky
Check 'H1 hover Risky (no-doc path): exactly one Raises: line' ($rl.Count -eq 1) ("lines=" + ($rl -join ' | '))
Check 'H1 hover Risky: EFoo (bound), EArgumentException (spelled), source order' ($mdRisky -match 'Raises: EFoo \(bound\), EArgumentException \(spelled\)') ($rl -join ' | ')
$rs = RaisesLines $mdSafe
Check 'H1 hover Safe (doc path): Raises: EFoo (handler) -- the reraise under on E: EFoo' ($rs.Count -eq 1 -and $mdSafe -match 'Raises: EFoo \(handler\)') ("md=" + ($mdSafe -replace "`n", ' / '))
Check 'H1 control: the doc path really is the doc path (summary text shown)' ($mdSafe -match 'absorbs what it may raise')
Check 'H3 hover Plain: no Raises: line' ($mdPlain -ne '' -and (RaisesLines $mdPlain).Count -eq 0) ("md=" + ($mdPlain -replace "`n", ' / '))
$b = $on[5].result
Check 'H2 hoverBundle markdown carries the line' ($null -ne $b -and ([string]$b.markdown) -match 'Raises: EFoo \(bound\), EArgumentException \(spelled\)')
$bf = @(); if ($null -ne $b -and $null -ne $b.model) { $bf = @($b.model.facts) }
Check 'H2 hoverBundle model facts carry the line (the IDE popup renders these)' (@($bf | Where-Object { $_ -eq 'Raises: EFoo (bound), EArgumentException (spelled)' }).Count -eq 1) ("facts=" + ($bf -join ' | '))

$lens = @(); if ($null -ne $on[6]) { $lens = @($on[6].result) }
$lnRisky = LineOf '^\s*procedure Risky;'
$lnSafe  = LineOf '^\s*procedure Safe;'
$lnPlain = LineOf '^\s*procedure Plain;'
function LensTitles($ls, $ln) { return @($ls | Where-Object { $_.range.start.line -eq $ln } | ForEach-Object { [string]$_.command.title }) }
$tR = LensTitles $lens $lnRisky; $tS = LensTitles $lens $lnSafe; $tP = LensTitles $lens $lnPlain
Check 'L1 lens on Risky: raises 2 types' ($tR -contains 'raises 2 types') ($tR -join ' | ')
Check 'L1 lens on Safe: raises 1 type, handles 2 types' ($tS -contains 'raises 1 type, handles 2 types') ($tS -join ' | ')
Check 'L1 no exception lens on Plain' (@($tP | Where-Object { $_ -match 'raises|handles' }).Count -eq 0) ($tP -join ' | ')
Check 'L1 caller lenses still there (Risky 1 caller)' ($tR -contains '1 caller') ($tR -join ' | ')

# ---------------- OFF (--no-exception-facts) ----------------
$off = Session @('--no-exception-facts') 'off'
$oRisky = HoverMd $off[2]; $oSafe = HoverMd $off[3]
Check 'O1 OFF: hover still answers' ($oRisky -match 'Risky') ("md=" + ($oRisky -replace "`n", ' / '))
Check 'O1 OFF: no Raises: line' ((RaisesLines $oRisky).Count -eq 0 -and (RaisesLines $oSafe).Count -eq 0)
function Strip([string]$md) { return ((($md -split "`n") | Where-Object { $_ -notmatch 'Raises:' }) -join "`n") }
# Risky's only fact is Raises:, so ON also carries the 'Analysis facts:' header that line opened.
$riskyOnMinus = $mdRisky -replace '\r\n\r\n\*\*Analysis facts:\*\*\r\n- Raises: [^\r\n]*\r\n', "`r`n"
Check 'O1 OFF markdown == ON markdown minus its Raises: block (Risky, no-doc, Raises: the only fact)' ($oRisky -ne '' -and $riskyOnMinus -ne $mdRisky -and $riskyOnMinus -ceq $oRisky)
Check 'O1 OFF markdown == ON markdown minus its Raises: line (Safe, doc)' ($oSafe -ne '' -and (Strip $mdSafe) -ceq $oSafe)
$ob = @(); if ($null -ne $off[5].result -and $null -ne $off[5].result.model) { $ob = @($off[5].result.model.facts) }
Check 'O1 OFF: no Raises: in bundle facts' (@($ob | Where-Object { $_ -match 'Raises:' }).Count -eq 0)
$olens = @(); if ($null -ne $off[6]) { $olens = @($off[6].result) }
Check 'O1 OFF: no exception lens' (@($olens | Where-Object { ([string]$_.command.title) -match 'raises|handles' }).Count -eq 0)
Check 'O1 OFF: caller lenses unchanged' ((LensTitles $olens $lnRisky) -contains '1 caller')

if ($script:Failed) { Write-Host 'run_lsp_hover_exceptions_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_hover_exceptions_guard: PASS' -ForegroundColor Green
exit 0
} finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
