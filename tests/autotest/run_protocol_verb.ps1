<#
  run_protocol_verb.ps1 -- `drag-lint protocol register|unregister|status`, the verb that replaced
  charts\src\Register-DragLintProtocol.ps1 (retired), against a SCRATCH registry root.

  THE REAL KEY IS NEVER TOUCHED. Every engine run below goes through Invoke-Protocol, which sets
  DRAGLINT_PROTOCOL_TEST_ROOT=Software\drag-lint-test\protocol-<stamp> first and refuses to run
  without it; the verb then reads and writes HKCU\<that>\Classes\draglint instead of
  HKCU\Software\Classes\draglint. The real key is exported (`reg export`) before and after and the
  two exports must be byte-identical (or the key absent both times). The scratch root is deleted
  in a finally block, pass or fail.

  The legacy copy %LOCALAPPDATA%\drag-lint\Open-DragLintUri.ps1 is NOT deleted under the test root:
  the verb reports `left in place (DRAGLINT_PROTOCOL_TEST_ROOT is set)` instead, and this guard
  asserts that line plus the copy's existence/hash unchanged. The real deletion (no test root) is
  MANUAL-VERIFIED, not guarded -- exercising it would need the real key.

    PV-USAGE      no sub-verb / unknown sub-verb / unknown flag / --handler with no value: usage on
                  stderr, exit 2, nothing written
    PV-ROOTSAFE   a test root that is, or (as TRegistry reads it: '\Software', 'Software\') resolves to,
                  Software or anything under Software\Classes: exit 2 before anything is opened. Only
                  read-only invocations are used for these
    PV-NONE       status on an empty root: `draglint://: none`, exit 1
    PV-NOHANDLER  register with a bogus --handler: `handler not found`, exit 2
    PV-DEFAULT    register --dry-run with no --handler names <exe dir>\drag-lint-open.exe
    PV-DRY        register --dry-run: `would register`, nothing written
    PV-WT         a handler under ...-wt\...: refused exit 1; with --force accepted
    PV-REG        register a scratch copy of drag-lint-open.exe: status ours exit 0; the three
                  registry values exact; status --json fields
    PV-LEGACY     a pre-seeded legacy PowerShell command: register --dry-run names it as current and
                  writes nothing; unregister removes it; register replaces it silently (status ours)
    PV-FOREIGN    a pre-seeded foreign command: register refused exit 1, --force replaces;
                  unregister refused exit 1 without --force, removes it with --force
    PV-BARE       a key with no shell\open\command is kept by unregister, removed with --force
    PV-NONSTRING  a DWORD command classifies as foreign (no raise); register --force replaces it
    PV-UNREG      unregister --dry-run writes nothing; unregister removes; again: nothing to remove
    PV-PARITY     GOLDEN: `protocol register --dry-run` names the key path the retired
                  Register-DragLintProtocol.ps1 -DryRun named (HKCU\Software\Classes\draglint\shell\open\command,
                  frozen from its last green parity run, 2026-10-14)
    PV-REALKEY    the real HKCU\Software\Classes\draglint export is unchanged
    PV-REALCOPY   the real legacy copy is unchanged

  Exit: 0 all PASS, 1 any FAIL, 2 setup.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Handler = "$PSScriptRoot\..\..\src\tools\uri-handler\Win64\Debug\drag-lint-open.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

foreach ($p in @($Exe, $Handler)) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "SETUP: not found: $p" -ForegroundColor Red; exit 2 }
}
$Exe     = (Resolve-Path -LiteralPath $Exe).ProviderPath
$Handler = (Resolve-Path -LiteralPath $Handler).ProviderPath

$stamp    = '{0}-{1}' -f (Get-Date -Format 'yyyyMMddHHmmss'), $PID
$TestRoot = "Software\drag-lint-test\protocol-$stamp"
$TestKey  = "HKCU:\$TestRoot\Classes\draglint"
$CmdKey   = "$TestKey\shell\open\command"
$RealKey  = 'HKCU\Software\Classes\draglint'
$Work     = Join-Path ([IO.Path]::GetTempPath()) "drag-lint-protocol-guard-$stamp"
if ($Work -match '-wt\\') { Write-Host "SETUP: temp path $Work contains -wt\" -ForegroundColor Red; exit 2 }
$RealCopy = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'drag-lint\Open-DragLintUri.ps1' } else { '' })

function Export-RealKey([string]$To) {
  & reg.exe query $RealKey *> $null
  if ($LASTEXITCODE -ne 0) { return $null }
  & reg.exe export $RealKey $To /y *> $null
  if ($LASTEXITCODE -ne 0) { throw "reg export $RealKey failed" }
  [IO.File]::ReadAllBytes($To)
}
function Get-CopyFingerprint {
  if ($RealCopy -and (Test-Path -LiteralPath $RealCopy)) { (Get-FileHash -LiteralPath $RealCopy).Hash } else { '(absent)' }
}

