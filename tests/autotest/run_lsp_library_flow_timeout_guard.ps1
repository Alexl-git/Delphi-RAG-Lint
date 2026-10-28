#Requires -Version 7
<#
  run_lsp_library_flow_timeout_guard.ps1 -- LSP C11 (E29 follow-up, lane X-PERF).

  After E29 dropped the project-rules pass for a platform-library unit,
  `lint System.IOUtils.pas --db library-Win64.sqlite` still spent 9.8 s of a
  17.5 s run in the FLOW phase (DRAGLINT_PROFILE, 100%-CPU box). `lsp
  --full-rules` (and the IDE plugin) give the child lint 8 s, so opening an RTL
  file timed out and fell back to the subset:
      drag-lint lsp: full-rules fallback to the subset (timeout, ...)
      full-rules ...System.IOUtils.pas 8093 ms 15 findings

  FIX. A store whose file name starts with `library-` (the E29 test) also skips
  the flow checker. The user cannot edit the RTL, so its dataflow findings are
  noise; a project store is never named `library-`, so project files keep it.

  A1  library-named store: `lint` does not run the flow checker
      ([lint-checker] flow absent) and reports no used-before-assignment.
  A2  library-named store via `lsp --full-rules`: no fallback line, and
      used-before-assignment is not published.
  A3  POSITIVE CONTROL -- the SAME fixture in a project-named store: lint runs
      the flow checker and `lsp --full-rules` publishes used-before-assignment.
      A fix that switched flow off for every store turns A3 red.
  A4  (opt-in, -LibraryDb + -LibraryUnit) the real file against a COPY of the
      platform library: `lsp --full-rules` didOpen does not fall back.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir    = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir     = "C:\TEMP\draglint_lsp_lib_flow_$PID",
  [string]$LibraryDb   = '',
  [string]$LibraryUnit = ''
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
Push-Location $WorkDir

# A local read before any write: used-before-assignment is a flow-checker rule.
Write-Ascii (Join-Path $src 'uFlowFx.pas') @'
unit uFlowFx;

interface

/// <summary>Fixture routine.</summary>
function Twice: Integer;

implementation

function Twice: Integer;
var
  N: Integer;
begin
  Result:= N * 2;
end;

end.
'@
$fx     = Join-Path $src 'uFlowFx.pas'
$libDb  = Join-Path $WorkDir 'library-Fixture.sqlite'
$projDb = Join-Path $WorkDir 'Fixture.sqlite'
foreach ($d in $libDb, $projDb) {
  $idx = & $exePath index $src --db $d 2>&1 | Out-String
  Check "SANITY: fixture indexed into $(Split-Path $d -Leaf)" ($LASTEXITCODE -eq 0) $idx
}

function LintDbg($db) {
  $env:DRAGLINT_DEBUG = '1'
  try { & $exePath lint $fx --db $db --rules-dir $rules 2>&1 | Out-String }
  finally { Remove-Item Env:\DRAGLINT_DEBUG }
}
function Frame($obj) { $j = $obj | ConvertTo-Json -Depth 20 -Compress; "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j" }
function LspOpen([string]$PasFile, [string]$Db, [string]$Tag) {
  $uri = 'file:///' + ($PasFile -replace '\\', '/')
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=[IO.File]::ReadAllText($PasFile) } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }))
  $dir = Join-Path $WorkDir $Tag; New-Item -ItemType Directory -Force $dir | Out-Null
  $in = Join-Path $dir 'in.txt'; $so = Join-Path $dir 'out.txt'; $se = Join-Path $dir 'err.txt'
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  $p = Start-Process $exePath -ArgumentList @('lsp', '--db', ('"' + $Db + '"'), '--full-rules') -WorkingDirectory $WorkDir `
         -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait -PassThru
  $out = [IO.File]::ReadAllText($so); $err = [IO.File]::ReadAllText($se)
  $codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
  $cost = ([regex]::Matches($err, 'full-rules[^\r\n]*') | ForEach-Object Value) -join ' | '
  Write-Host ("  ({0}) exit={1} published: {2} :: {3}" -f $Tag, $p.ExitCode, $(if ($codes.Count) { ($codes | Sort-Object -Unique) -join ', ' } else { '<none>' }), $cost) -ForegroundColor DarkGray
  return @{ Out = $out; Err = $err; Codes = $codes }
}

$lib  = LintDbg $libDb
$proj = LintDbg $projDb
Check 'SANITY: the library-named store still serves the per-file checkers (store=True, fid>0)' `
      ($lib -match 'store=True' -and $lib -notmatch 'fid=0\b') `
      (($lib -split "`n" | Where-Object { $_ -match '\[flowdb\]' }) -join ' ')
Check 'A1  library-named store: lint does not run the flow checker' ($lib -notmatch '\[lint-checker\] flow') ''
Check 'A1b library-named store: no used-before-assignment finding' ($lib -notmatch '\] used-before-assignment:') ''
Check 'A3  CONTROL: a project-named store runs the flow checker' ($proj -match '\[lint-checker\] flow') ''
Check 'A3b CONTROL: a project-named store reports used-before-assignment' ($proj -match '\] used-before-assignment:') ''

$lspLib  = LspOpen $fx $libDb  'lsplib'
$lspProj = LspOpen $fx $projDb 'lspproj'
Check 'A2  lsp --full-rules, library store: no fallback to the subset' `
      ($lspLib.Err -match 'full-rules .+ \d+ ms \d+ findings' -and $lspLib.Err -notmatch 'fallback') $lspLib.Err
Check 'A2b lsp --full-rules, library store: used-before-assignment not published' ($lspLib.Codes -notcontains 'used-before-assignment') ''
Check 'A3c CONTROL: lsp --full-rules, project store: used-before-assignment IS published' `
      ($lspProj.Codes -contains 'used-before-assignment' -and $lspProj.Err -notmatch 'fallback') $lspProj.Err

if ($LibraryDb -ne '' -and $LibraryUnit -ne '') {
  if (-not (Split-Path $LibraryDb -Leaf).StartsWith('library-', [StringComparison]::OrdinalIgnoreCase)) {
    Check 'A4  -LibraryDb must be named library-*.sqlite (a COPY of the platform library)' $false $LibraryDb
  } else {
    $real = LspOpen $LibraryUnit $LibraryDb 'lspreal'
    Check 'A4  real library unit: lsp --full-rules didOpen finishes inside the budget (no fallback)' `
          ($real.Err -match 'full-rules .+ \d+ ms \d+ findings' -and $real.Err -notmatch 'fallback') $real.Err
  }
} else {
  Write-Host '[INFO] A4 not run (pass -LibraryDb <copy of library-*.sqlite> -LibraryUnit <file in it>)'
}

Write-Host ''
if ($fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
}
finally {
  Pop-Location -ErrorAction SilentlyContinue
}
