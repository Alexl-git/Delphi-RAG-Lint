<#
  run_doc_stacked_region_preserves_prose.ps1 -- `document --apply` must not
  destroy a PRECEDING declaration's authored prose when two doc blocks are
  CONTIGUOUS.

  WHY THIS FILE EXISTS. `INBOX-autodoc-strips-authored-prose-from-a-record.md`
  records the measurement: applying `document --project` over this repo's own
  src\ changed 91 files, 20 of which LOST authored documentation -- 128 lines
  in total. One case: TAstChecker.CheckWithHiding lost its summary, four
  <param> descriptions, its <returns> and its <remarks>.

  THE TRIGGER IS A STACKED DOC REGION, and getting there took two wrong
  guesses. The note first blamed a RECORD type; four isolated single-block
  fixtures were built on that guess, all four preserved the prose, and the note
  was WITHDRAWN as unreproducible. The withdrawal was the dangerous error --
  the real sweep then destroyed 128 lines. A synthetic repro failing is not
  absence.

  What actually does it: two `///` blocks sitting back to back with no blank
  line between them are ONE region to TDocCommentScanner, so the region found
  above a declaration swallows the block belonging to a DIFFERENT declaration.
  Regenerating deletes the whole span and re-emits only the trailing block.

  In this repo's own source the shape reads:

      /// <summary>...CheckMutableGlobalVars' doc...</summary>   <-- swallowed
      /// <remarks>...</remarks>
      /// <summary>...CheckWithHiding's doc...</summary>          <-- kept
      /// <param ...>
      class function CheckWithHiding(...);
      class function CheckMutableGlobalVars(...);                 <-- its doc is
                                                                      above, not
                                                                      adjacent

  THE TWO ARMS ARE A DISCRIMINATING PAIR:

    * Stacked -- two contiguous blocks above one documented routine. Both
      authored texts must survive, AND the engine must still write its facts.
      That second half is the positive control: without it "the prose survived"
      is equally consistent with an engine that went inert for the shape, which
      is exactly how a sibling guard (run_doc_p3_guards D5) once passed for the
      wrong reason -- see run_doc_malformed_region_holds.ps1's header.
    * Single -- the SAME routine, the SAME caller, ONE block. Proves the merge
      preserves prose in the ordinary case, so a stacked failure is specific to
      stacking and not a general regression in the merge.

  RED ON THE UNFIXED BUILD: arm 1's "first block's authored prose survives"
  fails -- the whole region is deleted and only the trailing block is re-emitted.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-stacked-region"
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

# Identical in both arms, so the engine's FACTS are identical in both arms.
# The only difference is the shape of the doc block above Documented.
$callerUnit = @'
unit AOnly;

interface

procedure CallFromA;

implementation

uses Stk;

procedure CallFromA;
begin
  Documented;
end;

end.
'@

function New-Arm([string]$Name, [string]$StkUnit) {
  $root = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force "$root\shared", "$root\a\_D-RAG" | Out-Null
  Write-Ascii "$root\shared\Stk.pas" $StkUnit
  Write-Ascii "$root\a\AOnly.pas"    $callerUnit
  Write-Ascii "$root\a\_D-RAG\drag-lint-project.json" '{ "ownRoots": [".", "../shared"] }'
  $db = "$root\a\_D-RAG\A.sqlite"
  & $Exe index "$root\shared" --db $db 2>&1 | Out-Null
  & $Exe index "$root\a"      --db $db 2>&1 | Out-Null
  [PSCustomObject]@{ Db = $db; Pas = "$root\shared\Stk.pas" }
}

# Two complete doc blocks, CONTIGUOUS. The first belongs to something else --
# in the real source, to a declaration that sits BELOW the one being documented,
# which is how the shape arises. Only the second describes Documented.
$stacked = @'
unit Stk;

interface

/// <summary>FIRST BLOCK PROSE THAT MUST SURVIVE.</summary>
/// <remarks>FIRST BLOCK REMARK THAT MUST SURVIVE.</remarks>
/// <summary>SECOND BLOCK PROSE THAT MUST SURVIVE.</summary>
/// <remarks>SECOND BLOCK REMARK THAT MUST SURVIVE.</remarks>
procedure Documented;

implementation

procedure Documented;
begin
end;

end.
'@

# The ordinary case: one block, same routine, same caller.
$single = @'
unit Stk;

interface

/// <summary>SECOND BLOCK PROSE THAT MUST SURVIVE.</summary>
/// <remarks>SECOND BLOCK REMARK THAT MUST SURVIVE.</remarks>
procedure Documented;

implementation

procedure Documented;
begin
end;

end.
'@

Write-Host 'STACKED -- two contiguous doc blocks above one declaration' -ForegroundColor Cyan
$arm    = New-Arm 'stacked' $stacked
$before = [System.IO.File]::ReadAllText($arm.Pas)
$dry    = (& $Exe document --unit $arm.Pas --db $arm.Db 2>&1) -join "`n"
& $Exe document --unit $arm.Pas --db $arm.Db --apply --no-backup 2>&1 | Out-Null
$after  = [System.IO.File]::ReadAllText($arm.Pas)

Check 'the FIRST block''s authored summary survives' `
  ($after -match 'FIRST BLOCK PROSE THAT MUST SURVIVE') `
  '<-- this is the 128-line data loss; RED before the fix'
Check 'the FIRST block''s authored remark survives' `
  ($after -match 'FIRST BLOCK REMARK THAT MUST SURVIVE')
Check 'the SECOND block''s authored summary survives' `
  ($after -match 'SECOND BLOCK PROSE THAT MUST SURVIVE')
Check 'the SECOND block''s authored remark survives' `
  ($after -match 'SECOND BLOCK REMARK THAT MUST SURVIVE')

# POSITIVE CONTROL for arm 1. "Nothing was lost" is worthless if the engine
# simply stopped writing: a fix that declines every stacked region would pass
# the four assertions above and silently drop the shape out of the sweep.
Check 'and the engine STILL writes its facts for this declaration' `
  ($after -match 'Called from: AOnly\.CallFromA') `
  "dry said: $(($dry -split "`n" | Select-String 'doc:') -join '')"

Write-Host ''
Write-Host 'CONTROL -- the same routine with ONE block' -ForegroundColor Cyan
$ctl       = New-Arm 'single' $single
$ctlBefore = [System.IO.File]::ReadAllText($ctl.Pas)
$ctlDry    = (& $Exe document --unit $ctl.Pas --db $ctl.Db 2>&1) -join "`n"
& $Exe document --unit $ctl.Pas --db $ctl.Db --apply --no-backup 2>&1 | Out-Null
$ctlAfter  = [System.IO.File]::ReadAllText($ctl.Pas)

Check 'the ordinary merge wants to write' `
  ($ctlDry -match 'edit\(s\)') "said: $(($ctlDry -split "`n" | Select-String 'doc:') -join '')"
Check 'the ordinary merge preserves authored prose' `
  ($ctlAfter -match 'SECOND BLOCK PROSE THAT MUST SURVIVE')
Check 'the ordinary merge writes the fact' `
  ($ctlAfter -match 'Called from: AOnly\.CallFromA')

if (-not ($ctlAfter -match 'Called from: AOnly\.CallFromA')) {
  Write-Host '  !! The control failed, so arm 1 proves NOTHING -- prose surviving' -ForegroundColor Yellow
  Write-Host '  !! is then equally consistent with an engine that writes nothing.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
