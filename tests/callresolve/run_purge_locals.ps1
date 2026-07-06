<#
  run_purge_locals.ps1 -- TDD harness for D5 Task 12: the `purge-locals` verb.

  purge-locals is a SIZE ESCAPE HATCH: once ResolveCallTargets (Task 6) has
  populated call_edges, the numerous skLocalVar/skParam symbols (one per local /
  param in the whole codebase -- Tasks 2-3) have done their job (they let the
  resolver type call-site receivers). Deleting them reclaims index space. The
  CRITICAL guarantee is that the resolved CALL GRAPH is byte-for-byte identical
  before and after the purge -- call_edges references call TARGETS (methods) and
  receiver TYPES (classes), NEVER a local/param, so no FK cascade can drop an
  edge.

  Fixture receivers.pas has an skParam AAlpha (TCaller.ViaParam) + an skLocalVar
  B (TCaller.ViaLocal) + 5 resolvable call edges. We:
    1. index the fixture,
    2. BEFORE purge, capture: AAlpha=param + B=local_var present; the full
       dump-call-edges text; the resolved find-callers/find-callees results,
    3. run purge-locals --db,
    4. AFTER purge assert: AAlpha/B GONE; dump-call-edges byte-IDENTICAL (THE
       critical assertion); resolved find-callers/find-callees IDENTICAL; a
       nonzero rows-removed count + a smaller-or-equal DB size,
    5. run purge-locals AGAIN -> 0 rows removed, still exit 0 (idempotent).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\receivers.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_purgelocals'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'receivers.pas'
$db      = Join-Path $scratch 'receivers.sqlite'
Copy-Item $fixture $target -Force

# Count symbols of kind $k named $name in a `query --name` JSON result.
function KindCount([string]$name, [string]$k) {
  $j = & $exePath query --name $name --json --db $db 2>$null | Out-String
  if ([string]::IsNullOrWhiteSpace($j)) { return 0 }
  $rows = $j | ConvertFrom-Json
  return @($rows | Where-Object { $_.kind -eq $k }).Count
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- BEFORE purge: locals/params present, call graph captured. ---
  Check 'BEFORE: AAlpha present as skParam'    ((KindCount 'AAlpha' 'param')     -eq 1)
  Check 'BEFORE: B present as skLocalVar'      ((KindCount 'B'      'local_var') -eq 1)

  $edgesBefore    = (& $exePath dump-call-edges --db $db 2>$null | Out-String).Trim()
  $callersBefore  = (& $exePath query find-callers --name Run --resolved --json --db $db 2>$null | Out-String).Trim()
  $calleesBefore  = (& $exePath find-callees --qname receivers.TCaller.ViaLocal --json --db $db 2>$null | Out-String).Trim()
  $edgeCountBefore = @($edgesBefore -split "`r?`n" | Where-Object { $_ -match '^\d+\|[A-Za-z_][\w.]*\|(certain|ambiguous)$' }).Count
  Check 'BEFORE: call_edges populated (>= 5)'  ($edgeCountBefore -ge 5)

  $sizeBefore = (Get-Item $db).Length

  # --- Run purge-locals. ---
  $purgeTxt = & $exePath purge-locals --db $db 2>$null | Out-String
  Check 'purge-locals exit 0'                  ($LASTEXITCODE -eq 0)
  # It must report a nonzero rows-removed count (receivers.pas has 1 param + 1 local).
  # D5 fast-follow (T12/T13): this probe PARSES the verb's plain-text success
  # message to recover the count -- inherently fragile if the wording changes.
  # Loosened to match the essential tokens only (a removed/purged VERB followed
  # by a NUMBER, in either order) rather than the whole sentence, so a minor
  # wording tweak (e.g. "removed" -> "purged", or reordering "N symbol(s)
  # removed") doesn't break this test. If the CLI ever stops reporting a count
  # in plain text at all, prefer asserting via `--json` (already covered below)
  # over patching this regex further.
  $removed = 0
  if ($purgeTxt -match '(?:removed|purged)\D*(\d+)') { $removed = [int]$Matches[1] }
  elseif ($purgeTxt -match '(\d+)\D*(?:removed|purged)') { $removed = [int]$Matches[1] }
  Check 'purge reported >= 2 rows removed'     ($removed -ge 2)

  # --- AFTER purge: locals/params gone, call graph IDENTICAL. ---
  Check 'AFTER: AAlpha (param) gone'           ((KindCount 'AAlpha' 'param')     -eq 0)
  Check 'AFTER: B (local_var) gone'            ((KindCount 'B'      'local_var') -eq 0)

  $edgesAfter   = (& $exePath dump-call-edges --db $db 2>$null | Out-String).Trim()
  $callersAfter = (& $exePath query find-callers --name Run --resolved --json --db $db 2>$null | Out-String).Trim()
  $calleesAfter = (& $exePath find-callees --qname receivers.TCaller.ViaLocal --json --db $db 2>$null | Out-String).Trim()

  # THE critical assertion: the resolved call graph is byte-identical.
  Check 'CRITICAL: dump-call-edges IDENTICAL before==after' ($edgesBefore -eq $edgesAfter)
  Check 'find-callers --resolved IDENTICAL before==after'   ($callersBefore -eq $callersAfter)
  Check 'find-callees IDENTICAL before==after'              ($calleesBefore -eq $calleesAfter)

  $sizeAfter = (Get-Item $db).Length
  Check 'DB size not larger after purge+VACUUM' ($sizeAfter -le $sizeBefore)

  # --- Idempotent second run: nothing left to delete. ---
  $purge2Txt = & $exePath purge-locals --db $db 2>$null | Out-String
  Check 'second purge exit 0 (idempotent)'     ($LASTEXITCODE -eq 0)
  $removed2 = -1
  if ($purge2Txt -match '(?:removed|purged)\D*(\d+)') { $removed2 = [int]$Matches[1] }
  elseif ($purge2Txt -match '(\d+)\D*(?:removed|purged)') { $removed2 = [int]$Matches[1] }
  Check 'second purge removed 0 rows'          ($removed2 -eq 0)

  # --json shape: rows removed + before/after size fields. Use a SEPARATE fresh
  # DB (not $db, which was already purged): the incremental indexer skips a
  # re-parse when the file sha is unchanged, so re-indexing into $db would NOT
  # re-emit the purged locals. A fresh DB force-parses them so --json has real
  # rows to remove.
  $jdb = Join-Path $scratch 'json_probe.sqlite'
  if (Test-Path $jdb) { Remove-Item $jdb -Force }
  & $exePath index $scratch --db $jdb 2>$null | Out-Null
  $jsonOut = & $exePath purge-locals --db $jdb --json 2>$null | Out-String
  Check '--json: parses as an object'          ($jsonOut.Trim().StartsWith('{'))
  $jo = $jsonOut | ConvertFrom-Json
  Check '--json: removed >= 2'                 ([int]$jo.removed -ge 2)
  Check '--json: has size_before/size_after'   (($null -ne $jo.size_before) -and ($null -ne $jo.size_after))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
