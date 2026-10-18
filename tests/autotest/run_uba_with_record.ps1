<#
  run_uba_with_record.ps1 -- `with F do` on a RECORD local is not a read of F.

  B-14 / triage A1 (INBOX-used-before-assignment-record-and-shadow-residual, item 1).
  The CFG adds a `with` statement's entity as an ordinary item, so the bare
  identifier `F` in `with F do` was collected as a READ, and an unassigned record
  local was reported "is used before it is assigned" (error) on the with line --
  although `with` on a record only takes its address. The with-body is opaque, so
  the field writes inside it were not seen either.

  The fix: with a store, the entity of a `with` that is a bare RECORD local (the
  same tcRecord test the record-method-call seam uses) DEFINES the local instead
  of reading it -- the body is opaque and a with-block over a record is how its
  fields get filled, exactly as `F.Init` is treated.

  A CLASS reference is different: `with Obj do` dereferences Obj, so an
  unassigned class local in a `with` is a genuine nil/garbage dereference and MUST
  keep firing. That, and an ordinary unassigned Integer read, are the positive
  controls -- a test asserting only "the FP is gone" passes with the rule off.

    WithRecord        F: TFact; with F do begin ..fields.. end; Use(F)  -> SILENT
    WithRecordRead    F: TFact; with F do Sid := 1; Result := F.Sid    -> SILENT
    WithClassUnasgn   B: TBox (class); with B do Val := 1              -> MUST FIRE (with line)
    PlainUnassigned   N: Integer; Result := N + 1                      -> MUST FIRE

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uba-with-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$app  = Join-Path $WorkDir 'app'
$drag = Join-Path $app '_D-RAG'
foreach ($d in @($WorkDir, $app, $drag)) { New-Item -ItemType Directory $d -Force | Out-Null }

Write-Ascii (Join-Path $app 'uWith.pas') @'
unit uWith;

interface

type
  TFact = record
    Sid  : Integer;
    Reads: string;
  end;

  TBox = class
  public
    Val: Integer;
  end;

procedure WithRecord(AId: Integer);
function WithRecordRead: Integer;
procedure WithClassUnasgn;
function PlainUnassigned: Integer;

implementation

procedure Use(const A: TFact);
begin
end;

procedure WithRecord(AId: Integer);
var
  F: TFact;
begin
  with F do { MUST NOT be reported }
  begin
    Sid := AId;
    Reads := '';
  end;
  Use(F);
end;

function WithRecordRead: Integer;
var
  F: TFact;
begin
  with F do { MUST NOT be reported }
    Sid := 1;
  Result := F.Sid;
end;

procedure WithClassUnasgn;
var
  B: TBox;
begin
  with B do { MUST be reported: dereferences an unassigned class reference }
    Val := 1;
end;

function PlainUnassigned: Integer;
var
  N: Integer;
begin
  Result := N + 1; { MUST be reported }
end;

end.
'@

Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uWith in 'uWith.pas';
begin
  WithRecord(1);
end.
'@
Write-Ascii (Join-Path $drag 'drag-lint-project.json') '{ "ownRoots": ["."] }'

$db  = Join-Path $drag 'app.sqlite'
$src = Join-Path $app 'uWith.pas'
Push-Location $env:TEMP
try {
  & $Exe index $app --db $db 2>&1 | Out-Null
  $out  = & $Exe lint $src --db $db 2>&1 | Out-String
} finally { Pop-Location }
$uba = @($out -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment' })
$srcLines = [System.IO.File]::ReadAllLines($src)
function LineOf($pat) { for ($i = 0; $i -lt $srcLines.Count; $i++) { if ($srcLines[$i] -match $pat) { return ($i + 1) } }; return -1 }
function UbaAt($ln) { return (@($uba | Where-Object { $_ -match ":$ln`:" }).Count -gt 0) }
function UbaFor($name) { return @($uba | Where-Object { $_ -match ('"' + $name + '"') }) }

Check 'SANITY: index + lint ran and produced output' ($out.Trim().Length -gt 0) $out
Check 'POSITIVE CONTROL: PlainUnassigned (N: Integer read unassigned) still fires' `
      (UbaAt (LineOf 'Result := N \+ 1')) ($uba -join "`n")
Check 'POSITIVE CONTROL: `with B do` on an unassigned CLASS local still fires' `
      (UbaAt (LineOf 'with B do')) ($uba -join "`n")
Check 'B-14: `with F do` on a RECORD local is not a read (no finding for "f")' `
      ((UbaFor 'f').Count -eq 0) ($uba -join "`n")
Check 'exactly the 2 true positives are reported' ($uba.Count -eq 2) ($uba -join "`n")

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
