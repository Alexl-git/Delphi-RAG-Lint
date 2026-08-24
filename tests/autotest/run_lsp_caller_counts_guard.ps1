<#
  run_lsp_caller_counts_guard.ps1 -- `draglint/callerCounts` answers a whole
  file's caller counts in ONE round trip, against already-open stores.

  WHAT IT REPLACES. DragLint.Plugin.CodeLensCache listed a file's methods with a
  `surface` spawn and then shelled `query find-callers` ONCE PER METHOD, parsing
  the text output by line shape. Measured on DataCopy's uMainZeissCopy.pas: 136
  routines at ~165 ms per process start -- over twenty seconds of serial
  spawning to label one file, repeated on every repopulate. The same argument
  that produced draglint/hoverBundle, which replaced four spawns per tooltip.

  WHAT THIS PINS, and why each part is here rather than "it returned something":

    THE COUNT IS RIGHT. A fixture with a known call graph -- one routine called
    three times, one called once, one never -- so a handler that returned a
    constant, or the number of routines, or zero, fails.

    ROUTINES ONLY. Fields and properties have no caller count worth a lens, and
    including them would put '[0 callers]' on half the lines of a form class.

    LINES ARE 0-BASED. The store is 1-based and the plugin's cache is 0-based.
    The conversion happens on the server so exactly one place knows about the
    offset -- and an off-by-one here would hang every label one line off its
    routine, which is the kind of defect that looks like "the feature is a bit
    wrong" rather than "the feature is broken".

    AN UNKNOWN FILE IS NOT AN ERROR. A file in no index has no lenses; it must
    answer an empty list, not an error the client would retry forever.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-caller-counts"
)
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
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

# A known call graph: Thrice x3, Once x1, Never x0, plus a field and a property
# that must not appear at all.
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

function CountsFor([string]$path) {
  $uri = 'file:///' + ($path -replace '\\', '/')
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/callerCounts'; params=@{ textDocument=@{ uri=$uri } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    # ,@(...) -- PowerShell UNROLLS an empty array on return, so a correct
    # `{"counts":[]}` reply would arrive here as $null and read as 'the server
    # errored'. The comma operator is what keeps 'answered with nothing'
    # distinguishable from 'did not answer'.
    if ($o.id -eq 2 -and $null -ne $o.result) { return ,@($o.result.counts) }
  }
  return $null
}

$counts = CountsFor $file
Check 'the method answered' ($null -ne $counts) $(if ($null -eq $counts) { '<no result>' } else { "entries=$($counts.Count)" })
if ($null -eq $counts) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

# Map 0-based reply lines back to the routine that declares them, so the
# assertions below name routines rather than magic line numbers.
$lines = [System.IO.File]::ReadAllLines($file)
function CountOfRoutine([string]$declPattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $declPattern) {
      $hit = @($counts | Where-Object { $_.line -eq $i })
      if ($hit.Count -eq 1) { return [int]$hit[0].count }
    }
  }
  return -1   # not reported at this line at all
}

Write-Host ''
Write-Host 'THE COUNTS: a known call graph' -ForegroundColor Cyan
Check 'Thrice is reported with 3 callers' ((CountOfRoutine '^\s*procedure Thrice;') -eq 3) `
  "got=$(CountOfRoutine '^\s*procedure Thrice;')"
Check 'Once is reported with 1 caller'    ((CountOfRoutine '^\s*procedure Once;')   -eq 1) `
  "got=$(CountOfRoutine '^\s*procedure Once;')"
Check 'Never is reported with 0 callers'  ((CountOfRoutine '^\s*procedure Never;')  -eq 0) `
  "got=$(CountOfRoutine '^\s*procedure Never;')"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
# The counts must DISCRIMINATE. A handler returning one constant would satisfy
# any single assertion above.
$distinct = @($counts | ForEach-Object { $_.count } | Sort-Object -Unique)
Check 'CONTROL: not every routine got the same count' ($distinct.Count -ge 2) "distinct counts: $($distinct -join ', ')"

# A field and a property have no lens. If either appears, the kind filter is gone.
$fieldLine = -1; $propLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^\s*FCount: Integer;')            { $fieldLine = $i }
  if ($lines[$i] -match '^\s*property Count: Integer read') { $propLine  = $i }
}
Check 'CONTROL: the private FIELD is not reported'    (-not ($counts | Where-Object { $_.line -eq $fieldLine })) "line0=$fieldLine"
Check 'CONTROL: the PROPERTY is not reported'         (-not ($counts | Where-Object { $_.line -eq $propLine  })) "line0=$propLine"

# 0-based, and pinned against the actual declaration line rather than restated.
$thriceDecl = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*procedure Thrice;') { $thriceDecl = $i; break } }
Check 'CONTROL: lines are 0-BASED (interface decl of Thrice is reported)' `
  ($null -ne ($counts | Where-Object { $_.line -eq $thriceDecl })) "0-based decl line=$thriceDecl"

# An unknown file must be an empty answer, not an error.
$unknown = CountsFor (Join-Path $src 'uNotIndexed.pas')
Check 'CONTROL: a file in no index answers an EMPTY list, not an error' `
  (($null -ne $unknown) -and ($unknown.Count -eq 0)) `
  $(if ($null -eq $unknown) { '<error or no result>' } else { "entries=$($unknown.Count)" })

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
