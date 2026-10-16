<#
  run_lsp_config_lint.ps1 -- the LSP's publishDiagnostics honours the "lint"
  block of the repository's _D-RAG\config.json, as the CLI does (E3b item 5,
  2026-10-14).

  THE GAP. DRagLint.LSP.Completion.DiscoverLintConfig walked up from the file
  looking for drag-lint-lint.json or drag-lint.json and knew nothing of
  config.json. Inside a configured repository the CLI's lint config is the
  config.json "lint" block (E3a) -- so `lint` and the editor disagreed: a rule
  the repository opts in was reported on the command line and never shown in
  the IDE, which is the surface people actually read.

  THE RULE, the same precedence the CLI's LoadLintConfig has:
    * a config.json above the file with a "lint" object -> that block;
    * otherwise the walk-up as before (drag-lint-lint.json, drag-lint.json),
      so an unconfigured folder -- the author's layout -- is untouched.

  CASES (FixtureNilCmp.pas: a default-OFF nil-comparison plus a default-ON
  empty-except):
    C   config.json "lint": {"enabled": ["nil-comparison"]} -> published      <- FIX
    C'  CONTROL: the CLI `lint` of the same file reports it too (parity)
    N   config.json WITHOUT "lint" + a loose drag-lint-lint.json enabling it
        -> still published (no "lint" block: the walk-up still answers)
    K   CONTROL: an unconfigured folder with drag-lint-lint.json -> published
    E   CONTROL: empty-except is published in every case
  RED-CHECK: on the pre-fix exe C fails; C', N, K and E pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_lsp_cfg_lint_$PID"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

$src = @'
unit FixtureNilCmp;

interface

type
  TFoo = class
  public
    procedure Go(const AObj: TObject);
  end;

implementation

procedure TFoo.Go(const AObj: TObject);
begin
  if AObj = nil then
    Exit;
  try
    AObj.ToString;
  except
  end;
end;

end.
'@

$cRepo = Join-Path $WorkDir 'withlint'
$nRepo = Join-Path $WorkDir 'nolint'
$plain = Join-Path $WorkDir 'plain'
$cFix  = Join-Path $cRepo 'src\FixtureNilCmp.pas'
$nFix  = Join-Path $nRepo 'src\FixtureNilCmp.pas'
$kFix  = Join-Path $plain 'FixtureNilCmp.pas'
Write-Ascii $cFix $src
Write-Ascii $nFix $src
Write-Ascii $kFix $src
Write-Ascii (Join-Path $cRepo '_D-RAG\config.json') '{ "version": 1, "projects": [], "lint": { "enabled": ["nil-comparison"] } }'
Write-Ascii (Join-Path $nRepo '_D-RAG\config.json') '{ "version": 1, "projects": [] }'
Write-Ascii (Join-Path $nRepo 'src\drag-lint-lint.json') '{ "enabled": ["nil-comparison"] }'
Write-Ascii (Join-Path $plain 'drag-lint-lint.json') '{ "enabled": ["nil-comparison"] }'

function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function PublishedCodes([string]$PasFile, [string]$Tag) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($PasFile)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $io = Join-Path $WorkDir ("lsp-" + $Tag)
  New-Item -ItemType Directory $io -Force | Out-Null
  $in = Join-Path $io 'in.txt'
  $so = Join-Path $io 'out.txt'
  $se = Join-Path $io 'err.txt'
  [System.IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  # A neutral CWD: the file's own path is what must find the configuration.
  $p = Start-Process $Exe -ArgumentList 'lsp' -WorkingDirectory C:\TEMP `
         -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se `
         -NoNewWindow -Wait -PassThru
  $out = ''
  if (Test-Path $so) { $out = [System.IO.File]::ReadAllText($so) }
  $codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
  Write-Host ("  ({0}) exit={1}, published: {2}" -f $Tag, $p.ExitCode, $(if ($codes.Count) { ($codes | Sort-Object -Unique) -join ', ' } else { '<none>' })) -ForegroundColor DarkGray
  return $codes
}

Write-Host ''
Write-Host 'run_lsp_config_lint -- the editor reads the same lint config as the CLI' -ForegroundColor Cyan

Write-Host ''
Write-Host 'C -- config.json "lint" block' -ForegroundColor Cyan
$c = PublishedCodes $cFix 'withlint'
Check 'C nil-comparison IS published (config.json "lint" opts it in)' ($c -contains 'nil-comparison') ("published=[" + (($c | Sort-Object -Unique) -join ',') + "]")
Check 'E empty-except is published' ($c -contains 'empty-except') ''
Push-Location C:\TEMP
try { $cli = (& $Exe lint $cFix 2>&1) -join "`n" } finally { Pop-Location }
Check "C' CONTROL: CLI lint of the same file reports nil-comparison (the parity being enforced)" ($cli -match 'nil-comparison') ''

Write-Host ''
Write-Host 'N -- config.json without "lint": the loose file still answers' -ForegroundColor Cyan
$n = PublishedCodes $nFix 'nolint'
Check 'N nil-comparison is published (loose drag-lint-lint.json, no "lint" block to win over it)' ($n -contains 'nil-comparison') ("published=[" + (($n | Sort-Object -Unique) -join ',') + "]")
Check 'E empty-except is published' ($n -contains 'empty-except') ''

Write-Host ''
Write-Host 'K -- CONTROL: an unconfigured folder, as before' -ForegroundColor Cyan
$k = PublishedCodes $kFix 'plain'
Check 'K nil-comparison is published (drag-lint-lint.json beside the file)' ($k -contains 'nil-comparison') ("published=[" + (($k | Sort-Object -Unique) -join ',') + "]")
Check 'E empty-except is published' ($k -contains 'empty-except') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_lsp_cfg_lint_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
