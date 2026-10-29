<#
  run_reftype_refs.ps1 -- lane REFTYPE (gaps wave, 2026-10-27).

  A type named ONLY inside a procedural / anonymous-method type declaration
  (`T = reference to function(..): X`, `T = procedure(..) of object`), or as the
  element of a `set of` / `array of` / `class of` type declaration, emitted NO
  type_use ref: TryWalkProcType and TryWalkOtherTypeDecl emitted the symbol and
  Exit'ed the dispatch without walking the signature. uses-audit then called the
  declaring unit movable to the implementation section (the real case:
  DRagLint.Analysis.LintTree.pas `TStoreOpener = reference to function(..):
  ISymbolStore` and DRagLint.Core.Interfaces).

  Indexes tests\index\reftype\uRefTypeProbe.pas + uRefTypeDefs.pas into a temp
  DB and asserts, per { M-... } marker line (never a line number), one type_use
  ref for every expected name. POSITIVE CONTROLS: the field / const / var /
  method shapes that already worked stay asserted, so a runner that cannot see
  refs fails them too. NEGATIVE: a parameter NAME (pA) is never a type_use, and
  no type name gets two type_use rows on one marker line (no double emission).
  Finally uses-audit on the probe must NOT offer uRefTypeDefs as movable.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-reftype-refs-$PID"
)
try {
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
$py  = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { Write-Host 'FATAL: python not on PATH' -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\index\reftype\*.pas') $SrcDir
$probe = Join-Path $SrcDir 'uRefTypeProbe.pas'

$db = Join-Path $WorkDir 'reftype.sqlite'
& $Exe index $SrcDir --db $db 2>&1 | Out-Null

# marker -> type names that must carry a type_use ref on that line
$expect = [ordered]@{
  'M-REFFUNC'   = @('TRtParamA', 'TRtResA')
  'M-REFPROC'   = @('TRtParamB')
  'M-METHFUNC'  = @('TRtParamC', 'TRtResC')
  'M-PLAINPROC' = @('TRtParamD')
  'M-GENRES'    = @('TFunc', 'TRtGenE')
  'M-GENPARAM'  = @('TProc', 'TRtGenF')
  'M-OPENARR'   = @('TRtOpenG')
  'M-DEFAULT'   = @('TRtDefH')
  'M-ARRRES'    = @('TArray', 'TRtArrI')
  'M-SETOF'     = @('TRtSetO')
  'M-ARROF'     = @('TRtArrP')
  'M-IDXARR'    = @('TRtIdxQ', 'TRtElemQ')
  'M-CLASSOF'   = @('TRtClsR')
  'M-NESTGEN'   = @('TRtGenS', 'TRtArgS')
  # positive controls -- shapes that already emitted before the fix
  'M-FIELD'     = @('TRtFieldJ')
  'M-METHOPEN'  = @('TRtOpenK')
  'M-METHDEF'   = @('TRtDefL', 'TRtResL')
  'M-CONST'     = @('TRtConstM')
  'M-VAR'       = @('TRtVarN', 'TRtVarResN')
}

$pyFile = Join-Path $WorkDir 'rt.py'
@'
import sqlite3, sys, json
db, probe, fname = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(probe, encoding='ascii').read().split('\n')
c = sqlite3.connect(db)
c.row_factory = sqlite3.Row
markers = {}
for i, l in enumerate(lines):
    p = l.find('{ M-')
    if p >= 0:
        markers[l[p + 2:l.index(' }', p)]] = i + 1
q = ("select r.start_line as line, r.kind as kind, r.name_text as name from refs r "
     "join files f on f.id = r.file_id where f.path like ?")
rows = [dict(r) for r in c.execute(q, ('%' + fname,))]
print(json.dumps({'markers': markers, 'rows': rows}))
'@ | Set-Content -Encoding ascii $pyFile
$data = (& python -I $pyFile $db $probe 'uRefTypeProbe.pas' | Out-String) | ConvertFrom-Json

$tu = @($data.rows | Where-Object { $_.kind -eq 'type_use' })
Check 'probe indexed (type_use rows present)' ($tu.Count -gt 0) "rows=$($tu.Count)"
foreach ($m in $expect.Keys) {
  $line = $data.markers.$m
  if (-not $line) { Check "$m marker found" $false; continue }
  foreach ($n in $expect[$m]) {
    $hits = @($tu | Where-Object { $_.line -eq $line -and $_.name -eq $n })
    Check "$m type_use $n" ($hits.Count -eq 1) "line=$line hits=$($hits.Count)"
  }
}
$paramHits = @($tu | Where-Object { $_.name -match '^p[A-Z]$' })
Check 'no parameter NAME is a type_use' ($paramHits.Count -eq 0) "hits=$($paramHits.Count)"

# uRefTypeOnly uses uRefTypeOnlyDefs ONLY in `reference to function(..): TRtOnly`.
# Before the fix uses-audit returned [{"unit":"uRefTypeOnlyDefs","verdict":"unused",..}].
$auditRaw = (& $Exe uses-audit (Join-Path $SrcDir 'uRefTypeOnly.pas') --db $db --format json 2>$null | Out-String)
$audit = @($auditRaw | ConvertFrom-Json)
Check 'uses-audit returned a JSON array' ($auditRaw.Trim().StartsWith('[')) $auditRaw.Trim()
$flagged = @($audit | Where-Object { $_.unit -eq 'uRefTypeOnlyDefs' })
Check 'uses-audit keeps uRefTypeOnlyDefs (signature-only use)' ($flagged.Count -eq 0) $auditRaw.Trim()

# ---- part 2: names used ONLY in initializer / bound / default-VALUE / attribute
# positions (uRefInitProbe.pas). Any ref kind counts (read, type_use, attribute);
# EXACTLY one row per name and line, so a fix that double-emits fails here.
$initExpect = [ordered]@{
  'M-UNTYPED'  = @('RiA')
  'M-TYPED'    = @('RiB')
  'M-ARRAY'    = @('RiC1', 'RiC2')
  'M-RECORD'   = @('RiD')
  'M-DEFVAL'   = @('RiF')
  'M-FREEDEF'  = @('RiF')
  'M-ENUMVAL'  = @('RiH')
  'M-RESSTR'   = @('RiS')
  'M-VARINIT'  = @('RiJ')
  # positive controls -- shapes that already emitted before the fix
  'M-SUBRANGE' = @('RiLo', 'RiHi')
  'M-ARRBOUND' = @('RiLo2', 'RiHi2')
  'M-ATTR'     = @('RiAttr', 'RiG')
  'M-EXPR'     = @('RiE')
  'M-SIZEOF'   = @('TRiSz')
  'M-SET'      = @('riK1', 'riK2')
}
$initProbe = Join-Path $SrcDir 'uRefInitProbe.pas'
$idata = (& python -I $pyFile $db $initProbe 'uRefInitProbe.pas' | Out-String) | ConvertFrom-Json
Check 'init probe indexed (rows present)' (@($idata.rows).Count -gt 0) "rows=$(@($idata.rows).Count)"
foreach ($m in $initExpect.Keys) {
  $line = $idata.markers.$m
  if (-not $line) { Check "$m marker found" $false; continue }
  foreach ($n in $initExpect[$m]) {
    $hits = @($idata.rows | Where-Object { $_.line -eq $line -and $_.name -eq $n })
    Check "$m ref $n" ($hits.Count -eq 1) "line=$line hits=$($hits.Count) kinds=$((@($hits | ForEach-Object kind)) -join ',')"
  }
}
# NEGATIVE: a declared NAME (the const / enum value / param being declared) is not a ref.
$declHits = @($idata.rows | Where-Object { $_.name -in @('CRiUntyped', 'CRiTyped', 'roA', 'SRiMsg', 'GRiInit', 'pX', 'pY') -and $_.line -lt $idata.markers.'M-FREEDEF' + 1 })
Check 'no declared name in an initializer line is a ref' ($declHits.Count -eq 0) "hits=$($declHits.Count)"

# uRefInitOnly uses uRefInitOnlyDefs ONLY in `CInitOnly = RiOnly;` (the CLI.pas:69 shape).
$iaRaw = (& $Exe uses-audit (Join-Path $SrcDir 'uRefInitOnly.pas') --db $db --format json 2>$null | Out-String)
Check 'uses-audit (init) returned a JSON array' ($iaRaw.Trim().StartsWith('[')) $iaRaw.Trim()
$iflag = @(@($iaRaw | ConvertFrom-Json) | Where-Object { $_.unit -eq 'uRefInitOnlyDefs' })
Check 'uses-audit keeps uRefInitOnlyDefs (initializer-only use)' ($iflag.Count -eq 0) $iaRaw.Trim()

if ($script:Failed) { Write-Host 'run_reftype_refs: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_reftype_refs: PASS' -ForegroundColor Green; exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
