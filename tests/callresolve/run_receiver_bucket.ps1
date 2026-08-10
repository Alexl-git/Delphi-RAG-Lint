<#
  run_receiver_bucket.ps1 -- schema v20: the RECEIVER decides who a same-named
  call belongs to.

  THE DEFECT THIS LOCKS. `refs` recorded only a call's LEAF NAME, so
  `TJSONArray.Create` was stored as name_text='Create' with the qualifier thrown
  away at index time. Every project constructor named `Create` then matched every
  unresolved `Create(` site in the corpus, and TQueryRule.Create -- constructed in
  exactly ONE place -- was documented with 77 callers. The information needed to
  tell them apart existed in the source and was discarded before anything could
  use it.

  v20 adds refs.receiver_text, written by the resolve pass (which already computed
  the value via ExtractReceiverExpr and dropped it), and FindUnresolvedNameCallers
  filters on it.

  On fixture receiver_bucket.pas the caller list of TOnlyOnce.Create went
    BEFORE: MakeOne, MakeQualified ?, NoiseA ?, NoiseB ?, NoiseC ?
    AFTER : MakeOne, MakeQualified ?
  and NoiseA/B/C construct TUnknownA/B/C -- nothing to do with TOnlyOnce.

  Note the fixture reproduces the fabrication even though 'Create' is UNIQUE
  there: the bucket's ambiguity gate has a deliberate `Distinct.Count > 0` escape
  ("one caller resolved, so the list is mixed and ' ?' will warn the reader"), and
  the real callers open it. Uniqueness alone was never sufficient.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\receiver_bucket.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_receiver_bucket'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'receiver_bucket.pas'
$db     = Join-Path $scratch 'rcv.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- the column exists and is POPULATED, including '' for a bare call -------
  # Sanity before the behaviour assertions: if receiver_text were NULL the filter
  # would correctly no-op (NULL = "never resolved by a v20 engine") and every
  # assertion below would pass for the WRONG reason.
  $dump = & $exePath query --name Create --db $db --json 2>$null
  Check 'index ran and the fixture is queryable' ($LASTEXITCODE -eq 0)

  $doc = (& $exePath document --unit $target --db $db 2>$null) -join "`n"
  $calledFrom = ($doc -split "`n" | Where-Object { $_ -match 'Called from:' } | Select-Object -First 1)
  Check 'a Called from: line was generated' ($null -ne $calledFrom) $calledFrom

  # --- the real callers SURVIVE ----------------------------------------------
  Check 'REAL: MakeOne is listed' ($calledFrom -match 'receiver_bucket\.MakeOne') $calledFrom
  # MakeQualified writes receiver_bucket.TOnlyOnce.Create -- a FULL DOTTED CHAIN.
  # The filter must match its LAST SEGMENT; comparing the whole receiver string
  # would drop a genuine caller. (The resolver itself does not resolve a dotted
  # receiver -- TypeReceiver bails on any '.' -- so this caller reaches the list
  # only through this bucket, which is exactly why the rule matters.)
  Check 'REAL: MakeQualified survives (fully qualified receiver, last-segment match)' `
    ($calledFrom -match 'receiver_bucket\.MakeQualified') $calledFrom

  # --- the fabricated callers are GONE ---------------------------------------
  # NoiseGeneric constructs TArray<string>. Its receiver ends in '>', which the
  # left-walking extractor used to break on -- returning '', the same value a
  # BARE call yields, so every generic construction slipped back in through the
  # '' arm of the filter.
  foreach ($n in 'NoiseA','NoiseB','NoiseC','NoiseGeneric') {
    Check "FABRICATED: $n is NOT listed" ($calledFrom -notmatch "receiver_bucket\.$n") $calledFrom
  }

  # --- and the list is exactly the two real ones -----------------------------
  # A caller entry is 'receiver_bucket.NAME (file)', so require the following
  # ' (' -- without it the FILE NAME in each entry's parentheses
  # ('receiver_bucket.pas') is scraped as a third "caller".
  $names = @([regex]::Matches($calledFrom, 'receiver_bucket\.(\w+) \(') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  Check 'the caller list is EXACTLY {MakeOne, MakeQualified}' `
    (($names.Count -eq 2) -and ($names -contains 'MakeOne') -and ($names -contains 'MakeQualified')) `
    ("got: " + ($names -join ','))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
