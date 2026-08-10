<#
  run_doc_exception_cref.ps1 -- mined raises are emitted as real
  <exception cref="..."> tags, not as a 'Raises:' line inside <remarks>.

  WHY
  --------------------------------------------------------------------------------
  <exception cref=""> is the one tag REQUIRED by this project's documentation
  standard that the engine never generated. A raise mined from a body surfaced
  only as prose -- `Raises: EFoo` -- inside <remarks>. That is the wrong element:
  DocInsight and Help Insight render <exception> as its own section, and a
  linter looking for the required tag never saw one. The engine emitted
  <exception> in exactly one place, to PRESERVE a tag a human had written.

  So the tag is now generated, and the 'Raises:' line is gone rather than kept
  alongside it -- one comment should not say the same thing twice. Nothing else
  read that line: it existed only in the managed doc block, while hover and the
  context bundle build their facts through FormatPhase2FactLines, which never
  carried it.

  STRUCTURAL, NOT INVENTED
  --------------------------------------------------------------------------------
  The tag is emitted with an EMPTY description, on the same terms as <param>
  (ruling D-3): the tag set mirrors what the code does, and the meaning is left
  for a human. The class name is the only thing the source states -- WHEN it is
  raised is a claim the miner cannot make, and guessing it would break the
  "absence over wrong" policy in the place a wrong claim does most damage.

  THE OWNERSHIP PIN (phase 2 below) IS THE LOAD-BEARING ASSERTION
  --------------------------------------------------------------------------------
  Generating a tag is easy; not FREEZING it is the hard half, and it is what
  the <param> work had to get right too. An engine-written tag is marked, so
  when the raise is deleted from the body the tag must disappear on the next
  run. Phase 2 deletes the raise, reindexes and re-applies, and asserts exactly
  that. Without it, a first-run-only test would pass over an engine that
  cements a stale <exception cref> into every file it ever touches.

  Phase 1 covers the other three ownership arms in one file: a fresh comment
  (Fresh, TwoKinds), a hand-written tag that must survive verbatim (HandDoc),
  and a routine that raises nothing and must gain no tag (Quiet).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_exccref_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

$src = Join-Path $scratch 'excgen.pas'
$db  = Join-Path $scratch 'e.sqlite'

Write-Ascii $src @'
unit excgen;

interface

procedure Fresh;
procedure TwoKinds;
procedure Quiet;

/// <summary>Has a hand-written exception tag that must survive.</summary>
/// <exception cref="EAlreadyDocumented">Explained by a human.</exception>
procedure HandDoc;

implementation

procedure Fresh;
begin
  raise EFreshError.Create('boom');
end;

procedure TwoKinds;
begin
  if Random(2) = 0 then
    raise EAlpha.Create('a')
  else
    raise EBeta.Create('b');
end;

procedure HandDoc;
begin
  raise EAlreadyDocumented.Create('x');
end;

procedure Quiet;
begin
end;

end.
'@

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5First = Get-FileMd5 $src
  $text = [IO.File]::ReadAllText($src)
  Write-Host '--- applied file ---' -ForegroundColor DarkGray
  Write-Host $text -ForegroundColor DarkGray

  # --- generation ----------------------------------------------------------
  Check 'Fresh gets <exception cref="EFreshError">' `
    ($text -match '<exception cref="EFreshError">') $text
  Check '  ...and it carries the engine ownership marker' `
    ($text -match '<exception cref="EFreshError"><!-- drag-lint:auto --></exception>') $text
  Check 'TwoKinds gets a tag for EAlpha' ($text -match '<exception cref="EAlpha">')
  Check 'TwoKinds gets a tag for EBeta'  ($text -match '<exception cref="EBeta">')

  # --- the fact line is gone -----------------------------------------------
  Check 'no "Raises:" fact line survives anywhere in the file' `
    (-not ($text -match 'Raises:')) $text

  # --- hand-written tags are untouched -------------------------------------
  Check 'HandDoc keeps its hand-written description verbatim' `
    ($text -match '<exception cref="EAlreadyDocumented">Explained by a human\.</exception>') $text
  Check 'HandDoc does NOT get a second, engine-generated tag for the same cref' `
    (([regex]::Matches($text, '<exception cref="EAlreadyDocumented"')).Count -eq 1) `
    ("count=" + ([regex]::Matches($text, '<exception cref="EAlreadyDocumented"')).Count)
  Check 'the hand-written tag gains NO ownership marker' `
    (-not ($text -match '<exception cref="EAlreadyDocumented"><!-- drag-lint:auto -->'))

  # --- CONTROL against over-generation -------------------------------------
  # Quiet raises nothing. If any <exception> attaches to it, generation is
  # firing off something other than a mined raise.
  $quietBlock = ($text -split "`r?`n" | Select-String -Pattern 'procedure Quiet;' -Context 6,0 | Out-String)
  Check 'CONTROL: Quiet (raises nothing) gains no <exception> tag' `
    (-not ($quietBlock -match '<exception')) $quietBlock

  # --- idempotency ----------------------------------------------------------
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'IDEMPOTENT: reindex + a second --apply is byte-identical' `
    ((Get-FileMd5 $src) -eq $md5First) ("first=$md5First second=" + (Get-FileMd5 $src))

  Check 'every emitted /// line is 7-bit ASCII' `
    (@([IO.File]::ReadAllLines($src) | Where-Object { $_ -match '^\s*///' -and ($_.ToCharArray() | Where-Object { [int]$_ -gt 126 }) }).Count -eq 0)

  # =========================================================================
  # PHASE 2 -- THE OWNERSHIP PIN: delete the raise, the tag must follow
  # =========================================================================
  Write-Host ''
  Write-Host '=== PHASE 2: a deleted raise deletes its generated tag ===' -ForegroundColor Cyan

  $after = ([IO.File]::ReadAllText($src)) -replace [regex]::Escape("raise EFreshError.Create('boom');"), 'Exit;'
  [System.IO.File]::WriteAllText($src, $after, [System.Text.Encoding]::ASCII)
  Check 'PHASE 2 SETUP: the raise really is gone from the body' `
    (-not ((Get-Content $src -Raw) -match 'EFreshError\.Create')) ''

  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  $text2 = [IO.File]::ReadAllText($src)

  Check 'the engine-generated <exception cref="EFreshError"> is REMOVED' `
    (-not ($text2 -match '<exception cref="EFreshError"')) $text2
  # ...while everything a human owns is still there. A regeneration that clears
  # the stale tag by clearing everything would pass the check above.
  Check 'CONTROL: the hand-written EAlreadyDocumented tag still survives phase 2' `
    ($text2 -match '<exception cref="EAlreadyDocumented">Explained by a human\.</exception>') $text2
  Check 'CONTROL: EAlpha/EBeta (still raised) keep their tags' `
    (($text2 -match '<exception cref="EAlpha">') -and ($text2 -match '<exception cref="EBeta">')) $text2
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
