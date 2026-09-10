<#
  run_default_section_visibility.ps1 -- PLAN A T5, spec 8.1 gap 2.

  WHAT IS MISSING. VisibilityOfSection returns 'public' for a declSection that
  carries NO visibility keyword. In a {$M+} class (and in any class compiled with
  it, which is every TPersistent descendant) that unlabelled leading section is
  actually PUBLISHED, and the index cannot tell the two apart -- both read
  modifiers='public'.

  WHY THIS IS A SEPARATE COLUMN AND NOT A NEW WORD IN `modifiers`.
  The design spec said "e.g. modifiers = 'default'". That would BREAK the very
  consumers the new-column decision exists to protect: CLI.IsValidTarget tests
  `Vis in ('published','public')`, so a member whose visibility read 'default'
  would silently vanish from every proptree target list. LSP.Completion and
  Convert.PropTree equality-match the visibility word too. The fact gets its own
  additive column, vis_explicit, and `modifiers` keeps saying 'public' exactly as
  it does today -- which this guard asserts, because "unchanged" is the whole
  promise.

  vis_explicit is TRUE when a visibility keyword was actually written for the
  member's section, FALSE for the unlabelled default section. NULL on a pre-v22
  row reads back as TRUE -- the conservative direction: an old index claims the
  keyword WAS written rather than inventing a published member.

  CASES
    positive  a class whose first section has no keyword -> that member is
              vis_explicit=false while a later `public` member is true; BOTH
              still read modifiers='public'.
    negative  `strict private` -> vis_explicit=true, modifiers='strict private'
              (a two-word visibility must not be mistaken for "no keyword").
    control   modifiers for every member is byte-identical to the pre-change
              engine.

  MEASURED RED, THEN GREEN -- pre-change engine
  (scratchpad\engine-preA, extractor 1.14.0-alpha,
   sha256 C47510745578EB3C4F501EBEB3BCD832E8B3F9A1F3357F0FF8B28EF847B12C34):
  every vis_explicit assertion fails with FIELD-ABSENT; every modifiers control
  passes. See the T6 block below for the verbatim reading.

  VERBATIM RED, captured 2026-09-09 22:49 against that engine:

    engine: extractor=1.14.0-alpha exe=C:\TEMP\claude\c--Projects-Delphi-RAG-lint\46ac75c6-8655-4a1c-9ca4-6ea10187bdad\scratchpad\engine-preA\drag-lint.exe
      [PASS] index exits 0 exit=0
      [FAIL] FDefaultField has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] FDefaultField modifiers is still 'public' got: 'public'
      [FAIL] DefaultMethod has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] DefaultMethod modifiers is still 'public' got: 'public'
      [FAIL] FPublicField has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] FPublicField modifiers is still 'public' got: 'public'
      [FAIL] FStrictField has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] FStrictField modifiers is still 'strict private' got: 'strict private'
      [FAIL] FPrivateField has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] FPrivateField modifiers is still 'private' got: 'private'
      [FAIL] FPublishedField has a 'vis_explicit' field got: FIELD-ABSENT
      [PASS] FPublishedField modifiers is still 'published' got: 'published'
    FAIL

#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-default-section-visibility"
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

$info = (& $Exe info --json 2>$null) -join "`n" | ConvertFrom-Json
Write-Host ("engine: extractor={0} exe={1}" -f $info.extractor_version, $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$work = Join-Path $WorkDir 'fixture'
Write-Ascii (Join-Path $work 'uVis.pas') @'
unit uVis;

interface

type
  TVisKit = class(TObject)
    FDefaultField: Integer;
    procedure DefaultMethod;
  public
    FPublicField: Integer;
  strict private
    FStrictField: Integer;
  private
    FPrivateField: Integer;
  published
    FPublishedField: Integer;
  end;

implementation

procedure TVisKit.DefaultMethod;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'vis.sqlite'
$null = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Get-Member([string]$Name) {
  $raw = (& $Exe query --name $Name --exact --json --db $db 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return @($raw | ConvertFrom-Json) | Select-Object -First 1
}

Write-Host ''
Write-Host 'POSITIVE: the unlabelled default section is distinguishable' -ForegroundColor Cyan
$cases = @(
  @{ Name = 'FDefaultField';   Explicit = $false; Modifiers = 'public'         }
  @{ Name = 'DefaultMethod';   Explicit = $false; Modifiers = 'public'         }
  @{ Name = 'FPublicField';    Explicit = $true;  Modifiers = 'public'         }
  @{ Name = 'FStrictField';    Explicit = $true;  Modifiers = 'strict private' }
  @{ Name = 'FPrivateField';   Explicit = $true;  Modifiers = 'private'        }
  @{ Name = 'FPublishedField'; Explicit = $true;  Modifiers = 'published'      }
)
foreach ($c in $cases) {
  $s = Get-Member $c.Name
  if ($null -eq $s) { Check "$($c.Name) is indexed" $false 'not found'; continue }
  $has = $null -ne ($s.PSObject.Properties.Name | Where-Object { $_ -eq 'vis_explicit' })
  Check "$($c.Name) has a 'vis_explicit' field" $has "got: $(if ($has) { $s.vis_explicit } else { 'FIELD-ABSENT' })"
  if ($has) {
    Check "$($c.Name) vis_explicit = $($c.Explicit)" (([bool]$s.vis_explicit) -eq $c.Explicit) "got: $([bool]$s.vis_explicit)"
  }
  # CONTROL: the visibility word itself must not have moved.
  Check "$($c.Name) modifiers is still '$($c.Modifiers)'" (([string]$s.modifiers).Trim() -eq $c.Modifiers) "got: '$($s.modifiers)'"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
