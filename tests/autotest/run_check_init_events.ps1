<#
  run_check_init_events.ps1 -- acceptance for check-init lane EVENTS (1.52, rulings HB2 + HB4):
  DRagLint.Query.HappensBefore.Events.CollectEvents / HbIsNeverSet.

  Indexes the three fixtures tests\fixtures\happens-before\events-{global,args,softwriters} with the
  engine under test, builds tests\fixtures\happens-before\events-harness\HbEventsHarness.dpr (dcc64,
  search paths read from src\cli\drag-lint.dproj) and asserts on its JSON, which is the check-init
  answer shape (HbAnswerJson): `.writers` / `.uses` rows exactly (file, line, col, routine, how,
  resolved, counts, fired_by, callers), the target kind / zero value, the usage errors (exit 2 with
  the candidates), --at selection, and the NEVER-SET preconditions.

  TWINS (each MAY case has its one-line partner):
    * assign-nil:  GPtr := nil (counts false, blocker nil-write-only)  vs  GCount := 1 (counts true)
    * NEVER-SET:   GPlain (no writer: NEVER-SET)  vs  GPlainTwin (+ Poke(@GPlainTwin): soft-writer)
    * guarded:     Assigned(GCache) (guarded-test)  vs  GCache.Free (judged)
    * arguments:   Fill(GFill) var / Get(GOut) out (writers)  vs  Show(GConst) const / ShowV value (none)
    * published:   TSoftForm.edtName (DFM component: dfm-stream, published)  vs  FCount (private: none)
  CROSS-CHECK: read-never-assigned reports a fixture unit variable  <=>  HbIsNeverSet says NEVER-SET
  (with a positive control that both sides are non-empty).

  Usage: pwsh -File tests\autotest\run_check_init_events.ps1 [-Exe <drag-lint.exe>]
  Exit 0 = PASS, 1 = FAIL, 2 = could not run (harness did not compile).
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path C:\TEMP "draglint_hbev_$PID"
$script:pass = 0
$script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++ } else { $script:fail++ }
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail -and -not $Ok) { "  ($Detail)" } else { '' }))
}

$src = Join-Path $work 'src'; $dcu = Join-Path $work 'dcu'; $out = Join-Path $work 'out'
foreach ($d in @($src, $dcu, $out)) { [void](New-Item -ItemType Directory -Force -Path $d) }
$fixRoot = Join-Path $repo 'tests\fixtures\happens-before'
$dbs = @{}
foreach ($fx in @('events-global', 'events-args', 'events-softwriters')) {
  Copy-Item (Join-Path $fixRoot $fx) $src -Recurse -Force
  $db = Join-Path $work "$fx.sqlite"
  & { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $src $fx) --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $dbs[$fx] = $db
}

. (Join-Path $repo 'tests\autotest\lib\CliBuildPaths.ps1')
$cli = Get-CliDcc64Args
# src\charts (DRagLint.Charts.Index, the read-only query helper) is listed by the .dpr, not on the CLI search path
$args2 = $cli.Args.Replace('-U"', ('-U"{0};' -f (Join-Path $repo 'src\charts')))
$bat = Join-Path $work 'build.bat'
$lines = @('@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"',
  ('cd /d "{0}"' -f (Join-Path $fixRoot 'events-harness')),
  ('dcc64 -B {0} -E"{1}" -NU"{2}" HbEventsHarness.dpr' -f $args2, $out, $dcu),
  'echo BUILD_EXITCODE=%ERRORLEVEL%')
[IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$log = Join-Path $work 'build.log'
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$b = Get-Content $log -Raw
if ($b -notmatch 'BUILD_EXITCODE=0') {
  ($b -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal|BUILD_EXITCODE' } | ForEach-Object { Write-Host $_ }
  Write-Host 'FATAL: harness did not compile'; exit 2
}
[void](Copy-TreeSitterDlls -Dest $out)
$harness = Join-Path $out 'HbEventsHarness.exe'

function Hb([string]$Fx, [string]$Target, [string]$At = '') {
  $a = @($dbs[$Fx], $(if ($Target) { $Target } else { '-' }))
  if ($At) { $a += $At }
  $errFile = Join-Path $work 'err.txt'
  $o = & { $ErrorActionPreference = 'Continue'; & $harness @a 2>$errFile }
  $r = [pscustomobject]@{ Exit = $LASTEXITCODE; Json = $null; Err = (Get-Content $errFile -Raw) }
  if ($r.Exit -eq 0) { $r.Json = (($o -join "`n") | ConvertFrom-Json) }
  return $r
}
function WriterRows($J) {
  return @($J.writers | ForEach-Object {
    '{0}:{1}:{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f (Split-Path $_.file -Leaf), $_.line, $_.col, $_.routine, $_.how,
      $_.resolved.ToString().ToLower(), $_.counts.ToString().ToLower(), $_.fired_by, $_.callers.count, ($_.callers.top -join ',') })
}
function UseRows($J) {
  return @($J.uses | ForEach-Object { '{0}:{1}:{2}|{3}|{4}' -f (Split-Path $_.file -Leaf), $_.line, $_.col, $_.routine, ($_.reasons -join ',') })
}
function Same([string[]]$Got, [string[]]$Want) { return (($Got -join "`n") -ceq ($Want -join "`n")) }
function GotText([string[]]$Got) { return ('got: ' + ($Got -join ' ;; ')) }

# raw output once, before any filtering
$raw = & { $ErrorActionPreference = 'Continue'; & $harness $dbs['events-global'] 'evgData.GCache' 2>&1 | ForEach-Object { "$_" } }
Write-Host '  raw (evgData.GCache):'
Write-Host "  $raw"

try {
  # ---- events-global: how, assign-nil twins, guarded twins, callers, fired_by ----
  $r = Hb 'events-global' 'evgData.GCache'
  $w = WriterRows $r.Json; $u = UseRows $r.Json
  Check 'GCache: target is a unit-variable with zero value nil' (($r.Json.target.kind -eq 'unit-variable') -and ($r.Json.target.zero_value -eq 'nil') -and ($r.Json.target.line -eq 25))
  Check 'GCache: writers = create-into (callers CallA, CallB) + := nil + FreeAndNil (assign-nil, do not count)' (Same $w @(
    'evgData.pas:47:3|evgData.SetUp|create-into|true|true||2|evgData.CallA,evgData.CallB',
    'evgData.pas:63:3|evgData.Reset|assign-nil|true|false||0|',
    'evgData.pas:68:14|evgData.Reset|assign-nil|true|false||0|')) (GotText $w)
  Check 'GCache: uses = Assigned(GCache) guarded-test, GCache.Free judged (FreeAndNil arg is no use)' (Same $u @(
    'evgData.pas:75:15|evgData.UseIt|guarded-test',
    'evgData.pas:76:5|evgData.UseIt|')) (GotText $u)

  $r = Hb 'events-global' 'evgData.GCount'
  $w = WriterRows $r.Json
  Check 'GCount: assign counts; DFM-bound handler names BOTH bindings in fired_by, callers 0' (Same $w @(
    'evgData.pas:48:3|evgData.SetUp|assign|true|true||2|evgData.CallA,evgData.CallB',
    'evgMain.pas:28:3|evgMain.TMainForm.btnGoClick|assign|true|true|MainForm.btnGo.OnClick, MainForm.btnAgain.OnClick|0|')) (GotText $w)
  Check 'GCount (assign-nil twin): verdict not NEVER-SET, no blocker' (($r.Json.verdict -eq 'MAY-BE-UNSET') -and (@($r.Json.reasons).Count -eq 0))

  $r = Hb 'events-global' 'evgData.GPtr'
  $w = WriterRows $r.Json; $u = UseRows $r.Json
  Check 'GPtr := nil: assign-nil, does not count' (Same $w @('evgData.pas:64:3|evgData.Reset|assign-nil|true|false||0|')) (GotText $w)
  Check 'GPtr: only nil writes -> not NEVER-SET, blocker nil-write-only' (($r.Json.verdict -eq 'MAY-BE-UNSET') -and ((@($r.Json.reasons) -join ',') -eq 'nil-write-only'))
  Check 'GPtr <> nil is a guarded-test use' (Same $u @('evgData.pas:77:6|evgData.UseIt|guarded-test')) (GotText $u)

  $r = Hb 'events-global' 'evgData.GProc'
  $w = WriterRows $r.Json; $u = UseRows $r.Json
  Check 'GProc :=<newline> nil (procedural, right side on the next line): assign-nil' (Same $w @('evgData.pas:66:3|evgData.Reset|assign-nil|true|false||0|')) (GotText $w)
  Check 'GProc = nil is a guarded-test use' (Same $u @('evgData.pas:81:6|evgData.UseIt|guarded-test')) (GotText $u)

  $r = Hb 'events-global' 'evgData.GIntf'
  $w = WriterRows $r.Json
  Check 'GIntf (interface): := nil in Reset and in FormCreate (fired_by MainForm.OnCreate), neither counts' (Same $w @(
    'evgData.pas:65:3|evgData.Reset|assign-nil|true|false||0|',
    'evgMain.pas:34:3|evgMain.TMainForm.FormCreate|assign-nil|true|false|MainForm.OnCreate|0|')) (GotText $w)

  $r = Hb 'events-global' 'evgMain.MainForm'
  $w = WriterRows $r.Json
  Check 'MainForm: Application.CreateForm(.., MainForm) in the program block is a var-arg writer' (Same $w @('evGlobal.dpr:15:37|evGlobal|var-arg|true|true||0|')) (GotText $w)

  $r = Hb 'events-global' 'evgData.GNever'
  Check 'GNever: no writer -> NEVER-SET, no blocker, its read is a use' (($r.Json.verdict -eq 'NEVER-SET') -and (@($r.Json.writers).Count -eq 0) -and (Same (UseRows $r.Json) @('evgData.pas:78:19|evgData.UseIt|')))

  $r = Hb 'events-global' 'TEvgCfg.CInstances'
  Check 'TEvgCfg.CInstances is a class-var, written in Init' (($r.Json.target.kind -eq 'class-var') -and (Same (WriterRows $r.Json) @('evgData.pas:89:3|evgData.TEvgCfg.Init|assign|true|true||0|')))
  $r = Hb 'events-global' 'evgData.TEvgCfg.FName'
  Check 'TEvgCfg.FName is an instance-field with zero value '''', written in Init' (($r.Json.target.kind -eq 'instance-field') -and ($r.Json.target.zero_value -eq "''") -and (Same (WriterRows $r.Json) @('evgData.pas:88:3|evgData.TEvgCfg.Init|assign|true|true||0|')))

  # ---- usage errors: exit 2 with a one-line reason / the candidates ----
  $r = Hb 'events-global' 'GAmb'
  Check 'bare GAmb: exit 2, ambiguous, both candidates printed' (($r.Exit -eq 2) -and ($r.Err -match 'ambiguous target "GAmb"') -and ($r.Err -match 'candidate: evgData\.GAmb') -and ($r.Err -match 'candidate: evgOther\.GAmb')) $r.Err
  $r = Hb 'events-global' 'evgOther.GAmb'
  Check 'qualified evgOther.GAmb resolves (control): initialization writer' (($r.Exit -eq 0) -and (Same (WriterRows $r.Json) @('evgOther.pas:13:3|evgOther.initialization|assign|true|true||0|')))
  foreach ($case in @(@('evgData.UseIt.L', 'is a local variable'), @('TEvgCfg.Name', 'is a property'), @('TEvgRec.RVal', 'is a record field'),
                      @('cEvgTyped', 'is a constant'), @('NoSuchVar', 'unknown target "NoSuchVar"'))) {
    $r = Hb 'events-global' $case[0]
    Check ("{0}: exit 2, '{1}'" -f $case[0], $case[1]) (($r.Exit -eq 2) -and ($r.Err -match [regex]::Escape($case[1]))) $r.Err
  }

  # ---- --at ----
  $r = Hb 'events-global' '' 'evgData.pas:76:5'
  Check '--at on a use: target GCache, the ONE use judged' (($r.Exit -eq 0) -and ($r.Json.target.qname -eq 'evgData.GCache') -and (Same (UseRows $r.Json) @('evgData.pas:76:5|evgData.UseIt|')))
  $r = Hb 'events-global' '' 'evgData.pas:76'
  Check '--at file:line with one variable on the line resolves without a column' (($r.Exit -eq 0) -and (Same (UseRows $r.Json) @('evgData.pas:76:5|evgData.UseIt|')))
  $r = Hb 'events-global' '' 'evgData.pas:25:3'
  Check '--at on the declaration: every use is judged' (($r.Exit -eq 0) -and (@($r.Json.uses).Count -eq 2))
  $r = Hb 'events-global' '' 'evgData.pas:78'
  Check '--at line with three variables: exit 2, add the column, candidates' (($r.Exit -eq 2) -and ($r.Err -match 'names 3 variables') -and ($r.Err -match 'candidate: evgData\.GNever')) $r.Err
  $r = Hb 'events-global' 'evgData.GCount' 'evgData.pas:76:5'
  Check 'QName and a --at naming another variable: exit 2' (($r.Exit -eq 2) -and ($r.Err -match '--at names evgData\.GCache, not evgData\.GCount')) $r.Err
  $r = Hb 'events-global' '' 'nosuch.pas:3'
  Check '--at on a file the index does not hold: exit 2' (($r.Exit -eq 2) -and ($r.Err -match 'no indexed file matches')) $r.Err

  # ---- events-args: var / out writers vs const / value controls ----
  foreach ($case in @(@('GFill', 'evaData.pas:42:8|evaData.Run|var-arg|true|true||1|evArgs'),
                      @('GOut', 'evaData.pas:43:7|evaData.Run|out-arg|true|true||1|evArgs'),
                      @('GInc', 'evaData.pas:48:7|evaData.Run|var-arg|true|true||1|evArgs'),
                      @('GDpr', 'evArgs.dpr:11:8|evArgs|var-arg|true|true||0|'))) {
    $r = Hb 'events-args' $case[0]
    $w = WriterRows $r.Json
    Check ("{0}: one counting argument writer" -f $case[0]) (Same $w @($case[1])) (GotText $w)
    Check ("{0}: the argument is no use" -f $case[0]) (@($r.Json.uses).Count -eq 0)
  }
  $r = Hb 'events-args' 'GFillTwice'
  Check 'GFillTwice: two var-arg rows, one per call' (Same (WriterRows $r.Json) @(
    'evaData.pas:46:8|evaData.Run|var-arg|true|true||1|evArgs', 'evaData.pas:47:8|evaData.Run|var-arg|true|true||1|evArgs')) (GotText (WriterRows $r.Json))
  $r = Hb 'events-args' 'GConst'
  Check 'GConst (control): const and value arguments write nothing -> NEVER-SET, two uses' (($r.Json.verdict -eq 'NEVER-SET') -and (@($r.Json.writers).Count -eq 0) -and
    (Same (UseRows $r.Json) @('evaData.pas:44:8|evaData.Run|', 'evaData.pas:45:9|evaData.Run|')))

  # ---- events-softwriters: soft writers, the NEVER-SET twin, published ----
  $r = Hb 'events-softwriters' 'GPlain'
  Check 'GPlain: NEVER-SET, no blocker' (($r.Json.verdict -eq 'NEVER-SET') -and (@($r.Json.reasons).Count -eq 0) -and (@($r.Json.writers).Count -eq 0))
  $r = Hb 'events-softwriters' 'GPlainTwin'
  Check 'GPlainTwin (+ Poke(@GPlainTwin)): address-of soft writer, MAY-BE-UNSET, blocker soft-writer' (($r.Json.verdict -eq 'MAY-BE-UNSET') -and
    ((@($r.Json.reasons) -join ',') -eq 'soft-writer') -and (Same (WriterRows $r.Json) @('evsData.pas:34:9|evsData.Touch|address-of|false|false||0|'))) (GotText (WriterRows $r.Json))
  $r = Hb 'events-softwriters' 'GWith'
  Check 'GWith: the unresolved write inside `with` is with-opaque, soft' (Same (WriterRows $r.Json) @('evsData.pas:32:5|evsData.Touch|with-opaque|false|false||0|')) (GotText (WriterRows $r.Json))
  $r = Hb 'events-softwriters' 'GAbs'
  Check 'GAbs: GAlias := 4 (GAlias absolute GAbs) is a soft writer; the absolute clause is no use' (($r.Json.verdict -eq 'MAY-BE-UNSET') -and
    (Same (WriterRows $r.Json) @('evsData.pas:33:3|evsData.Touch|address-of|false|false||0|')) -and (Same (UseRows $r.Json) @('evsData.pas:35:42|evsData.Touch|'))) (GotText (WriterRows $r.Json))
  $r = Hb 'events-softwriters' 'GAlias'
  Check 'GAlias: an absolute overlay itself (limits absolute-overlay)' (@($r.Json.limits) -contains 'absolute-overlay')
  $r = Hb 'events-softwriters' 'TSoftForm.edtName'
  Check 'edtName: DFM component -> dfm-stream writer (counts), published, zero nil' ((Same (WriterRows $r.Json) @(
    'evsForm.dfm:7:3|evsForm.TSoftForm (DFM streaming of SoftForm)|dfm-stream|true|true||0|')) -and (@($r.Json.limits) -contains 'published') -and ($r.Json.target.zero_value -eq 'nil')) (GotText (WriterRows $r.Json))
  $r = Hb 'events-softwriters' 'TSoftForm.FCount'
  Check 'FCount (published control): private field, not streamed -> NEVER-SET, not published' (($r.Json.verdict -eq 'NEVER-SET') -and -not (@($r.Json.limits) -contains 'published'))

  # ---- cross-check with read-never-assigned (spec 9: the NEVER-SET list must agree with the rule) ----
  $ruleSet = @(); $hbSet = @()
  foreach ($fx in @('events-global', 'events-args', 'events-softwriters')) {
    $vars = (& { $ErrorActionPreference = 'Continue'; & $exePath sql --db $dbs[$fx] --query "SELECT s.qualified_name AS q FROM symbols s JOIN symbols p ON p.id = s.parent_id WHERE s.kind = 'var' AND p.kind = 'unit' ORDER BY 1" --json 2>$null }) -join "`n"
    $vj = $vars.Substring($vars.IndexOf('{')) | ConvertFrom-Json
    foreach ($row in $vj.rows) {
      $q = [string]$row[0]
      $r = Hb $fx $q
      if ($r.Exit -eq 0 -and $r.Json.verdict -eq 'NEVER-SET') { $hbSet += $q }
    }
    foreach ($pas in (Get-ChildItem (Join-Path $src $fx) -Filter *.pas)) {
      $lj = (& { $ErrorActionPreference = 'Continue'; & $exePath lint $pas.FullName --db $dbs[$fx] --rule read-never-assigned --json 2>$null }) -join "`n"
      foreach ($f in @($lj | ConvertFrom-Json)) {
        if ($f.message -match 'Global variable (\w+) is read') { $ruleSet += ('{0}.{1}' -f $pas.BaseName, $Matches[1]) }
      }
    }
  }
  $ruleSet = @($ruleSet | Sort-Object); $hbSet = @($hbSet | Sort-Object)
  Write-Host ("  read-never-assigned: {0}" -f ($ruleSet -join ', '))
  Write-Host ("  HbIsNeverSet       : {0}" -f ($hbSet -join ', '))
  Check 'cross-check positive control: both lists have at least 5 variables' (($ruleSet.Count -ge 5) -and ($hbSet.Count -ge 5))
  Check 'cross-check: read-never-assigned <=> NEVER-SET for every fixture unit variable' (Same $ruleSet $hbSet)
}
catch {
  Write-Host "[FAIL] runner error: $_"
  $script:fail++
}
finally {
  Write-Host ("SUMMARY: {0} PASS, {1} FAIL -> {2}" -f $script:pass, $script:fail, $(if ($script:fail -eq 0) { 'PASS' } else { 'FAIL' }))
}
if ($script:fail -gt 0) { exit 1 }
exit 0
