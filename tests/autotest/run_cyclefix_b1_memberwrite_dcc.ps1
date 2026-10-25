<#
  run_cyclefix_b1_memberwrite_dcc.ps1 -- recipe B1 (plan 2026-10-25-cycles-fix-refusal-recipes.md):
  an R2 cut whose consumer WRITES a member of the class, followed, COMPILES and the program
  behaves exactly as before. Needs RAD Studio (msbuild via rsvars).

  Trees: tests\fixtures\cyclefix\memberwrite as shipped ('property': `LastGage := 0` inside the
  `with` body writes a property with a `write` accessor), and the same writing a public FIELD
  instead ('field': `Count := 3`). Each gets the fixture's MemberWrite.dpr with one line added
  that prints the written member AFTER the write, so the write is observable on stdout. The
  runner builds the untouched copy (msbuild, Win64 Debug) and keeps its stdout, plans
  `cycles --plan` on a second copy, applies cycle 1 with tools\follow-cycle-plan.ps1, checks the
  cycle is GONE (`cycles` on a re-index), builds it (BUILD_EXITCODE=0, no `error E` / `fatal F`
  line), runs it and compares stdout BYTE-FOR-BYTE.

  POSITIVE CONTROLS: (pc1) the followed 'property' tree with its setter body emptied still
  builds but its stdout DIFFERS -- so the byte comparison sees a setter that does not write;
  (pc2) the same tree with `with Sender as TDemoGagePort do` put back does NOT compile -- so the
  build check can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-b1-dcc-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite'
$Ascii = [Text.Encoding]::ASCII
$WriteLine = '    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it'

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# pFile in pDir with pOld replaced by pNew; False when nothing changed.
function Edit-File([string]$Dir, [string]$File, [string]$Old, [string]$New) {
  $p = Join-Path $Dir $File
  $t = [IO.File]::ReadAllText($p)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  Set-Text $p $n
  return ($n -ne $t)
}

# A copy of the fixture; pMember is the member the program prints after the run.
function New-Tree([string]$Dir, [string]$Member, [scriptblock]$Edit) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem $Fx -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  $ok = Edit-File $Dir 'MemberWrite.dpr' "        Writeln('[gageport] ', GPort.Log[I]);`n" `
    ("        Writeln('[gageport] ', GPort.Log[I]);`n      Writeln('[gageport] {0} after the run: ', GPort.{0});`n" -f $Member)
  if ($Edit) { $ok = (& $Edit $Dir) -and $ok }
  return $ok
}

function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}

# stdout of the built program, base64; pText gets it as text for the report.
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\MemberWrite.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Invoke-Cycles([string]$Dproj, [string]$Tag, [string[]]$Extra) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}

function Test-Tree([string]$Tag, [string]$Member, [scriptblock]$Edit) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $work = Join-Path $WorkDir "$Tag-edit"
  $okB = New-Tree $base $Member $Edit; $okW = New-Tree $work $Member $Edit
  Check "$Tag 0a the variant edits applied" ($okB -and $okW) ''
  $b0 = Invoke-Build (Join-Path $base 'MemberWrite.dproj')
  Check "$Tag 0b the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'MemberWrite.dproj')
  $txt0 = if ($out0 -ne '<no exe>') { [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($out0)) } else { '' }
  Check "$Tag 0c the untouched program prints the member after the write" ($txt0 -match "(?m)^\[gageport\] $Member after the run: ") ''
  $plan = Invoke-Cycles (Join-Path $work 'MemberWrite.dproj') "$Tag-plan" @('--plan')
  Check "$Tag 1 planned (exit 0) by member hand-over with a setter, no refusal" `
    (($plan.Exit -eq 0) -and ($plan.Text -notmatch 'refused: ') -and $plan.Text.Contains("procedure Set$Member(const pValue: ")) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $leafP = Join-Path $work 'DemoGagePort.Untangle.pas'
  $leaf = if (Test-Path $leafP) { [IO.File]::ReadAllText($leafP) } else { '' }
  Check "$Tag 3 the leaf carries a read/write property for $Member" ($leaf -match "property $Member\s*:\s*Integer read Get$Member write Set$Member;") ''
  $after = Invoke-Cycles (Join-Path $work 'MemberWrite.dproj') "$Tag-after" @()
  Check "$Tag 4 the cycle is gone after a re-index" ($after.Text -match 'No circular unit dependencies found\.') ($after.Text.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $work 'MemberWrite.dproj')
  Check "$Tag 5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $work 'MemberWrite.dproj')
  Check "$Tag 6 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return @{ Dir = $work; Out = $out0 }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  $prop = Test-Tree 'property' 'LastGage' $null
  $null = Test-Tree 'field' 'Count' {
    param($d)
    $a = Edit-File $d 'DemoGagePort.pas' "    FLastGage: Integer;`n  public`n" "    FLastGage: Integer;`n  public`n    /// <summary>A public field the UI connection writes.</summary>`n    Count: Integer;`n"
    $b = Edit-File $d 'DemoUIConnect.pas' $WriteLine '    Count := 3;'
    return ($a -and $b)
  }

  Write-Host '== positive control 1: the followed property tree with an empty setter body' -ForegroundColor Cyan
  $gpP = Join-Path $prop.Dir 'DemoGagePort.pas'
  $gp0 = [IO.File]::ReadAllText($gpP)
  $ok1 = Edit-File $prop.Dir 'DemoGagePort.pas' "begin`n  LastGage := pValue;`nend;" "begin`nend;"
  Check 'pc1a the setter body was emptied' $ok1 ''
  $bp = Invoke-Build (Join-Path $prop.Dir 'MemberWrite.dproj')
  $op = Invoke-Program (Join-Path $prop.Dir 'MemberWrite.dproj')
  Check 'pc1b it builds, and its stdout DIFFERS (the comparison sees a setter that does not write)' ($bp.Ok -and ($op -ne '<no exe>') -and ($op -cne $prop.Out)) $bp.Errors
  Set-Text $gpP $gp0

  Write-Host '== positive control 2: the followed property tree with the class cast put back' -ForegroundColor Cyan
  $ok2 = Edit-File $prop.Dir 'DemoUIConnect.pas' 'with TComponent(Sender) as IDemoGagePortSurface do' 'with Sender as TDemoGagePort do'
  Check 'pc2a the cast line was changed back' $ok2 ''
  $bc = Invoke-Build (Join-Path $prop.Dir 'MemberWrite.dproj')
  Check 'pc2b it does NOT compile (the build check has teeth)' (-not $bc.Ok) $bc.Errors
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
