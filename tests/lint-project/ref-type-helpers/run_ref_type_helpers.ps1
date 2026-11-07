<#
  run_ref_type_helpers.ps1 -- guard for the two exports of DRagLint.Lint.RefTypeRules that other
  rules build on (lane 145 L0): TypeDescendsFrom (H4) and StaticTypeLeafOfExpr (O1).

  Lane 145 gaps: a member read off a call result (ref-gap G6), a bare local at its use site, and
  the reader's own answer inside `with` (a row is proof, a written type is not).

  Indexes uRhTypes.pas with the engine under test, builds RefTypeHelpersHarness.dpr, runs it twice:
  on the DB (TRIGGER: dotted and call expressions answer their type, descent answers yes and no)
  and on a copy with ref_types dropped (the no-table degrade: every LEAF answers '-', and DESC
  answers exactly as before because it reads type_ancestors only).
  CONTROLS: an unknown expression and an unrelated or unfollowable ancestry never answer yes.

  Usage: pwsh -File tests\lint-project\ref-type-helpers\run_ref_type_helpers.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path C:\TEMP "draglint_rth_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
try {
  $src = Join-Path $work 'src'; $dcu = Join-Path $work 'dcu'; $out = Join-Path $work 'out'
  foreach ($d in @($src, $dcu, $out)) { [void](New-Item -ItemType Directory -Force -Path $d) }
  Copy-Item (Join-Path $PSScriptRoot 'uRhTypes.pas') $src
  $db = Join-Path $work 'rth.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  Copy-Item $db "$db.notable"

  . (Join-Path $repo 'tests\autotest\lib\CliBuildPaths.ps1')
  $cli = Get-CliDcc64Args
  $bat = Join-Path $work 'build.bat'
  $lines = @('@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"',
    ('cd /d "{0}"' -f $PSScriptRoot),
    ('dcc64 -B {0} -E"{1}" -N0"{2}" RefTypeHelpersHarness.dpr' -f $cli.Args, $out, $dcu),
    'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $work 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  $b = Get-Content $log -Raw
  if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host 'FATAL: harness did not compile'; exit 2 }
  [void](Copy-TreeSitterDlls -Dest $out)
  $h = Join-Path $out 'RefTypeHelpersHarness.exe'
  $on  = @(& $h $db 2>&1)
  $off = @(& $h "$db.notable" notable 2>&1)
  $on  | ForEach-Object { Write-Host "  on : $_" }
  $off | ForEach-Object { Write-Host "  off: $_" }

  # TRIGGER: dotted and call expressions answer the type of their last hop
  Check 'dotted: H.FLeaf is TRhLeaf'            ($on -contains 'LEAF|H.FLeaf|TRhLeaf')
  Check 'call: H.Make(1) is TRhMid'             ($on -contains 'LEAF|H.Make(1)|TRhMid')
  Check 'chain call: H.Names().Make(2) is TRhMid' ($on -contains 'LEAF|H.Names().Make(2)|TRhMid')
  # CONTROL: an expression with no ref_types row answers nothing, it is not guessed
  Check 'control: Zip.Zap has no type'          ($on -contains 'LEAF|Zip.Zap|-')
  # NO-TABLE: a DB without ref_types answers nothing for every expression
  $offLeaf = @($off | Where-Object { $_ -like 'LEAF|*' })
  Check 'no table: every LEAF is -' (($offLeaf.Count -eq @($on | Where-Object { $_ -like 'LEAF|*' }).Count) -and ($offLeaf.Count -gt 4) -and (@($offLeaf | Where-Object { $_ -notlike '*|-' }).Count -eq 0))
  Check 'every expression reached a node' (@($on | Where-Object { $_ -like '*|`?node' }).Count -eq 0) (@($on | Where-Object { $_ -like '*|`?node' }) -join ',')

  # GAP 1: a member read off a call result has a ref and a type, for every call-rooted shape
  Check 'call-rooted: H.Names().FLeaf is TRhLeaf'    ($on -contains 'LEAF|H.Names().FLeaf|TRhLeaf')
  Check 'call-rooted: RhFree().FLeaf (no args)'      ($on -contains 'LEAF|RhFree().FLeaf|TRhLeaf')
  Check 'call-rooted: RhFree2(1, 2).FLeaf (two args)' ($on -contains 'LEAF|RhFree2(1, 2).FLeaf|TRhLeaf')
  Check 'call-rooted: a dotted hop after the calls'  ($on -contains 'LEAF|H.Pick(1, 2).Names().Sub.FLeaf|TRhOther')
  # CONTROL: the ref exists but nothing declares the member, or the chain's root is unknown: no type
  Check 'call-rooted: bare call on the implicit Self' ($on -contains 'LEAF|W23(Names().FLeaf)>Names().FLeaf|TRhLeaf')
  Check 'control: H.Names().NoSuch has no type'      ($on -contains 'LEAF|H.Names().NoSuch|-')
  Check 'control: Zip.Make().Zap has no type'        ($on -contains 'LEAF|Zip.Make().Zap|-')
  # The shape G5 already covers keeps its answer and exactly one member-access row
  Check 'hard-cast shape: RhOne(1).FLeaf still typed' ($on -contains 'LEAF|RhOne(1).FLeaf|TRhLeaf')
  function CountRefs([string]$Where) {
    $j = (& $exePath sql --db $db --query "SELECT COUNT(*) FROM refs WHERE $Where" --json 2>$null) -join "`n"
    $start = $j.IndexOf('{')
    return [int](($j.Substring($start) | ConvertFrom-Json).rows[0][0])
  }
  $srcLines = [IO.File]::ReadAllLines((Join-Path $src 'uRhTypes.pas'))
  function LineOf([string]$Text) { return [array]::FindIndex($srcLines, [Predicate[string]] { param($l) $l.Contains($Text) }) + 1 }
  $l1 = LineOf 'M:= RhOne(1).FLeaf;'
  $l2 = LineOf 'M:= H.Names().FLeaf;'
  $l3 = LineOf 'H.Names().FLeaf:= nil;'
  Check 'no double row: G5 shape has ONE member-access' ((CountRefs "start_line = $l1 AND name_text = 'FLeaf' AND kind = 'member-access'") -eq 1)
  Check 'G6: H.Names().FLeaf has ONE member-access' ((CountRefs "start_line = $l2 AND name_text = 'FLeaf' AND kind = 'member-access' AND receiver_text = 'H.Names()'") -eq 1)
  Check 'G6: the write form binds the field too' ((CountRefs "start_line = $l3 AND name_text = 'FLeaf' AND kind = 'member-access' AND symbol_id IS NOT NULL") -eq 1)

  # GAP 2: a bare local at its use site; the same name at its declaration answers nothing
  Check 'bare local: Q at RhUse(Q) is TRhLeaf'       ($on -contains 'LEAF|RhUse(Q)>Q|TRhLeaf')
  Check 'control: Q at its declaration has no type'  ($on -contains 'LEAF|Q|-')

  # GAP 3: inside `with` the reader answers only on proof. PROOF: the resolver decided the name.
  Check 'with: a subject member wins the local'      ($on -contains 'LEAF|W01(Q)>Q|TRhOther')
  Check 'with: complete subject without it, the local' ($on -contains 'LEAF|W02(Q)>Q|TRhLeaf')
  Check 'with: bare member of the subject'           ($on -contains 'LEAF|W05(FLeaf)>FLeaf|TRhOther')
  Check 'with: chain on a proved local'              ($on -contains 'LEAF|W07(H.FLeaf)>H.FLeaf|TRhLeaf')
  Check 'with: a call on the subject'                ($on -contains 'LEAF|W10(Names())>Names()|TRhOther')
  Check 'with: Self is never a with member'          ($on -contains 'LEAF|W13(Self.FLeaf)>Self.FLeaf|TRhLeaf')
  Check 'with: T(x) that is a subject method, not a cast' ($on -contains 'LEAF|W20(TRhMid(1))>TRhMid(1)|TRhOther')
  # UNKNOWN, never a wrong type: the subject's surface cannot be followed, or the written type is no proof
  foreach ($e in @('W03(Q)>Q', 'W04(Q)>Q', 'W06(H.FLeaf)>H.FLeaf', 'W08(TRhLeaf(Q))>TRhLeaf(Q)', 'W09(Q as TRhLeaf)>Q as TRhLeaf',
                   'W11(TRhHolder(Q).FLeaf)>TRhHolder(Q).FLeaf', 'W12(RhFree().FLeaf)>RhFree().FLeaf', 'W14(TRhLeaf.Create)>TRhLeaf.Create',
                   'W15(RhFree())>RhFree()', 'W17(Names().FLeaf)>Names().FLeaf', 'W18(TRhLeaf(Q))>TRhLeaf(Q)', 'TRhHolder(Q)')) {
    Check "with: unknown for $e" ($on -contains "LEAF|$e|-")
  }
  # CONTROLS: out of the scope answers again: a `with` first subject and code after the with
  Check 'control: after the with Q is the local'     ($on -contains 'LEAF|W99(Q)>Q|TRhLeaf')
  Check 'control: a with first subject is not in its scope' ($on -contains 'LEAF|H.Sub|TRhShadow')
  Check 'control: a with first subject cast answers' ($on -contains 'LEAF|TRhShadow(Q)|TRhShadow')
  # H4
  Check 'descent: TRhLeaf from TRhBase is yes'  ($on -contains 'DESC|TRhLeaf|TRhBase|yes')
  Check 'descent: case-insensitive'             ($on -contains 'DESC|trhleaf|TRHMID|yes')
  Check 'descent: a type descends from itself'  ($on -contains 'DESC|TRhLeaf|TRhLeaf|yes')
  Check 'control: unrelated ancestor is no'     ($on -contains 'DESC|TRhLeaf|TRhOther|no')
  Check 'control: TRhOther from TRhBase is no'  ($on -contains 'DESC|TRhOther|TRhBase|no')
  Check 'unfollowable: named ancestor is yes'   ($on -contains 'DESC|TRhLibKid|TRhNowhere|yes')
  Check 'unfollowable: other ancestor is unknown, never no' ($on -contains 'DESC|TRhLibKid|TRhBase|unknown')
  Check 'control: unknown type is unknown'      ($on -contains 'DESC|TNoSuchType|TRhBase|unknown')
  Check 'no table: descent answers as with the table' ((@($off | Where-Object { $_ -like 'DESC|*' }) -join ',') -eq (@($on | Where-Object { $_ -like 'DESC|*' }) -join ','))
}
finally { if (Test-Path $work) { [IO.Directory]::Delete($work, $true) } }
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'
