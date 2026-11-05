<#
  run_lsp_ide_parity_guard.ps1 -- G0 (headless half): for the same file, the findings the IDE
  plugin's live gutter gets (`lint <file> --db <db>`, the text the plugin's LintOutputParse reads;
  DragLint.Plugin.LiveDiagnostics) and the ones `lsp --db <db> --full-rules` publishes to VS Code's
  Problems tab must be the SAME set of (line, rule, message). Plain `lsp --db` publishes a documented
  SUBSET (no built-ins, C1): that is the config cause of the "VS Code differs" reports.

  Positive controls: the subset run must really differ (the comparator can see a difference), and the
  dl:ok fixture must fire with its marker removed (the marker check can see a suppression).
  Not covered, needs a person: the panel's own display filter, the unsaved-buffer snapshot.

  -MeasureDb + -MeasureUnits: print per-unit counts and differences for real units, no assertions.
  Call it with & from pwsh for this mode: pwsh -File does not bind a list to -MeasureUnits.
  Run from any CWD, pwsh 7.
#>
#Requires -Version 7
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-ide-parity-$PID",
  [string]$MeasureDb = '',
  [string[]]$MeasureUnits = @()
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
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Exe = (Resolve-Path $Exe).Path

function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
# The plugin's view: the text report, parsed the way TryParseFindingLine reads it.
function IdeKeys([string]$Pas, [string]$Db) {
  $keys = foreach ($l in (& $Exe lint $Pas --db $Db 2>$null)) {
    $m = [regex]::Match([string]$l, ':(\d+):\d+\s+\[\w+\]\s+([a-z0-9\-]+):\s(.*)$')
    if ($m.Success) { '{0}|{1}|{2}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value.Trim() }
  }
  return ,@($keys | Sort-Object -Unique)
}
# VS Code's view: the LAST publishDiagnostics for the file, line made 1-based.
function LspKeys([string]$Pas, [string[]]$Flags, [string]$Tag) {
  $uri = 'file:///' + ($Pas -replace '\\', '/')
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didSave'; params=@{ textDocument=@{ uri=$uri } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  $in = Join-Path $dir 'in.txt'; $so = Join-Path $dir 'out.txt'; $se = Join-Path $dir 'err.txt'
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList (@('lsp') + $Flags) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $last = $null
  foreach ($part in ([IO.File]::ReadAllText($so) -split 'Content-Length: \d+\r\n\r\n')) {
    if ($part -notmatch 'publishDiagnostics') { continue }
    $o = $part | ConvertFrom-Json -Depth 30
    if ($o.method -eq 'textDocument/publishDiagnostics') { $last = $o }
  }
  $keys = if ($last) { foreach ($d in $last.params.diagnostics) { '{0}|{1}|{2}' -f ([int]$d.range.start.line + 1), $d.code, ([string]$d.message).Trim() } }
  return ,@($keys | Sort-Object -Unique)
}
function OnlyIn([string[]]$A, [string[]]$B) { return ,@($A | Where-Object { $_ -notin $B }) }

if ($MeasureDb) {
  foreach ($u in $MeasureUnits) {
    $n = [IO.Path]::GetFileNameWithoutExtension($u)
    $i = IdeKeys $u $MeasureDb
    $f = LspKeys $u @('--db', $MeasureDb, '--full-rules') "$n-full"
    $p = LspKeys $u @('--db', $MeasureDb) "$n-plain"
    Write-Host ("{0}: ide={1} lsp-full={2} lsp-plain={3}" -f $n, $i.Count, $f.Count, $p.Count)
    foreach ($k in (OnlyIn $i $f)) { Write-Host "  ide-only      $k" }
    foreach ($k in (OnlyIn $f $i)) { Write-Host "  full-only     $k" }
    foreach ($k in (OnlyIn $p $i)) { Write-Host "  plain-only    $k" }
    $missed = (OnlyIn $i $p) | ForEach-Object { ($_ -split '\|')[1] } | Sort-Object -Unique
    Write-Host ("  plain misses {0}: {1}" -f (OnlyIn $i $p).Count, ($missed -join ', '))
  }
  exit 0
}

$body = @('unit FxParity;', '', 'interface', '', 'type', '  TA = class', '    constructor Create;', '  end;', '',
  'implementation', '', 'constructor TA.Create;', 'begin', '  Writeln(1);', 'end;', '',
  'procedure Go(const S: string);', 'begin', '  Exit;', '  Writeln(S);', 'end;', '',
  'procedure Reviewed(const S: string);', 'begin', '  Exit;', '  Writeln(S); // dl:ok code-after-exit -- fixture: the reviewed one', 'end;', '', 'end.') -join "`r`n"
$Src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory -Force $Src | Out-Null
$Pas = Join-Path $Src 'FxParity.pas'
[IO.File]::WriteAllText($Pas, $body + "`r`n", [Text.Encoding]::ASCII)
$NoMarkerDir = Join-Path $WorkDir 'nomarker'; New-Item -ItemType Directory -Force $NoMarkerDir | Out-Null
$NoMarker = Join-Path $NoMarkerDir 'FxParity.pas'
[IO.File]::WriteAllText($NoMarker, ($body -replace ' // dl:ok[^\r]*', '') + "`r`n", [Text.Encoding]::ASCII)
$Db = Join-Path $WorkDir 'fx.sqlite'
$env:DRAGLINT_CONTEXT_DEFAULTS = Join-Path $WorkDir 'context-defaults.json'
[IO.File]::WriteAllText($env:DRAGLINT_CONTEXT_DEFAULTS, '{}', (New-Object Text.UTF8Encoding($false)))
& $Exe index $Src --db $Db 2>&1 | Out-Null
if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB' -ForegroundColor Red; exit 2 }

Write-Host 'G0: IDE live lint vs LSP Problems tab, same file, same DB' -ForegroundColor Cyan
$Ide  = IdeKeys $Pas $Db
$Full = LspKeys $Pas @('--db', $Db, '--full-rules') 'full'
$Plain= LspKeys $Pas @('--db', $Db) 'plain'
$Open = IdeKeys $NoMarker $Db
Check 'setup: the IDE view has findings'          ($Ide.Count -ge 2) "n=$($Ide.Count)"
Check 'setup: the rule under test fires'          (@($Ide | Where-Object { $_ -match '\|code-after-exit\|' }).Count -eq 1)
Check 'parity: nothing only in the IDE view'      ((OnlyIn $Ide $Full).Count -eq 0) ((OnlyIn $Ide $Full) -join ' ;; ')
Check 'parity: nothing only in lsp --full-rules'  ((OnlyIn $Full $Ide).Count -eq 0) ((OnlyIn $Full $Ide) -join ' ;; ')
Check 'dl:ok: both views drop the reviewed line'  (@($Ide + $Full | Where-Object { $_ -match '^26\|code-after-exit\|' }).Count -eq 0) ($Ide -join ' ;; ')
Check 'control: without the marker it fires'      (@($Open | Where-Object { $_ -match '^26\|code-after-exit\|' }).Count -eq 1) ($Open -join ' ;; ')
Check 'control: plain lsp IS a smaller set'       ((OnlyIn $Ide $Plain).Count -gt 0) "misses=$((OnlyIn $Ide $Plain).Count)"
Check 'subset: plain lsp adds nothing of its own' ((OnlyIn $Plain $Ide).Count -eq 0) ((OnlyIn $Plain $Ide) -join ' ;; ')
if ($script:Failed) { exit 1 }
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
