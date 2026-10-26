<#
  run_cyclefix_c7_typecast_dcc.ps1 -- plan 2026-10-25 C7 `type-cast` (owner-delegated 2026-10-26): a member
  hand-over (R2) plan whose consumer HARD-CASTS the class, `TX(Y).M` (run_cyclefix_c7_typecast.ps1), followed,
  COMPILES and the program behaves exactly as before. Needs RAD Studio (msbuild via rsvars) and the platform
  library DB (R2 reads class ancestry from it). The run_cyclefix_r2_dcc.ps1 pattern.

  Trees (tests\fixtures\cyclefix\memberwrite without its `with`-body write, plus one line in DemoUIConnect.pas):
  castmember (TDemoGagePort(Sender).Log.Add('cast') -- Sender: TObject, rewritten through TComponent),
  castowner (TDemoGagePort(Owner).Log.Add('attach cast') -- Owner: TComponent), castwrite
  (TDemoGagePort(Sender).LastGage := 0 -- the B1 read/write property). Each: the untouched copy builds and its
  stdout is kept; `cycles --plan` on a second copy, follow-cycle-plan applies cycle 1, the followed copy builds
  and its stdout is byte-identical (the program prints the port's log, so the cast line's text is in it).

  The engine never opens the real library: -LibraryDb is copied into the $PID scratch dir and the copy is
  passed with --library-db; check z1 compares size + mtime of the real library DBs.

  POSITIVE CONTROL: the followed castmember tree with the rewritten line's text changed ('cast' -> 'cast2')
  still compiles, but its stdout must DIFFER -- a compare that cannot see the cast line would pass.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-c7-dcc-$PID",
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

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# Replaces pOld by pNew in one file of a copy (CRLF); False when nothing changed.
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  Set-Text $Path $n
  return ($n -ne $t)
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

function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\MemberWrite.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Get-PlanFile([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o }
}

# Untouched build + stdout, then plan / follow / build / run on a second copy; pCast = the cast line added.
function Test-Tree([string]$Tag, [string]$Anchor, [string]$Cast, [string]$Rewritten) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $edit = Join-Path $WorkDir "$Tag-edit"
  Copy-Tree $Fx $base; Copy-Tree $Fx $edit
  foreach ($d in $base, $edit) {
    $u = Join-Path $d 'DemoUIConnect.pas'
    $ok = Edit-File $u "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n" ''
    $ok = $ok -and (Edit-File $u $Anchor ($Anchor + $Cast))
    Check "$Tag prep the copy carries the cast line" $ok ''
  }
  $b0 = Invoke-Build (Join-Path $base 'MemberWrite.dproj')
  Check "$Tag 0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'MemberWrite.dproj')
  $plan = Get-PlanFile (Join-Path $edit 'MemberWrite.dproj') $Tag
  $planText = [IO.File]::ReadAllText($plan.File)
  Check "$Tag 1 planned (exit 0), cut by member hand-over, no refusal" (($plan.Exit -eq 0) -and $planText.Contains('by **member hand-over through an extracted interface**') -and ($planText -notmatch 'refused: ')) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $edit 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $ui = [IO.File]::ReadAllText((Join-Path $edit 'DemoUIConnect.pas'))
  $uiCode = (($ui -split "`r?`n") | ForEach-Object { ($_ -replace '//.*$', '') -replace '\{[^}]*\}', '' }) -join "`n"
  Check "$Tag 3 the consumer carries the rewritten cast and its code no longer names TDemoGagePort" ($ui.Contains($Rewritten) -and ($uiCode -notmatch '\bTDemoGagePort\b')) ''
  $b1 = Invoke-Build (Join-Path $edit 'MemberWrite.dproj')
  Check "$Tag 4 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit 'MemberWrite.dproj')
  Check "$Tag 5 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return @{ Edit = $edit; Out0 = $out0 }
}

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib
  $onData = "  if not (Sender is TDemoGagePort) then`n    Exit;`n"
  $attach = "  if not (Owner is TDemoGagePort) then`n    Exit;`n"
  $member = Test-Tree 'castmember' $onData "  TDemoGagePort(Sender).Log.Add('cast');`n" "  (TComponent(Sender) as IDemoGagePortSurface).Log.Add('cast');"
  $null = Test-Tree 'castowner' $attach "  TDemoGagePort(Owner).Log.Add('attach cast');`n" "  (Owner as IDemoGagePortSurface).Log.Add('attach cast');"
  $null = Test-Tree 'castwrite' $onData "  TDemoGagePort(Sender).LastGage := 0;`n" "  (TComponent(Sender) as IDemoGagePortSurface).LastGage := 0;"

  Write-Host '== positive control: the followed castmember tree with the cast line''s text changed' -ForegroundColor Cyan
  $u = Join-Path $member.Edit 'DemoUIConnect.pas'
  Check 'pc0 the rewritten line was changed' (Edit-File $u "(TComponent(Sender) as IDemoGagePortSurface).Log.Add('cast');" "(TComponent(Sender) as IDemoGagePortSurface).Log.Add('cast2');") ''
  $bc = Invoke-Build (Join-Path $member.Edit 'MemberWrite.dproj')
  Check 'pc1 it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program (Join-Path $member.Edit 'MemberWrite.dproj')
  Check 'pc2 its stdout DIFFERS from the untouched build (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $member.Out0)) ''
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z1 the real library DBs are unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
