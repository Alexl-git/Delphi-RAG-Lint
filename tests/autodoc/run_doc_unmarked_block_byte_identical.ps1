<#
  run_doc_unmarked_block_byte_identical.ps1 -- a hand-written (unmarked) tag
  survives `document --apply` BYTE-IDENTICAL, not merely text-preserved.

  THE CONTRACT (docs\AI-USAGE.md, "THE PROVENANCE CONTRACT")
  --------------------------------------------------------------------------------
    "A tag WITHOUT the marker is yours. drag-lint never touches it -- not its
     text, not its whitespace, whatever it says."

  THE DEFECT (PLAN-autofix-campaign 4.2, sample B, BASICSF.pas:385-394)
  --------------------------------------------------------------------------------
  `CopyRecords` carried a hand-written block. The preview said `delete lines
  385..393` and re-inserted it whitespace-normalised, with `<param
  name="Count">` re-spelled to the declared `COunt`. The words survived; the
  bytes did not. The repair path rebuilt every preserved tag from the PARSED
  model (TDocCommentParser.CollapseWhitespace collapses runs of blanks; the
  <param> arm writes the SIGNATURE's spelling of the name) instead of copying
  the author's own lines through.

  WHY THE ASSERTION IS BYTE-LEVEL
  --------------------------------------------------------------------------------
  "Whitespace-normalised but preserved" IS the defect, so a text compare that
  trims or collapses whitespace would pass against the broken engine and prove
  nothing. Every check below compares whole lines, exactly.

  The fixture is built so that the engine HAS something to add (a mined raise
  and a facts fence), which is what forces the REPAIR path -- an engine with
  nothing to say leaves the region alone trivially, and that is not the case
  under test. The positive control asserts the additions actually landed.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_unmarked_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

$src = Join-Path $scratch 'unmarked.pas'
$db  = Join-Path $scratch 'u.sqlite'

# The hand-written block, EXACTLY as the author typed it. Deliberate features,
# each one something the parsed-model rebuild destroys:
#   * a multi-line <summary> whose second line carries a run of THREE blanks
#     and an indented continuation;
#   * <param name="Count"> where the signature says COunt (case differs);
#   * a <param> whose description spans two lines with a 4-blank indent;
#   * a hand-written <exception> with doubled blanks inside its text;
#   * a <seealso> spelled with a blank before the self-close.
$handLines = @(
  '/// <summary>function Handed',
  '///   Copy records from source to destination.   Handles different',
  '///     field order between the two datasets.</summary>',
  '/// <param name="Source">(TDataSet)  the source</param>',
  '/// <param name="Destination">(TDataSet)',
  '///     the destination</param>',
  '/// <param name="Count">(integer)</param>',
  '/// <returns>Returns  the number of records copied.</returns>',
  '/// <exception cref="EConvertError">When   a field cannot be converted.</exception>',
  '/// <seealso cref="Other" />'
)

$original = @'
unit unmarked;

interface

uses
  System.SysUtils;

@@HAND@@
function Handed(Source, Destination: string; COunt: Integer): Integer;

procedure Other;

implementation

function Handed(Source, Destination: string; COunt: Integer): Integer;
begin
  Result := 0;
  if Source = '' then
    raise EOther.Create('no source');
  Result := COunt;
end;

procedure Other;
begin
end;

end.
'@
$original = $original.Replace('@@HAND@@', ($handLines -join "`n"))
Write-Ascii $src $original
$origBytes = [IO.File]::ReadAllBytes($src)
$md5Orig = Get-FileMd5 $src

# True when every element of $needles appears in $hay as an EXACT line, in the
# same relative order (a subsequence match -- engine lines may sit between).
function Test-OrderedExactLines([string[]]$hay, [string[]]$needles) {
  $k = 0
  foreach ($h in $hay) {
    if ($k -lt $needles.Length -and $h -ceq $needles[$k]) { $k++ }
  }
  return ($k -eq $needles.Length)
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5First = Get-FileMd5 $src
  $text  = [IO.File]::ReadAllText($src)
  $lines = [IO.File]::ReadAllLines($src)
  Write-Host '--- applied file ---' -ForegroundColor DarkGray
  Write-Host $text -ForegroundColor DarkGray

  # --- POSITIVE CONTROL: the repair path really ran and added its own tags --
  Check 'CONTROL: the engine ADDED its mined <exception cref="EOther"> (repair path ran)' `
    ($text -match '<exception cref="EOther"><!-- drag-lint:auto exc -->no source</exception>') $text
  Check 'CONTROL: the engine ADDED a facts fence' `
    ($text -match '<!-- drag-lint:auto BEGIN -->') $text
  Check 'CONTROL: the file changed at all' ($md5First -ne $md5Orig)

  # --- THE CONTRACT: every hand-written line, byte for byte, in order -------
  foreach ($hl in $handLines) {
    Check ("hand-written line survives EXACTLY: " + $hl) `
      (@($lines | Where-Object { $_ -ceq $hl }).Count -ge 1)
  }
  Check 'hand-written lines keep their original relative order' `
    (Test-OrderedExactLines $lines $handLines)
  Check 'the author''s spelling <param name="Count"> is NOT re-spelled to COunt' `
    (-not ($text -match '<param name="COunt">\(integer\)')) $text
  Check 'no hand-written tag gained an engine marker' `
    (-not ($text -match '<param name="Count"><!--')) $text

  # --- idempotency ----------------------------------------------------------
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'IDEMPOTENT: reindex + a second --apply is byte-identical' `
    ((Get-FileMd5 $src) -eq $md5First) ("first=$md5First second=" + (Get-FileMd5 $src))

  # --- the exact inverse: strip restores the ORIGINAL BYTES -----------------
  # AI-USAGE: "document --strip --apply is the exact inverse of a document
  # run ... leaves every other byte alone". With the author's lines carried
  # through verbatim, that inverse is now testable against the original file
  # rather than against a normalised copy of it.
  & $exePath document --unit $src --db $db --strip --apply 2>$null | Out-Null
  Check 'document --strip --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5Strip = Get-FileMd5 $src
  Check 'INVERSE: strip(apply(original)) is byte-identical to the original' `
    ($md5Strip -eq $md5Orig) ("orig=$md5Orig strip=$md5Strip")
  if ($md5Strip -ne $md5Orig) {
    Write-Host '--- stripped file ---' -ForegroundColor DarkGray
    Write-Host ([IO.File]::ReadAllText($src)) -ForegroundColor DarkGray
  }
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
