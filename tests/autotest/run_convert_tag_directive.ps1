<#
  run_convert_tag_directive.ps1 -- `#tag <Ident>` is TOLERATED by
  convert-validate, and tolerating it invents no rule.

  WHY THIS EXISTS. The conversion-rule corpus wants to label a #convert block so
  a transfer job can later select rules by tag. Before this change,
  ParseConversionRules had no #tag arm, so the line fell through to the
  unknown-directive catch-all and `convert-validate` FAILED:

      line 2: unknown directive: #tag          (exit 1)

  That is a hard block: a corpus cannot carry tags at all while the validator
  rejects them, and the owner's ruling was explicit -- "until the engine
  understands #tag we won't use them". The strip-on-the-way-out workaround was
  proposed and TURNED DOWN, so tolerating it in the engine is the whole fix.

  WHAT SHIPPED IS TOLERATE-ONLY, ON PURPOSE. The tag is not captured into the
  rule model, so it cannot yet be typo-checked or selected on. That was the
  filed ask; carrying tags in the model is a separate one that was explicitly
  left optional and is NOT done here. This guard therefore asserts the boundary
  in BOTH directions: the directive is accepted, and the parsed rule COUNT does
  not move.

  SCOPE. A tag labels the enclosing #convert block, so a #tag before the first
  #convert has nothing to label and is an ERROR rather than a silent no-op.

  THE POSITIVE CONTROL IS THE POINT. An arm that swallowed EVERY unknown
  directive would satisfy "no more unknown directive: #tag" perfectly, and would
  be a far worse defect than the one being fixed -- every typo'd directive in
  every rules file would go silent. So #frobnicate must STILL error.

  Note the two scope checks assert the SPECIFIC message text, not merely "an
  error occurred". Against the pre-fix engine those files DO error -- with
  'unknown directive: #tag' -- so a check that only counted errors would PASS on
  the broken engine and could never have gone red.

  MEASURED RED, THEN GREEN.

  RED -- 2026-09-09, against the pre-fix engine copy
  (C:\TEMP\draglint-prefix-engine-2026-09-09, 1.10.1-alpha, built 01:24:06),
  2 PASS / 5 FAIL, verbatim:

    [FAIL] #tag inside a #convert block validates OK exit=1
    [FAIL]   ...and no unknown-directive error is reported for it
    [PASS] TOLERATE INVENTS NO RULE: tagged=2 untagged=2
    [PASS] an unknown directive STILL errors exit=1
    [FAIL] a #tag BEFORE any #convert is an error, not a silent no-op exit=1
    [FAIL]   ...and it is NOT reported as an unknown directive
    [FAIL] a bare #tag with no name is an error exit=1

  Note which two PASSED there, because it is the useful part: the positive
  control (an unknown directive still errors) and the rule-count invariant both
  hold on the BROKEN engine. They are not measuring the fix -- they are fencing
  the two ways the fix could go wrong.

  GREEN -- 2026-09-09, SAME runner, against the engine deployed to
  third_party\dll-win64 (1.10.1-alpha, built 10:54:29): 7 PASS / 0 FAIL.
  #tag now validates OK (exit 0), the count invariant still holds at 2 = 2, and
  #frobnicate still errors -- so the arm tolerates #tag specifically rather than
  swallowing unknown directives generally.

  Run from a NEUTRAL CWD, pwsh 7.
    pwsh -File tests\autotest\run_convert_tag_directive.ps1
    pwsh -File tests\autotest\run_convert_tag_directive.ps1 -Exe <pre-fix engine>
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'

# convert-validate EXITS 1 when a rules file has errors -- which is the expected
# outcome for three of the fixtures below. pwsh 7.4+ can promote a native
# non-zero exit to a terminating error; pin it off so an exit code is a value to
# assert on, not something that kills the runner.
$PSNativeCommandUseErrorActionPreference = $false

