<#
  run_exception_unit_writer.ps1 -- STAGE 3, part 2: MATERIALISING the derived
  classes into the exceptions unit, and rewriting the raise sites to use them.

  Part 1 (deriving a NAME from a message) is run_exception_class_naming.ps1 and
  is not re-tested here. This guard starts where that one stops: a name exists,
  and now it has to become a DECLARATION that survives being regenerated.

  THE INVOCATION THIS ENCODES -- OWNER RULING 2026-08-30 (session 52)
  ------------------------------------------------------------------
  Owner: "I thought fix-it is an IDE command. To me it looks more like (iii)."

  The unit writer is NOT a fix-it and must not be reached through --fix. A
  fix-it is per-finding, per-file, at a cursor -- that is what the IDE surfaces
  as an LSP code action. The writer's INPUT is the project-wide harvested
  message set and its OUTPUT is one generated unit, so it is a project-level
  materialisation and it gets its own verb:

      drag-lint exceptions-sync --db <db> [--config <cfg>] [--apply]

  The CALL-SITE rewrite is a genuine per-file fix and stays in `lint --fix`,
  and therefore stays reachable as a code action. Controls 6 and 8 below are
  the only two that drive `lint`; every other control drives exceptions-sync.
  That split is the thing being pinned -- if someone later folds the writer
  into lint-all --fix, controls 1-5 stop being able to reach it.

  WHY EACH CONTROL EXISTS (none is illustrative)
  ----------------------------------------------
    1 CREATION      the unit does not exist yet -> it is created, and the
                    console SAYS so. A silently created file in an unexpected
                    folder is how this feature loses a day.
    2 IDEMPOTENCE   run twice, byte-compare EVERY file. This is the kill
                    condition from the plan: an unstable writer rewrites source
                    on every run, which is worse than not shipping it. It goes
                    RED the moment the message->name map is not read back.
    3 APPEND        a new message harvested BEFORE the ones it collides with
                    must NOT renumber them. UniqueExceptionClassName's own remarks
                    say the numeric suffix is only stable because the map is
                    persisted; this is the assertion that makes that true.
    4 RENAME        a human renames a mediocre generated class and KEEPS its
                    comment. The comment is the key, so the rename must
                    survive: no second class for the same message.
    5 HOSTILE MSG   a message containing '}' and doubled quotes. The comment is
                    a SAME-LINE // comment precisely because a brace comment
                    would END at the message's own '}'. This repo has paid for
                    that trap twice (see memory brace-directive-in-brace-comment
                    and the build it cost on 2026-08-31). Goes RED if anyone
                    "simplifies" the writer to { }.
    6 REWRITE       the raise site names the class; uses gained the unit; the
                    MESSAGE ARGUMENT IS UNTOUCHED. Drives `lint --fix`.
    7 DRY RUN       without --apply nothing on disk changes, but the report
                    still says what it would do. Stat-gated-destructive
                    precedent; also the only control that proves --apply is
                    load-bearing rather than decorative.
    8 SKIPS         a raise with no string literal is neither declared nor
                    rewritten, AND still produces its raise-bare-exception
                    finding. It is skipped by the NAMER, not by the RULE --
                    carried over from the naming guard, where the same control
                    is what stopped "no name appeared" from passing with the
                    whole feature switched off.
    9 UNCONFIGURED  no "exceptions" block -> no unit, no edits, and the lint
                    output byte-identical. Expressed with an explicit key-less
                    --config, NOT by omitting the flag: since 2026-08-28
                    lint-all discovers a config from the --db path, so omitting
                    it no longer means unconfigured.
   10 COLLAPSE      two messages differing only by a format specifier map to
                    ONE class. Pins the already-shipped NormalizeExcMessage
                    amendment (the one pair on ORM3 that justified the whole
                    normalizer and that the normalizer originally missed).
   12 WHITESPACE    a message with leading/trailing spaces survives its own
                    read-back. Found on ORM3 by the --apply kill condition, not
                    here -- every message in this fixture had been tidy.
   13 ROOT + USES   a configured ancestor declared in ANOTHER unit reaches the
                    exceptions unit's uses clause. The CREATION path always did
                    this; the SPLICE path did not, and ORM3 could not show it,
                    because its root is declared in the file being written.
   11 LINT-CLEAN    the generated unit parses AND lints to zero. This repo's
                    global rule holds tool-written code to the same standard as
                    hand-written code, and nothing else pins it. Must run after
                    a REINDEX -- see the note at the control.

  POSITIVE CONTROLS. Controls 8 and 9 are the ones that fail if the feature is
  switched off entirely; without them, "the unit has no bogus class in it" is
  satisfied by a writer that writes nothing at all.

  STATUS WHEN WRITTEN (2026-08-31): every control RED -- `exceptions-sync` is
  not a verb yet, so the CLI exits non-zero on an unknown command. That is the
  intended starting state and it is recorded here so a future reader can tell a
  never-run guard from a regression.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-excwriter"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAscii([string]$Path, [string]$Text) {
  $t = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $t, [System.Text.Encoding]::ASCII)
}
# Hash every source file in a tree, so IDEMPOTENCE and DRY RUN compare the
# whole project rather than the one file we happen to suspect.
function TreeHash([string]$Root) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($f in (Get-ChildItem -Path $Root -Recurse -File -Include *.pas, *.dpr |
                  Sort-Object FullName)) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
    $out.Add(("{0}={1}" -f $f.FullName.Substring($Root.Length), $h))
  }
  return ($out -join "`n")
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---------------------------------------------------------------------------
# Project A -- the exceptions unit ALREADY EXISTS (an empty managed block), so
# the writer must resolve it through the store and edit it in place. Project B
# (further down) is the same fixture with the unit absent, which is control 1.
# ---------------------------------------------------------------------------
#
# The two EOrderLineQuantityMustExceedZero messages are deliberate: they derive
# the SAME base name (the 6-word cap cuts both after "zero") but carry DIFFERENT
# keys, which is the only shape in which a numeric suffix is ever allocated.
# Control 3 then adds a third one beginning with the stopword "An" -- dropped
# from key and name alike, so the base still collides -- and splices it in
# AHEAD of the other two. That placement IS the control: harvest order is FILE
# order, so a writer that re-derives the block from scratch each run hands the
# unsuffixed name to the NEWCOMER and renumbers the two that already existed.
# Appending it at the END instead would produce identical output with and
# without a persisted map, and the control could never go red.
$raisesA = @'
unit uRaises;
interface
procedure RunAll(const M: string);
implementation
uses System.SysUtils;

