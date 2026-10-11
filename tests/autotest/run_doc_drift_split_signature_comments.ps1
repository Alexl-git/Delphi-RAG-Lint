<#
  run_doc_drift_split_signature_comments.ps1 -- doc-drift must read a routine's
  parameters with the COMMENTS inside its parameter list removed.

  THE BUG (C14, filed 2026-10-05 by the converter stream)
  ------------------------------------------------------
  The indexed Signature of a declaration split over several lines is the lines
  JOINED WITH A SPACE, comments included. A trailing `//` comment on line 1 then
  runs straight into line 2, and its text became parameter text:

    function AnalyzeUnit(const AUnitPas: string; const AReader: TReader;  // dl:ok x -- REVIEWED; a; b drop ...
      const ACodeUses: TObject = nil): Integer;

  reported `signature param "b drop ... const ACodeUses" has no <param> tag` and
  `documented param "ACodeUses" not in signature`. `{ }` and `(* *)` comments
  carrying a ';' split a group the same way. The writer (`document`) parsed the
  same text, so it could not emit the <param> the checker wanted either.

  Cases (doc-drift --qname <Unit>.<Routine> --json, one JSON object per line)
    S1  split list, trailing // comment with ';'      no param finding
    S2  { } comment with ';' inside the list           no param finding
    S3  (* *) comment with ';' inside the list         no param finding
    S4  '//' inside a STRING default value             no param finding
    W1  writer: S1's shape, ACodeUses undocumented     `document` proposes <param name="ACodeUses">
    P1  S1's shape, ACodeUses undocumented             ddParamMissing "ACodeUses" (positive control)
    P2  S1's shape, a documented AGhost not in the sig ddParamRenamedOrRemoved "AGhost" (positive control)
    S5  // comment, then an {$IFDEF NEVERDEF} param    no param finding (the index already
                                                     dropped Z; the source must not bring it back)
    S6  // comment between '(' and the first ':'      no param finding
    P3  S6's shape, B undocumented                    ddParamMissing "B" (positive control)
    W2  writer: P3                                    `document` proposes <param name="B">, no comment text
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-drift-split-sig-$PID"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
try {
  $srcDir = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $srcDir | Out-Null
  $db = Join-Path $WorkDir 'splitsig.sqlite'
  $body = @'
unit SplitSig;

interface

type
  TReader = class
  end;

/// <summary>S1: split list with a trailing line comment.</summary>
/// <param name="AUnitPas">The unit.</param>
/// <param name="AReader">The reader.</param>
/// <param name="ACodeUses">Lookup.</param>
/// <returns>A count.</returns>
function S1(const AUnitPas: string; const AReader: TReader;  // dl:ok x -- REVIEWED; a; b drop this marker when they do
  const ACodeUses: TObject = nil): Integer;

/// <summary>S2: brace comment inside the list.</summary>
/// <param name="A">First.</param>
/// <param name="C">Second.</param>
/// <returns>A count.</returns>
function S2(const A: Integer; { note; x } const C: Integer): Integer;

/// <summary>S3: paren-star comment inside the list.</summary>
/// <param name="A">First.</param>
/// <param name="C">Second.</param>
/// <returns>A count.</returns>
function S3(const A: Integer; (* note; y *) const C: Integer): Integer;

/// <summary>S4: a string default that contains two slashes.</summary>
/// <param name="AUrl">The url.</param>
/// <param name="ATries">How many.</param>
procedure S4(const AUrl: string = 'http://x'; ATries: Integer = 0);

/// <summary>P1: split list, a real parameter left undocumented.</summary>
/// <param name="AUnitPas">The unit.</param>
/// <param name="AReader">The reader.</param>
/// <returns>A count.</returns>
function P1(const AUnitPas: string; const AReader: TReader;  // note; a; b
  const ACodeUses: TObject = nil): Integer;

/// <summary>P2: split list, a documented parameter that does not exist.</summary>
/// <param name="AUnitPas">The unit.</param>
/// <param name="AReader">The reader.</param>
/// <param name="ACodeUses">Lookup.</param>
/// <param name="AGhost">Gone.</param>
/// <returns>A count.</returns>
function P2(const AUnitPas: string; const AReader: TReader;  // note; a; b
  const ACodeUses: TObject = nil): Integer;

/// <summary>S5: a line comment, then a parameter the preprocessor drops.</summary>
/// <param name="A">First.</param>
/// <param name="B">Second.</param>
procedure S5(const A: Integer; // one; two
  {$IFDEF NEVERDEF} Z: Integer; {$ENDIF}
  B: Integer);

/// <summary>S6: a line comment before the first parameter.</summary>
/// <param name="A">First.</param>
/// <param name="B">Second.</param>
procedure S6( // leading note; x
  const A: Integer;
  B: Integer);

/// <summary>P3: S6's shape, B undocumented.</summary>
/// <param name="A">First.</param>
procedure P3( // leading note; x
  const A: Integer;
  B: Integer);

implementation

function S1(const AUnitPas: string; const AReader: TReader;
  const ACodeUses: TObject = nil): Integer;
begin
  Result := 0;
end;

function S2(const A: Integer; const C: Integer): Integer;
begin
  Result := A + C;
end;

function S3(const A: Integer; const C: Integer): Integer;
begin
  Result := A + C;
end;

procedure S4(const AUrl: string = 'http://x'; ATries: Integer = 0);
begin
end;

function P1(const AUnitPas: string; const AReader: TReader;
  const ACodeUses: TObject = nil): Integer;
begin
  Result := 0;
end;

function P2(const AUnitPas: string; const AReader: TReader;
  const ACodeUses: TObject = nil): Integer;
begin
  Result := 0;
end;

procedure S5(const A: Integer; B: Integer);
begin
end;

procedure S6(const A: Integer; B: Integer);
begin
end;

procedure P3(const A: Integer; B: Integer);
begin
end;

end.
'@
  $norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $srcDir 'SplitSig.pas'), $norm, [System.Text.Encoding]::ASCII)

  & $Exe index $srcDir --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  function Get-Findings([string]$QName) {
    $lines = & $Exe doc-drift --qname $QName --db $db --json 2>$null
    $objs = @()
    foreach ($line in $lines) {
      $t = "$line".Trim()
      if ($t -eq '' -or -not $t.StartsWith('{')) { continue }
      try { $objs += ($t | ConvertFrom-Json) } catch { }
    }
    return @{ Findings = $objs; Raw = ($lines -join ' | ') }
  }
  $paramKinds = @('ddParamMissing', 'ddParamRenamedOrRemoved')

  Write-Host 'Positive controls (a real parameter mismatch is still reported)' -ForegroundColor Cyan
  $p1 = Get-Findings 'SplitSig.P1'
  Check 'P1 undocumented ACodeUses -> ddParamMissing "ACodeUses"' (
    @($p1.Findings | Where-Object { $_.kind -eq 'ddParamMissing' -and $_.detail -match '"ACodeUses"' }).Count -eq 1) $p1.Raw
  Check 'P1 nothing else' (@($p1.Findings | Where-Object { $paramKinds -contains $_.kind }).Count -eq 1) $p1.Raw
  $p2 = Get-Findings 'SplitSig.P2'
  Check 'P2 ghost param -> ddParamRenamedOrRemoved "AGhost"' (
    @($p2.Findings | Where-Object { $_.kind -eq 'ddParamRenamedOrRemoved' -and $_.detail -match '"AGhost"' }).Count -eq 1) $p2.Raw
  Check 'P2 nothing else' (@($p2.Findings | Where-Object { $paramKinds -contains $_.kind }).Count -eq 1) $p2.Raw
  $p3 = Get-Findings 'SplitSig.P3'
  Check 'P3 comment before the first param, B undocumented -> ddParamMissing "B"' (
    @($p3.Findings | Where-Object { $_.kind -eq 'ddParamMissing' -and $_.detail -match '"B"' }).Count -eq 1) $p3.Raw
  Check 'P3 nothing else' (@($p3.Findings | Where-Object { $paramKinds -contains $_.kind }).Count -eq 1) $p3.Raw

  Write-Host ''
  Write-Host 'A comment inside the parameter list is not parameter text' -ForegroundColor Cyan
  foreach ($q in @('S1', 'S2', 'S3', 'S4', 'S5', 'S6')) {
    $r = Get-Findings ('SplitSig.' + $q)
    Check ("$q no param finding") (@($r.Findings | Where-Object { $paramKinds -contains $_.kind }).Count -eq 0) $r.Raw
  }

  Write-Host ''
  Write-Host 'Writer agrees with the checker' -ForegroundColor Cyan
  $w = (& $Exe document --qname SplitSig.P1 --db $db 2>$null) -join "`n"
  Check 'W1 document proposes <param name="ACodeUses">' ($w -match '<param name="ACodeUses">')
  Check 'W1 document proposes no comment-text param' (-not ($w -match '<param name="(b|a|note)\b'))
  $w2 = (& $Exe document --qname SplitSig.P3 --db $db 2>$null) -join "`n"
  Check 'W2 document proposes <param name="B"> for S6''s shape' ($w2 -match '<param name="B">')
  Check 'W2 document proposes no comment-text param' (-not ($w2 -match '<param name="(x|note|leading)\b'))
}
finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
