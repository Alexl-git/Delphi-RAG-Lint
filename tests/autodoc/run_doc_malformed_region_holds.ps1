<#
  run_doc_malformed_region_holds.ps1 -- the malformed-region guard holds on a
  declaration the engine ACTUALLY HAS OUTPUT FOR.

  WHY THIS FILE EXISTS. `INBOX-returns-type-baseline-destroys-malformed-blocks`
  records a `<returns>` type baseline that was written, went red on
  run_doc_p3_guards.ps1's D5 arm, and was REVERTED. Its most valuable sentence is
  not about `<returns>` at all:

      "the guard was never really guarding the malformed block; it was guarded by
       accident, because nothing wanted to write there."

  That is the vacuous-guard failure mode. D5's fixture routine had no minable
  return case, so the engine emitted NOTHING for it, so no edit was produced, so
  the malformed block survived -- and the test went green without the protection
  ever being exercised. The note concluded that any future attempt "must first
  make the malformed-region guard hold on a declaration the engine DOES have
  output for", and left that precondition UNPROVEN.

  MEASURED 2026-08-16: it holds. This file pins it, so the precondition stops
  being an open question and a future `<returns>` attempt has something to build
  on.

  THE TWO ARMS ARE A DISCRIMINATING PAIR, which is the whole point:

    * Malformed  -- a routine WITH callers (so the engine has real facts to
      write) whose block opens an auto fence that never closes, with
      hand-written prose after it. The engine must report "nothing to document"
      and leave the file byte-identical.
    * Control    -- the SAME routine with the SAME caller and NO block at all.
      The engine MUST want to write (Called from: + Pure). This is what makes
      the first arm mean something: without it, "nothing to document" is equally
      consistent with an engine that had nothing to say, which is exactly how
      D5 came to pass for the wrong reason.

  If protection regressed, arm 1 produces an edit and fails. If the engine went
  inert for this shape, arm 2 fails and says so.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-malformed-region"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The caller is identical in both arms, so the engine's FACTS are identical in
# both arms. The only difference is the doc block.
$callerUnit = @'
unit AOnly;

interface

procedure CallFromA;

implementation

uses Mal;

procedure CallFromA;
begin
  Documented;
end;

end.
'@

function New-Arm([string]$Name, [string]$MalUnit) {
  $root = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force "$root\shared", "$root\a\_D-RAG" | Out-Null
  Write-Ascii "$root\shared\Mal.pas" $MalUnit
  Write-Ascii "$root\a\AOnly.pas"    $callerUnit
  Write-Ascii "$root\a\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'
  $db = "$root\a\_D-RAG\A.sqlite"
  & $Exe index "$root\shared" --db $db 2>&1 | Out-Null
  & $Exe index "$root\a"      --db $db 2>&1 | Out-Null
  [PSCustomObject]@{ Db = $db; Pas = "$root\shared\Mal.pas" }
}

# An auto fence that OPENS and never reaches END, with the author's own prose
# after it. Fail-closed territory: the engine cannot tell where its region ends,
# so it must not rewrite anything here.
$malformed = @'
unit Mal;

interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: somebody.Old (Old.pas)
/// <value>HAND WRITTEN PROSE THAT MUST SURVIVE</value>
/// </remarks>
procedure Documented;

implementation

procedure Documented;
begin
end;

end.
'@

$plain = @'
unit Mal;

interface

procedure Documented;

implementation

procedure Documented;
begin
end;

end.
'@

Write-Host 'malformed managed region -- fail closed' -ForegroundColor Cyan
$arm  = New-Arm 'malformed' $malformed
$before = [System.IO.File]::ReadAllText($arm.Pas)
$dry  = (& $Exe document --unit $arm.Pas --db $arm.Db 2>&1) -join "`n"
& $Exe document --unit $arm.Pas --db $arm.Db --apply --no-backup 2>&1 | Out-Null
$after = [System.IO.File]::ReadAllText($arm.Pas)

Check 'the engine declines to document a malformed region' `
  ($dry -match 'nothing to document') "said: $(($dry -split "`n" | Select-String 'doc:') -join '')"
Check 'the file is byte-identical after --apply' ($after -eq $before)
Check 'the hand-written <value> survives' `
  ($after -match 'HAND WRITTEN PROSE THAT MUST SURVIVE')

Write-Host ''
Write-Host 'CONTROL -- the engine is NOT merely inert for this declaration' -ForegroundColor Cyan
$ctl    = New-Arm 'control' $plain
$ctlDry = (& $Exe document --unit $ctl.Pas --db $ctl.Db 2>&1) -join "`n"
Check 'same routine, same caller, no block: the engine WANTS to write' `
  ($ctlDry -match '1 edit\(s\)') "said: $(($ctlDry -split "`n" | Select-String 'doc:') -join '')"
Check 'and what it would write is a real fact, not an empty block' `
  ($ctlDry -match 'Called from: AOnly\.CallFromA')

if (-not ($ctlDry -match '1 edit\(s\)')) {
  Write-Host '  !! The control failed, so the three assertions above prove NOTHING --' -ForegroundColor Yellow
  Write-Host '  !! "nothing to document" is then equally consistent with an engine' -ForegroundColor Yellow
  Write-Host '  !! that simply had no facts, which is how run_doc_p3_guards.ps1 D5' -ForegroundColor Yellow
  Write-Host '  !! came to pass for the wrong reason. See the header.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