procedure ChannelSetup;
begin
  raise Exception.Create('Data Channel %d is not set up properly');
end;

procedure OrderThisItem;
begin
  raise Exception.Create('Order line quantity must exceed zero for this item');
end;

procedure OrderThatCustomer;
begin
  raise Exception.Create('Order line quantity must exceed zero for that customer');
end;

procedure HostileMessage;
begin
  raise Exception.Create('Set }brace{ and ''quoted'' text');
end;

procedure PaddedMessage;
begin
  raise Exception.Create('  Padded message needs trimming   ');
end;

procedure LookupByName;
begin
  raise Exception.Create('LookupAccountName failed for %s');
end;

procedure LookupById;
begin
  raise Exception.Create('LookupAccountName failed for %d');
end;

procedure NoLiteral(const M: string);
begin
  raise Exception.Create(M);
end;

procedure RunAll(const M: string);
begin
  ChannelSetup; OrderThisItem; OrderThatCustomer; HostileMessage; PaddedMessage;
  LookupByName; LookupById; NoLiteral(M);
end;

end.
'@

# The pre-existing definitions unit. The managed block is EMPTY and carries no
# `type` keyword -- the writer emits `type` INSIDE the block when it has at
# least one entry, so that an empty block is still legal Object Pascal. A
# `type` left stranded outside an empty block does not compile, and a generated
# unit that does not compile is the one failure this feature cannot survive.
$defsA = @'
unit uExceptionDefinitions;

{ Exception classes for this project. The block below is maintained by
  drag-lint `exceptions-sync`; everything outside it is yours. }

interface

uses
  System.SysUtils;

{ drag-lint:auto BEGIN exceptions }
{ drag-lint:auto END exceptions }

implementation

end.
'@

