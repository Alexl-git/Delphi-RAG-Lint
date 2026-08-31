<#
  run_lint_duplicate_global_decl.ps1 -- docs\PLAN-coupling-census-and-duplicate-decls.md
  (owner request 2026-08-30).

  THE DEFECT CLASS, in the owner's words: "Const declared in 2 different units
  is often my mistake. I don't know why it is not a syntax error." It is not an
  error because Delphi resolves an unqualified name through the uses clause in
  REVERSE order, current unit first -- so ADDING or REORDERING a uses entry
  silently changes which declaration compiles, and the compiler says nothing.

  REPORTED ALWAYS, NOT ONLY WHEN THE VALUES DIFFER, and that decision came from
  measurement rather than taste. All 11 real findings on ORM3 are byte-identical
  after normalization, so a differ-only rule would ship SILENT on the exact
  corpus that motivated the request. Two identical copies are still a hazard --
  a uses reorder swaps which one you get, and they are only identical UNTIL
  someone edits one of them. Differing declarations are strictly worse, so they
  escalate the MESSAGE, not the severity.

  THE NORMALIZATION CONTROL IS THE ONE THAT CAUGHT SOMETHING. Raw string
  comparison of the 11 real signatures says 1 of them differs -- tbltdistrcount,
  'integer' in BASICS.PAS against 'Integer' in Z19b5.pas. A case difference is
  not a semantic difference, and reporting it as one would have taught the
  reader to distrust the escalation. CNorm pins that.

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dupdecl"
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
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# --- A: carries one half of every pair, plus the names that must stay silent.
Emit 'uDupA.pas' @'
unit uDupA;
interface
const
  CDup      = 7;
  COnlyHere = 99;
  CSame     = 5;
  CDiff     = 1;
  CNorm: integer = 5;
type
  TCarrier = class
  public
    const CMember = 3;
  end;
  TDupArr = array [1 .. 10] of Integer;
  TDupRec = record
    X: Integer;
  end;
var
  gDup     : Integer;
  gImplOnly: Integer;
procedure DupProc;
procedure Register;
implementation
procedure DupProc;
begin
end;
procedure Register;
begin
end;
end.
'@

# --- B: the other half. CMember is a CLASS const here too -- the parent gate
#     is what keeps that silent, not luck.
Emit 'uDupB.pas' @'
unit uDupB;
interface
const
  CDup  = 7;
  CSame = 5;
  CDiff = 2;
  CNorm: Integer = 5;
type
  TOther = class
  public
    const CMember = 4;
  end;
  TDupArr = array [1 .. 20] of Integer;
  TDupRec = record
    X: Integer;
  end;
var
  gDup: Integer;
procedure DupProc;
procedure Register;
implementation
const
  gImplOnly = 1;
procedure DupProc;
begin
end;
procedure Register;
begin
end;
end.
'@

# --- THE CAP. Eight units declaring one name, so the message must stop
#     enumerating and say how many it elided. Widening the rule to routines on
#     2026-08-31 produced a real finding that printed 134 absolute paths in a
#     single message; a report line nobody can read is the same defect as a
#     rule that floods, it just arrives as one row instead of many.
foreach ($i in 1..8) {
  Emit "uMany$i.pas" @"
unit uMany$i;
interface
const
  CManySites = $i;
implementation
end.
"@
}

# --- COPY control. An Explorer copy of a unit would otherwise fabricate a
#     duplicate of EVERY unit-level name it contains. Measured 2026-08-30: the
#     re-indexed ORM3 DBs contain zero '- Copy' files, so the corpus cannot
#     prove this clause works -- only a fixture can, which is why one is here.
Emit 'uDupA - Copy.pas' @'
unit uDupACopy;
interface
const
  CCopyOnly = 42;
implementation
end.
'@

# --- configs ---------------------------------------------------------------
$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOn,  '{ }', [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgOff, '{ "disabled": [ "duplicate-global-decl" ] }',
                               [System.Text.Encoding]::ASCII)

# --- index -----------------------------------------------------------------
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecDup", "db": "dup.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\dup.sqlite'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecDup --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut  = & $Exe lint-all --db $db --config $cfgOn  --quiet 2>&1 | Out-String
  $offOut = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
} finally { Pop-Location }

$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'duplicate-global-decl' })
function DupFor([string]$name) {
  @($lines | Where-Object { $_ -match ("(?i)\b" + [regex]::Escape($name) + "\b") })
}

Write-Host ''
Write-Host 'THE FINDING' -ForegroundColor Cyan
$cdup = DupFor 'CDup'
Check 'POSITIVE const: CDup is reported exactly once' ($cdup.Count -eq 1) `
  ("got " + $cdup.Count + " line(s) of " + $lines.Count + " total")
Check 'and the finding names BOTH declaring sites' `
  ((($cdup -join ' ') -match 'uDupA\.pas') -and (($cdup -join ' ') -match 'uDupB\.pas')) `
  'one site alone does not tell the reader what collides with what'
Check 'and it says the kind is a const' `
  (($cdup -join ' ') -match '(?i)const') ''
