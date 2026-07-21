<#
  run_convert_scaffold_assignability.ps1 -- convert-scaffold consumes the
  proptree assignability engine (Track 3, proptree assignability engine,
  Task 5).

  TASK 5 restricts convert-scaffold's auto-'#link' TARGETS (the To/T side) to
  leaves that are actually valid assignment targets, using the is_writable /
  visibility / member_kind fields Tasks 2-4 already added to TPropNode (both
  the From and To trees come from the SAME BuildPropTree call convert-scaffold
  has always used, so no extra wiring was needed -- see
  src/cli/DRagLint.CLI.pas DoConvertScaffold).

  A new '--surface dfm|pas' flag picks the TARGET-side visibility bar:
    dfm (default) -> only member_kind='property' AND visibility='published'
                      (the DFM-streamable surface; matches today's dominant
                      component-conversion use case).
    pas           -> visibility='published' OR 'public', ANY member_kind
                      (also allows public FIELDS as targets).
  On BOTH surfaces, is_writable=false (a typed class CONST today; a read-only
  PROPERTY once Task 6 lands) is NEVER a valid target -- it gets NO #link (and
  no #default either -- it is fully excluded from the per-To-path scaffold
  loop, the same way DoPropTree's --min-visibility silently drops a
  tier-failing leaf with no extra note).

  FIXTURE (ScafFix.pas):
    TFrom (published Color: Integer; published Caption: string)
    TTo:
      published property Color: Integer   -- (a) normal writable published
                                              leaf; must ALWAYS get a concrete
                                              #link on EVERY surface.
      public    const KMax: Integer = 5;  -- (b) READ-ONLY leaf (is_writable=
                                              false); must get NO #link/#default
                                              line AT ALL, on EITHER surface
                                              (the is_writable filter, not
                                              merely the surface/member_kind
                                              filter, must be doing the work --
                                              load-bearing on the pas surface,
                                              where a public field/const would
                                              otherwise be allowed).
      public    property Caption: string  -- (c) PUBLIC-ONLY leaf (visibility=
                                              'public', not 'published'); on
                                              the dfm surface it gets NO TO-side
                                              line (no #link, no #default) --
                                              it IS still legitimately named on
                                              the FROM side, in a '#note
                                              DROPPED Caption (no T target)'
                                              (TFrom.Caption's only leaf+type
                                              counterpart is filtered out as a
                                              target, so the DROPPED-note loop
                                              -- which uses the SAME
                                              IsValidTarget test -- correctly
                                              reports it dropped rather than
                                              silently neither linked nor
                                              noted). On the pas surface it IS
                                              INCLUDED (concrete #link,
                                              unambiguous match against
                                              TFrom.Caption).
      public    FThing: Integer;          -- (d) WRITABLE PUBLIC FIELD
                                              (member_kind='field',
                                              is_writable=true, visibility=
                                              'public') -- a DIFFERENT case
                                              from KMax (b): KMax short-
                                              circuits at the is_writable gate
                                              (IsValidTarget's FIRST check)
                                              before the surface/member_kind
                                              branch is ever reached, so a
                                              read-only fixture alone can
                                              never exercise the dfm surface's
                                              "member_kind='field' -> Exit(False)"
                                              line (CLI.pas:11147) -- the exact
                                              bug class Task 4 had to
                                              review-fix in the sibling
                                              PassesMinVisibility (a
                                              published-section FIELD still
                                              had to be barred from the
                                              'published' TIER despite its own
                                              Modifiers visibility). FThing is
                                              WRITABLE, so it reaches that
                                              branch: on the dfm surface it
                                              gets NO TO-side line (field
                                              excluded, same DROPPED-note
                                              pattern as Caption); on the pas
                                              surface it IS INCLUDED (concrete
                                              #link, unambiguous match against
                                              TFrom.FThing, which mirrors the
                                              To-side field so the ONLY thing
                                              gating the link is the surface).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-convert-scaffold-assignability
  by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-scaffold-assignability"
)
$ErrorActionPreference = 'Continue'
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

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------------------
# Build + index the ScafFix fixture (F=TFrom, T=TTo)
# ---------------------------------------------------------------------------
$FixBody = @'
unit ScafFix;

interface

type
  TFrom = class(TPersistent)
  private
    FColor: Integer;
    FCaption: string;
  public
    FThing: Integer;
  published
    property Color: Integer read FColor write FColor;
    property Caption: string read FCaption write FCaption;
  end;

  TTo = class(TPersistent)
  private
    FColor: Integer;
    FCaption: string;
  public
    FThing: Integer;
    const KMax: Integer = 5;
    property Caption: string read FCaption write FCaption;
  published
    property Color: Integer read FColor write FColor;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'ScafFix.pas') $FixBody

$db = Join-Path $WorkDir 'scaffix.sqlite'
Write-Host 'Indexing ScafFix fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

# ---------------------------------------------------------------------------
# (1) DEFAULT surface (dfm, published-only): Color concrete #link; KMax and
#     Caption BOTH absent entirely (no #link, no #default, no mention).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --from ScafFix.TFrom --to ScafFix.TTo (default surface = dfm)' -ForegroundColor Cyan
$dfmRaw = (& $Exe convert-scaffold --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --db $db) -join "`n"
$dfmExit = $LASTEXITCODE
Check 'scaffold (default) exits 0' ($dfmExit -eq 0) "exit=$dfmExit"
Write-Host $dfmRaw -ForegroundColor DarkGray

