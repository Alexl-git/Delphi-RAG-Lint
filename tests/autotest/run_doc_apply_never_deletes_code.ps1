<#
  run_doc_apply_never_deletes_code.ps1 -- `document --apply` may only ever touch
  `///` lines. If a write would change ANY other line, it is refused and the
  file is restored byte-for-byte.

  WHY THIS EXISTS. On 2026-09-08 a consumer reported that
  `document --unit --apply --no-backup` DELETED two method declarations from a
  class in DataCopy. Each lost declaration had been replaced by a duplicated
  `/// </remarks>`, so the file still PARSED and nothing shouted; it was caught
  only because a later lint run reported `doc-orphan-block` and a class-surface
  diff against the committed revision showed two methods gone. One step later
  and the deletion would have been committed. `--no-backup` made it
  unrecoverable without a VCS.

  THE DEFECT IS NOT FIXED AND IS NOT REPRODUCED. Two faithful attempts to build
  a minimal case failed -- documented then hand-edited blocks ending in
  `/// </remarks>` directly above the declaration, a brand-new method added in
  the same edit, reindexed in between, run twice. Nothing was lost either time.
  A synthetic fixture staying silent is NOT evidence the defect is absent; it
  means the fixture does not match the trigger. So this runner does NOT assert
  the bug is gone. It asserts the DAMAGE CANNOT REACH DISK, which is worth
  having whether or not the root cause is ever found.

  THE INVARIANT, and why it is exactly right for this path. Measured before it
  was written: on the non-strip `document` path, plain `//` comments, `{ }`
  comments and code lines all survive untouched -- the writer manages `///`
  blocks and nothing else. So "every non-`///` line survives, in order" is a
  complete description of a legal doc write, with no false positives from
  comment styles. A declaration line is not a `///` line, so consuming one is
  caught by construction.

  THE CONTROLS:

    C1  an ordinary `document --apply` still succeeds and still writes its
        blocks. The guard must not be bought by refusing legitimate work --
        which is what a guard that fires on everything would do.
    P1  POSITIVE CONTROL, and the reason this runner is worth anything: with
        DRAGLINT_DOC_SELFTEST_DAMAGE=1 the doc path appends one synthetic edit
        that deletes a CODE line -- the shape of the reported damage. The guard
        must refuse, exit non-zero, and leave the file byte-identical. Without
        this the runner would pass against a build whose guard never fires,
        which is the failure mode this repo has hit three times.
    P2  the refusal must NAME the file and say what it saw, or an operator
        cannot act on it.
    N1  the restore must be byte-exact, not merely "the declaration is back" --
        a guard that repairs approximately is a second corruption.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_docguard_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# The reported shape: hand-written blocks ending in `/// </remarks>` DIRECTLY
# above the declaration line, which is what the two damaged declarations had.
$unit = Join-Path $src 'uGuard.pas'
Write-Ascii $unit @"
unit uGuard;

interface

type
  TGuardBase = class
  public
    /// <summary>Names the backup job for a file.</summary>
    /// <returns>The job name.</returns>
    function BackupJobName(const AFile: string): string; virtual;

    /// <summary>Finalises every pending backup.</summary>
    /// <remarks>
    /// Hand-written, closing tag directly above the declaration line.
    /// </remarks>
    procedure FinaliseBackups;

    /// <summary>Copies one file to every destination.</summary>
    /// <remarks>
    /// Also hand-written, also closing directly above its declaration.
    /// </remarks>
    function BackupFile(const AFile: string; out AMess: string): Boolean; virtual;
  end;

implementation

function TGuardBase.BackupJobName(const AFile: string): string;
begin
  Result := AFile;
end;

procedure TGuardBase.FinaliseBackups;
begin
end;

function TGuardBase.BackupFile(const AFile: string; out AMess: string): Boolean;
begin
  AMess := '';
  Result := BackupJobName(AFile) <> '';
end;

end.
"@

$db = Join-Path $scratch 'g.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function CodeLines([string]$Path) {
  # Every line that is NOT a /// comment -- exactly what the guard protects.
  @(Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch '^\s*///' })
}

$beforeCode  = CodeLines $unit
$beforeBytes = [System.IO.File]::ReadAllBytes($unit)

