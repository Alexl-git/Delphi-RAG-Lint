<#
run_lint_dependent_project_not_recompiled.ps1 -- R2's guard.

WHAT THE RULE DOES. A unit marked `dl:shared` is compiled by more than one
project. Edit it, build the project you have open, and the OTHER projects still
hold object code for the old text -- with no error anywhere, because nothing in
either build knows the other exists.

WHY THIS GUARD NEEDS A REAL COMPILER, and cannot be faked. The staleness stamp
`files.last_compiled_unix` is written ONLY by `refresh-findings`, and only on
its NON-FAILURE path -- a compile that errors deliberately records findings
WITHOUT stamping. There is no read-only verb that sets it, so a positive case
needs a project that genuinely builds. Without dcc this SKIPS, loudly, the same
way run_lint_tree_compile_shadow.ps1 does.

TWO DIVERGENCES FROM docs\INDEX-SCHEMA.md:174 ARE ASSERTED HERE ON PURPOSE, so
that "fixing" the rule to match the schema doc turns this red:

  * staleness compares against the CURRENT DISK mtime, not the stored
    mtime_unix. The edit below happens WITHOUT reindexing project A, so the two
    clocks disagree -- and the rule must still fire. Comparing the stored mtime
    would call a just-edited file current, going quiet exactly when it has
    something to say.
  * a NULL stamp is SILENT, not stale. ProjC is indexed and never compiled, so
    its stamp is NULL. Reporting it would flood a fresh checkout with findings
    about work nobody has done yet.

THE SKIP IS TIED TO THE COMPILE, NOT TO THE FINDING COUNT, and that correction
is the most useful thing in this file. The first version skipped whenever the
lint produced no rows -- which cannot tell "the fixture never compiled" from
"the rule went silent because it is wrong". Measured: the mutation that makes
staleness read the STORED mtime silences the rule, and that version EXITED 0
on it. `refresh-findings --json` reports `stamped`, so the skip now depends on
whether the fixture reached the state under test, and a stamped fixture that
produces no rows is a FAILURE.

MUTATION RESULTS, MEASURED 2026-09-10 against the finished rule:

  M1 staleness compares against the STORED mtime -> the CONTROL and both POS
     rows (only after the skip was tightened; before that it exited 0)
  M2 a NULL stamp is treated as STALE            -> the ProjC NEG only

THE SIBLING RESOLVER READS A MANIFEST, which is why this writes its own and
passes --config: without it the resolver would read the MACHINE's manifest,
find no section called ProjB, return nil, and the rule would be silent for a
reason that has nothing to do with the code under test.

A PROJECT SECTION'S DB IS DERIVED, not declared -- <project folder>\_D-RAG\
<project file base>.sqlite, the 2026-08-11 one-db-per-project layout. Writing a
"db" key instead produces a manifest that loads and indexes nothing.

Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
if (-not (Test-Path $dcc)) {
  Write-Host "[SKIP] dcc32 not found at $dcc -- the compiled-at stamp can only be written by a real compile"
  exit 0
}