Check 'default: Color gets a concrete #link' ($dfmRaw -match '#link\s+Color\s+<-\s+Color') "raw=$dfmRaw"
Check 'default: KMax (read-only) NOT mentioned at all' ($dfmRaw -notmatch 'KMax') "raw=$dfmRaw"
# Caption (public-only) must get NO #link/#default TO-side line on the dfm
# surface -- it IS still legitimately named on the FROM side, in a '#note
# DROPPED Caption (no T target)' line: TFrom.Caption's only leaf+type
# counterpart (TTo.Caption) is filtered OUT as a target on this surface, so
# ToHasCounterpart correctly reports it dropped (same IsValidTarget test as
# the #link loop -- this is the load-bearing proof the DROPPED-note loop was
# updated too, not just the #link loop).
Check 'default: Caption gets NO #link line' ($dfmRaw -notmatch '#link\s+Caption') "raw=$dfmRaw"
Check 'default: Caption gets NO #default line' ($dfmRaw -notmatch '#default\s+Caption') "raw=$dfmRaw"
Check 'default: Caption (FROM side) correctly reported DROPPED' ($dfmRaw -match '#note\s+DROPPED\s+Caption\s+\(no T target\)') "raw=$dfmRaw"

# FThing (WRITABLE public field) -- the load-bearing case for the dfm
# surface's member_kind='field' exclusion (CLI.pas:11147). Unlike KMax,
# FThing is_writable=true, so it actually REACHES that branch instead of
# short-circuiting at the is_writable gate. Same TO-side exclusion + FROM-side
# DROPPED-note pattern as Caption.
Check 'default: FThing (writable field) gets NO #link line' ($dfmRaw -notmatch '#link\s+FThing') "raw=$dfmRaw"
Check 'default: FThing (writable field) gets NO #default line' ($dfmRaw -notmatch '#default\s+FThing') "raw=$dfmRaw"
Check 'default: FThing (FROM side) correctly reported DROPPED' ($dfmRaw -match '#note\s+DROPPED\s+FThing\s+\(no T target\)') "raw=$dfmRaw"

# ---------------------------------------------------------------------------
# (2) Explicit --surface dfm: same as default (sanity: default really IS dfm).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --surface dfm (explicit)' -ForegroundColor Cyan
$dfmExplicitRaw = (& $Exe convert-scaffold --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --surface dfm --db $db) -join "`n"
$dfmExplicitExit = $LASTEXITCODE
Check '--surface dfm exits 0' ($dfmExplicitExit -eq 0) "exit=$dfmExplicitExit"
Check '--surface dfm output == default output' ($dfmExplicitRaw -eq $dfmRaw) "explicit=$dfmExplicitRaw`ndefault=$dfmRaw"

# ---------------------------------------------------------------------------
# (3) --surface pas: Color concrete #link; Caption concrete #link (now
#     INCLUDED -- public property, unambiguous match); KMax STILL absent (the
#     is_writable filter, independent of the surface/member_kind bar).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --surface pas' -ForegroundColor Cyan
$pasRaw = (& $Exe convert-scaffold --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --surface pas --db $db) -join "`n"
$pasExit = $LASTEXITCODE
Check '--surface pas exits 0' ($pasExit -eq 0) "exit=$pasExit"
Write-Host $pasRaw -ForegroundColor DarkGray

Check 'pas: Color still gets a concrete #link' ($pasRaw -match '#link\s+Color\s+<-\s+Color') "raw=$pasRaw"
Check 'pas: Caption (public-only) NOW INCLUDED with a concrete #link' ($pasRaw -match '#link\s+Caption\s+<-\s+Caption') "raw=$pasRaw"
Check 'pas: KMax (read-only) STILL NOT mentioned at all' ($pasRaw -notmatch 'KMax') "raw=$pasRaw"
# FThing (writable public field): on pas surface member_kind='field' is
# allowed, so the writable-field target IS auto-linked -- the counterpart
# assertion to the dfm-surface exclusion above; together these two prove
# CLI.pas:11147 gates on SURFACE, not on some other accidental property.
Check 'pas: FThing (writable field) NOW INCLUDED with a concrete #link' ($pasRaw -match '#link\s+FThing\s+<-\s+FThing') "raw=$pasRaw"

# ---------------------------------------------------------------------------
# (4) Round-trip: the pas-surface emitted file must still validate clean
#     (every concrete path emitted is real, even though the tree used for
#     validation is the FULL unfiltered tree).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --surface pas --out (write file), then convert-validate round-trip' -ForegroundColor Cyan
$emitted = Join-Path $WorkDir 'emitted-pas-rules.txt'
$outOut = & $Exe convert-scaffold --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --surface pas --out $emitted --db $db 2>&1
$outExit = $LASTEXITCODE
Check 'scaffold --out exits 0' ($outExit -eq 0) "exit=$outExit; $($outOut -join ' | ')"
Check 'emitted file exists' (Test-Path $emitted) "path=$emitted"

Push-Location $WorkDir
try {
  $valOut = (& $Exe convert-validate --rules $emitted --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --db $db) -join "`n"
  $valExit = $LASTEXITCODE
} finally { Pop-Location }
Check 'round-trip convert-validate exits 0' ($valExit -eq 0) "exit=$valExit; out=$valOut"

# ---------------------------------------------------------------------------
# (5) Bad --surface value -> usage error exit 2.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'convert-scaffold --surface bogus' -ForegroundColor Cyan
$badSurfOut = ((& $Exe convert-scaffold --from 'ScafFix.TFrom' --to 'ScafFix.TTo' --surface bogus --db $db 2>&1) -join "`n")
$badSurfExit = $LASTEXITCODE
Check 'bad --surface value exits 2' ($badSurfExit -eq 2) "exit=$badSurfExit; out=$badSurfOut"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
