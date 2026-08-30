<#
  run_exception_class_naming.ps1 -- STAGE 3, part 1: deriving a class NAME
  from a raise message.

  THE OWNER RULINGS THIS ENCODES
  ------------------------------
  2026-08-29: "We need some algorithm to create an Exception name derived from
  the message, make sure it is unique, define it in that unit and use the new
  name instead of a general Exception.Create."

  2026-08-30, after seeing the first generated table: the NAME IS A CATCH-TAG,
  NOT DOCUMENTATION. Every generated class has a companion message, so the name
  only has to classify in a logger and be findable in source; the definitions
  unit carries the full message in a same-line comment. That ruling is what
  licenses dropping words and using numeric suffixes -- both of which the design
  doc had rejected on readability grounds that no longer apply.

  WHAT WAS MEASURED, AND WHAT WAS DECLINED
  ----------------------------------------
  The owner also asked for each word to be truncated to its first 6 characters.
  Measured over the whole 82-message corpus, that buys TWO CHARACTERS -- longest
  name 40 without truncation, 38 at 7 chars, 35 at 6 -- because the 40-char soft
  cap and the 6-word cap already bound the length; the STRUCTURAL fixes (context
  prefix, clause cut, noise words) are what removed the long names. It costs
  EMetroloComponeNotFound, EDriverDissape, EConverFailed. So truncation is NOT
  implemented, the bound is met anyway, and MAX_NAME_CHARS is the one constant to
  change if that call is ever reversed.

  EACH CASE BELOW PINS ONE RULE. They are not illustrative; each was a real
  defect found by running the algorithm over the corpus:

    WrongCall        an illegal literal ('Z1.9') is dropped
    StatsmanCall     a SHORT clause head is KEPT, not dropped. Dropping it gave
                     EWrongCall for BOTH this and Z1.9, i.e. a collision created
                     by discarding the only distinguishing word.
    ControlMode      a GENERIC head ('Internal Error:') IS skipped -- the
                     opposite of the case above, and the pair is why both rules
                     are needed rather than one.
    FieldNotFound    the context prefix is stripped in its `Ident SPACE ERROR`
                     form, not only `Ident:`. This is the single biggest win:
                     six 57-61 char TBlueprint4 monsters became three names.
    SidFailed        a token with internal capitals is an IDENTIFIER and keeps
                     its full length. 7 chars of ConvertSidToStringSid is not a
                     shorter name, it is a different one.
    InvoiceNotFound  format specifiers never reach the name -- no digits, no %s.
    CantIdentify     an apostrophe is DELETED, not split on. Splitting made
                     "can't" into can + t, the t was dropped as an illegal
                     literal, and the name silently lost its negation.
    NoLiteral        a raise with no string literal is SKIPPED, never named.

  IT MUST RUN THROUGH lint-all, NOT `lint <file>`. The first version of this
  guard used `lint <file>` and was RED against a WORKING build: ExceptionsUnit
  is wired in DoLintAll ONLY, so the single-file path never enriches at all.
  That is the documented "lint <file> is a silent subset of lint-all" defect,
  and a fixture that cannot REACH the feature reads exactly like a feature that
  does not work.

  POSITIVE CONTROLS, without which every assertion above passes with the
  generator switched off:
    * UNCONFIGURED -- with no exceptions unit, the message must be EXACTLY what
      it always was. Expressed with an explicit key-less --config, NOT by
      omitting --config: since 2026-08-28 lint-all discovers a config from the
      --db path, so omitting the flag no longer means "unconfigured".
    * NoLiteral must still produce a raise-bare-exception finding -- it is
      skipped by the NAMER, not by the RULE.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-excname"
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

$fixture = @'
unit uRaises;
interface
implementation
uses System.SysUtils;

procedure WrongCall;
begin
  raise Exception.Create('Z1.9: Wrong Call');
end;

procedure StatsmanCall;
begin
  raise Exception.Create('Statsman: Wrong Call');
end;

procedure ControlMode;
begin
  raise Exception.Create('Internal Error: Unknown control mode=');
end;

procedure FieldNotFound;
begin
  raise Exception.Create('TBlueprint4_Model.AssignActiveFieldValue ERROR Field not found.');
end;

procedure SidFailed;
begin
  raise Exception.Create('ConvertSidToStringSid failed:');
end;

procedure InvoiceNotFound(Id: Integer);
begin
  raise Exception.CreateFmt('Invoice %d was not found', [Id]);
end;

procedure CantIdentify;
begin
  raise Exception.Create('Internal error, can''t identify the button');
end;

procedure NoLiteral(const M: string);
begin
  raise Exception.Create(M);
end;

procedure RepeatA;
begin
  raise Exception.Create('This plan is set on the HUB screen');
end;

procedure RepeatB;
begin
  raise Exception.Create('This plan is set on the HUB screen');
end;

procedure RepeatC;
begin
  raise Exception.Create('This plan is set on the HUB screen');
end;

end.
'@
New-Item -ItemType Directory (Join-Path $WorkDir 'src') | Out-Null
$src = Join-Path $WorkDir 'src\uRaises.pas'
[System.IO.File]::WriteAllText($src, (($fixture -replace "`r`n", "`n") -replace "`n", "`r`n"),
                               [System.Text.Encoding]::ASCII)

# Config naming the exceptions unit. The DEFAULT name is uExceptionDefinitions,
# so an EMPTY exceptions block must be enough to turn the feature on -- that is
# what "the name is in the default settings as default" means. An ABSENT block
# stays the off switch, because the enrichment costs an extra AST walk per file
# and the unconfigured case has to stay genuinely free.
$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOn,  '{ "exceptions": { } }', [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgOff, '{ }',                   [System.Text.Encoding]::ASCII)

# The enrichment lives in lint-all, so an index is required.
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecRaise", "db": "raise.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\raise.sqlite'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecRaise --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut  = & $Exe lint-all --db $db --config $cfgOn  --quiet 2>&1 | Out-String
  $offOut = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
} finally { Pop-Location }

Write-Host ''
Write-Host 'Derived class names' -ForegroundColor Cyan
function Named([string]$expect) { $onOut -match [regex]::Escape($expect) }

Check 'WrongCall       -> EWrongCall (illegal literal Z1.9 dropped)' `
  (Named 'EWrongCall') ''
Check 'StatsmanCall    -> EStatsmanWrongCall (short head KEPT)' `
  (Named 'EStatsmanWrongCall') 'dropping it collides with the Z1.9 case'
Check 'ControlMode     -> EUnknownControlMode (generic head skipped)' `
  (Named 'EUnknownControlMode') ''
Check 'FieldNotFound   -> EFieldNotFound (Ident SPACE ERROR prefix stripped)' `
  (Named 'EFieldNotFound') ''
Check 'SidFailed       -> EConvertSidToStringSidFailed (identifier not cut)' `
  (Named 'EConvertSidToStringSidFailed') ''
Check 'InvoiceNotFound -> EInvoiceNotFound (format specifier never in the name)' `
  (Named 'EInvoiceNotFound') ''
Check 'CantIdentify    -> EInternalErrorCantIdentifyButton (apostrophe deleted)' `
  (Named 'EInternalErrorCantIdentifyButton') 'splitting on it loses the negation'

Write-Host ''
Write-Host 'No name is ever malformed' -ForegroundColor Cyan
$names = @([regex]::Matches($onOut, '\bE[A-Za-z][A-Za-z0-9]*\b') |
           ForEach-Object { $_.Value } | Sort-Object -Unique |
           Where-Object { $_ -ne 'Exception' })
Check 'every derived name is a legal ASCII Pascal identifier' `
  (-not ($names | Where-Object { $_ -notmatch '^E[A-Za-z][A-Za-z0-9]*$' })) ''
$tooLong = @($names | Where-Object { $_.Length -gt 40 })
Check 'no derived name exceeds 40 characters' ($tooLong.Count -eq 0) `
  ("over: " + ($tooLong -join ', '))
Check 'no derived name carries a format specifier or a bare digit run' `
  (-not ($names | Where-Object { $_ -match '\d{2,}' })) ''

Write-Host ''
Write-Host 'ONE MESSAGE IS ONE CLASS' -ForegroundColor Cyan
# FOUND ON THE CORPUS, NOT BY THIS FIXTURE. The first implementation added
# every generated name to the taken-set immediately, so the SAME message at N
# sites collided with itself and produced EPlanSetOnHUBScreen ..2 ..3 up to
# ..10 on ORM3. A suffix must separate DIFFERENT messages, never one message
# from itself. The original fixture had eight DISTINCT messages and no
# repeats, so it was structurally incapable of seeing this.
$hub = @([regex]::Matches($onOut, 'add (EPlanSetOnHUBScreen\d*) to') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check 'the same message at 3 sites yields ONE name, not three' `
  ($hub.Count -eq 1) ("got: " + ($hub -join ', '))
Check 'and that one name carries no numeric suffix' `
  ($hub -contains 'EPlanSetOnHUBScreen') ("got: " + ($hub -join ', '))

Write-Host ''
Write-Host 'POSITIVE CONTROLS' -ForegroundColor Cyan
Check 'NoLiteral still raises a raise-bare-exception finding' `
  ($onOut -match 'uRaises\.pas:\d+:.*raise-bare-exception') `
  'skipped by the NAMER, not by the RULE'
Check 'NoLiteral is not given an invented name' `
  (-not ($onOut -match 'ENoLiteral|EM\b')) ''
Check 'UNCONFIGURED: no derived name appears at all' `
  (-not ($offOut -match 'EWrongCall|EStatsmanWrongCall|EUnknownControlMode')) `
  'an absent exceptions block must leave the message byte-identical'
Check 'UNCONFIGURED: raise-bare-exception still fires' `
  ($offOut -match 'raise-bare-exception') `
  'otherwise the control above passes because the rule is off'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
