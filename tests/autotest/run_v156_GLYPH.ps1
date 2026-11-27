#Requires -Version 7.3
<#
  run_v156_GLYPH.ps1 -- 1.56 GLYPH: `--glyph-stitch` promoted from a hidden switch to a documented one.

  1.54/1.55 shipped the stitch behind a switch the engine never advertised (docs\wiki\convert-apply.md:
  "info --json does not advertise glyph_stitch yet ... until the owner promotes the switch"). Promotion =
    * `info --json` capabilities.glyph_stitch = true  (the editor un-greys G-link books on it)
    * --help describes the flag on BOTH verbs, not only lists it in the usage line
    * README.md and docs\AI-USAGE.md say the same
    * a registry entry (features\entries\convert-glyph-stitch.json) + its wiki page exist
  The stitch code (src\report\DRagLint.Convert.*) is untouched: the existing runner
  run_convert_glyph_strip.ps1 is re-run here as the "behaviour unchanged" control.

    G1 info capability glyph_stitch is true
    G2 convert-apply --help describes --glyph-stitch   G3 convert-validate --help describes it
    G4 README.md   G5 docs\AI-USAGE.md   G6 registry entry   G7 wiki page
    G8 POSITIVE CONTROL: the description matcher REJECTS a usage-line-only text (the pre-1.56 help)
    G9 behaviour control: run_convert_glyph_strip.ps1 is green on this exe (bar its I1, which asserts the old OFF state)
  Run: pwsh -File tests\autotest\run_v156_GLYPH.ps1 [-Exe <drag-lint.exe>] [-SkipBehaviour]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipBehaviour)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:fail = 0
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail++ }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path

# The sentence every help / doc surface must carry: the flag NAME followed by its OFF-by-default meaning.
function HasDescription([string]$Text) { return ($Text -match '--glyph-stitch\s*\(OFF by default[^)]*G\[I/N\]') }
# A verb's own help block: from its "drag-lint <verb> " line to the next "drag-lint " line.
function VerbBlock([string]$Help, [string]$Verb) {
  $m = [regex]::Match($Help, '(?ms)^\s*drag-lint ' + [regex]::Escape($Verb) + ' .*?(?=^\s*drag-lint \S|\z)')
  return $m.Value
}

$ij = (& $Exe info --json 2>$null) -join "`n" | ConvertFrom-Json
Check 'G1 info capability glyph_stitch is true' ($ij.capabilities.glyph_stitch -eq $true) "capabilities.glyph_stitch = [$($ij.capabilities.glyph_stitch)]"

$help = (& $Exe --help 2>&1 | ForEach-Object { "$_" }) -join "`n"
Check 'G2 --help: convert-apply describes --glyph-stitch' (HasDescription (VerbBlock $help 'convert-apply'))
Check 'G3 --help: convert-validate describes --glyph-stitch' (HasDescription (VerbBlock $help 'convert-validate'))

$readme = [IO.File]::ReadAllText("$Repo\README.md")
$aiuse  = [IO.File]::ReadAllText("$Repo\docs\AI-USAGE.md")
Check 'G4 README.md describes the flag' ($readme -match '--glyph-stitch` \(OFF by default')
Check 'G5 AI-USAGE.md describes the flag' ($aiuse -match '--glyph-stitch` \(OFF by default')

$entryPath = "$Repo\features\entries\convert-glyph-stitch.json"
$entry = if (Test-Path -LiteralPath $entryPath) { Get-Content -Raw -LiteralPath $entryPath | ConvertFrom-Json } else { $null }
Check 'G6 registry entry convert-glyph-stitch: exists, a workflow surface, a question names the flag' `r
  ($entry -and $entry.id -eq 'convert-glyph-stitch' -and (@($entry.surfaces | Where-Object { $_.type -eq 'workflow' }).Count -eq 1) -and (@($entry.questions | Where-Object { $_.command -match '--glyph-stitch' }).Count -ge 1))
Check 'G7 wiki page named by the entry exists' ($entry -and (Test-Path -LiteralPath "$Repo\docs\wiki\$($entry.wikiPage).md") -and (Test-Path -LiteralPath "$Repo\$($entry.surfaces[0].doc)"))

$usageOnly = '  drag-lint convert-apply --unit <F.pas> --rules <file> [--glyph-stitch] [--apply]   (rewrites the five surfaces)'
Check 'G8 positive control: matcher rejects the usage-line-only help (the 1.55 shape)' (-not (HasDescription $usageOnly))

if (-not $SkipBehaviour) {
  # run_convert_glyph_strip.ps1 I1 asserts "info does NOT advertise glyph_stitch" -- the very thing this lane
  # flips (request GLYPH -> CONVERTER). That ONE assertion is expected to fail; any other [FAIL] is a regression.
  $out = & pwsh -NoProfile -File "$PSScriptRoot\run_convert_glyph_strip.ps1" -Exe $Exe 2>&1 | ForEach-Object { "$_" }
  $bad = @($out | Where-Object { $_ -match '^\[FAIL\]' -and $_ -notmatch '^\[FAIL\] I1 ' })
  $passN = @($out | Where-Object { $_ -match '^\[PASS\]' }).Count
  Check 'G9 behaviour control: run_convert_glyph_strip.ps1 has no [FAIL] except the superseded I1' (($bad.Count -eq 0) -and ($passN -ge 20)) "failing: $($bad -join ' | '); passes=$passN"
}Write-Host ("v156 GLYPH: {0}" -f (@('GREEN', "RED ($script:fail failing)")[[int]($script:fail -gt 0)]))
exit ([int]($script:fail -gt 0))
