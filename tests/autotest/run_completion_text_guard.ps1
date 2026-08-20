<#
  run_completion_text_guard.ps1 -- how a completion row READS.

  WHAT THE OWNER ASKED FOR (live IDE, 2026-08-19):
    "The popup that we get for autocompletion ... the IDE autocomplete provides
     a full type - procedure instead of p etc. ... functions should show
     returned types. Could be procedures should show optional parameters. Not
     just prompt split for a string, but split(...)"

  Before, a row was built as:   '<glyph> <name> - <whole signature>'
    f Split - (const S: string; ASep: Char): TArray<string>
  Now:                          '<kind> <name><params>: <return>'
    function Split(const S: string; ASep: Char): TArray<string>

  WHY BOTH RENDERINGS ARE MEASURED. The harness prints the NEW row and a
  faithful reproduction of the OLD one, so these assertions prove the change is
  real. A test that only checked the new string would pass against a renderer
  that had always produced it.

  THE CONTROLS:
    * NESTED -- a parameter whose own type carries parentheses. Splitting at the
      FIRST close paren cuts it in half and puts the tail where the return type
      belongs. This is the case a naive Pos(')') implementation fails.
    * BROKEN -- an unbalanced signature must be shown verbatim, not guessed at.
    * BARE   -- no signature: the name alone, with nothing appended.
#>
[CmdletBinding()]
param(
  [string]$FixtureDir = "$PSScriptRoot\fixtures\completiontext",
  [string]$WorkDir    = "$env:TEMP\drag-lint-completiontext-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$pluginDir = "$PSScriptRoot\..\..\src\delphi-plugin"
$outDir    = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" CompletionTextHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
          -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'CompletionTextHarness.dpr builds (Win64 Debug)' $buildOk `
  (($log -split "`r?`n" | Select-Object -Last 6) -join ' | ')

$exe = "$outDir\CompletionTextHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) {
  Write-Host "FATAL: harness exe not found at $exe -- see $logPath" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

$out = & $exe 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) {
  if ($line -match '^\s*([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2].Trim() }
}
Check 'harness ran to completion' ($out -match 'DONE') $(($out -split "`r?`n" | Select-Object -First 3) -join ' | ')

Write-Host ''
Write-Host 'WHAT WAS ASKED FOR' -ForegroundColor Cyan
Check 'FUNC: the kind is a WORD, not a letter' ($kv['FUNC.NEW'] -like 'function *') "got '$($kv['FUNC.NEW'])'"
Check 'FUNC: the OLD row used the letter (guard discriminates)' ($kv['FUNC.OLD'] -like 'f *') "got '$($kv['FUNC.OLD'])'"
Check 'FUNC: parameters stay attached to the name -- Split(...)' ($kv['FUNC.NEW'] -match 'Split\(const S: string; ASep: Char\)') `
  "got '$($kv['FUNC.NEW'])'"
Check 'FUNC: the return type is rendered after a colon' ($kv['FUNC.NEW'] -match ':\s*TArray<string>$') `
  "got '$($kv['FUNC.NEW'])'"
Check 'PROC: a procedure shows parameters and NO return type' `
  (($kv['PROC.NEW'] -match 'SetBounds\(ALeft, ATop, AWidth, AHeight: Integer\)$')) "got '$($kv['PROC.NEW'])'"
Check 'PROP: a property shows its declared type' ($kv['PROP.NEW'] -eq 'property Enabled: Boolean') `
  "got '$($kv['PROP.NEW'])'"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
Check 'CONTROL: a nested parenthesis does not split the parameter list' `
  ($kv['NESTED.NEW'] -match ':\s*Integer$') "got '$($kv['NESTED.NEW'])'"
Check 'CONTROL: the nested parameter list survives whole' `
  ($kv['NESTED.NEW'] -match 'array of \(Byte\)\)') "got '$($kv['NESTED.NEW'])'"
Check 'CONTROL: no signature -> nothing appended' ($kv['BARE.NEW'] -eq 'variable Counter') `
  "got '$($kv['BARE.NEW'])'"
Check 'CONTROL: an unbalanced signature is shown verbatim' ($kv['BROKEN.NEW'] -match '\(const S: string$') `
  "got '$($kv['BROKEN.NEW'])'"

Write-Host ''
Write-Host 'CONSTS: the colon belongs to a type, not to a value' -ForegroundColor Cyan
Check 'CONST: a typed const keeps its colon' `
  ($kv['CONSTTYPED.NEW'] -eq 'const MaxItems: Integer = 100') "got '$($kv['CONSTTYPED.NEW'])'"
Check 'CONST: a const with no inferable type drops the colon' `
  ($kv['CONSTVALUE.NEW'] -eq 'const Derived = MaxItems * 2') "got '$($kv['CONSTVALUE.NEW'])'"
# The discriminator. Without CompletionTypeSeparator this row reads
# 'const Derived: = MaxItems * 2' -- so assert the stray colon is ABSENT, not
# merely that the text looks plausible.
Check 'CONST: no stray colon before an "=" value' `
  ($kv['CONSTVALUE.NEW'] -notmatch ':\s*=') "got '$($kv['CONSTVALUE.NEW'])'"
Check 'CONST: a declared array type keeps its colon' `
  ($kv['CONSTARRAY.NEW'] -eq "const Names: array[0..1] of string = ('a', 'b')") "got '$($kv['CONSTARRAY.NEW'])'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
