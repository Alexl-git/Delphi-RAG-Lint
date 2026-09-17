<#
  run_context_record_surface.ps1 --
  The `## Class surface` of a RECORD must list EVERY field, in lean mode,
  without `--full-surface`.

  THE DEFECT (measured 2026-09-17 on the self-index).
    context --task "modify TTypeAncestor" --db src\cli\_D-RAG\drag-lint.sqlite
  printed a surface of ONE field (`Ordinal : Integer; // ...`) followed by the
  `///` doc comments of the other fields with the declarations they document
  MISSING -- Name, Kind, Resolved, SymbolId, FileId, ResolvedName, TypeArgs
  were all gone, and the doc text for ResolvedName/TypeArgs sat orphaned above
  MatchesName. The reader's fallback is to open the whole unit, which is the
  cost the bundle exists to avoid.

  WHY IT EXISTED. The lean-surface filter (StripDfmFields) exists to drop the
  hundreds of auto-generated `Button1: TButton;` component fields a FORM class
  streams from its .dfm. It starts with InPublished = True (a $M+ form's
  default section is published) and drops every `Ident: TType;` line in that
  section -- and it was applied to EVERY surface, a record's included. A record
  has no visibility specifier, so all of its fields sit in the "default"
  section and every one of them looked like a component field. Ordinal alone
  survived because its trailing `// comment` stops the line ending in ';'.

  THE FIX. The filter is applied only when the surface's OWNER is a CLASS. A
  record (or an interface) is never DFM-streamed, so nothing in it is noise.

  THE CONTROLS, and what each rules out:
    * a FORM-like class still has its component fields stripped in lean mode,
      while a plain field in its PUBLIC section is kept (the surface is built
      with AAllVisibility=False, so a private one would be absent by design)
      -> the fix did not simply switch the filter off
    * the same form with --full-surface shows them
      -> the switch still works
    * a METHOD target on the record lists the record's fields too
      -> the owner-kind check works on the parent-lookup path, not only when
         the target IS the type
    * an invented member is absent
      -> the substring assertions are not vacuous

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_record_surface"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# TPayload: four fields, two documented with ///, two not, plus one method.
# TMainForm: a form-shaped class whose default section holds component fields
# -- the thing the lean filter exists to strip.
Write-Ascii (Join-Path $src 'uRec.pas') @"
unit uRec;

interface

type
  TPayload = record
    Alpha: Integer;
    /// <summary>Documented beta.</summary>
    Beta: string;
    Gamma: Boolean;
    /// <summary>Documented delta.</summary>
    Delta: Int64;
    function Describe: string;
  end;

  TMainForm = class(TForm)
    Button1: TButton;
    Edit1: TEdit;
    procedure Button1Click(Sender: TObject);
  public
    FCount: Integer;
    procedure Refresh;
  end;

implementation

function TPayload.Describe: string;
begin
  Result := Beta;
end;

procedure TMainForm.Button1Click(Sender: TObject);
begin
  FCount := FCount + 1;
end;

procedure TMainForm.Refresh;
begin
  FCount := 0;
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# Returns the `## Class surface` section only (the call operator, not
# Start-Process -- see run_context_bare_name_body.ps1).
function Surface([string]$Task, [switch]$Full) {
  $extra = @()
  if ($Full) { $extra = @('--full-surface') }
  $out = ((& $exePath context --task $Task --db $db --format markdown @extra 2>$null) -join "`n")
  if ($out -match '(?s)## Class surface(.*?)(\n## |\z)') { return $Matches[1] }
  return ''
}
function HasField([string]$Text, [string]$Name, [string]$Type) {
  return [bool]($Text -match ('(?m)^\s*' + $Name + '\s*:\s*' + $Type + '\s*;'))
}

# ---- T1: the defect (type target) -------------------------------------------
$rec = Surface 'modify uRec.TPayload'
Check 'V the record target has a Class surface section' ($rec -ne '') 'no surface at all -- run_context_type_surface.ps1 territory'
Check 'T1a undocumented field Alpha is listed'  (HasField $rec 'Alpha' 'Integer') ($rec -replace "`n", ' / ')
Check 'T1b documented field Beta is listed'     (HasField $rec 'Beta'  'string')  ($rec -replace "`n", ' / ')
Check 'T1c undocumented field Gamma is listed'  (HasField $rec 'Gamma' 'Boolean') ($rec -replace "`n", ' / ')
Check 'T1d documented field Delta is listed'    (HasField $rec 'Delta' 'Int64')   ($rec -replace "`n", ' / ')
Check 'T1e the method Describe is listed too'   ($rec -match 'function Describe') ($rec -replace "`n", ' / ')
Check 'T1f CONTROL an invented member is absent (the match is not vacuous)' (-not ($rec -match 'ZzNotAMember')) ''

# ---- T2: the same fix on the parent-lookup path (method target) -------------
$mth = Surface 'modify uRec.TPayload.Describe'
Check 'T2 a METHOD target on the record lists all four fields in its owner surface' `
      ((HasField $mth 'Alpha' 'Integer') -and (HasField $mth 'Beta' 'string') -and (HasField $mth 'Gamma' 'Boolean') -and (HasField $mth 'Delta' 'Int64')) `
      ($mth -replace "`n", ' / ')

# ---- T3: the form-class positive control -- lean mode still strips ----------
$lean = Surface 'modify uRec.TMainForm'
Check 'P1 POSITIVE CONTROL a form-like class still has Button1/Edit1 STRIPPED in lean mode' `
      (($lean -ne '') -and -not (HasField $lean 'Button1' 'TButton') -and -not (HasField $lean 'Edit1' 'TEdit')) `
      ($lean -replace "`n", ' / ')
Check 'P1b and keeps its handler, its PUBLIC plain field and its public method' `
      (($lean -match 'Button1Click') -and (HasField $lean 'FCount' 'Integer') -and ($lean -match 'procedure Refresh')) `
      ($lean -replace "`n", ' / ')
$full = Surface 'modify uRec.TMainForm' -Full
Check 'P2 POSITIVE CONTROL --full-surface shows the component fields again' `
      ((HasField $full 'Button1' 'TButton') -and (HasField $full 'Edit1' 'TEdit')) `
      ($full -replace "`n", ' / ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
