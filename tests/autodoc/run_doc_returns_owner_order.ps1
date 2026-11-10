<#
  run_doc_returns_owner_order.ps1 -- 150 X2: `Owns returned:` must not depend
  on the order in which `index` met the units.

  THE DEFECT (found as TL's LSP.Server "duplicate insert" residual)
  -----------------------------------------------------------------
  symbol_facts.returns_owner is computed per file, inside that file's index
  transaction (Core.Indexer facts pass -> Doc.SymbolFacts.AnalyzeReturnsOwner).
  Its object-type gate, IsReferenceTypeName, asks the STORE what the return type
  is. On a fresh `index` the unit declaring that type may not be stored yet, so
  the gate falls back to the T/I naming convention and a RECORD return type is
  stored as 'borrowed'. A later incremental reindex of the same, unchanged unit
  finds the record and stores ''. `document` renders the stored word, so a
  block written from a full index carries `Owns returned: borrowed`, and after
  any incremental reindex doc-drift flags it and `document` proposes to rewrite
  it -- the residual TL saw on TLSPServer.Defaults (TContextDefaults is a
  record). It was never a duplicate insert: the dry run is `delete 495..508`
  plus `insert after 494`, a replace.

  THE FIX (Doc.Facts, read side; Doc.SymbolFacts is extractor-hashed)
  -------------------------------------------------------------------
  TDocFactsBuilder.Build re-applies the gate's ground-truth NEGATIVE against
  the store as it is NOW: a stored 'borrowed'/'self' whose return type resolves
  to a record or enum is dropped. Suppression only.

  WHAT THIS RUNNER PINS (fixtures\returns_owner_order: A_Owner sorts before
  Z_Types, so A_Owner's facts pass runs before TZValue / TZThing are stored)
    1. after a fresh index + `document --apply`, TOwner.Value (returns the
       record TZValue) carries NO `Owns returned:` line            [RED before]
    2. POSITIVE CONTROL: TOwner.Thing (returns the class TZThing) still
       carries `Owns returned: borrowed` -- a fix that drops the fact for
       everything fails here
    3. after an incremental reindex of the touched unit: doc-drift 0 on it
       and `document` proposes no edit                             [RED before]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fixture = Join-Path $PSScriptRoot 'fixtures\returns_owner_order'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("dl-ro-order-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
Copy-Item (Join-Path $fixture '*.pas') $scratch -Force
$db    = Join-Path $scratch 'q.sqlite'
$owner = Join-Path $scratch 'A_Owner.pas'

$fails = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { Write-Host "[PASS] $name" } else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fails++ }
}
# The /// lines directly above the FIRST line matching $declRx.
function BlockAbove([string]$path, [string]$declRx) {
  $lines = [IO.File]::ReadAllLines($path)
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match $declRx) {
      $out = @(); $k = $i - 1
      while ($k -ge 0 -and $lines[$k].TrimStart().StartsWith('///')) { $out = @($lines[$k]) + $out; $k-- }
      return ,$out
    }
  }
  return ,@()
}

& $exePath index $scratch --db $db 2>$null | Out-Null
Check 'fresh index exits 0' ($LASTEXITCODE -eq 0)
$stored = (& $exePath sql --query "select f.returns_owner from symbols s join symbol_facts f on f.symbol_id=s.id where s.qualified_name='A_Owner.TOwner.Value'" --db $db 2>$null) -join ' '
Write-Host "  (info) stored returns_owner of TOwner.Value after the fresh index: $stored"

& $exePath document --unit $owner --db $db --apply --no-backup 2>$null | Out-Null
Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)

$valBlock   = BlockAbove $owner '^\s*function\s+Value\s*:'
$thingBlock = BlockAbove $owner '^\s*function\s+Thing\s*:'
Check 'Value has a doc block at all (the apply ran)' ($valBlock.Count -gt 0)
Check 'Value (record return) carries NO Owns returned line' (-not (($valBlock -join "`n") -match 'Owns returned'))
Check 'POSITIVE CONTROL: Thing (class return) carries Owns returned: borrowed' (($thingBlock -join "`n") -match 'Owns returned: borrowed')

# Touch the unit without moving a line, so the incremental pass re-parses it.
[IO.File]::AppendAllText($owner, "`r`n", [Text.Encoding]::ASCII)
& $exePath index $scratch --db $db 2>$null | Out-Null
Check 'incremental reindex exits 0' ($LASTEXITCODE -eq 0)

$raw = (& $exePath lint $owner --db $db --rule doc-drift --project-rules --json 2>$null) -join "`n"
$arr = @()
if ($raw.IndexOf('[') -ge 0) { $arr = @($raw.Substring($raw.IndexOf('[')) | ConvertFrom-Json) }
Check "doc-drift after incremental reindex is 0 (got $($arr.Count))" ($arr.Count -eq 0)

$dry = (& $exePath document --unit $owner --db $db 2>&1) -join "`n"
Check 'document after incremental reindex proposes no edit' (-not ($dry -match '(?m)^\s*(insert|delete)\b'))

try { [IO.Directory]::Delete($scratch, $true) } catch { }
if ($fails -gt 0) { Write-Host "FAIL ($fails)"; exit 1 }
Write-Host 'PASS'
exit 0