# Every engine run goes through here: the test root is set FIRST, and a run without it is refused.
# -Root overrides it ONLY for PV-ROOTSAFE, whose runs are read-only verbs the engine must refuse up front.
function Invoke-Protocol([string[]]$ArgList, [string]$Root = $TestRoot) {
  if (-not $Root) { throw 'empty test root -- refusing to run the verb' }
  $env:DRAGLINT_PROTOCOL_TEST_ROOT = $Root
  if ($env:DRAGLINT_PROTOCOL_TEST_ROOT -ne $Root) { throw 'test root not set -- refusing to run the verb' }
  $o = Join-Path $Work 'out.txt'; $e = Join-Path $Work 'err.txt'
  $p = Start-Process -FilePath $Exe -ArgumentList (@('protocol') + $ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) `
         -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  [pscustomobject]@{ Code = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Get-Cmd { (Get-ItemProperty -LiteralPath $CmdKey -ErrorAction SilentlyContinue).'(default)' }
function Test-Written { Test-Path -LiteralPath $TestKey }
function Set-Seed([string]$Cmd) {
  New-Item -Path $CmdKey -Force | Out-Null
  Set-ItemProperty -LiteralPath $CmdKey -Name '(default)' -Value $Cmd
}

New-Item -ItemType Directory -Force $Work | Out-Null
$realBefore = Export-RealKey (Join-Path $Work 'real-before.reg')
$copyBefore = Get-CopyFingerprint
try {
  $good = Join-Path $Work 'bin\drag-lint-open.exe'
  New-Item -ItemType Directory -Force (Split-Path $good) | Out-Null
  Copy-Item -LiteralPath $Handler -Destination $good
  $wtDir = Join-Path $Work 'repo-wt\bin'
  New-Item -ItemType Directory -Force $wtDir | Out-Null
  $wt = Join-Path $wtDir 'drag-lint-open.exe'
  Copy-Item -LiteralPath $Handler -Destination $wt
  $expectCmd = '"{0}" "%1"' -f $good

  # ---- usage ------------------------------------------------------------------------------------
  $r = Invoke-Protocol @()
  Check 'PV-USAGE (none)'    ($r.Code -eq 2 -and $r.Err -match 'drag-lint protocol register' -and -not (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('frobnicate')
  Check 'PV-USAGE (unknown)' ($r.Code -eq 2 -and $r.Err -match 'drag-lint protocol' -and -not (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('status', '--bogus')
  Check 'PV-USAGE (flag)'    ($r.Code -eq 2 -and $r.Err -match '--bogus' -and -not (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('register', '--handler')
  Check 'PV-USAGE (--handler no value)' ($r.Code -eq 2 -and $r.Err -match '--handler needs a value' -and -not (Test-Written)) "exit $($r.Code)"

  # ---- a test root that resolves to the REAL tree is refused before anything is opened ----------
  # Only read-only invocations (status, register --dry-run), so even a broken refusal writes nothing;
  # PV-REALKEY at the end still byte-compares the real key.
  foreach ($bad in @('\Software', 'Software\', ' \\Software\\ ', 'Software\Classes', 'software\classes\draglint-x')) {
    $r1 = Invoke-Protocol @('status') $bad
    $r2 = Invoke-Protocol @('register', '--handler', $Handler, '--dry-run', '--force') $bad
    Check "PV-ROOTSAFE '$bad'" ($r1.Code -eq 2 -and $r2.Code -eq 2 -and $r1.Err -match 'refusing' -and $r1.Out -eq '' -and $r2.Out -eq '') "exit $($r1.Code)/$($r2.Code)"
  }

  # ---- status none ------------------------------------------------------------------------------
  $r = Invoke-Protocol @('status')
  Check 'PV-NONE' ($r.Code -eq 1 -and $r.Out -match 'draglint://: none') "exit $($r.Code) out=$($r.Out.Trim())"

  # ---- handler missing / default ----------------------------------------------------------------
  $r = Invoke-Protocol @('register', '--handler', (Join-Path $Work 'nope\drag-lint-open.exe'))
  Check 'PV-NOHANDLER' ($r.Code -eq 2 -and ($r.Out + $r.Err) -match 'handler not found: ' -and -not (Test-Written)) "exit $($r.Code)"
  $defaultHandler = Join-Path (Split-Path $Exe) 'drag-lint-open.exe'
  $r = Invoke-Protocol @('register', '--dry-run', '--force')
  Check 'PV-DEFAULT' (($r.Out + $r.Err).Contains($defaultHandler) -and -not (Test-Written)) "exit $($r.Code)"

  # ---- dry run ----------------------------------------------------------------------------------
  $r = Invoke-Protocol @('register', '--handler', $good, '--dry-run')
  Check 'PV-DRY' ($r.Code -eq 0 -and $r.Out -match 'would register' -and $r.Out -match 'current : \(none\)' -and
                  $r.Out.Contains($expectCmd) -and -not (Test-Written)) "exit $($r.Code)"

  # ---- worktree refusal -------------------------------------------------------------------------
  $r = Invoke-Protocol @('register', '--handler', $wt)
  Check 'PV-WT (refused)' ($r.Code -eq 1 -and ($r.Out + $r.Err) -match 'worktree' -and -not (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('register', '--handler', $wt, '--force')
  Check 'PV-WT (--force)' ($r.Code -eq 0 -and (Get-Cmd) -eq ('"{0}" "%1"' -f $wt)) "exit $($r.Code) cmd=$(Get-Cmd)"

  # ---- register ---------------------------------------------------------------------------------
  $r = Invoke-Protocol @('register', '--handler', $good)
  $root = Get-ItemProperty -LiteralPath $TestKey
  $cmdKind = (Get-Item -LiteralPath $CmdKey).GetValueKind('')
  Check 'PV-REG (register)' ($r.Code -eq 0 -and $r.Out -match 'registered: HKCU\\' -and $r.Out -match 'undo    : drag-lint protocol unregister') "exit $($r.Code)"
  Check 'PV-REG (default)'      ($root.'(default)' -ceq 'URL:drag-lint protocol') $root.'(default)'
  Check 'PV-REG (URL Protocol)' ($null -ne $root.'URL Protocol' -and $root.'URL Protocol' -eq '' -and
                                 (Get-Item -LiteralPath $TestKey).GetValueKind('URL Protocol') -eq 'String')
  Check 'PV-REG (command)'      ((Get-Cmd) -ceq $expectCmd -and $cmdKind -eq 'String') "$(Get-Cmd) ($cmdKind)"
  $r = Invoke-Protocol @('status')
  Check 'PV-REG (status ours)'  ($r.Code -eq 0 -and $r.Out -match 'draglint://: ours' -and $r.Out.Contains($expectCmd)) "exit $($r.Code)"
  $r = Invoke-Protocol @('status', '--json')
  $j = $null; try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'PV-REG (status --json)' ($r.Code -eq 0 -and $j -and $j.schema -eq 'protocol/1' -and $j.registered -eq $true -and
                                  $j.class -eq 'ours' -and $j.command -eq $expectCmd -and $j.handler -eq $good) $r.Out.Trim()

  # ---- legacy PowerShell registration is replaced silently --------------------------------------
  $legacy = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" "%1"' -f (Join-Path $Work 'Open-DragLintUri.ps1')
  Set-Seed $legacy
  $r = Invoke-Protocol @('status')
  Check 'PV-LEGACY (status)'   ($r.Code -eq 1 -and $r.Out -match 'draglint://: legacy-powershell') "exit $($r.Code)"
  $r = Invoke-Protocol @('register', '--handler', $good, '--dry-run')
  Check 'PV-LEGACY (dry over legacy)' ($r.Code -eq 0 -and $r.Out -match 'would register' -and $r.Out.Contains("current : $legacy") -and
                                      (Get-Cmd) -ceq $legacy) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister')
  Check 'PV-LEGACY (unregister)' ($r.Code -eq 0 -and $r.Out -match 'unregistered: ' -and $r.Out -match 'left in place' -and -not (Test-Written)) "exit $($r.Code)"
  Set-Seed $legacy
  $r = Invoke-Protocol @('register', '--handler', $good)
  Check 'PV-LEGACY (replaced)' ($r.Code -eq 0 -and (Get-Cmd) -ceq $expectCmd -and
                                $r.Out -match 'left in place \(DRAGLINT_PROTOCOL_TEST_ROOT is set\)') "exit $($r.Code) out=$($r.Out.Trim())"

  # ---- foreign registration ---------------------------------------------------------------------
  $foreign = '"C:\Other\handler.exe" "%1"'
  Set-Seed $foreign
  $r = Invoke-Protocol @('status')
  Check 'PV-FOREIGN (status)'  ($r.Code -eq 1 -and $r.Out -match 'draglint://: foreign') "exit $($r.Code)"
  $r = Invoke-Protocol @('register', '--handler', $good)
  Check 'PV-FOREIGN (refused)' ($r.Code -eq 1 -and ($r.Out + $r.Err).Contains("refusing: draglint:// is registered to $foreign; pass --force to replace it") -and
                                (Get-Cmd) -ceq $foreign) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister')
  Check 'PV-FOREIGN (unreg refused)' ($r.Code -eq 1 -and (Get-Cmd) -ceq $foreign) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister', '--force')
  Check 'PV-FOREIGN (unreg --force)' ($r.Code -eq 0 -and -not (Test-Written)) "exit $($r.Code)"
  Set-Seed $foreign
  $r = Invoke-Protocol @('register', '--handler', $good, '--force')
  Check 'PV-FOREIGN (--force)' ($r.Code -eq 0 -and (Get-Cmd) -ceq $expectCmd) "exit $($r.Code)"

  # ---- a key with no command, and a non-string command ------------------------------------------
  Remove-Item -LiteralPath $TestKey -Recurse -Force
  New-Item -Path $TestKey -Force | Out-Null
  Set-ItemProperty -LiteralPath $TestKey -Name '(default)' -Value 'someone else'
  $r = Invoke-Protocol @('unregister')
  Check 'PV-BARE (kept)'    ($r.Code -eq 0 -and $r.Out -match 'nothing to remove' -and (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister', '--force')
  Check 'PV-BARE (--force)' ($r.Code -eq 0 -and -not (Test-Written)) "exit $($r.Code)"
  New-Item -Path $CmdKey -Force | Out-Null
  New-ItemProperty -LiteralPath $CmdKey -Name '(default)' -PropertyType DWord -Value 7 -Force | Out-Null
  $r = Invoke-Protocol @('status')
  Check 'PV-NONSTRING'      ($r.Code -eq 1 -and $r.Out -match 'draglint://: foreign') "exit $($r.Code) out=$($r.Out.Trim()) err=$($r.Err.Trim())"
  $r = Invoke-Protocol @('register', '--handler', $good, '--force')
  Check 'PV-NONSTRING (--force)' ($r.Code -eq 0 -and (Get-Cmd) -ceq $expectCmd) "exit $($r.Code)"

  # ---- unregister -------------------------------------------------------------------------------
  $r = Invoke-Protocol @('unregister', '--dry-run')
  Check 'PV-UNREG (dry)'    ($r.Code -eq 0 -and $r.Out -match 'would remove: HKCU\\' -and (Get-Cmd) -ceq $expectCmd) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister')
  Check 'PV-UNREG (remove)' ($r.Code -eq 0 -and $r.Out -match 'unregistered: ' -and -not (Test-Written)) "exit $($r.Code)"
  $r = Invoke-Protocol @('unregister')
  Check 'PV-UNREG (again)'  ($r.Code -eq 0 -and $r.Out -match 'nothing to remove') "exit $($r.Code)"

  # ---- parity with the retired Register-DragLintProtocol.ps1, golden ----------------------------
  # The key its -DryRun plan named (frozen from its last green parity run, 2026-10-14).
  $scriptKey = 'HKCU\Software\Classes\draglint\shell\open\command'
  $r = Invoke-Protocol @('register', '--handler', $good, '--dry-run')
  $m = [regex]::Match($r.Out, 'key     : (\S+)')
  $verbKey = $m.Groups[1].Value.Replace("HKCU\$TestRoot\Classes\", 'HKCU\Software\Classes\')
  Check 'PV-PARITY' ($m.Success -and $verbKey -eq $scriptKey) "verb=$verbKey script(golden)=$scriptKey"
}
finally {
  Remove-Item -LiteralPath "HKCU:\Software\drag-lint-test\protocol-$stamp" -Recurse -Force -ErrorAction SilentlyContinue
  $parent = 'HKCU:\Software\drag-lint-test'
  if ((Test-Path $parent) -and -not (Get-ChildItem $parent) -and -not (Get-Item $parent).ValueCount) { Remove-Item $parent -Force }
  Remove-Item Env:\DRAGLINT_PROTOCOL_TEST_ROOT -ErrorAction SilentlyContinue
}
Check 'PV-SCRATCH (cleaned)' (-not (Test-Path "HKCU:\Software\drag-lint-test\protocol-$stamp"))

$realAfter = Export-RealKey (Join-Path $Work 'real-after.reg')
$same = ($null -eq $realBefore -and $null -eq $realAfter) -or
        ($null -ne $realBefore -and $null -ne $realAfter -and [Linq.Enumerable]::SequenceEqual([byte[]]$realBefore, [byte[]]$realAfter))
Check 'PV-REALKEY' $same $(if ($null -eq $realBefore) { 'absent before' } else { "$($realBefore.Length) bytes before" })
Check 'PV-REALCOPY' ((Get-CopyFingerprint) -eq $copyBefore) $copyBefore
[IO.Directory]::Delete($Work, $true)

if ($script:Failed) { Write-Host 'run_protocol_verb: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_protocol_verb: PASS' -ForegroundColor Green
exit 0
