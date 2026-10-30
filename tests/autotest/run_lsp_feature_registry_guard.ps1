#Requires -Version 7
<#
  run_lsp_feature_registry_guard.ps1 -- the LSP feature registry (S0) is wired
  end to end, and the refactor that introduced it changed no existing answer.

  WHAT THIS PINS, and why each part is here:

    THE REGISTRY ADVERTISES. `initialize` must carry capabilities.draglint.ping
    = true. That pair is added ONLY by TPingFeature.AddCapabilities, so it is
    the positive control for "HandleInitialize asked every registered feature".

    THE REGISTRY DISPATCHES. `draglint/ping` must answer {pong:true, version}
    with version equal to the `--version` banner. Nothing in Run's hard-coded
    chain knows that method, so an answer proves the method->feature table.

    THE CATCH-ALL SURVIVES (negative control). `draglint/nosuch` must still be
    -32601. A table that swallowed unknown methods -- or answered every method
    with ping -- would pass the two checks above and fail this one.

    NOTHING ELSE MOVED. hover / definition / references / callerCounts are
    moved into Compute* methods by S0. Their reply bodies on a fixed fixture
    are compared JSON-equal against a baseline captured from the PRE-change
    engine (fixtures\lsp\s0-baseline.json; -Capture rewrites it). The fixture
    path is normalised to <SRC> so the baseline is machine independent.

    CONTEXT.STORES IS HISTORY-FREE (fix round 1, I1). After a loose file is
    hovered (the server caches its ephemeral index), ping's `stores` count --
    Length(ILspServerContext.Stores) -- must still be the --db count. RED
    before the fix: stores=2.

  RED before S0: the capability and ping checks FAIL, the baseline PASSES.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir  = "$env:TEMP\drag-lint-feature-registry-$PID",
  [string]$Baseline = "$PSScriptRoot\fixtures\lsp\s0-baseline.json",
  [switch]$Capture
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
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"  # LSP-1 CORE: hover/notice text never depends on the user's real defaults
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

# The caller-counts fixture: a known call graph, so callerCounts has content.
$file = Join-Path $src 'uLens.pas'
WriteAnsi $file @'
unit uLens;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    procedure Thrice;
    procedure Once;
    procedure Never;
    property Count: Integer read FCount write FCount;
  end;

procedure Driver;

implementation

procedure TThing.Thrice;
begin
end;

procedure TThing.Once;
begin
end;

procedure TThing.Never;
begin
end;

procedure Driver;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Thrice;
  T.Thrice;
  T.Thrice;
  T.Once;
end;

end.
'@

$db = Join-Path $WorkDir 'lens.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$banner = (& $Exe --version 2>$null | Select-Object -First 1)
$bannerVersion = if ($banner -match '^drag-lint\s+(\S+)') { $Matches[1] } else { '' }
Check 'the --version banner names a version' ($bannerVersion -ne '') "banner='$banner'"

# Positions are derived from the fixture text, never restated as numbers.
$lines = [System.IO.File]::ReadAllLines($file)
$callLine = -1; $blankLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if (($callLine -lt 0) -and ($lines[$i] -match '^\s*T\.Thrice;')) { $callLine = $i }
  if (($blankLine -lt 0) -and ($lines[$i] -eq '')) { $blankLine = $i }
}
$callCol = $lines[$callLine].IndexOf('Thrice') + 1
$uri = 'file:///' + ($file -replace '\\', '/')
$td  = @{ uri = $uri }
$pos = @{ line = $callLine; character = $callCol }

# A loose unit OUTSIDE $src, so no --db owns it.
$looseDir = Join-Path $WorkDir 'loose'; New-Item -ItemType Directory $looseDir | Out-Null
$looseFile = Join-Path $looseDir 'uLoose.pas'
WriteAnsi $looseFile @'
unit uLoose;

interface

procedure LooseProc;

implementation

procedure LooseProc;
begin
end;

end.
'@
$looseLines = [System.IO.File]::ReadAllLines($looseFile)
$looseLine  = [Array]::FindIndex($looseLines, [Predicate[string]]{ param($l) $l -match '^procedure LooseProc;' })
$loosePos   = @{ line = $looseLine; character = $looseLines[$looseLine].IndexOf('LooseProc') + 1 }
$looseUri   = 'file:///' + ($looseFile -replace '\\', '/')

