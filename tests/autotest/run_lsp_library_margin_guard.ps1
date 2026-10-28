#Requires -Version 7
<#
  run_lsp_library_margin_guard.ps1 -- LSP C12 (follow-up of C11).

  After C11 a platform-library unit (System.IOUtils.pas vs library-Win64) ran
  `lsp --full-rules` didOpen in 7843 ms on a 100%-CPU box: inside the 8 s child
  budget by 157 ms. C12 buys margin two ways:

  * ENGINE: a `library-*` store also skips the type-aware checker (float
    equality, lossy casts, FreeAndNil-on-interface ...). On IOUtils it produced
    0 findings for ~0.5 s; it is type-correctness of code the user cannot edit.
    The scm rules and the structural AST checks still run (they are what an RTL
    file shows).
  * LSP: when the FIRST store owning the file is a `library-*` index the child
    gets LINT_CHILD_LIBRARY_TIMEOUT_MS (16 s; DRagLint.Core.LintBudget since C13) instead of 8 s. The IDE
    plugin's own 8 s live-runner budget is a separate constant and unchanged.

  B1  library-named store: lint does not run the type-aware checker and does
      not report float-equality-comparison.
  B2  POSITIVE CONTROL -- the same fixture in a project-named store: the
      type-aware checker runs and float-equality-comparison is reported.
  B3  lsp --full-rules, library store, a stub child that answers after
      -StubSleepMs (default 10 s, > 8 s, < 16 s): the answer is published
      (synthetic zz-stub-rule), no fallback.
  B4  POSITIVE CONTROL -- the same stub against the project store still hits
      the 8 s budget and falls back to the subset.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir    = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir     = "C:\TEMP\draglint_lsp_lib_margin_$PID",
  [int]   $StubSleepMs = 10000
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

# A Double compared with = : float-equality-comparison is a type-aware rule.
Write-Ascii (Join-Path $src 'uTypeFx.pas') @'
unit uTypeFx;

interface

/// <summary>Fixture routine.</summary>
function IsHalf(const pValue: Double): Boolean;

implementation

function IsHalf(const pValue: Double): Boolean;
begin
  Result:= pValue = 0.5;
end;

end.
'@
$fx     = Join-Path $src 'uTypeFx.pas'
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
$lib  = LintDbg $libDb
$proj = LintDbg $projDb
Check 'SANITY: the library-named store serves the file (store=True, fid>0)' ($lib -match 'store=True' -and $lib -notmatch 'fid=0\b') ''
Check 'B1  library-named store: lint does not run the type-aware checker' ($lib -notmatch '\[lint-checker\] type-aware') ''
Check 'B1b library-named store: no float-equality-comparison finding' ($lib -notmatch '\] float-equality-comparison:') ''
Check 'B2  CONTROL: a project-named store runs the type-aware checker' ($proj -match '\[lint-checker\] type-aware') ''
Check 'B2b CONTROL: a project-named store reports float-equality-comparison' ($proj -match '\] float-equality-comparison:') ''

# ---- B3/B4: the LSP child budget, through the test-only substitute child ----
$csc = @('Framework64', 'Framework') | ForEach-Object { Join-Path $env:WINDIR "Microsoft.NET\$_\v4.0.30319\csc.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1
$stubExe = Join-Path $WorkDir 'FullRulesChildStub.exe'
if ($csc) { $null = & $csc /nologo /out:$stubExe (Join-Path $PSScriptRoot 'fixtures\lsp\FullRulesChildStub.cs') 2>&1 }
Check 'SANITY: the stub child compiled (csc + FullRulesChildStub.cs)' (Test-Path $stubExe) ('csc=' + $csc)
$emitF = Join-Path $WorkDir 'emit.json'
# The stub's answer is a REAL lint array (project store) with the rule id made synthetic,
# so a published zz-stub-rule can only come from the substituted child.
$arr = (& $exePath lint $fx --db $projDb --rules-dir $rules --json 2>$null) -join "`n"
Write-Ascii $emitF ($arr -replace 'float-equality-comparison', 'zz-stub-rule')

function Frame($obj) { $j = $obj | ConvertTo-Json -Depth 20 -Compress; "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j" }
function LspOpenStub([string]$Db, [string]$Tag) {
  $uri = 'file:///' + ($fx -replace '\\', '/')
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=[IO.File]::ReadAllText($fx) } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }))
  $dir = Join-Path $WorkDir $Tag; New-Item -ItemType Directory -Force $dir | Out-Null
  $in = Join-Path $dir 'in.txt'; $so = Join-Path $dir 'out.txt'; $se = Join-Path $dir 'err.txt'
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  $env:DRAGLINT_FULLRULES_CHILD_EXE = $stubExe; $env:STUB_MODE = 'slowemit'; $env:STUB_SLEEP_MS = "$StubSleepMs"; $env:STUB_JSON_FILE = $emitF
  try {
    $p = Start-Process $exePath -ArgumentList @('lsp', '--db', ('"' + $Db + '"'), '--full-rules') -WorkingDirectory $WorkDir `
           -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait -PassThru
  } finally {
    Remove-Item Env:DRAGLINT_FULLRULES_CHILD_EXE, Env:STUB_MODE, Env:STUB_SLEEP_MS, Env:STUB_JSON_FILE -ErrorAction SilentlyContinue
  }
  $out = [IO.File]::ReadAllText($so); $err = [IO.File]::ReadAllText($se)
  $codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
  $cost = ([regex]::Matches($err, 'full-rules[^\r\n]*') | ForEach-Object Value) -join ' | '
  Write-Host ("  ({0}) exit={1} published: {2} :: {3}" -f $Tag, $p.ExitCode, $(if ($codes.Count) { ($codes | Sort-Object -Unique) -join ', ' } else { '<none>' }), $cost) -ForegroundColor DarkGray
  return @{ Out = $out; Err = $err; Codes = $codes }
}
if (Test-Path $stubExe) {
  $sl = LspOpenStub $libDb  'stublib'
  $sp = LspOpenStub $projDb 'stubproj'
  Check ("B3  library store: a child answering after {0} ms is published (zz-stub-rule)" -f $StubSleepMs) ($sl.Codes -contains 'zz-stub-rule') $sl.Err
  Check 'B3b library store: no fallback to the subset' ($sl.Err -notmatch 'fallback') $sl.Err
  Check 'B4  CONTROL: project store: the same child hits the 8 s budget and falls back' `
        ($sp.Err -match 'full-rules fallback to the subset' -and $sp.Codes -notcontains 'zz-stub-rule') $sp.Err
  Check 'B4b no orphan stub left behind' (-not (Get-Process -Name FullRulesChildStub -ErrorAction SilentlyContinue)) ''
}

Write-Host ''
if ($fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
}
finally {
  Pop-Location -ErrorAction SilentlyContinue
}