$work = Join-Path $env:TEMP ("dl-depproj-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# The shared unit. The marker goes on the `unit` line and names the three
# projects that compile it -- see DRagLint.Lint.SharedUnit for why the set is
# written down rather than derived.
function WriteShared([int]$n){
  W (Join-Path $work 'SharedThing.pas') @(
    'unit SharedThing;   // dl:shared ProjA, ProjB, ProjC','',
    'interface','',
    'function Answer: Integer;','',
    'implementation','',
    'function Answer: Integer;','begin',"  Result:= $n;",'end;','','end.')
}
WriteShared 1

foreach ($p in 'ProjA','ProjB','ProjC') {
  W (Join-Path $work "$p.dpr") @(
    "program $p;",'{$APPTYPE CONSOLE}','uses','  SharedThing in ''SharedThing.pas'';',
    'begin','  Writeln(Answer);','end.')
  W (Join-Path $work "$p.dproj") @(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
    '  <PropertyGroup><MainSource>' + $p + '.dpr</MainSource><Platform>Win32</Platform></PropertyGroup>',
    '  <ItemGroup><DCCReference Include="SharedThing.pas"/></ItemGroup>',
    '</Project>')
}

$cfg = Join-Path $work 'manifest.drag-lint.json'
$esc = $work.Replace('\','\\')
W $cfg @(
  '{',
  '  "settings": { "defaultPlatform": "Win32", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },',
  '  "indexes": {',
  '    "sections": [',
  ('      { "name": "ProjA", "include": ["' + $esc + '\\ProjA.dproj"] },'),
  ('      { "name": "ProjB", "include": ["' + $esc + '\\ProjB.dproj"] },'),
  ('      { "name": "ProjC", "include": ["' + $esc + '\\ProjC.dproj"] }'),
  '    ]',
  '  }',
  '}')

$skip = $false
Push-Location $work
try {
  & $Exe index --all --config $cfg --jobs 1 *> $null
  $dbA = Join-Path $work '_D-RAG\ProjA.sqlite'
  $dbB = Join-Path $work '_D-RAG\ProjB.sqlite'
  Check 'all three fixture projects indexed' `
        ((Test-Path $dbA) -and (Test-Path $dbB) -and (Test-Path (Join-Path $work '_D-RAG\ProjC.sqlite')))

  # ProjB is compiled -> it gets a stamp. ProjC never is -> NULL, the silent case.
  $rfJson  = (& $Exe refresh-findings --project (Join-Path $work 'ProjB.dproj') --db $dbB --json 2>&1 | Out-String)
  $stamped = 0
  if ($rfJson -match '"stamped"\s*:\s*(\d+)') { $stamped = [int]$Matches[1] }

  if ($stamped -lt 1) {
    Write-Host "[SKIP] refresh-findings stamped nothing (stamped=$stamped) -- the fixture never reached"
    Write-Host "       the state under test, so nothing below would measure the rule. NOT a pass."
    $skip = $true
  }

  if (-not $skip) {
    Check 'the fixture reached the state under test (ProjB carries a stamp)' ($stamped -ge 1) "stamped=$stamped"

    Start-Sleep -Seconds 2
    WriteShared 2          # the edit: disk mtime now moves past ProjB's stamp

    # Deliberately NOT reindexing A: the rule must compare against the CURRENT
    # disk mtime, and A's stored mtime is now the OLD one.
    $out  = (& $Exe lint-all --db $dbA --config $cfg --quiet --enable dependent-project-not-recompiled 2>$null | Out-String)
    $rows = @($out -split "`r?`n" | Where-Object { $_ -match 'dependent-project-not-recompiled' })

    Check 'CONTROL a stamped fixture produces at least one row' ($rows.Count -ge 1) `
          '0 rows here is the rule going silent, NOT a fixture problem -- the stamp landed above'

    Check 'POS a project that compiled BEFORE the edit is reported' `
          (($rows | Where-Object { $_ -match 'ProjB' }).Count -ge 1) "rows: $($rows.Count)"

    Check 'POS it fires against the CURRENT DISK mtime, with A''s index deliberately stale' `
          (($rows | Where-Object { $_ -match 'ProjB' }).Count -ge 1) `
          'comparing the STORED mtime would call a just-edited file current'

    Check 'NEG a NULL stamp (never compiled) is SILENT, not stale' `
          (($rows | Where-Object { $_ -match 'ProjC' }).Count -eq 0) `
          'a fresh checkout would flood with findings about work nobody has done'

    # Rebuild ProjB: its stamp now passes the edit, so the finding must go.
    #
    # THE REINDEX IS PART OF THE REBUILD, not test scaffolding. refresh-findings
    # decides which units to recompile from the STORED mtime, so against an index
    # that still holds the pre-edit mtime it finds nothing stale and never
    # re-stamps -- measured here, as this case failing. That is also why the rule
    # itself reads the DISK: the two clocks are genuinely different, and only one
    # of them knows when the file changed.
    & $Exe index --all --config $cfg --only ProjB --jobs 1 *> $null
    & $Exe refresh-findings --project (Join-Path $work 'ProjB.dproj') --db $dbB *> $null
    $out2  = (& $Exe lint-all --db $dbA --config $cfg --quiet --enable dependent-project-not-recompiled 2>$null | Out-String)
    $rows2 = @($out2 -split "`r?`n" | Where-Object { $_ -match 'dependent-project-not-recompiled' -and $_ -match 'ProjB' })
    Check 'the finding CLEARS once that project is rebuilt' ($rows2.Count -eq 0) `
          'a finding that never clears is one people learn to ignore'

    Check 'the rule is OFF by default (R3 audits before it ships ON)' `
          (((& $Exe lint-all --db $dbA --config $cfg --quiet 2>$null | Out-String) -notmatch 'dependent-project-not-recompiled')) `
          'a new project-wide rule must not default ON before its volume is measured'
  }
}
finally {
  Pop-Location
  Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if($skip){ exit 0 }
if($fail){ Write-Host 'DEPENDENT PROJECT GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'DEPENDENT PROJECT GUARD: PASS' -ForegroundColor Green; exit 0 }
