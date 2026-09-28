<#
  run_doc_unit_name_extension_segment.ps1 --
  A `Used in units:` entry that is a dotted UNIT NAME ending in a segment spelled
  like a file extension (`Fx.Parser.DFM`) is keyed as that unit, not stripped.

  THE DEFECT (filed 2026-09-24, INBOX-entryunitkey-strips-unit-name-suffix;
  reproduced 2026-09-28 on 1.19.1-alpha). Doc.SharedFacts.EntryUnitKey dropped a
  trailing `.pas` / `.dpr` / `.dfm` from EVERY entry as if it were a file name,
  so `DRagLint.Parser.DFM` keyed `draglint.parser` -- a unit no closure holds.
  The entry then read as FOREIGN (written by a project this index cannot see):
    * the block entered the project-tag regime although the unit is unshared
      (`Used in units: [FxApp]Fx.Other, ...`);
    * a STALE entry naming that unit -- the unit is indexed and no longer uses
      the type -- was preserved forever instead of reaped.

  THE FIX. The extension is dropped only from a FILE form: the `(file.pas)`
  part of an entry, or a path. A bare entry is a unit name.

  THE CONTROLS, and what each rules out:
    * P1 a stale entry naming an ordinary indexed unit (`Fx.Parser.Plain`) is
      reaped -> the reaping path runs in this fixture at all
    * P2 a stale entry naming a unit this index does NOT hold, spelled with the
      same `.DFM` segment (`Fx.Elsewhere.DFM`), is still PRESERVED -> the fix did
      not make every dotted name vouchable (that direction deletes facts)
    * P3 the live entry `Fx.Other` is kept

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_doc_unit_ext_segment_$PID"
)
try {
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

# Fx.Core.TThing's stored block names four units. Only Fx.Other still uses it.
# Fx.Parser.DFM and Fx.Parser.Plain are indexed members that stopped using it
# (stale, reapable). Fx.Elsewhere.DFM is not in this closure at all (foreign).
Write-Ascii (Join-Path $src 'Fx.Core.pas') @'
unit Fx.Core;

interface

type
  /// <summary>A thing.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (Fx.Other.pas)</para>
  /// <para>Used in units: Fx.Other, Fx.Parser.DFM, Fx.Parser.Plain</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TThing = class
  public
    procedure Go;
  end;

  /// <summary>Another thing.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (Fx.Other.pas)</para>
  /// <para>Used in units: Fx.Elsewhere.DFM, Fx.Other</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOther = class
  end;

implementation

procedure TThing.Go;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'Fx.Parser.DFM.pas') @'
unit Fx.Parser.DFM;

interface

procedure P;

implementation

procedure P;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'Fx.Parser.Plain.pas') @'
unit Fx.Parser.Plain;

interface

procedure P2;

implementation

procedure P2;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'Fx.Other.pas') @'
unit Fx.Other;

interface

uses Fx.Core;

procedure Q(const AThing: TThing; const AOther: TOther);

implementation

procedure Q(const AThing: TThing; const AOther: TOther);
begin
  AThing.Go;
end;

end.
'@
Write-Ascii (Join-Path $src 'FxApp.dpr') @'
program FxApp;

uses
  Fx.Core in 'Fx.Core.pas',
  Fx.Parser.DFM in 'Fx.Parser.DFM.pas',
  Fx.Parser.Plain in 'Fx.Parser.Plain.pas',
  Fx.Other in 'Fx.Other.pas';

begin
end.
'@

$db = Join-Path $WorkDir 'FxApp.sqlite'
& $exePath index --project (Join-Path $src 'FxApp.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# Apply and read the FILE back: a dry run prints only the blocks it would EDIT,
# so a preserved block (the P2 control) would be invisible in its output.
$core = Join-Path $src 'Fx.Core.pas'
& $exePath document --unit $core --db $db --apply --no-backup 2>&1 | Out-Null
$out = [IO.File]::ReadAllText($core)
$units = @([regex]::Matches($out, 'Used in units: ([^<]*)</para>') | ForEach-Object { $_.Groups[1].Value.Trim() })
Check 'V the unit still holds both blocks (two Used-in-units lines)' ($units.Count -eq 2) ($units -join ' | ')
$thing = if ($units.Count -ge 1) { $units[0] } else { '' }
$other = if ($units.Count -ge 2) { $units[1] } else { '' }

Check 'T1 the stale entry Fx.Parser.DFM (an indexed unit) is reaped' (-not ($thing -match 'Fx\.Parser\.DFM')) $thing
Check 'T2 the unshared block does not enter the project-tag regime' (-not ($thing -match '\[')) $thing
Check 'P1 POSITIVE CONTROL the stale ordinary entry Fx.Parser.Plain is reaped' (-not ($thing -match 'Fx\.Parser\.Plain')) $thing
Check 'P3 the live entry Fx.Other is kept' ($thing -match 'Fx\.Other') $thing
Check 'P2 NEGATIVE CONTROL a .DFM-named unit NOT in this closure is still preserved' ($other -match 'Fx\.Elsewhere\.DFM') $other

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_doc_unit_ext_segment_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