$projA = Join-Path $WorkDir 'a'
New-Item -ItemType Directory (Join-Path $projA 'src') | Out-Null
WriteAscii (Join-Path $projA 'src\uRaises.pas') $raisesA
WriteAscii (Join-Path $projA 'src\uExceptionDefinitions.pas') $defsA

$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
WriteAscii $cfgOn  '{ "exceptions": { } }'
WriteAscii $cfgOff '{ }'

function NewManifest([string]$Root, [string]$Section, [string]$Db) {
  $p = Join-Path $Root 'manifest.drag-lint.json'
  $t = '{' + [char]10 +
    '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
    '  "indexes": { "outDir": "out", "sections": [ { "name": "' + $Section + '", "db": "' + $Db + '", "include": ["src"] } ] }' + [char]10 +
    '}'
  WriteAscii $p $t
  return $p
}
$manA = NewManifest $projA 'SecA' 'a.sqlite'
$dbA  = Join-Path $projA 'out\a.sqlite'

# Reindexing is not optional between runs: the writer reads the file list from
# the store, and control 3 ADDS a raise. A stale index there would silently test
# nothing -- the append would never be seen and the control would pass green.
function Reindex([string]$Manifest, [string]$Section) {
  Push-Location C:\TEMP
  try { & $Exe index --all --config $Manifest --only $Section --jobs 1 2>&1 | Out-Null }
  finally { Pop-Location }
}
# THE VERB MUST BE PROVEN TO HAVE RUN. When `exceptions-sync` does not exist
# the CLI prints the whole usage banner and exits nonzero -- and that banner
# contains the words "--apply", "unchanged" and "up to date", so four controls
# below MATCHED IT and passed green against a build with no writer in it at all.
# That was observed, not imagined (first RED run, 2026-08-31). Anything that
# looks like the banner is therefore a hard failure, not a value to match on.
function Sync([string]$Db, [string]$Cfg, [switch]$Apply) {
  Push-Location C:\TEMP
  try {
    if ($Apply) { $o = & $Exe exceptions-sync --db $Db --config $Cfg --apply 2>&1 | Out-String }
    else        { $o = & $Exe exceptions-sync --db $Db --config $Cfg         2>&1 | Out-String }
    $code = $LASTEXITCODE
  } finally { Pop-Location }
  if ($o -match '(?m)^Usage:' -or $o -match 'drag-lint index <path>') {
    Check 'exceptions-sync is a real verb' $false `
      'the CLI printed its usage banner -- the verb is unknown, so every control below is vacuous'
    return [pscustomobject]@{ Output = ''; Code = $code; Ran = $false }
  }
  if ($code -ne 0) {
    Check 'exceptions-sync exited 0' $false ("exit $code : " + $o.Trim())
    return [pscustomobject]@{ Output = $o; Code = $code; Ran = $false }
  }
  return [pscustomobject]@{ Output = $o; Code = $code; Ran = $true }
}

Reindex $manA 'SecA'
if (-not (Test-Path $dbA)) { Write-Host "FATAL: index did not produce $dbA" -ForegroundColor Red; exit 2 }

$defsPathA = Join-Path $projA 'src\uExceptionDefinitions.pas'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 7 -- DRY RUN (runs FIRST, while the tree is pristine)' -ForegroundColor Cyan
# Ordered first on purpose: "nothing changed" is only meaningful before any
# --apply has touched the tree.
$beforeDry = TreeHash $projA
$dry       = Sync $dbA $cfgOn
$dryOut    = $dry.Output
$afterDry  = TreeHash $projA
Check 'DRY RUN: the verb ran at all' $dry.Ran `
  'gates every "nothing changed" assertion below -- they are all true of a verb that does not exist'
Check 'DRY RUN: changes NOTHING on disk' (($beforeDry -eq $afterDry) -and $dry.Ran) `
  'without --apply the writer must be inert'
Check 'DRY RUN: still REPORTS the class it would add' `
  ($dryOut -match 'EDataChannelNotSetUpProperly') `
  'a silent dry run is indistinguishable from a broken one'
Check 'DRY RUN: names itself a dry run AND says how to make it real' `
  (($dryOut -match '(?i)dry.run') -and ($dryOut -match '(?i)--apply')) `
  'matching --apply alone also matches the usage banner'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROLS 2,5,10 -- APPLY, then the shape of what was written' -ForegroundColor Cyan
$hash0 = TreeHash $projA
$run1  = (Sync $dbA $cfgOn -Apply).Output
$hash1 = TreeHash $projA
# THE POSITIVE CONTROL FOR IDEMPOTENCE. "Run twice, nothing changed" is
# trivially true of a writer that never writes; it must be paired with proof
# that the FIRST run changed something.
Check 'APPLY: the first run actually changed the tree' ($hash0 -ne $hash1) `
  'without this, IDEMPOTENCE below passes with the writer switched off'
$defs1 = [System.IO.File]::ReadAllText($defsPathA)

function BlockOf([string]$Text) {
  $m = [regex]::Match($Text,
    '(?s)\{\s*drag-lint:auto BEGIN exceptions\s*\}(.*?)\{\s*drag-lint:auto END exceptions\s*\}')
  if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}
$block1 = BlockOf $defs1
Check 'the managed block is still delimited after the write' ($block1 -ne '') ''
Check 'and it is no longer empty' ($block1.Trim() -ne '') `
  'the stub started with an EMPTY block, so "delimited" alone proves nothing'
Check 'a class was declared for the Data Channel message' `
  ($block1 -match 'EDataChannelNotSetUpProperly\s*=\s*class\(') ''
Check 'the declaration carries the message in a SAME-LINE // comment' `
  ($block1 -match 'EDataChannelNotSetUpProperly\s*=\s*class\([^)]*\);\s*//\s*Data Channel %d is not set up properly') `
  'the raw message, specifiers and all, is what makes the comment the key'
Check 'the block emits its own `type` keyword' ($block1 -match '(?m)^\s*type\s*$') `
  'a type outside an empty block does not compile'

# 5 -- the hostile message.
Check 'HOSTILE: the } in the message did not end anything' `
  ($block1 -match '//.*\}brace\{') 'a brace comment would have ended at the }'
Check 'HOSTILE: doubled quotes are unescaped exactly once' `
  ($block1 -match "//.*'quoted'") 'the comment holds the message as the user reads it'
Check 'HOSTILE: its declaration is still one legal line' `
  ($block1 -match '(?m)^\s*E[A-Za-z0-9]+\s*=\s*class\([^)]*\);\s*//.*\}brace\{') ''

# WHITESPACE ROUND-TRIP -- found on ORM3, NOT by this fixture, which is why it
# is now here. The comment is written from the message VERBATIM but read back
# with Trim(), so a message ending in a space was written long on run 1 and
# re-rendered short on run 2: `exceptions-sync --apply` twice in a row rewrote
# CommonExceptions.pas while reporting `0 class(es) added` (9504 -> 9493 bytes,
# 11 of 78 messages affected). The file was STABLE from run 2 on, so this is a
# one-time churn -- and a one-time churn is still a tool editing source it was
# asked not to change. Fixed by trimming at WRITE time so the first write is
# already canonical. IDEMPOTENCE above is what actually catches a regression;
# this pins the reason.
Check 'WHITESPACE: the padded message is stored trimmed' `
  ($block1 -match '(?m)^  EPaddedMessageNeedsTrimming = class\([^)]*\); // Padded message needs trimming?$') `
  'written verbatim, it would not survive its own read-back'

# 10 -- the specifier-only pair collapses.
$lookup = @([regex]::Matches($block1, '(?m)^\s*(E[A-Za-z0-9]*Lookup[A-Za-z0-9]*)\s*=\s*class\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check 'COLLAPSE: %s and %d variants share ONE class' ($lookup.Count -eq 1) `
  ("got: " + ($lookup -join ', '))

# 2 -- idempotence, the kill condition. Gated on the positive control above.
$s2    = Sync $dbA $cfgOn -Apply
$run2  = $s2.Output
$hash2 = TreeHash $projA
Check 'IDEMPOTENCE: a second --apply changes NO file at all' `
  (($hash1 -eq $hash2) -and $s2.Ran -and ($hash0 -ne $hash1)) `
  'KILL CONDITION -- an unstable writer rewrites source every run'
Check 'IDEMPOTENCE: and it says it added nothing' `
  ($run2 -match '(?i)\b0 new\b|no new class|unchanged|already up to date') `
  ("second run said: " + $run2.Trim())

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 3 -- APPEND, never RENUMBER' -ForegroundColor Cyan
# Capture the two colliding names as allocated on the first pass.
$before3 = @([regex]::Matches($block1, '(?m)^\s*(EOrderLineQuantityMustExceedZero\d*)\s*=\s*class\(') |
             ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Check 'two different messages sharing a base got a numeric suffix' `
  ($before3.Count -eq 2) ("got: " + ($before3 -join ', '))

# "An" is a stopword: dropped from the key AND the name, so the base still
# collides -- but the RAW message now sorts before both existing ones.
$appended = (([System.IO.File]::ReadAllText((Join-Path $projA 'src\uRaises.pas'))) -replace
  'procedure OrderThisItem',
@'
procedure OrderOneMore;
begin
  raise Exception.Create('An order line quantity must exceed zero for one more');
end;

procedure OrderThisItem
'@)
WriteAscii (Join-Path $projA 'src\uRaises.pas') $appended
Reindex $manA 'SecA'
$run3  = (Sync $dbA $cfgOn -Apply).Output
$block3 = BlockOf ([System.IO.File]::ReadAllText($defsPathA))
$after3 = @([regex]::Matches($block3, '(?m)^\s*(EOrderLineQuantityMustExceedZero\d*)\s*=\s*class\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object)
Check 'APPEND: the earlier-sorting message became a THIRD class' `
  ($after3.Count -eq 3) ("got: " + ($after3 -join ', '))
Check 'APPEND: the two existing names are untouched' `
  (($before3.Count -eq 2) -and ($after3.Count -eq 3) -and
   ((($before3 | Where-Object { $after3 -notcontains $_ }).Count) -eq 0)) `
  ("before: " + ($before3 -join ', ') + " | after: " + ($after3 -join ', '))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 4 -- a human RENAME survives, because the comment is the key' -ForegroundColor Cyan
$renamed = ([System.IO.File]::ReadAllText($defsPathA)) -replace
  'EDataChannelNotSetUpProperly', 'EChannelBad'
WriteAscii $defsPathA $renamed
Reindex $manA 'SecA'
$run4   = (Sync $dbA $cfgOn -Apply).Output
$block4 = BlockOf ([System.IO.File]::ReadAllText($defsPathA))
Check 'RENAME: the hand-chosen name is still there' `
  ($block4 -match 'EChannelBad\s*=\s*class\(') ''
Check 'RENAME: no duplicate class was appended for the same message' `
  (($block4 -match 'EChannelBad\s*=\s*class\(') -and
   (-not ($block4 -match 'EDataChannelNotSetUpProperly'))) `
  'the key is the comment, so renaming the class must not orphan the message'
$chanCount = @([regex]::Matches($block4, '//\s*Data Channel %d is not set up properly')).Count
Check 'RENAME: the message appears exactly ONCE in the block' ($chanCount -eq 1) `
  ("occurrences: " + $chanCount)

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROLS 6,8 -- the CALL-SITE rewrite, which is a per-file `lint --fix`' -ForegroundColor Cyan
$raisesPathA = Join-Path $projA 'src\uRaises.pas'
Push-Location C:\TEMP
try {
  $fixOut = & $Exe lint $raisesPathA --db $dbA --config $cfgOn `
                   --fix --fix-rule raise-bare-exception --apply 2>&1 | Out-String
} finally { Pop-Location }
$src6 = [System.IO.File]::ReadAllText($raisesPathA)
Check 'REWRITE: the renamed class is what the raise site now names' `
  ($src6 -match 'raise\s+EChannelBad\.Create\(') `
  'the rewrite must read the map from the UNIT, not re-derive a name'
Check 'REWRITE: the message argument is untouched' `
  ($src6 -match "raise\s+EChannelBad\.Create\('Data Channel %d is not set up properly'\)") ''
Check 'REWRITE: uses gained the exceptions unit' `
  ($src6 -match '(?m)^\s*uses\b[^;]*uExceptionDefinitions') ("uses clause did not gain it")
Check 'REWRITE: no bare Exception.Create with a literal survives' `
  (-not ($src6 -match "raise\s+Exception\.Create\('")) ''

# 8 -- the skip, and its positive control.
Check 'SKIP: the no-literal raise is NOT rewritten' `
  ($src6 -match 'raise\s+Exception\.Create\(M\)') `
  'no literal means no name; inventing one here is the expensive failure'
# Counting the DECLARATIONS is what proves the no-literal raise produced none.
# "no class has an empty comment" is satisfied by a writer that emitted nothing,
# and by one that emitted a class for M with a junk comment. Six is the exact
# number of distinct literal messages in the fixture after control 3's append
# and control 10's collapse: Data Channel, three Order variants, the hostile
# message, the padded message, and the ONE Lookup class the %s/%d pair
# folded into.
$declCount = @([regex]::Matches($block4, '(?m)^\s*E[A-Za-z0-9]+\s*=\s*class\(')).Count
Check 'SKIP: the unit holds exactly 7 classes -- one per distinct literal' `
  ($declCount -eq 7) ("declared: " + $declCount + " (the no-literal raise must contribute none)")
Push-Location C:\TEMP
try { $lintOut = & $Exe lint-all --db $dbA --config $cfgOn --quiet 2>&1 | Out-String }
finally { Pop-Location }
Check 'SKIP: it still produces a raise-bare-exception finding' `
  ($lintOut -match 'uRaises\.pas:\d+:.*raise-bare-exception') `
  'skipped by the NAMER, not by the RULE -- without this, "no name appeared" passes with the feature off'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 1 -- CREATION, in a project where the unit does not exist' -ForegroundColor Cyan
$projB = Join-Path $WorkDir 'b'
New-Item -ItemType Directory (Join-Path $projB 'src') | Out-Null
WriteAscii (Join-Path $projB 'src\uRaises.pas') $raisesA
$manB = NewManifest $projB 'SecB' 'b.sqlite'
$dbB  = Join-Path $projB 'out\b.sqlite'
Reindex $manB 'SecB'
$sB = Sync $dbB $cfgOn -Apply
$runB = $sB.Output
$madeB = @(Get-ChildItem -Path $projB -Recurse -File -Filter 'uExceptionDefinitions.pas')
Check 'CREATION: the unit was created' ($madeB.Count -eq 1) `
  ("found " + $madeB.Count + " copies")
Check 'CREATION: the console SAYS it created a file' `
  ($runB -match '(?i)creat') 'a silently created unit in an unexpected folder costs a day'
if ($madeB.Count -eq 1) {
  $blockB = BlockOf ([System.IO.File]::ReadAllText($madeB[0].FullName))
  Check 'CREATION: the new unit carries a delimited managed block' ($blockB -ne '') ''
  Check 'CREATION: with the derived class and its message' `
    ($blockB -match 'EDataChannelNotSetUpProperly\s*=\s*class\([^)]*\);\s*//\s*Data Channel') ''
  Check 'CREATION: and the unit name matches the configured default' `
    (([System.IO.File]::ReadAllText($madeB[0].FullName)) -match '(?m)^\s*unit\s+uExceptionDefinitions\s*;') ''
}


# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 11 -- the GENERATED unit is itself lint-clean' -ForegroundColor Cyan
# This repo's global rule is that code we write is not finished until it is
# lint-clean. Code the TOOL writes is held to the same standard, and nothing
# was pinning that.
#
# It has to be checked AFTER a reindex, and the reason is worth keeping: on a
# stale index type-name-prefix cannot see that EFoo descends from Exception --
# its exception-ancestry sub-check asks the store -- so it falls back to
# demanding a T prefix and reports one finding per generated class. Measured
# 2026-08-31: 5 findings before the reindex, 0 after. So a run of this control
# against a stale index would report a rule defect that does not exist, and
# the reindex below is load-bearing rather than hygiene.
Reindex $manB 'SecB'
Push-Location C:\TEMP
try {
  $genLint = & $Exe lint $madeB[0].FullName --db $dbB 2>&1 | Out-String
} finally { Pop-Location }
Check 'GENERATED: the unit parses -- no parser-error, no syntax-error' `
  (-not ($genLint -match 'parser-error|syntax-error')) `
  'a generated unit that does not compile is the one failure this feature cannot survive'
Check 'GENERATED: and it is lint-clean' `
  ($genLint -match '(?m)^0 finding\(s\)') `
  ("lint said: " + (($genLint -split "`n" | Where-Object { $_ -match 'finding\(s\)' }) -join ' '))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 13 -- a configured ROOT in ANOTHER unit reaches the uses clause' -ForegroundColor Cyan
# The ancestor is configurable, so the exceptions unit must USE whatever unit
# declares it or every generated `class(<root>);` fails to compile.
#
# The CREATION path always got this right. The SPLICE path -- an exceptions unit
# that already exists, which is the ordinary case -- did not, and ORM3 could not
# reveal it: its root, EMicroniteError, is declared in CommonExceptions.pas,
# the very file being written, so no uses entry was ever required. This fixture
# puts the root somewhere else on purpose.
$projD = Join-Path $WorkDir 'd'
New-Item -ItemType Directory (Join-Path $projD 'src') | Out-Null
WriteAscii (Join-Path $projD 'src\uRaises.pas') $raisesA
WriteAscii (Join-Path $projD 'src\uBase.pas') @'
unit uBase;

interface

uses
  System.SysUtils;

type
  EMicroniteError = class(Exception);

implementation

end.
'@
# The existing exceptions unit does NOT use uBase. That is the whole point.
WriteAscii (Join-Path $projD 'src\uExceptionDefinitions.pas') $defsA
$cfgRoot = Join-Path $WorkDir 'root.json'
WriteAscii $cfgRoot '{ "exceptions": { "root": "EMicroniteError" } }'
$manD = NewManifest $projD 'SecD' 'd.sqlite'
$dbD  = Join-Path $projD 'out\d.sqlite'
Reindex $manD 'SecD'
$sD1 = Sync $dbD $cfgRoot -Apply
$defsD = [System.IO.File]::ReadAllText((Join-Path $projD 'src\uExceptionDefinitions.pas'))
Check 'ROOT: the generated classes descend from the configured root' `
  ($defsD -match 'E[A-Za-z0-9]+\s*=\s*class\(EMicroniteError\);') `
  'without this the "root" config key does nothing'
Check 'ROOT: the exceptions unit now USES the unit declaring the root' `
  ($defsD -match '(?s)interface.*?\buses\b[^;]*\buBase\b[^;]*;') `
  'otherwise every generated declaration fails to compile'
# Idempotence again, narrowly: the uses entry must be added ONCE.
$hD1 = TreeHash $projD
$sD2 = Sync $dbD $cfgRoot -Apply
$defsD2 = [System.IO.File]::ReadAllText((Join-Path $projD 'src\uExceptionDefinitions.pas'))
$uBaseCount = @([regex]::Matches($defsD2, '(?m)^\s*uBase\s*,')).Count
Check 'ROOT: a second run does not add uBase twice' `
  (($uBaseCount -le 1) -and ($hD1 -eq (TreeHash $projD)) -and $sD2.Ran) `
  ("uBase entries: " + $uBaseCount)

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROL 9 -- UNCONFIGURED is genuinely free' -ForegroundColor Cyan
$projC = Join-Path $WorkDir 'c'
New-Item -ItemType Directory (Join-Path $projC 'src') | Out-Null
WriteAscii (Join-Path $projC 'src\uRaises.pas') $raisesA
$manC = NewManifest $projC 'SecC' 'c.sqlite'
$dbC  = Join-Path $projC 'out\c.sqlite'
Reindex $manC 'SecC'
$beforeC = TreeHash $projC
$sC = Sync $dbC $cfgOff -Apply
$runC = $sC.Output
$afterC  = TreeHash $projC
Check 'UNCONFIGURED: --apply with no exceptions block writes nothing' `
  (($beforeC -eq $afterC) -and $sC.Ran) 'an absent block is the off switch and must stay free'
Check 'UNCONFIGURED: no unit is created' `
  ((@(Get-ChildItem -Path $projC -Recurse -File -Filter 'uExceptionDefinitions.pas').Count -eq 0) -and $sC.Ran) ''
Check 'UNCONFIGURED: it says why it did nothing' `
  ($runC -match '(?i)exceptions') 'silence here reads exactly like a crash'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