$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/ping'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/nosuch'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=4; method='textDocument/hover'; params=@{ textDocument=$td; position=$pos } }
$m += Frame @{ jsonrpc='2.0'; id=5; method='textDocument/hover'; params=@{ textDocument=$td; position=@{ line=$blankLine; character=0 } } }
$m += Frame @{ jsonrpc='2.0'; id=6; method='textDocument/definition'; params=@{ textDocument=$td; position=$pos } }
$m += Frame @{ jsonrpc='2.0'; id=7; method='textDocument/references'; params=@{ textDocument=$td; position=$pos; context=@{ includeDeclaration=$true } } }
$m += Frame @{ jsonrpc='2.0'; id=8; method='textDocument/references'; params=@{ textDocument=$td; position=$pos; context=@{ includeDeclaration=$false } } }
$m += Frame @{ jsonrpc='2.0'; id=9; method='draglint/callerCounts'; params=@{ textDocument=$td } }
# I1: a loose file (owned by no --db) is hovered, which makes the server cache
# a single-unit ephemeral index for it; ping's `stores` must not count it.
$m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/hover'; params=@{ textDocument=@{ uri=$looseUri }; position=$loosePos } }
$m += Frame @{ jsonrpc='2.0'; id=12; method='draglint/ping'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=10; method='shutdown'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }
$inF  = Join-Path $WorkDir 'in.txt'
$outF = Join-Path $WorkDir 'out.txt'
[System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF `
  -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null

# id -> raw JSON text of the reply, kept raw so the baseline compares bytes of
# the engine's own serialisation (after path normalisation), not a re-encoding.
$raw = @{}
foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  $t = $mm.Value.Trim()
  try { $o = $t | ConvertFrom-Json } catch { continue }
  if ($null -ne $o.id) { $raw[[int]$o.id] = $t }
}
function Reply([int]$id) { if ($raw.ContainsKey($id)) { return ($raw[$id] | ConvertFrom-Json) } return $null }

Write-Host ''
Write-Host 'THE REGISTRY: advertise + dispatch' -ForegroundColor Cyan
$init = Reply 1
Check 'initialize answered' ($null -ne $init -and $null -ne $init.result)
$cap = if ($init -and $init.result -and $init.result.capabilities) { $init.result.capabilities.draglint } else { $null }
Check 'capabilities.draglint.ping == true (added by the Ping feature)' (($null -ne $cap) -and ($cap.ping -eq $true)) "draglint=$($cap | ConvertTo-Json -Compress)"
Check 'CONTROL: built-in capabilities still present (hoverProvider)' ($init.result.capabilities.hoverProvider -eq $true)

$ping = Reply 2
Check 'draglint/ping answers pong=true' (($null -ne $ping) -and ($null -ne $ping.result) -and ($ping.result.pong -eq $true)) `
  $(if ($null -eq $ping) { '<no reply>' } elseif ($ping.error) { "error=$($ping.error.code) $($ping.error.message)" } else { $raw[2] })
Check 'draglint/ping version equals the --version banner' (($null -ne $ping) -and ($null -ne $ping.result) -and ($ping.result.version -eq $bannerVersion)) `
  "banner=$bannerVersion got=$(if ($ping -and $ping.result) { $ping.result.version })"

Write-Host ''
Write-Host 'CONTEXT.STORES: configured stores only (I1)' -ForegroundColor Cyan
Check 'CONTROL: ping reports stores = 1 before any loose file' (($null -ne $ping) -and ($ping.result.stores -eq 1)) "stores=$(if ($ping -and $ping.result) { $ping.result.stores })"
$looseHover = Reply 11
Check 'CONTROL: the loose file was indexed (hover names LooseProc)' (($null -ne $looseHover) -and ($raw[11] -match 'LooseProc')) $(if ($null -eq $looseHover) { '<no reply>' } else { $raw[11] })
$ping2 = Reply 12
Check 'Stores excludes the cached loose-file index (stores still 1)' (($null -ne $ping2) -and ($ping2.result.stores -eq 1)) "stores=$(if ($ping2 -and $ping2.result) { $ping2.result.stores })"

$nosuch = Reply 3
Check 'NEGATIVE CONTROL: draglint/nosuch is still -32601' (($null -ne $nosuch) -and ($null -ne $nosuch.error) -and ($nosuch.error.code -eq -32601)) `
  $(if ($null -eq $nosuch) { '<no reply>' } else { $raw[3] })

Write-Host ''
Write-Host 'THE EXISTING SURFACE: same bodies as the pre-S0 engine' -ForegroundColor Cyan
function Normalise([string]$json) {
  if ($null -eq $json) { return '<no reply>' }
  $o = $json | ConvertFrom-Json
  $res = $o.result
  # callerCounts comes out of a TDictionary walk; compare it as a set.
  if (($o.id -eq 9) -and $res -and $res.counts) {
    $res = [pscustomobject]@{ counts = @($res.counts | Sort-Object line, count) }
  }
  $j = ConvertTo-Json -InputObject $res -Compress -Depth 20
  return ($j -replace 'file:///[^"]*?/src/', 'file:///<SRC>/')
}
$current = [ordered]@{}
foreach ($id in 4..9) { $current["$id"] = Normalise $raw[$id] }
$names = @{ '4'='hover (call site)'; '5'='hover (blank line, null)'; '6'='definition'; '7'='references +decl'; '8'='references -decl'; '9'='callerCounts' }

if ($Capture) {
  $dir = Split-Path $Baseline -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
  $body = ($current | ConvertTo-Json -Depth 5)
  WriteAnsi $Baseline ($body + "`n")
  Write-Host "  captured baseline -> $Baseline" -ForegroundColor Yellow
  Write-Host 'CAPTURED -- comparison not run' -ForegroundColor Yellow
  exit 0
}
if (-not (Test-Path $Baseline)) { Check 'baseline file present' $false $Baseline }
else {
  $base = Get-Content $Baseline -Raw | ConvertFrom-Json
  foreach ($id in 4..9) {
    $want = $base."$id"
    $got  = $current["$id"]
    Check "$($names["$id"]) unchanged" ($want -eq $got) $(if ($want -ne $got) { "`n      want=$want`n      got =$got" })
  }
  # The baseline must not be vacuous: the call-site hover and definition carry content.
  Check 'CONTROL: baseline hover has markdown' ($base.'4' -match 'Thrice')
  Check 'CONTROL: baseline definition has a location' ($base.'6' -match 'uLens\.pas')
  Check 'CONTROL: baseline callerCounts has a 3' ($base.'9' -match '"count":3')
}

Write-Host ''
Write-Host ''
Write-Host 'S8: a raising feature answers -32603 and the server stays alive' -ForegroundColor Cyan
function RaiseSession([bool]$withHook) {
  $mr  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $mr += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $mr += Frame @{ jsonrpc='2.0'; method='draglint/testRaise'; params=@{} }
  $mr += Frame @{ jsonrpc='2.0'; id=2; method='draglint/testRaise'; params=@{} }
  $mr += Frame @{ jsonrpc='2.0'; id=3; method='draglint/ping'; params=@{} }
  $mr += Frame @{ jsonrpc='2.0'; id=4; method='shutdown'; params=@{} }
  $mr += Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }
  $inR  = Join-Path $WorkDir 'in-raise.txt'
  $outR = Join-Path $WorkDir 'out-raise.txt'
  [System.IO.File]::WriteAllText($inR, $mr, (New-Object System.Text.ASCIIEncoding))
  $env:DRAGLINT_LSP_TEST_RAISE = $(if ($withHook) { '1' } else { '' })
  try {
    Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
      -RedirectStandardInput $inR -RedirectStandardOutput $outR `
      -RedirectStandardError (Join-Path $WorkDir 'err-raise.txt') -NoNewWindow -Wait | Out-Null
  } finally { $env:DRAGLINT_LSP_TEST_RAISE = $null }
  $rr = @{}
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outR), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.id) { $rr[[int]$o.id] = $o }
  }
  return $rr
}
$rh = RaiseSession $true
Check 'S8: the raising feature answers error -32603' ($rh.ContainsKey(2) -and $null -ne $rh[2].error -and $rh[2].error.code -eq -32603) $(if ($rh.ContainsKey(2)) { ($rh[2] | ConvertTo-Json -Compress -Depth 4) } else { '<no reply>' })
Check 'S8: the server is still alive -- the next request (ping) is answered' ($rh.ContainsKey(3) -and $rh[3].result.pong -eq $true) $(if ($rh.ContainsKey(3)) { '' } else { '<no reply: server died>' })
Check 'S8: shutdown still answered after the failure' ($rh.ContainsKey(4))
$errTxt = [System.IO.File]::ReadAllText((Join-Path $WorkDir 'err-raise.txt'))
Check 'S8: a raising NOTIFICATION is logged to stderr (not swallowed silently)' ($errTxt -match 'draglint/testRaise raised ETestRaise') ($errTxt.Trim())
$rn = RaiseSession $false
Check 'S8 CONTROL: without the test env var the hook does not exist (-32601)' ($rn.ContainsKey(2) -and $null -ne $rn[2].error -and $rn[2].error.code -eq -32601) $(if ($rn.ContainsKey(2)) { ($rn[2] | ConvertTo-Json -Compress -Depth 4) } else { '<no reply>' })

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @($WorkDir)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
