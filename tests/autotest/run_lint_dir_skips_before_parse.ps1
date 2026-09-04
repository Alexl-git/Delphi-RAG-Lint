<#
  run_lint_dir_skips_before_parse.ps1 -- `lint <dir>` must skip a non-member
  file BEFORE parsing it, not merely drop its findings afterwards.

  >>> WHY AN EXISTING 12-CONTROL GUARD COULD NOT SEE THIS.

  B8 shipped a pre-parse scope filter: TLinter.WalkFilter, fed by
  `WalkClosure(AArgs, Store, InClosure)`. It was INERT. `Store` was opened 425
  lines AFTER the walk that used it, so WalkClosure always got nil, always
  answered "no closure", and the filter passed every file straight through.

  Nothing failed. The REPORT stayed correct, because ScopeWalkFindingsToClosure
  drops non-member findings after the fact -- so every assertion in
  run_lint_walk_scope_guard.ps1, all twelve of them, kept passing. Only the cost
  was wrong: on ORM3 CLIENT, 84 of 284 files were parsed purely to have their
  output discarded.

  It stopped being only a cost question when item 1b derived the marker scan's
  scanned-set from this same walk.

  THE LESSON THIS GUARD ENCODES: you cannot test a pre-parse skip by looking at
  the output, because a post-hoc filter produces byte-identical output. You have
  to observe the PARSE. So this guard makes the non-member file IMPOSSIBLE TO
  READ -- an exclusive lock -- and asserts the run does not complain about it.

    scoping works  -> the file is never opened -> silence
    scoping inert  -> LintFolder opens it, fails, and prints `SKIP <path>: ...`

  That signal cannot be forged by a filter that runs later, which is exactly the
  property the previous guard lacked.

  RED-CHECK: against a build with the store opened after the walk, case 2 emits
  `SKIP ... EInOutError` (or an access error) naming the locked file. Verified.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  # NOT "..._skip": the assertion below searches for the engine's `SKIP <path>`
  # line, and a WorkDir containing "skip" put that word into every path the
  # engine printed. The guard then matched its own directory name and reported
  # RED against a CORRECT build -- and, worse, against the broken one too, so
  # its first RED-check proved nothing. Keep this name free of "skip".
  [string]$WorkDir = "$env:TEMP\draglint_dir_preparse_scope",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null

# Two project MEMBERS, and one LOOSE unit that belongs to no project.
W (Join-Path $WorkDir 'uMemberA.pas') @'
unit uMemberA;
interface
procedure MemberAThing;
implementation
procedure MemberAThing;
begin
  try
    MemberAThing;
  except
  end;
end;
end.
'@
W (Join-Path $WorkDir 'uMemberB.pas') @'
unit uMemberB;
interface
procedure MemberBThing;
implementation
procedure MemberBThing;
begin
end;
end.
'@
$loose = Join-Path $WorkDir 'uLooseNotAMember.pas'
W $loose @'
unit uLooseNotAMember;
interface
procedure LooseThing;
implementation
procedure LooseThing;
begin
  try
    LooseThing;
  except
  end;
end;
end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uMemberA in 'uMemberA.pas',
  uMemberB in 'uMemberB.pas';
begin
end.
'@

$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null

Write-Host '== lint <dir> must skip a non-member BEFORE parsing it ==' -ForegroundColor Cyan

# 1. PRECONDITION -- unlocked, the run is clean and the loose file is not reported.
#    If this is not true, case 2 proves nothing.
$out1 = (& $Exe lint $WorkDir --db $db 2>&1 | Out-String)
# Match a FINDING line (`<path>:<line>:<col>`), not the bare filename. The scope
# report deliberately NAMES what it dropped ("not a project member: <path>") --
# that is the repo's "named, never silent" rule, and an assertion on the bare
# name reads that correct behaviour as a failure. It did, the first time.
Check 'PRECONDITION: an ordinary run reports no FINDING for the non-member' `
  (-not ($out1 -match 'uLooseNotAMember\.pas:\d+:\d+')) `
  'the post-hoc finding filter is not working either -- fix that first'
Check 'PRECONDITION: and it does not SKIP-error on anything' `
  (-not ($out1 -match 'SKIP ')) "unexpected SKIP in a clean run"

# 2. THE DEFECT. Lock the non-member so it CANNOT be read. A pre-parse skip never
#    touches it; an inert filter opens it and reports the failure.
$fs = $null
try {
  $fs = [System.IO.File]::Open($loose, [System.IO.FileMode]::Open,
                               [System.IO.FileAccess]::Read,
                               [System.IO.FileShare]::None)
  Check 'the non-member is genuinely locked (fixture integrity)' ($null -ne $fs) ''

  $out2 = (& $Exe lint $WorkDir --db $db 2>&1 | Out-String)

  # Report WHAT matched, not just that something did. A bare boolean here cost a
  # debugging round: the assertion fired while a hand-run of the same commands
  # was clean, and nothing in the output said why.
  # Anchored to the START of a line: LintFolder prints `  SKIP <path>: <class>: <msg>`.
  # An unanchored search matched the word inside a PATH -- see the WorkDir note above.
  $skipHit = ''
  if ($out2 -match '(?m)^\s*(SKIP\s[^\r\n]*)') { $skipHit = $Matches[1] }
  Check 'a LOCKED non-member produces no SKIP error -- it was never opened' `
    ($skipHit -notmatch 'uLooseNotAMember') `
    ("RED: the walk parsed a file outside the project closure -- WalkClosure got a nil store, so the pre-parse filter is inert. Offending line: '" + $skipHit + "'")

  # 3. CONTROL -- the members must STILL be linted while the loose file is locked.
  #    Without this, "skip everything" satisfies case 2.
  # bare-except, NOT sleep-in-vcl: f709bea correctly scoped sleep-in-vcl to units
  # whose closure touches VCL, so it never fires in a fixture like this one. An
  # assertion keyed on a rule that cannot fire here is vacuous in both directions
  # -- it failed against CORRECT code the first time this guard was run.
  Check 'CONTROL: the members are still linted (bare-except fires on uMemberA)' `
    ($out2 -match 'uMemberA') `
    'the walk skipped the project members too -- the filter is now over-scoping'
}
finally {
  if ($fs) { $fs.Close(); $fs.Dispose() }
}

# 4. CONTROL -- with NO --db there is no closure, and an unscoped walk must still
#    lint everything. Otherwise "no store" would silently become "skip all".
$out4 = (& $Exe lint $WorkDir 2>&1 | Out-String)
Check 'CONTROL: with no --db the walk is unscoped and still lints the loose file' `
  ($out4 -match 'uLooseNotAMember\.pas:\d+:\d+') `
  'an absent store must mean "no scope", never "empty scope"'

Write-Host ''
if ($script:fail) { Write-Host 'DIR-PREPARSE-SKIP GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DIR-PREPARSE-SKIP GUARD: PASS' -ForegroundColor Green
exit 0
