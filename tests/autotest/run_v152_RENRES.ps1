<#
  run_v152_RENRES.ps1 -- wave v152 lane RENRES: rename residue.

  A  a routine-local rename's --col before a non-ASCII character (bytes vs chars). The index and lint findings count
     UTF-8 bytes, an editor counts characters; BuildLocalScan takes either. On `function TA.Go({<3 umlauts>} a, b:
     Integer)` character column 25 is `b`, and byte column 25 is `a`.
     a1  --col 25: refused [column-ambiguous], exit 2, nothing renamed (RED before 1.52: `a` planned -- the wrong
         local, silently).
     a2  --col 28 (b's byte column; as characters it is `Integer`, no local): b is planned, a is not.
     a3  POSITIVE CONTROL, pure-ASCII line: --col of b plans b in the declaration, the header and the body.
     a4  --col 22 (a's character column; as bytes it is inside the comment): a is planned (pre-1.52 behaviour kept).
  L  a form component named as an item of a `Prop = ( ... )` list (Micronite: 410 such lists; 148 RN measured the
     dfm-name-unbound refusals of component renames there). Fixture: tests\autotest\fixtures\v151-DFMREN\frdemo.
     l1  renaming FrMain.TFrmMain.BtnGo: the item in FrMain.dfm's list is an edit, no [dfm-name-unbound] there
         (RED before 1.52: refused [dfm-name-unbound] at the list item).
     l2  a one-line list `Prop = (BtnGo Lbl)` in the descendant form FrKid.dfm is an edit too.
     l3  POSITIVE CONTROL (another form's name): the frame FrFrame.dfm's own list naming BtnGo is not edited and
         not refused.
     l4  POSITIVE CONTROL (still undecided): an `Owner.BtnGo` list item refuses [dfm-name-unbound].
  T  RunAsync's stall budget (owner IDE test, 144 wave 2): the plugin kills a rename child after 60 s with no output and
     no CPU (rename has no heartbeat channel). Rename Symbol builds twice through the gate; msbuild writes to a log, not
     to the child's stdout. The frdemo project gets a pre-build step that sleeps SlowSeconds with no output and no CPU.
     t1  the gated rename applies (exit 0).
     t2  CONTROL: both builds outlast the gate's 10 s progress line (the sleep happened).
     t3  no silence on stdout + stderr longer than MaxSilentSeconds: the plugin's 60 s budget cannot fire.
     Needs dcc; T SKIPs without rsvars.bat. A and L need no dcc (plans only).
#>
param(
  [string]$Exe              = '',
  [string]$Rsvars           = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [int]   $SlowSeconds      = 15,  # each build's silent, idle pre-build step
  [int]   $MaxSilentSeconds = 12   # the gate's progress line comes every 10 s
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'  # native stderr must not terminate; every call is checked by exit code
$script:Passed = 0; $script:FailCount = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  ok   $Name" }
  else { $script:FailCount++; Write-Host "  FAIL $Name" -ForegroundColor Red; if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\fixtures\v151-DFMREN").Path
$Tmp = Join-Path $env:TEMP ('v152_renres_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$Utf8 = New-Object Text.UTF8Encoding($false)
function Run([string[]]$EngArgs) {
  Push-Location $Tmp
  try { $o = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe @EngArgs 2>&1 | ForEach-Object { "$_" } } | Out-String); $script:LastExit = $LASTEXITCODE } finally { Pop-Location }
  return $o
}
function Lines([string[]]$L) { return (($L -join "`r`n") + "`r`n") }
# The plan's edits as "<file name>:<line>:<col>" (a `File: <path>` line heads each file's `  L<n>:C<n>  old -> new` lines).
function PlanEdits([string]$Out) {
  $file = ''; $r = @()
  foreach ($l in ($Out -split "`r?`n")) {
    if ($l -match '^File: (.+)$') { $file = [IO.Path]::GetFileName($Matches[1].Trim()) }
    elseif ($l -match '^\s+L(\d+):C(\d+)\s') { $r += '{0}:{1}:{2}' -f $file, $Matches[1], $Matches[2] }
  }
  return ,$r
}

try {
  # ---------------------------------------------------------------- A: bytes vs chars
  Write-Host '== A: --kind param, a column before a non-ASCII character ==' -ForegroundColor Cyan
  $Uml = [string][char]0xC4 + [char]0xD6 + [char]0xDC   # three 2-byte UTF-8 characters, kept out of this file's bytes
  $src = Lines @('unit uNa;', '', 'interface', '', 'type', '  TA = class', '  public',
    "    function Go({$Uml} a, b: Integer): Integer;", '    function Hi(a, b: Integer): Integer;', '  end;', '', 'implementation', '',
    "function TA.Go({$Uml} a, b: Integer): Integer;", 'begin', '  Result:= a * 10 + b;', 'end;', '',
    'function TA.Hi(a, b: Integer): Integer;', 'begin', '  Result:= a - b;', 'end;', '', 'end.')
  $nf = Join-Path $Tmp 'uNa.pas'
  [IO.File]::WriteAllText($nf, $src, $Utf8)
  # line 14 = the Go header; char col of b = 25, byte col of a = 25, byte col of b = 28 (char 28 = `Integer`)
  function Plan([int]$Line, [int]$Col, [string]$To) { return (Run @('rename', '--kind', 'param', '--in', $nf, '--line', "$Line", '--col', "$Col", '--to', $To, '--plan')) }
  $o = Plan 14 25 'bb'
  Write-Host '  -- raw a1 (once) --' -ForegroundColor DarkGray; Write-Host $o -ForegroundColor DarkGray
  Check 'a1 --col 25: refused [column-ambiguous]; not proved' ($o -match 'uNa\.pas:14:25: refused \[column-ambiguous\]' -and $o -match 'not proved') "exit $($script:LastExit) $o"
  Check 'a1b no edit planned' ($o -notmatch '(?m)^\s+L\d+:C\d+\s') $o
  $o = Plan 14 28 'bb'
  Check 'a2 --col 28 (b as bytes, Integer as characters): b planned at L8:C26 L14:C25 L16:C21' ($script:LastExit -eq 0 -and $o -match 'L8:C26\s+b -> bb' -and $o -match 'L14:C25\s+b -> bb' -and $o -match 'L16:C21\s+b -> bb') "exit $($script:LastExit) $o"
  Check 'a2b a is not planned' ($o -notmatch '\ba -> bb') $o
  $o = Plan 19 19 'bb'
  Check 'a3 control, ASCII line: b planned in declaration, header and body' ($script:LastExit -eq 0 -and $o -match 'L9:C20\s+b -> bb' -and $o -match 'L19:C19\s+b -> bb' -and $o -match 'L21:C16\s+b -> bb' -and $o -notmatch '\ba -> bb') "exit $($script:LastExit) $o"
  # char col 22 = `a`; byte col 22 is inside the comment: the character reading is taken
  $o = Plan 14 22 'aa'
  Check 'a4 a character column whose byte reading names nothing: a planned' ($script:LastExit -eq 0 -and $o -match 'L14:C22\s+a -> aa' -and $o -match 'L16:C12\s+a -> aa' -and $o -notmatch '\bb -> aa') "exit $($script:LastExit) $o"
  # ---------------------------------------------------------------- L: list items in a form
  Write-Host '== L: a form component named in a ( ... ) list ==' -ForegroundColor Cyan
  $d = Join-Path $Tmp 'frdemo'
  Copy-Item (Join-Path $Fx 'frdemo') $d -Recurse
  $m = Join-Path $d 'FrMain.dfm'
  [IO.File]::WriteAllText($m, [IO.File]::ReadAllText($m).Replace("    FocusControl = BtnGo`r`n", "    FocusControl = BtnGo`r`n    Partners = (`r`n      Lbl`r`n      BtnGo)`r`n    Owners = (`r`n      FrmMain.BtnGo)`r`n"), [Text.Encoding]::ASCII)
  $k = Join-Path $d 'FrKid.dfm'
  [IO.File]::WriteAllText($k, [IO.File]::ReadAllText($k).Replace("    Caption = 'Kid'`r`n", "    Caption = 'Kid'`r`n    Partners = (BtnGo Lbl)`r`n"), [Text.Encoding]::ASCII)
  $f = Join-Path $d 'FrFrame.dfm'
  $ft = [IO.File]::ReadAllText($f)
  $ft = $ft.Substring(0, $ft.LastIndexOf('end')) + "  Partners = (`r`n    BtnGo)`r`nend`r`n"
  [IO.File]::WriteAllText($f, $ft, [Text.Encoding]::ASCII)
  Write-Host ('  FrMain.dfm / FrKid.dfm / FrFrame.dfm prepared; frame tail: ' + ($ft -replace "`r`n", ' | ')) -ForegroundColor DarkGray
  $db = Join-Path $d 'p.sqlite'
  $lib = Join-Path $Tmp 'lib.sqlite'
  $null = Run @('index', (Join-Path $Fx 'vclstub'), '--db', $lib, '--library-db', 'none')
  $null = Run @('index', '--project', (Join-Path $d 'FrDemo.dproj'), '--db', $db, '--library-db', 'none')
  $o = Run @('rename', '--kind', 'symbol', '--name', 'FrMain.TFrmMain.BtnGo', '--to', 'BtnRun', '--db', $db, '--library-db', $lib, '--plan')
  Write-Host '  -- raw plan (once) --' -ForegroundColor DarkGray; Write-Host $o -ForegroundColor DarkGray
  $mainLines = [IO.File]::ReadAllLines($m)
  $item = 0; $own = 0; for ($i = 0; $i -lt $mainLines.Count; $i++) { if ($mainLines[$i] -eq '      BtnGo)') { $item = $i + 1 }; if ($mainLines[$i] -eq '      FrmMain.BtnGo)') { $own = $i + 1 } }
  Check "l1 FrMain.dfm:$item list item: no [dfm-name-unbound]" ($o -notmatch "FrMain\.dfm:${item}:\d+: refused \[dfm-name-unbound\]") $o
  $ed = PlanEdits $o
  Check "l1b FrMain.dfm:$item list item is an edit" ($ed -contains "FrMain.dfm:${item}:7") ($ed -join ' ')
  Check 'l2 FrKid.dfm one-line list item is an edit, not refused' ($ed -contains 'FrKid.dfm:5:17' -and $o -notmatch 'FrKid\.dfm:5:\d+: refused') ($ed -join ' ')
  Check 'l3 control: the frame''s own list item is neither edited nor refused' ($o -notmatch 'FrFrame\.dfm:\d+:\d+' -and -not ($ed | Where-Object { $_ -like 'FrFrame.dfm:*' })) $o
  Check "l4 control: FrMain.dfm:$own ``FrmMain.BtnGo`` item still refuses [dfm-name-unbound]" ($o -match "FrMain\.dfm:${own}:\d+: refused \[dfm-name-unbound\]") $o

  # ---------------------------------------------------------------- T: the IDE's stall budget during the gate
  Write-Host '== T: a gated rename keeps talking while msbuild is silent and idle ==' -ForegroundColor Cyan
  if (-not (Test-Path $Rsvars)) { Write-Host "  SKIP T: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow }
  else {
    $g = Join-Path $Tmp 'slow'
    Copy-Item (Join-Path $Fx 'frdemo') $g -Recurse
    $gp = Join-Path $g 'FrDemo.dproj'
    # a pre-build step that sleeps with no output and no CPU: the shape the plugin's stall budget kills
    $x = [IO.File]::ReadAllText($gp).Replace("<PropertyGroup Condition=`"'`$(Base)'!=''`">", "<PropertyGroup Condition=`"'`$(Base)'!=''`">`r`n        <PreBuildEvent>ping -n $($SlowSeconds + 1) 127.0.0.1 &gt;nul</PreBuildEvent>")
    [IO.File]::WriteAllText($gp, $x, [Text.Encoding]::ASCII)
    $gdb = Join-Path $g 'p.sqlite'
    $null = Run @('index', '--project', $gp, '--db', $gdb, '--library-db', 'none')
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    foreach ($a in @('rename', '--kind', 'symbol', '--name', 'FrMain.TFrmMain.BtnGo', '--to', 'BtnRun', '--db', $gdb, '--library-db', $lib,
                     '--project', $gp, '--rsvars', $Rsvars, '--build-timeout', '600', '--apply', '--no-backup')) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Tmp
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    # timestamps taken ON the reader threads (a PowerShell event action would run only after WaitForExit returns)
    if (-not ('RenresTimedCapture' -as [type])) {
      Add-Type -TypeDefinition @"
using System; using System.Collections.Concurrent; using System.Diagnostics;
public static class RenresTimedCapture {
  public static ConcurrentQueue<Tuple<DateTime, string>> Run(ProcessStartInfo psi, out int exitCode) {
    var q = new ConcurrentQueue<Tuple<DateTime, string>>();
    using (var p = new Process()) {
      p.StartInfo = psi;
      p.OutputDataReceived += (s, e) => { if (e.Data != null) q.Enqueue(Tuple.Create(DateTime.UtcNow, e.Data)); };
      p.ErrorDataReceived  += (s, e) => { if (e.Data != null) q.Enqueue(Tuple.Create(DateTime.UtcNow, e.Data)); };
      p.Start(); p.StandardInput.Close();
      p.BeginOutputReadLine(); p.BeginErrorReadLine();
      p.WaitForExit();
      exitCode = p.ExitCode;
    }
    return q;
  }
}
"@
    }
    $t0 = [DateTime]::UtcNow
    $code = 0
    $q = [RenresTimedCapture]::Run($psi, [ref]$code)
    $t1 = [DateTime]::UtcNow
    $rows = @($q.ToArray() | ForEach-Object { [pscustomobject]@{ T = $_.Item1; L = $_.Item2 } } | Sort-Object T)
    $gaps = @(); $prev = $t0; foreach ($r in $rows) { $gaps += ($r.T - $prev).TotalSeconds; $prev = $r.T }; $gaps += ($t1 - $prev).TotalSeconds
    $maxGap = [Math]::Round(($gaps | Measure-Object -Maximum).Maximum, 1)
    $all = ($rows | ForEach-Object { '{0:N1}s {1}' -f ($_.T - $t0).TotalSeconds, $_.L }) -join "`n"
    Write-Host "  -- raw timed output (once) --`n$all" -ForegroundColor DarkGray
    Check "t1 the gated rename applied: exit 0 ($([Math]::Round(($t1 - $t0).TotalSeconds)) s)" ($code -eq 0) $all
    Check 't2 both builds outlasted the 10 s progress line (the control: the sleep happened)' (@($rows | Where-Object { $_.L -match ' -- 1\d s ' }).Count -ge 2) $all
    Check "t3 no silence longer than $MaxSilentSeconds s (largest $maxGap s; the plugin kills after 60 s of no output and no CPU)" ($maxGap -le $MaxSilentSeconds) $all
  }
}
finally {
  Write-Host ("run_v152_RENRES: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  if ($script:FailCount -eq 0) { try { [IO.Directory]::Delete($Tmp, $true) } catch { } } else { Write-Host "  work kept: $Tmp" }
}
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