Write-Host "`n--- C1: an ordinary apply still works ---" -ForegroundColor Cyan
$out1 = & $exePath document --unit $unit --apply --no-backup --db $db 2>&1 | Out-String
$code1 = CodeLines $unit
Check 'C1 the run reports edits applied' ($out1 -match 'edit\(s\) applied') ($out1.Trim())
Check 'C1 it really wrote managed blocks' ([bool](Select-String -LiteralPath $unit -Pattern 'drag-lint:auto BEGIN' -Quiet)) 'no managed block means the run did nothing and C1 proves nothing'
Check 'C1 every non-/// line survived unchanged' (($code1 -join "`n") -eq ($beforeCode -join "`n")) `
  'a legitimate doc write must not disturb code, comments or blank lines'

Write-Host "`n--- P1: the guard refuses an edit that would delete a code line ---" -ForegroundColor Cyan
# A FRESH, UNDOCUMENTED unit, not the one C1 just documented. Re-running against
# an already-documented file yields "nothing to document" -- zero edits, so the
# apply path is never entered and the guard cannot be observed at all. The first
# draft of this runner made exactly that mistake and reported a green N1 that had
# proven nothing.
$unit2 = Join-Path $src 'uGuard2.pas'
Write-Ascii $unit2 @"
unit uGuard2;

interface

type
  TGuardTwo = class
  public
    function Alpha(const A: Integer): Integer; virtual;
    /// <summary>Beta does a thing.</summary>
    /// <remarks>
    /// Hand-written, closing tag directly above the declaration.
    /// </remarks>
    procedure Beta;
    function Gamma(const S: string): string;
  end;

implementation

function TGuardTwo.Alpha(const A: Integer): Integer;
begin
  Result := A;
end;

procedure TGuardTwo.Beta;
begin
end;

function TGuardTwo.Gamma(const S: string): string;
begin
  Result := S;
end;

end.
"@
& $exePath index $src --db $db 2>&1 | Out-Null
$armedCode  = CodeLines $unit2
$armedBytes = [System.IO.File]::ReadAllBytes($unit2)
$unit = $unit2   # everything below asserts against the fresh unit

