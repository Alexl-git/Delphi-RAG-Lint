<#
  run_doc_p2_owner.ps1 -- Auto-Document Phase 2, Task 8: Returned-object
  ownership fact (conservative escape analysis -- does a function return a
  freshly-constructed object the caller must free ('new'), a borrowed
  reference ('borrowed'), or Self ('self')).

  Uses fixtures\docp2\owner.pas: TFoo with seven methods -- see that file's
  own header comment for the full per-method rationale. Summary:
    * MakeIt         -- Result := TFoo.Create (paren-less ctor call) -- the
                        ONE unanimous 'new' site. Expected: 'Owns returned:
                        new (caller owns)'.
    * GetIt          -- Result := FFoo (an own-class field of type TFoo) --
                        the ONE unanimous 'borrowed' site, object-type gate
                        passes. Expected: 'Owns returned: borrowed'.
    * Me             -- Result := Self as TFoo -- the ONE unanimous 'self'
                        site, object-type gate passes. Expected: 'Owns
                        returned: self'.
    * Amb            -- 'new' (TFoo.Create) + 'borrowed' (FFoo) on the
                        if/else branches -- NOT unanimous. Expected: NO
                        'Owns returned:' line (still has a managed block via
                        the unrelated Reads: FFoo fact).
    * Count          -- Result := FCount (a field -> 'borrowed'), but the
                        function returns Integer (not a reference type) --
                        the object-type gate rejects it. Expected: NO 'Owns
                        returned:' line (still has a managed block via the
                        unrelated Reads: FCount fact).
    * MakeViaExit    -- Exit(TFoo.Create) -- the value-form Exit(...) site
                        kind. Expected: 'Owns returned: new (caller owns)'.
    * DisposedResult -- Result := TFoo.Create followed by Result.Free -- the
                        disposal check must suppress the fact even though
                        the lone site alone reads as a clean 'new'. Expected:
                        NO 'Owns returned:' line (still has a managed block
                        via the unrelated Reads/Writes: FCount fact).

  FIX WAVE (Phase 2 T8 review) -- two adversarial regressions, locking in the
  reviewer-identified fixes:
    * Borrow (TUser.Borrow) -- Result := APool.Create, where APool: TWidgetPool
                        is a PARAMETER (an existing instance), and
                        TWidgetPool.Create is a PLAIN method (not a real
                        constructor) that just returns a shared field.
                        WITHOUT Fix 1's receiver gate, ExprIsConstructor
                        matches on the member name 'create' alone and this
                        reads back as a false 'new'. Expected: NO 'Owns
                        returned:' line (still has a managed block via the
                        unrelated Writes: FLastPool fact).
    * GetRec (TRecHolder.GetRec) -- Result := FRec, FRec an own-class field
                        of type TMyRec, a RECORD (value type). The site
                        classifies 'borrowed' (FRec is a real field), but
                        WITHOUT Fix 2's skRecord rejection, IsReferenceTypeName's
                        T/I-prefix fallback heuristic wrongly accepts 'TMyRec'
                        (starts with 'T') as a reference type. Expected: NO
                        'Owns returned:' line (still has a managed block via
                        the unrelated Reads: FRec fact, from the SAME
                        statement).

  FINAL REVIEW FIX WAVE -- one adversarial regression, locking in the
  reviewer-identified RTL-value-record fix:
    * GetBounds (TWidget.GetBounds) -- Result := FBounds, FBounds an own-class
                        field of type TRect. TRect is deliberately NOT
                        declared anywhere in this fixture (no System.Types
                        unit is indexed by this isolated test), so unlike
                        GetRec's TMyRec (a store-resolved skRecord, tier 1),
                        this exercises IsReferenceTypeName's TIER-2 T/I-prefix
                        FALLBACK path. The site classifies 'borrowed' (FBounds
                        is a real field), but WITHOUT TRect in the fallback's
                        exclusion list, the bare 'T'-prefix heuristic wrongly
                        accepted it as a reference type. Proven WRONG against
                        the real built exe before this fix wave ('Owns
                        returned: borrowed' for a copy-by-value record).
                        Expected: NO 'Owns returned:' line (still has a
                        managed block via the unrelated Reads: FBounds fact,
                        from the SAME statement).

  Drives `index` -> `document --unit --apply` (Stubs=False default: a decl
  with NO prior doc-comment and NO facts is skipped entirely -- not
  exercised here, since every method in this fixture carries SOME fact, by
  design -- see the fixture's own "ORDERING/BLOCK-INVARIANT NOTE").

  IDEMPOTENCY is scoped to each method's OWN 'Owns returned:' segment (NOT a
  whole-file byte comparison) -- deliberate, per the task's own instructions:
  a PRE-EXISTING, unrelated 'document --apply' merge-engine bug (see
  fixtures\docp2\sql.pas's "ORDERING NOTE", carried from Task 7) collapses a
  declaration's managed block to a bare stub on a 2nd apply under a
  fact->no-fact adjacency this fixture is designed to avoid entirely, but
  scoping the assertion narrowly is a second, independent safeguard this
  task does not attempt to "fix" that unrelated bug by relying on.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\owner.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2owner'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'owner.pas'
$db     = Join-Path $scratch 'docp2owner.sqlite'
Copy-Item $fixture $target -Force

# Same scan-upward idiom run_doc_p2_fields.ps1's Get-DocBlockAbove uses:
# returns the contiguous run of ///-prefixed lines immediately above the
# FIRST line matching $declPattern. $null if the declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

# Extracts the 'Owns returned: ...' line's raw value (everything after
# 'Owns returned: ' to end of that line), or $null if $block has no such
# line at all (either $block itself is $null -- no managed block whatsoever
# -- or the block exists but carries no ownership fact).
function Get-OwnsLine([string]$block) {
  if ($null -eq $block) { return $null }
  $m = [regex]::Match($block, 'Owns returned: ([^\r\n]*)')
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value.Trim()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- MakeIt: unanimous 'new' (Result := TFoo.Create) ----------------------
  $makeItBlock = Get-DocBlockAbove $lines '^\s*function MakeIt: TFoo;\s*$'
  Check 'MakeIt has a managed block (AUTO_BEGIN)' (($null -ne $makeItBlock) -and ($makeItBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'MakeIt Owns returned is exactly ''new (caller owns)''' ((Get-OwnsLine $makeItBlock) -eq 'new (caller owns)')

  # --- GetIt: unanimous 'borrowed' (Result := FFoo, a field) ----------------
  $getItBlock = Get-DocBlockAbove $lines '^\s*function GetIt: TFoo;\s*$'
  Check 'GetIt has a managed block (AUTO_BEGIN)' (($null -ne $getItBlock) -and ($getItBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'GetIt Owns returned is exactly ''borrowed''' ((Get-OwnsLine $getItBlock) -eq 'borrowed')

  # --- Me: unanimous 'self' (Result := Self as TFoo) ------------------------
  $meBlock = Get-DocBlockAbove $lines '^\s*function Me: TFoo;\s*$'
  Check 'Me has a managed block (AUTO_BEGIN)' (($null -ne $meBlock) -and ($meBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Me Owns returned is exactly ''self''' ((Get-OwnsLine $meBlock) -eq 'self')

  # --- Amb: mixed 'new' + 'borrowed' -> NOT unanimous -> omitted ------------
  # Still gets a managed block via the unrelated Reads: FFoo fact (else
  # branch), so this proves the OMISSION specifically, not merely "no block".
  $ambBlock = Get-DocBlockAbove $lines '^\s*function Amb\(AFlag: Boolean\): TFoo;\s*$'
  Check 'Amb has a managed block (AUTO_BEGIN, via the unrelated Reads: FFoo fact)' (($null -ne $ambBlock) -and ($ambBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Amb has NO Owns returned: line (ambiguous -- new+borrowed mixed -- absence over a guessed verdict)' ($null -eq (Get-OwnsLine $ambBlock))

  # --- Count: unanimous 'borrowed' site, but return type is Integer --------
  # (value type, not a reference type) -> the object-type gate rejects it.
  # Still gets a managed block via the unrelated Reads: FCount fact.
  $countBlock = Get-DocBlockAbove $lines '^\s*function Count: Integer;\s*$'
  Check 'Count has a managed block (AUTO_BEGIN, via the unrelated Reads: FCount fact)' (($null -ne $countBlock) -and ($countBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Count has NO Owns returned: line (return-type gate: Integer is not a reference type)' ($null -eq (Get-OwnsLine $countBlock))

  # --- MakeViaExit: unanimous 'new' via the value-form Exit(...) site -------
  $exitBlock = Get-DocBlockAbove $lines '^\s*function MakeViaExit: TFoo;\s*$'
  Check 'MakeViaExit has a managed block (AUTO_BEGIN)' (($null -ne $exitBlock) -and ($exitBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'MakeViaExit Owns returned is exactly ''new (caller owns)'' (proves Exit(..) sites are collected)' ((Get-OwnsLine $exitBlock) -eq 'new (caller owns)')

  # --- DisposedResult: Result.Free anywhere in the body -> suppressed -------
  # Still gets a managed block via the unrelated Reads/Writes: FCount fact
  # (the trailing 'FCount := FCount + 1'), so this proves the OMISSION
  # specifically, not merely "no block at all".
  $disposedBlock = Get-DocBlockAbove $lines '^\s*function DisposedResult: TFoo;\s*$'
  Check 'DisposedResult has a managed block (AUTO_BEGIN, via the unrelated Reads/Writes: FCount fact)' (($null -ne $disposedBlock) -and ($disposedBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'DisposedResult has NO Owns returned: line (Result.Free seen -- does not cleanly escape)' ($null -eq (Get-OwnsLine $disposedBlock))

  # --- FIX 1 regression: Borrow calls APool.Create where APool (a parameter)
  # is an EXISTING INSTANCE, not a bare type reference; TWidgetPool.Create is
  # a plain method (not a real constructor) that just returns a shared field.
  # WITHOUT the receiver gate, ExprIsConstructor's member-name-only match
  # ('create') would read this back as a false 'new'. Still gets a managed
  # block via the unrelated Writes: FLastPool fact, so this proves the
  # OMISSION specifically, not merely "no block at all".
  $borrowBlock = Get-DocBlockAbove $lines '^\s*function Borrow\(APool: TWidgetPool\): TWidget;\s*$'
  Check 'Borrow has a managed block (AUTO_BEGIN, via the unrelated Writes: FLastPool fact)' (($null -ne $borrowBlock) -and ($borrowBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'Borrow has NO Owns returned: line (APool.Create receiver is an existing instance, not a type -- FIX 1)' ($null -eq (Get-OwnsLine $borrowBlock))

  # --- FIX 2 regression: GetRec returns TMyRec, a RECORD (value type). The
  # site classifies 'borrowed' (FRec is a real own-class field), but WITHOUT
  # the skRecord rejection, IsReferenceTypeName's T/I-prefix fallback would
  # wrongly accept 'TMyRec' (starts with 'T') as a reference type. Still gets
  # a managed block via the unrelated Reads: FRec fact (the SAME statement),
  # so this proves the OMISSION specifically, not merely "no block at all".
  $getRecBlock = Get-DocBlockAbove $lines '^\s*function GetRec: TMyRec;\s*$'
  Check 'GetRec has a managed block (AUTO_BEGIN, via the unrelated Reads: FRec fact)' (($null -ne $getRecBlock) -and ($getRecBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'GetRec has NO Owns returned: line (TMyRec is a record, not a reference type -- FIX 2)' ($null -eq (Get-OwnsLine $getRecBlock))

  # --- FINAL REVIEW FIX WAVE regression: GetBounds returns TRect, a common
  # RTL value-record deliberately NOT declared anywhere in this fixture (so
  # it is UNRESOLVED -- exercises IsReferenceTypeName's tier-2 T/I-prefix
  # fallback, unlike GetRec's tier-1 store-resolved skRecord path). The site
  # classifies 'borrowed' (FBounds is a real own-class field), but WITHOUT
  # TRect in the fallback's exclusion list the bare 'T'-prefix heuristic
  # would wrongly accept it as a reference type. Still gets a managed block
  # via the unrelated Reads: FBounds fact (the SAME statement), so this
  # proves the OMISSION specifically, not merely "no block at all".
  $getBoundsBlock = Get-DocBlockAbove $lines '^\s*function GetBounds: TRect;\s*$'
  Check 'GetBounds has a managed block (AUTO_BEGIN, via the unrelated Reads: FBounds fact)' (($null -ne $getBoundsBlock) -and ($getBoundsBlock -match '<!-- drag-lint:auto BEGIN -->'))
  Check 'GetBounds has NO Owns returned: line (TRect is an unresolved RTL value-record, not a reference type -- FINAL REVIEW FIX)' ($null -eq (Get-OwnsLine $getBoundsBlock))

  # --- Idempotency: reindex (facts are index-time) + re-apply --------------
  # Scoped to each method's OWN 'Owns returned:' segment (not a whole-file
  # byte comparison) -- see this file's own header comment for why.
  $before = @{
    MakeIt         = Get-OwnsLine $makeItBlock
    GetIt          = Get-OwnsLine $getItBlock
    Me             = Get-OwnsLine $meBlock
    Amb            = Get-OwnsLine $ambBlock
    Count          = Get-OwnsLine $countBlock
    MakeViaExit    = Get-OwnsLine $exitBlock
    DisposedResult = Get-OwnsLine $disposedBlock
    Borrow         = Get-OwnsLine $borrowBlock
    GetRec         = Get-OwnsLine $getRecBlock
    GetBounds      = Get-OwnsLine $getBoundsBlock
  }
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $lines2 = [IO.File]::ReadAllLines($target)
  $after = @{
    MakeIt         = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function MakeIt: TFoo;\s*$')
    GetIt          = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function GetIt: TFoo;\s*$')
    Me             = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function Me: TFoo;\s*$')
    Amb            = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function Amb\(AFlag: Boolean\): TFoo;\s*$')
    Count          = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function Count: Integer;\s*$')
    MakeViaExit    = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function MakeViaExit: TFoo;\s*$')
    DisposedResult = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function DisposedResult: TFoo;\s*$')
    Borrow         = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function Borrow\(APool: TWidgetPool\): TWidget;\s*$')
    GetRec         = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function GetRec: TMyRec;\s*$')
    GetBounds      = Get-OwnsLine (Get-DocBlockAbove $lines2 '^\s*function GetBounds: TRect;\s*$')
  }
  foreach ($k in $before.Keys) {
    Check "idempotent: $k Owns-returned unchanged after reindex + 2nd apply" ($before[$k] -eq $after[$k])
  }
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
