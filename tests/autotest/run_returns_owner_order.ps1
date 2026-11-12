<#
  run_returns_owner_order.ps1 -- 151 X2R: symbol_facts.returns_owner (and so
  `Owns returned:` / doc-drift) must not depend on the order in which `index`
  met the units.

  THE DEFECT (150 X2 FOUND-150, "X2-r")
  -------------------------------------
  returns_owner is computed per file inside that file's index transaction
  (Doc.SymbolFacts.AnalyzeReturnsOwner -> IsReferenceTypeName). Tier 1 asked the
  WHOLE store whether the return type is a class; on a fresh index the unit that
  declares it may not be stored yet, so tier 2 (the T/I naming convention)
  decided. A class whose name does not start with T/I (Widget) therefore stored
  '' on a full index and 'borrowed' after an incremental reindex of the caller:
  doc-drift then flagged every block written from the full index.

  THE FIX: tier 1 only trusts a declaration in the routine's OWN file (already
  stored before the facts pass in every order); everything else goes to the
  store-free tier 2. The stored word is the same in both orders.

  WHAT THIS RUNNER PINS (fixtures\returns_owner_class_order: A_User sorts
  before Z_Kinds)
    1. stored returns_owner of GetWidget / GetThing / GetLocal identical after
       the fresh index and after an incremental reindex of A_User  [RED before]
    2. after `document --apply` on the fresh index + incremental reindex:
       doc-drift 0 on A_User and `document` proposes no edit       [RED before]
    3. POSITIVE CONTROL: GetThing (T-prefixed class from the later unit) is
       'borrowed' in both states -- fails if the gate drops everything
    4. POSITIVE CONTROL: GetLocal (non-T/I class declared in the SAME unit) is
       'borrowed' in both states -- fails if tier 1 is dropped wholesale

  152b DF / O7 (full precision for cross-file non-T/I classes, both halves):
  the index half stores the verdict unless the return type is a definite value
  type (own-file record/enum, or the built-in value list); Doc.Facts gates it
  at READ time with IsReferenceTypeName over the complete store (any file).
    5. GetWidget (non-T/I class from the LATER unit) shows `Owns returned:
       borrowed` in the block written from the FRESH index     [RED before]
    6. CONTROL: GetHandle / GetFlags (HWND / DWORD aliases from the later
       unit) show NO `Owns returned:` -- fails if only the index half lands
    7. the same block scan after the incremental reindex + re-document
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fixture = Join-Path $PSScriptRoot 'fixtures\returns_owner_class_order'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("dl-ro-class-order-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
Copy-Item (Join-Path $fixture '*.pas') $scratch -Force
$db   = Join-Path $scratch 'q.sqlite'
$user = Join-Path $scratch 'A_User.pas'

$fails = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { Write-Host "[PASS] $name" } else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fails++ }
}
# returns_owner per method, as 'GetLocal=borrowed;GetThing=borrowed;GetWidget=' (sorted).
function StoredFacts() {
  $raw = (& $exePath sql --query "select s.name, coalesce(f.returns_owner,'') from symbols s join symbol_facts f on f.symbol_id=s.id where s.qualified_name like 'A_User.TUser.Get%' order by s.name" --db $db --json 2>$null) -join "`n"
  $obj = $raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json
  $parts = @()
  foreach ($r in $obj.rows) { $parts += ('{0}={1}' -f $r[0], $r[1]) }
  return ($parts -join ';')
}

& $exePath index $scratch --db $db 2>$null | Out-Null
Check 'fresh index exits 0' ($LASTEXITCODE -eq 0)
$full = StoredFacts
Write-Host "  (info) after fresh index : $full"
Check 'all five methods have a facts row' (($full -split ';').Count -eq 5)

& $exePath document --unit $user --db $db --apply --no-backup 2>$null | Out-Null
Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)

# 152b O7: is `Owns returned:` in the /// block right above the interface
# declaration of $method (the block document --apply wrote)?
function OwnsShown([string]$method) {
  $lines = [IO.File]::ReadAllLines($user)
  $at = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ('^\s*function\s+' + $method + '\s*:')) { $at = $i; break }
  }
  if ($at -lt 0) { throw "declaration of $method not found in $user" }
  for ($j = $at - 1; ($j -ge 0) -and ($lines[$j] -match '^\s*///'); $j--) {
    if ($lines[$j] -match 'Owns returned:') { return $true }
  }
  return $false
}
function CheckShown([string]$state) {
  Check "O7: GetWidget (non-T/I class, later unit) shows Owns returned ($state)" (OwnsShown 'GetWidget')
  Check "O7 CONTROL: GetHandle (HWND alias, later unit) shows none ($state)" (-not (OwnsShown 'GetHandle'))
  Check "O7 CONTROL: GetFlags (DWORD alias, later unit) shows none ($state)" (-not (OwnsShown 'GetFlags'))
  Check "O7 CONTROL: GetThing and GetLocal still show Owns returned ($state)" ((OwnsShown 'GetThing') -and (OwnsShown 'GetLocal'))
}
CheckShown 'fresh index'

# Touch the unit without moving a line, so the incremental pass re-parses it.
[IO.File]::AppendAllText($user, "`r`n", [Text.Encoding]::ASCII)
& $exePath index $scratch --db $db 2>$null | Out-Null
Check 'incremental reindex exits 0' ($LASTEXITCODE -eq 0)
$incr = StoredFacts
Write-Host "  (info) after incremental : $incr"

Check 'stored returns_owner identical in both orders' ($full -eq $incr)
Check 'POSITIVE CONTROL: GetThing (T class, later unit) borrowed in both' (($full -match 'GetThing=borrowed') -and ($incr -match 'GetThing=borrowed'))
Check 'POSITIVE CONTROL: GetLocal (non-T/I class, same unit) borrowed in both' (($full -match 'GetLocal=borrowed') -and ($incr -match 'GetLocal=borrowed'))

$raw = (& $exePath lint $user --db $db --rule doc-drift --project-rules --json 2>$null) -join "`n"
$arr = @()
if ($raw.IndexOf('[') -ge 0) { $arr = @($raw.Substring($raw.IndexOf('[')) | ConvertFrom-Json) }
Check "doc-drift after incremental reindex is 0 (got $($arr.Count))" ($arr.Count -eq 0)

$dry = (& $exePath document --unit $user --db $db 2>&1) -join "`n"
Check 'document after incremental reindex proposes no edit' (-not ($dry -match '(?m)^\s*(insert|delete)\b'))
& $exePath document --unit $user --db $db --apply --no-backup 2>$null | Out-Null
CheckShown 'incremental reindex'

try { [IO.Directory]::Delete($scratch, $true) } catch { }
if ($fails -gt 0) { Write-Host "FAIL ($fails)"; exit 1 }
Write-Host 'PASS'
exit 0