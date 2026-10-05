<#
  run_impl_only_signature_type_uses.ps1 -- a routine whose HEADER is the only
  place its signature exists must emit type_use refs for its parameter and
  return types (Ref-gap F, extractor 1.21.0 + 1.21.1).

  Why this exists
  ---------------
  Two kinds of routine have no separate declaration that the walk would visit:
    * an implementation-only FREE routine (no interface decl) -- 1.21.0;
    * a NESTED routine (local to a free routine, a method impl, or an
      interface-declared routine) -- 1.21.1. 1.21.0 shipped without it and
      nothing failed, because 1.21.0 shipped without a guard.
  WalkDeclProc emits their SYMBOLS but never REFS, so an imported type used only
  in such a signature had no type_use row, and unused-unit-in-uses called its
  unit a dead import -- a false positive that tells the reader to delete a
  uses entry the compiler needs.

  What is checked
  ---------------
    (a) the exact type_use refs per line on the fixture, nested shapes included;
    (b) no symbol is emitted twice (the args walk must add refs, not params);
    (c) END TO END, lint-all with unused-unit-in-uses:
          * the fixture's types unit is NOT reported;
          * three one-shape units, each using the imported type ONLY in one
            nested signature, are NOT reported;
          * POSITIVE CONTROL: a genuinely unused import IS reported, so this
            guard cannot pass with the rule off or the lint path dead.
  lint-all --json is a bare ARRAY whose position field is start_line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_impl_only_sig_type_uses_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function SqlRows([string]$Db, [string]$Query) {
  $raw = & $Exe sql --db $Db --query $Query --json 2>$null | Out-String
  $j = $raw | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $names.Count; $k++) { $o[$names[$k]] = $r[$k] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}

Write-Host '== impl-only / nested routine signature type_use refs ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
$fix = Join-Path $PSScriptRoot 'fixtures'
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$lib = Join-Path $WorkDir 'lib'
$prj = Join-Path $WorkDir 'prj'
New-Item -ItemType Directory -Force -Path $lib | Out-Null
New-Item -ItemType Directory -Force -Path $prj | Out-Null

Copy-Item (Join-Path $fix 'impl_only_routine_type_uses_types.pas')  $lib
Copy-Item (Join-Path $fix 'impl_only_routine_type_uses_unused.pas') $lib
Copy-Item (Join-Path $fix 'impl_only_routine_type_uses.pas')        $prj

# One unit per nested shape, each using TImportedType ONLY in that signature,
# so the end-to-end check isolates the 1.21.1 arm from the 1.21.0 one.
Write-Ascii (Join-Path $prj 'uNestedInFree.pas') @'
unit uNestedInFree;

interface

implementation

uses
  impl_only_routine_type_uses_types;

procedure Outer;
  procedure Inner(P: TImportedType);
  begin
  end;
begin
end;

end.
'@

Write-Ascii (Join-Path $prj 'uNestedInMethod.pas') @'
unit uNestedInMethod;

interface

type
  TThing = class(TObject)
    procedure Run;
  end;

implementation

uses
  impl_only_routine_type_uses_types;

procedure TThing.Run;
  procedure Inner(P: TImportedType);
  begin
  end;
begin
end;

end.
'@

Write-Ascii (Join-Path $prj 'uNestedInIface.pas') @'
unit uNestedInIface;

interface

procedure Outer;

implementation

uses
  impl_only_routine_type_uses_types;

procedure Outer;
  function Inner: TImportedType;
  begin
    Result := nil;
  end;
begin
end;

end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'
$prjDb = Join-Path $WorkDir 'prj.sqlite'
& $Exe index $lib --db $libDb 2>&1 | Out-Null
& $Exe index $prj --db $prjDb 2>&1 | Out-Null

# --- (a) exact type_use refs per line on the fixture -------------------------
$refs = SqlRows $prjDb ("SELECT r.name_text AS n, r.start_line AS l FROM refs r JOIN files f ON f.id = r.file_id " +
                        "WHERE f.path LIKE '%impl_only_routine_type_uses.pas' AND r.kind = 'type_use' ORDER BY r.start_line, r.name_text")
$got = ($refs | ForEach-Object { '{0}:{1}' -f $_.l, $_.n }) -join ' '
# 22 TObject (class ancestor), 58 TLocalType (method-impl qualifier, Ref-gap E):
# pre-existing rows, pinned so a duplicate or a loss anywhere shows up here.
$want = '22:TObject 29:TImportedType 36:TImportedType 36:TImportedType 36:TImportedType ' +
        '42:TImportedType 42:TImportedType 49:TImportedType 58:TLocalType 59:TImportedType 69:TImportedType'
Check 'fixture type_use refs are exactly the expected set' ($got -eq $want) "got=[$got]"
foreach ($ln in 49, 59, 69) {
  Check "nested routine signature at line $ln emits ONE type_use TImportedType" `
    (@($refs | Where-Object { $_.l -eq $ln -and $_.n -eq 'TImportedType' }).Count -eq 1)
}

# --- (b) no duplicate symbols --------------------------------------------------
$dups = SqlRows $prjDb ("SELECT s.qualified_name AS q, s.start_line AS l, count(*) AS c FROM symbols s " +
                        "GROUP BY s.qualified_name, s.start_line, s.kind HAVING count(*) > 1")
Check 'no symbol is emitted twice' ($dups.Count -eq 0) (($dups | ForEach-Object { "$($_.q)@$($_.l)x$($_.c)" }) -join ', ')
$params = SqlRows $prjDb ("SELECT s.qualified_name AS q FROM symbols s JOIN files f ON f.id = s.file_id " +
                          "WHERE f.path LIKE '%impl_only_routine_type_uses.pas' AND s.kind = 'param' ORDER BY s.start_line, s.qualified_name")
Check 'fixture param symbols unchanged (6: Param1-3, Callback, P, Q)' ($params.Count -eq 6) "count=$($params.Count)"

# --- (c) end to end: unused-unit-in-uses --------------------------------------
$lintRaw = & $Exe lint-all --db $prjDb --db $libDb --rule unused-unit-in-uses --json 2>$null | Out-String
$findings = @()
try { $findings = @($lintRaw | ConvertFrom-Json) } catch { $findings = @() }
$uuiu = @($findings | Where-Object { $_.rule -eq 'unused-unit-in-uses' })
$typesHits  = @($uuiu | Where-Object { $_.message -match "'impl_only_routine_type_uses_types'" })
$unusedHits = @($uuiu | Where-Object { $_.message -match "'impl_only_routine_type_uses_unused'" })

Check 'POSITIVE CONTROL: the genuinely unused import IS reported' `
  (($unusedHits.Count -eq 1) -and ($unusedHits[0].start_line -eq 19) -and ($unusedHits[0].file_path -match 'impl_only_routine_type_uses\.pas$')) `
  "hits=$($unusedHits.Count) line=$(if ($unusedHits.Count) { $unusedHits[0].start_line })"
Check 'a unit used only in impl-only / nested signatures is NOT reported' `
  ($typesHits.Count -eq 0) (($typesHits | ForEach-Object { "$(Split-Path $_.file_path -Leaf):$($_.start_line)" }) -join ', ')
Check 'the rule reported exactly the control finding and nothing else' `
  ($uuiu.Count -eq 1) "count=$($uuiu.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'IMPL-ONLY SIGNATURE TYPE_USES GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'IMPL-ONLY SIGNATURE TYPE_USES GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\draglint_impl_only_sig_type_uses_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
