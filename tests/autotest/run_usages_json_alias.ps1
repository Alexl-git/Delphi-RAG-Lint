<#
  run_usages_json_alias.ps1 --
  `usages --json` must produce the SAME JSON document as `usages --format json`.

  THE DEFECT, reported by the converter team 2026-09-16. `--json` is a GLOBAL
  flag: ParseArgs sets AArgs.AsJson for it regardless of verb. `DoUsages` tested
  only AArgs.Format, so `usages --json` printed the HUMAN SUMMARY and exited 0.

  That is worse than an error. An accepted-but-ignored flag reads as a
  deliberate answer, so the caller concluded "usages has no JSON detail, only
  counts" -- which is false -- and moved on to something else. Their words, and
  the reason this guard exists rather than a one-line fix on its own: "we care
  that the CLI not answer a question it was not asked."

  WHY THE ASSERTIONS ARE SHAPED THIS WAY. Checking only that `--json` prints
  something JSON-ish would pass on a build that emitted `{}`, and checking only
  that it differs from the human text would pass on any garbage. So the document
  is compared to the `--format json` document FIELD BY FIELD, and the human
  summary is asserted ABSENT -- the two together are what pin the behaviour.

  Runs against this repo's own self-index, which the battery can rely on, and
  SKIPS cleanly when that index is absent rather than failing for the wrong
  reason.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$DbPath = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite"
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $DbPath)) { Write-Host "SKIP: self-index not present: $DbPath" -ForegroundColor Yellow; exit 0 }
$Exe = (Resolve-Path $Exe).Path
$DbPath = (Resolve-Path $DbPath).Path

# A symbol that exists in the self-index and has BOTH a declaration and calls, so
# an empty-document bug cannot pass by matching an empty document.
$Sym = 'EmitBlock'

function RunUsages([string[]]$ExtraArgs) {
  # STDOUT ONLY. Merging stderr with 2>&1 interleaves the engine's stale-index
  # note INTO the JSON document -- measured: "...index --all --only <Section>)"
  # landed inside the `attributes` array and ConvertFrom-Json failed at line 42.
  # The note is a stderr diagnostic; the document is stdout. Do not merge them.
  $raw = (& $Exe usages --name $Sym --db $DbPath @ExtraArgs 2>$null) -join "`n"
  $ex  = $LASTEXITCODE
  # convert-apply-style: the document is the first line that opens an object, so
  # a trailing "(loaded defaults from ...)" note cannot break the parse.
  $start = $raw.IndexOf('{')
  $json  = $null
  if ($start -ge 0) {
    $body = $raw.Substring($start)
    $end  = $body.LastIndexOf('}')
    if ($end -ge 0) { try { $json = ($body.Substring(0, $end + 1) | ConvertFrom-Json) } catch { $json = $null } }
  }
  return @{ Raw = $raw; Exit = $ex; J = $json }
}

$fmt  = RunUsages @('--format','json')
$alias= RunUsages @('--json')

# ---- P1 POSITIVE CONTROL -----------------------------------------------------
# Everything below compares the alias to --format json. If --format json is
# itself broken or empty, every comparison would pass vacuously.
Check 'P1 POSITIVE CONTROL --format json returns a populated document' `
      (($fmt.Exit -eq 0) -and ($null -ne $fmt.J) -and ($fmt.J.name -eq $Sym) -and `
       (@($fmt.J.declarations).Count -ge 1) -and (@($fmt.J.calls).Count -ge 1)) `
      ("the reference document is not usable, so nothing below proves anything:`n" + $fmt.Raw)

# ---- T1 the alias produces a document at all --------------------------------
Check 'T1 usages --json emits a JSON document' `
      (($alias.Exit -eq 0) -and ($null -ne $alias.J)) `
      ("exit=$($alias.Exit)`n" + $alias.Raw)

# ---- T2 it is the SAME document, field by field -----------------------------
# Not "some JSON" -- the same answer. A build that emitted {} would pass T1.
foreach ($f in @('name','width')) {
  Check "T2 usages --json matches --format json on '$f'" `
        (($null -ne $alias.J) -and ($alias.J.$f -eq $fmt.J.$f)) `
        ("alias='$($alias.J.$f)' format='$($fmt.J.$f)'")
}
foreach ($f in @('declarations','reads','writes','calls','types','attributes','events','impact')) {
  $a = if ($null -ne $alias.J) { @($alias.J.$f).Count } else { -1 }
  $b = @($fmt.J.$f).Count
  Check "T2 usages --json matches --format json on '$f' count" ($a -eq $b) "alias=$a format=$b"
}

# ---- T3 DISCRIMINATION the human summary is GONE ----------------------------
# This is the assertion that would have caught the defect: the old build printed
# exactly this line and exited 0.
Check 'T3 DISCRIMINATION the human summary is NOT printed under --json' `
      (-not ($alias.Raw -match 'usages of "' + [regex]::Escape($Sym) + '" \(width=')) `
      ("the flag was accepted and ignored -- the caller reads this as a real answer:`n" + $alias.Raw)

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