$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("cvtag_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$infoRaw = (& $exePath info --json 2>$null) -join "`n"
$engineVersion = '(unknown)'
try {
  $line = ($infoRaw -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -First 1)
  if ($line) { $j = $line | ConvertFrom-Json; $engineVersion = "$($j.version) / extractor $($j.extractor_version) / built $($j.build_date)" }
} catch { }
Write-Host ''
Write-Host ("engine : {0}" -f $exePath) -ForegroundColor Cyan
Write-Host ("         {0}" -f $engineVersion) -ForegroundColor Cyan

function Write-Rules([string]$Name, [string[]]$Lines) {
  $p = Join-Path $WorkDir $Name
  [IO.File]::WriteAllText($p, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  return $p
}

# Runs convert-validate and returns exit code, combined output, and the parsed
# rule count from the `parsed N rule(s)` line (-1 when it is not printed).
function Validate([string]$Path) {
  $out  = & $exePath convert-validate --rules $Path --print-parsed 2>&1
  $code = $LASTEXITCODE
  $text = ($out | Out-String)
  $n = -1
  $m = [regex]::Match($text, 'parsed\s+(\d+)\s+rule\(s\)')
  if ($m.Success) { $n = [int]$m.Groups[1].Value }
  return [pscustomobject]@{ Exit = $code; Text = $text; Rules = $n }
}

$CONVERT = '#convert Bde.DBTables.TQuery -> FireDAC.Comp.Client.TFDQuery, FireDAC.Comp.Client'
$LINK    = '#link SQL <- SQL'

$fTagged   = Write-Rules 'tagged.rules'   @($CONVERT, '#tag BDEtoFireDAC', $LINK)
$fUntagged = Write-Rules 'untagged.rules' @($CONVERT, $LINK)
$fFrob     = Write-Rules 'frob.rules'     @($CONVERT, '#frobnicate BDEtoFireDAC', $LINK)
$fOrphan   = Write-Rules 'orphan.rules'   @('#tag BDEtoFireDAC', $CONVERT, $LINK)
$fBare     = Write-Rules 'bare.rules'     @($CONVERT, '#tag', $LINK)

# --- 1-2. The fix ------------------------------------------------------------

Write-Host ''
Write-Host 'THE FIX -- #tag is accepted inside a #convert block' -ForegroundColor Cyan
$tagged = Validate $fTagged
Check '#tag inside a #convert block validates OK' ($tagged.Exit -eq 0) `
  "exit=$($tagged.Exit) -- pre-fix this is 1 with 'unknown directive: #tag'"
Check '  ...and no unknown-directive error is reported for it' `
  (-not ($tagged.Text -match 'unknown directive: #tag')) ''

$untagged = Validate $fUntagged
Check 'TOLERATE INVENTS NO RULE: tagged and untagged parse to the same count' `
  ($tagged.Rules -ge 1 -and $tagged.Rules -eq $untagged.Rules) `
  "tagged=$($tagged.Rules) untagged=$($untagged.Rules) -- if #tag added a rule, every consumer's rule count would shift"

# --- 3. POSITIVE CONTROL -----------------------------------------------------

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the catch-all still catches' -ForegroundColor Cyan
$frob = Validate $fFrob
Check 'an unknown directive STILL errors' `
  ($frob.Exit -ne 0 -and ($frob.Text -match 'unknown directive: #frobnicate')) `
  "exit=$($frob.Exit) -- without this, an arm that swallowed EVERY unknown directive would pass the checks above"

# --- 4-5. Scope and argument -------------------------------------------------
# These assert the SPECIFIC message. The pre-fix engine errors on these files too
# (with 'unknown directive: #tag'), so an error-count check would pass on the
# broken engine and this guard could never have gone red.

Write-Host ''
Write-Host 'SCOPE -- a tag labels the enclosing #convert block' -ForegroundColor Cyan
$orphan = Validate $fOrphan
Check 'a #tag BEFORE any #convert is an error, not a silent no-op' `
  ($orphan.Exit -ne 0 -and ($orphan.Text -match '#tag before any #convert')) `
  "exit=$($orphan.Exit) -- a silently-ignored tag is what a tagged corpus cannot afford"
Check '  ...and it is NOT reported as an unknown directive' `
  (-not ($orphan.Text -match 'unknown directive: #tag')) `
  'the pre-fix engine reports exactly that here, which is why the check above names the message'

$bare = Validate $fBare
Check 'a bare #tag with no name is an error' `
  ($bare.Exit -ne 0 -and ($bare.Text -match '#tag requires a tag name')) `
  "exit=$($bare.Exit)"

try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
