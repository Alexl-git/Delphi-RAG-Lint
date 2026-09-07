<#
  run_query_decl_contains.ps1 -- `query find --decl-contains` matches the
  DECLARING SOURCE LINE, and nothing else.

  WHY THIS FILE EXISTS. `INBOX-text-index-cannot-see-declaration-clauses.md`:

      drag-lint query --text "stored IsFontStored" --db library-Win32.sqlite
      -> 0 match(es)

  The phrase is present verbatim in Vcl.Controls.pas. The FTS5 text index
  carries .pas STRING LITERALS plus .dfm/.sql text, so a declaration clause is
  searchable nowhere. Two independent readers hit that on the same day and both
  fell back to grepping the RTL -- the outcome the "index is a product" rule
  exists to prevent.

  Declaration clauses are semantics the extractor does not model: the stored
  signature for TCustomEdit.AutoSize is exactly `Boolean`, and the `default
  True` is not in the database at all. Indexing them would be an EXTRACTION
  change costing a DRAGLINT_EXTRACTOR_VERSION bump -- hours across every
  database -- so this verb re-reads the declaring line at query time instead.

  THE ARMS:

    1. MATCH      -- a property with `stored IsColorStored default clWindow`
                     is found by both clauses.
    2. CONTROL    -- the SAME phrase in a COMMENT and in a STRING LITERAL must
                     NOT match. This is the arm that makes the verb mean
                     something: a naive implementation that grepped the file
                     would pass arm 1 and fail here.
    3. NARROWING  -- a bare --decl-contains with no --kind/--name/--unit must
                     REFUSE (exit 2) and name the flags. It re-reads source per
                     candidate; an unnarrowed library run is thousands of file
                     reads.
    4. NEGATIVE   -- a phrase in no declaration exits 1, not 0.
    5. LIBRARY    -- the note's own query, against library-Win32.sqlite if that
                     index is present. SKIPPED WITH A REASON when it is not --
                     never a silent pass.

  RED BEFORE A2: the flag did not exist and the verb exited 3
  ("Unknown argument: --decl-contains"). Recorded because PLAN-SESSION-72 said
  exit 2 and PLAN-SESSION-73 said 3; 3 is what it did.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-decl-contains",
  [string]$LibDb   = 'C:\Projects\.drag-lint\library-Win32.sqlite'
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
New-Item -ItemType Directory -Force "$WorkDir\_D-RAG" | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Decoy.Caption carries the phrase in a COMMENT and in a STRING LITERAL, and its
# own declaration says nothing of the sort. Real.Color carries it for real.
$unit = @'
unit Decl;

interface

uses
  Vcl.Graphics;

type
  TReal = class
  private
    FColor: TColor;
    function IsColorStored: Boolean;
    procedure SetColor(AValue: TColor);
  published
    property Color: TColor read FColor write SetColor stored IsColorStored default clWindow;
  end;

  TDecoy = class
  private
    FCaption: string;
    // stored IsColorStored default clWindow -- named in a COMMENT only
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

function TReal.IsColorStored: Boolean;
begin
  Result := FColor <> clWindow;
end;

procedure TReal.SetColor(AValue: TColor);
begin
  FColor := AValue;
end;

procedure Mention;
begin
  // and once more as a STRING LITERAL, which is what --text DOES index
  Writeln('stored IsColorStored default clWindow');
end;

end.
'@

Write-Ascii "$WorkDir\Decl.pas" $unit
$db = "$WorkDir\_D-RAG\Decl.sqlite"
& $Exe index "$WorkDir" --db $db 2>&1 | Out-Null

Write-Host '1. MATCH -- the declaring line is searchable' -ForegroundColor Cyan
$out = (& $Exe query find --decl-contains 'stored IsColorStored' --kind property --db $db 2>&1) -join "`n"
$rc  = $LASTEXITCODE
Check 'the `stored` clause finds TReal.Color' ($out -match 'TReal\.Color') $out
Check 'exit 0 when there are matches' ($rc -eq 0) "exit=$rc"
Check 'the declaration itself is printed as evidence' ($out -match 'property Color: TColor read FColor')

$out2 = (& $Exe query find --decl-contains 'default clWindow' --kind property --db $db 2>&1) -join "`n"
Check 'the `default` clause finds it too' ($out2 -match 'TReal\.Color')

Write-Host ''
Write-Host '2. CONTROL -- a comment and a string literal must NOT match' -ForegroundColor Cyan
# This is the discriminating arm. A grep over the file would pass arm 1 and
# fail here, and so would any implementation that searched anything but the
# declaring span.
Check 'the COMMENT occurrence does not produce TDecoy.Caption' (-not ($out -match 'TDecoy\.Caption')) $out
Check 'the STRING LITERAL occurrence produces no routine match' (-not ($out -match 'Mention'))
# And prove the decoys are really there, so the two assertions above are not
# passing because the fixture lost them.
$src = [System.IO.File]::ReadAllText("$WorkDir\Decl.pas")
Check 'FIXTURE: the comment decoy is present in the source' ($src -match '// stored IsColorStored')
Check 'FIXTURE: the string-literal decoy is present in the source' ($src -match "Writeln\('stored IsColorStored")

Write-Host ''
Write-Host '3. NARROWING -- a bare --decl-contains refuses' -ForegroundColor Cyan
$bare = (& $Exe query find --decl-contains 'stored IsColorStored' --db $db 2>&1) -join "`n"
$brc  = $LASTEXITCODE
Check 'exit 2, not a silent full scan' ($brc -eq 2) "exit=$brc"
Check 'and it NAMES the flags that would narrow it' `
  (($bare -match '--kind') -and ($bare -match '--name') -and ($bare -match '--unit')) $bare

Write-Host ''
Write-Host '4. NEGATIVE -- a phrase in no declaration exits 1' -ForegroundColor Cyan
$none = (& $Exe query find --decl-contains 'stored IsNeverStored' --kind property --db $db 2>&1) -join "`n"
$nrc  = $LASTEXITCODE
Check 'exit 1 when nothing matches' ($nrc -eq 1) "exit=$nrc"
Check 'and it says so rather than printing nothing' ($none -match '0 match\(es\)')

Write-Host ''
Write-Host '5. LIBRARY -- the note''s own query' -ForegroundColor Cyan
if (Test-Path $LibDb) {
  $lib = (& $Exe query find --decl-contains 'stored IsFontStored' --kind property --db $LibDb 2>&1) -join "`n"
  Check 'library-Win32 answers the query that sent two readers to grep' `
    ($lib -match 'stored IsFontStored') (($lib -split "`n" | Select-String 'match\(es\) in') -join '')
  Check 'and the answer is not truncated' (-not ($lib -match 'INCOMPLETE'))
} else {
  Write-Host "  [SKIP] library index not present at $LibDb -- arm 5 did not run." -ForegroundColor Yellow
  Write-Host '         Named rather than silently passed: this arm is the only one that' -ForegroundColor Yellow
  Write-Host '         exercises the real corpus the defect was reported against.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