$gdup = DupFor 'gDup'
Check 'POSITIVE var: gDup is reported' ($gdup.Count -eq 1) `
  ("got " + $gdup.Count + " line(s)")
Check 'and it says the kind is a var' `
  (($gdup -join ' ') -match '(?i)\bvar\b') ''

Write-Host ''
Write-Host 'IDENTICAL vs DIFFERING -- the message escalates, the severity does not' -ForegroundColor Cyan
$same = DupFor 'CSame'
$diff = DupFor 'CDiff'
Check 'the identical pair is reported' ($same.Count -eq 1) ("got " + $same.Count)
Check 'and says the declarations are identical' `
  (($same -join ' ') -match '(?i)identical') ''
Check 'and does NOT carry the differ escalation' `
  (-not (($same -join ' ') -match 'DIFFER')) `
  'an unconditional escalation would prove nothing'
Check 'the differing pair is reported' ($diff.Count -eq 1) ("got " + $diff.Count)
Check 'and DOES carry the differ escalation' `
  (($diff -join ' ') -match 'DIFFER') `
  'differing declarations are the strictly worse case and must read that way'
Check 'both stay at warning -- the escalation is textual only' `
  ((($same -join ' ') -match '\[warning\]') -and (($diff -join ' ') -match '\[warning\]')) ''

Write-Host ''
Write-Host 'CONTROLS -- each one is a way the rule can be wrong' -ForegroundColor Cyan
Check 'NORMALIZATION: integer vs Integer is reported, NOT escalated' `
  (((DupFor 'CNorm').Count -eq 1) -and (-not (((DupFor 'CNorm') -join ' ') -match 'DIFFER'))) `
  'RED means the value compare is raw-string -- the tbltdistrcount lesson'
Check 'SINGLE DECL: a name declared once is never reported' `
  ((DupFor 'COnlyHere').Count -eq 0) ''
Check 'SECTION: interface in one unit, implementation in the other -> SILENT' `
  ((DupFor 'gImplOnly').Count -eq 0) `
  'an implementation const is not exported, so nothing collides'
Check 'CLASS MEMBER: a class const of the same name -> SILENT' `
  ((DupFor 'CMember').Count -eq 0) `
  'RED means the parent gate is gone and every class const collides'
Check 'COPY: a - Copy.pas twin fabricates no duplicates' `
  ((DupFor 'CCopyOnly').Count -eq 0) `
  'and CDup above is the positive control for this same run'

Write-Host ''
Write-Host 'KINDS -- uses order decides a TYPE exactly as it decides a var' -ForegroundColor Cyan
# The gate was ('const','var') until 2026-08-31. The owner's report was about
# importing a global TYPE that already existed elsewhere, and the rule's own
# message -- "which one compiles depends on uses order" -- is exactly as true of
# a type, a record or a routine. Measured on ORM3 before widening: the rule saw
# 10 of 28 duplicated interface names on CLIENT and 10 of 26 on SERVER.
$dupArr  = DupFor 'TDupArr'
$dupRec  = DupFor 'TDupRec'
$dupProc = DupFor 'DupProc'
Check 'TYPE: a duplicated array type is reported' ($dupArr.Count -eq 1) `
  ("got " + $dupArr.Count)
Check 'and a DIFFERING type declaration still escalates' `
  (($dupArr -join ' ') -match 'DECLARATIONS DIFFER') `
  'array [1..10] vs array [1..20] is the ORM3 TARecTDistr shape -- 500 vs 100'
Check 'RECORD: a duplicated record is reported' ($dupRec.Count -eq 1) `
  ("got " + $dupRec.Count)
Check 'ROUTINE: a duplicated top-level procedure is reported' ($dupProc.Count -eq 1) `
  ("got " + $dupProc.Count)

Write-Host ''
Write-Host 'CONTROLS FOR THE WIDENING -- what it must NOT do' -ForegroundColor Cyan
Check 'REGISTER: Delphi''s registration protocol name -> SILENT' `
  ((DupFor 'Register').Count -eq 0) `
  'every design-time unit must declare `procedure Register`; ORM3 has 134 of them'
$many = DupFor 'CManySites'
Check 'CAP: a name in 8 units is reported once' ($many.Count -eq 1) `
  ("got " + $many.Count)
Check 'and the message ELIDES the tail instead of printing every site' `
  (($many -join ' ') -match 'and \d+ more') `
  'RED means one finding can render an unreadable wall of paths again'
Check 'and it still states the true unit count' `
  (($many -join ' ') -match 'in 8 units') `
  'the cap must shorten the ENUMERATION, never the count the reader acts on'

Write-Host ''
Write-Host 'OFF SWITCH' -ForegroundColor Cyan
Check 'a disabling config reports nothing' `
  (-not ($offOut -match 'duplicate-global-decl')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' `
  ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
