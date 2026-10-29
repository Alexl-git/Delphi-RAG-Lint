# Guard: dfm-password-edit-unmasked (gap-rules wave, lane G8, project-wide, info, CWE-549).
#
# Fixture tests\lint-project\dfm-password-edit-unmasked\uLogin.dfm:
#   edtPassword TEdit (no mask)            -> FIRES (line 2)
#   edtPwdConfirm TcxTextEdit (no mask)    -> FIRES (line 5)
#   edtOldPass TMaskEdit (no mask)         -> FIRES (line 20)
#   edtUserName TEdit                      -> silent (name does not match pass|pwd)
#   edtPassMasked TEdit PasswordChar='*'   -> silent (the non-hit)
#   edtPassCx TcxTextEdit EchoMode=eemPassword -> silent
#   lblPassword TLabel                     -> silent (class is not an edit)
# Fix: inserts PasswordChar = '*' (TEdit family) / Properties.EchoMode = eemPassword (cx) as the
# first property line; expected\uLogin.fixed.dfm is hand-written. Second run is a no-op.
# Usage: pwsh -File tests/autotest/run_dfm_password_edit_unmasked.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-g8-pwd-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$rule = 'dfm-password-edit-unmasked'
try {
  $fx = New-G8Scratch $rule $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $f = Get-G8Findings $Exe $db $rule
  Show-G8Findings $f
  $lines = @($f | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Check 'positive: TEdit edtPassword flagged (line 2)' ($lines -contains 2)
  Check 'positive: TcxTextEdit edtPwdConfirm flagged (line 5)' ($lines -contains 5)
  Check 'positive: TMaskEdit edtOldPass flagged (line 20)' ($lines -contains 20)
  Check 'negative: edtUserName / edtPassMasked / edtPassCx / lblPassword silent' ($f.Count -eq 3)
  Check 'severity is info' (($f.Count -gt 0) -and ($f[0].severity -eq 'info'))
  # --- fix
  $dfm = Join-Path $fx 'uLogin.dfm'
  $want = Join-Path $PSScriptRoot "..\lint-project\$rule\expected\uLogin.fixed.dfm"
  & $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-Null
  Check 'fix: result is byte-identical to expected\uLogin.fixed.dfm' (Test-G8BytesEqual $dfm $want)
  $before = [IO.File]::ReadAllBytes($dfm)
  $txt = (& $Exe lint-all --db $db --rule $rule --fix --fix-rule $rule --apply --no-backup 2>&1 | Out-String)
  Check 'fix: second run leaves the bytes unchanged' ([Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][IO.File]::ReadAllBytes($dfm)))
  Check 'fix: reindexed fixed file no longer fires' ((Invoke-G8Index $Exe $fx $db) -eq 0 -and (Get-G8Findings $Exe $db $rule).Count -eq 0)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }