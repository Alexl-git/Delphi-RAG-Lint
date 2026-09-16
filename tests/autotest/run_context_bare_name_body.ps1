<#
  run_context_bare_name_body.ps1 --
  A BARE name that RESOLVES must produce the same bundle BODY as its qualified form.

  THE DEFECT (measured 2026-09-15). `context --task "modify DoHover"` returned 870
  bytes with NO `## Impl slice`; `context --task "modify DRagLint.CLI.DoHover"`
  returned 5,035 bytes WITH it. The bare form is not a miss -- it RESOLVES, and
  says so: its header reads `# Context bundle: modify DRagLint.CLI.DoHover`. It
  then omits the one thing a "modify X" task asked for -- X's own body.

  WHY IT EXISTED. `DRagLint.Context.Bundler.pas:293-303` taught the bundler to
  resolve an unambiguous bare name and set `Result.QName` to the RESOLVED
  qualified name, so the header became honest. Three downstream uses kept reading
  the RAW `AQName`: the class-surface parent (:343), the impl slice (:361) and the
  caller name (:364). The header was fixed; the body was not.

  WHY IT MATTERS MORE THAN ITS SIZE. This is the verb the token-saving path runs
  on: a 25,198-line unit is ~338,500 tokens to Read and ~1,259 as a bundle. An
  agent handed the 870-byte bundle edits a routine it never saw, and nothing about
  the result looks wrong.

  WHAT MUST NOT REGRESS. An AMBIGUOUS bare name must still resolve to nothing
  (Bundler.pas:287-291): picking Syms[0] out of several would be a confidently
  wrong bundle, which is worse than an empty one. T3 pins that.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_bare_name"
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

# UniqueOnlyRoutine is deliberately unique in this fixture, so the bare name
# RESOLVES. TwinRoutine is deliberately declared in TWO units, so the bare name
# is AMBIGUOUS -- that is T3's fixture, and without it T3 could not fail.
Write-Ascii (Join-Path $src 'uOne.pas') @"
unit uOne;

interface

type
  TWorker = class(TObject)
  public
    function UniqueOnlyRoutine(const AMask: string): Integer;
    function TwinRoutine: Integer;
  end;

implementation

function TWorker.UniqueOnlyRoutine(const AMask: string): Integer;
var
  Scratch: Integer;
begin
  Scratch := Length(AMask);
  if Scratch > 3 then
    Scratch := Scratch * 2;
  Result := Scratch;
end;

function TWorker.TwinRoutine: Integer;
begin
  Result := 1;
end;

end.
"@

Write-Ascii (Join-Path $src 'uTwo.pas') @"
unit uTwo;

interface

type
  TOther = class(TObject)
  public
    function TwinRoutine: Integer;
    procedure CallIt;
  end;

implementation

uses
  uOne;

function TOther.TwinRoutine: Integer;
begin
  Result := 2;
end;

procedure TOther.CallIt;
var
  W: TWorker;
begin
  W := TWorker.Create;
  W.UniqueOnlyRoutine('abcd');
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# The call operator, NOT Start-Process -ArgumentList. Start-Process does not
# quote an argument containing spaces, so `--task` `modify uOne.TWorker.X`
# arrived as `--task modify` plus a stray positional, and the engine answered
# `No symbol matched: modify` -- 27 bytes that look exactly like the truncated
# bundle this guard is hunting. That false reading cost a diagnosis; do not
# "simplify" this back.
function Bundle([string]$Task) {
  return ((& $exePath context --task $Task --db $db --format markdown 2>$null) -join "`r`n")
}

$qual = Bundle 'modify uOne.TWorker.UniqueOnlyRoutine'
$bare = Bundle 'modify UniqueOnlyRoutine'

# ---- P1/P2 POSITIVE CONTROLS ------------------------------------------------
# Without these, T1/T2 pass against a build whose bundle emits no body for ANY
# name -- i.e. against a completely broken verb.
Check 'P1 POSITIVE CONTROL the QUALIFIED name produces an Impl slice' `
      ($qual -match '## Impl slice') `
      "the qualified bundle has no body either, so T1 would prove nothing. Got $($qual.Length) bytes."
Check 'P2 POSITIVE CONTROL the qualified bundle contains the routine BODY, not just its header' `
      ($qual -match 'Scratch') `
      'the Impl slice section is present but empty -- the assertion below would be vacuous'

# ---- T1/T2: the defect ------------------------------------------------------
Check 'T1 a RESOLVING bare name produces an Impl slice' `
      ($bare -match '## Impl slice') `
      "bare bundle is $($bare.Length) bytes with no body; qualified is $($qual.Length) bytes with one"
Check 'T2 the bare bundle carries the same routine body as the qualified one' `
      ($bare -match 'Scratch') `
      'the bare bundle resolved the symbol but omitted the body the task named'

# The header already reported the RESOLVED name before this fix; if that ever
# regresses, T1 would be chasing the wrong thing.
Check 'T2b the bare bundle still reports the RESOLVED qualified name in its header' `
      ($bare -match 'uOne\.TWorker\.UniqueOnlyRoutine') `
      'the header stopped naming which symbol was chosen -- the reader loses their evidence'

# ---- T3: the deliberate behaviour that must NOT regress ---------------------
$ambig = Bundle 'modify TwinRoutine'
Check 'T3 an AMBIGUOUS bare name still resolves to NOTHING (no confidently-wrong bundle)' `
      (-not ($ambig -match '## Impl slice')) `
      'an ambiguous bare name now picks one symbol and emits its body -- Bundler.pas:287-291 says that is worse than empty'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