$env:DRAGLINT_DOC_SELFTEST_DAMAGE = '1'
try {
  $log = Join-Path $scratch 'damage.log'
  cmd /c "`"$exePath`" document --unit `"$unit`" --apply --no-backup --db `"$db`" > `"$log`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $out2 = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
} finally { $env:DRAGLINT_DOC_SELFTEST_DAMAGE = '' }

Check 'P1 the run exits NON-ZERO' ($code -ne 0) "exit=$code -- a silent success is the defect being reported"
Check 'P1 it refuses, naming the refusal' ([bool]($out2 -match '(?i)refus|would (delete|change)')) ($out2.Trim())
Check 'P2 the message names the file' ([bool]($out2 -match 'uGuard2\.pas')) ($out2.Trim())

$afterBytes = [System.IO.File]::ReadAllBytes($unit)
Check 'N1 the file is restored BYTE-for-byte' `
  (($afterBytes.Length -eq $armedBytes.Length) -and (-not (Compare-Object $afterBytes $armedBytes -SyncWindow 0))) `
  "before=$($armedBytes.Length)B after=$($afterBytes.Length)B -- an approximate repair is a second corruption"
Check 'N1 control: the armed file really had the declarations' `
  ((@($armedCode | Where-Object { $_ -match '^\s{4}(function|procedure)\s' }).Count) -eq 3) `
  'if the fixture had no declarations, N1 would pass vacuously'

Write-Host "`n--- R: the REAL reproducer -- a lone CR skews the doc scanner by one line ---" -ForegroundColor Cyan
# THE ROOT CAUSE, reduced 2026-09-08 after the original report could not reduce it.
#
# TDocCommentScanner advances its line counter on #10 ONLY
# (src\parser\DRagLint.Parser.DocComments.pas:450), while TStringList.Text and the
# store both treat a LONE CR as a line break -- the store since session 79 made a
# lone CR a terminator. So one CR CR LF sequence anywhere above a doc block puts
# the scanner one line BEHIND every later line number, and the delete range it
# computes starts one line early: on the DECLARATION packed above the block.
#
# Measured against the unguarded build: this deletes
# `function BackupJobName(...)` outright, leaving the block's own
# `/// </remarks>` behind -- which is exactly the duplicated-closing-tag
# signature the original report described at three sites.
#
# This case asserts the DAMAGE IS BLOCKED, not that the skew is fixed. The
# scanner still miscounts; fixing that touches src\parser, which the
# extractor-version guard watches, so it costs a re-parse and is the owner's
# call. When it IS fixed, this case should keep passing -- via no violation
# rather than via a refusal -- so it is written to accept either outcome
# provided the file survives.
$srcR = Join-Path $scratch 'srcR'
New-Item -ItemType Directory -Path $srcR | Out-Null
$unitR = Join-Path $srcR 'uLoneCR.pas'
$bodyR = @"
unit uLoneCR;

interface

type
  TLoneCR = class
  public
    function BackupJobName(const AFile: string): string; virtual;
    /// <summary>Finalises every pending backup.</summary>
    /// <remarks>
    /// Hand-written block ending in a closing tag directly above the decl.
    /// </remarks>
    procedure FinaliseBackups;
    function BackupFile(const AFile: string; out AMess: string): Boolean; virtual;
  end;

implementation

function TLoneCR.BackupJobName(const AFile: string): string;
begin
  Result := AFile;
end;

procedure TLoneCR.FinaliseBackups;
begin
end;

function TLoneCR.BackupFile(const AFile: string; out AMess: string): Boolean;
begin
  AMess := '';
  Result := BackupJobName(AFile) <> '';
end;

end.
"@
$crlfR = ($bodyR -replace "`r`n","`n") -replace "`n","`r`n"
# The whole point: ONE extra CR, so CR CR LF. Invisible in an editor.
$skewed = $crlfR -replace "interface`r`n", "interface`r`r`n"
[System.IO.File]::WriteAllText($unitR, $skewed, (New-Object System.Text.UTF8Encoding($false)))

$rBytes = [System.IO.File]::ReadAllBytes($unitR)
$rDecls = @(Get-Content -LiteralPath $unitR | Where-Object { $_ -match '^\s{4}(function|procedure)\s' }).Count
Check 'R control: the fixture really carries a lone CR' `
  ((@($rBytes | Where-Object { $_ -eq 13 }).Count) -gt (@($rBytes | Where-Object { $_ -eq 10 }).Count)) `
  'without an unpaired CR this case tests nothing'
Check 'R control: the fixture has 3 packed declarations' ($rDecls -eq 3) 'the skew must have a declaration to land on'

& $exePath index $srcR --db (Join-Path $scratch 'r.sqlite') 2>&1 | Out-Null
$logR = Join-Path $scratch 'lonecr.log'
cmd /c "`"$exePath`" document --unit `"$unitR`" --apply --no-backup --db `"$(Join-Path $scratch 'r.sqlite')`" > `"$logR`" 2>&1" | Out-Null
$codeR = $LASTEXITCODE
$outR  = if (Test-Path -LiteralPath $logR) { Get-Content -LiteralPath $logR -Raw } else { '' }

$rDeclsAfter = @(Get-Content -LiteralPath $unitR | Where-Object { $_ -match '^\s{4}(function|procedure)\s' }).Count
Check 'R NO DECLARATION IS LOST' ($rDeclsAfter -eq 3) `
  "before=3 after=$rDeclsAfter -- exit=$codeR. This is the reported defect reaching disk."
Check 'R either refused cleanly, or applied without touching code' `
  ((($codeR -ne 0) -and ($outR -match '(?i)refus')) -or (($codeR -eq 0) -and ($rDeclsAfter -eq 3))) `
  ($outR.Trim())

# R2 -- THE CAUSE, not the containment. R above passes either way, so it stays
# green whether the scanner is fixed or merely fenced off by the guard. This one
# does not: it requires the run to SUCCEED. A build whose scanner still miscounts
# gets refused by the damage guard and fails here, which is the whole point --
# without R2 the scanner fix could be dropped and nothing would notice.
Check 'R2 the lone-CR unit documents SUCCESSFULLY (scanner counts CR as a line)' `
  ($codeR -eq 0) `
  "exit=$codeR -- non-zero means the damage guard had to catch a miscomputed edit range, i.e. the scanner is still counting LF only (DRagLint.Parser.DocComments.pas)"
Check 'R2 and it actually wrote managed blocks' `
  (($codeR -eq 0) -and [bool](Select-String -LiteralPath $unitR -Pattern 'drag-lint:auto BEGIN' -Quiet)) `
  'a clean exit that documented nothing would satisfy R2 vacuously'

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
