#Requires -Version 7.3
<#
  ReleaseGuard.ps1 -- Invoke-WithEngineBackup: run an action that is known to
  overwrite third_party\dll-win64\drag-lint.exe (build\pack-lint-release.ps1
  copies the RELEASE build over the deployed DEBUG engine) and put the deployed
  engine back byte-identically, proving it with sha256. Spec 15.6.

  Dot-source it:  . tools\lib\ReleaseGuard.ps1

  Invoke-WithEngineBackup -EnginePath <file> -Action <scriptblock> [-BackupDir <dir>]
    1. copies <file> to <BackupDir>\<name>.bak and verifies the copy's sha256
       (a bad copy throws BEFORE the action runs, so nothing is touched);
    2. runs the action; an exception from it is caught and returned as
       ActionError, never allowed to skip step 3;
    3. ALWAYS copies the backup back over <file> and verifies the sha256;
    4. deletes the backup only when the restore is verified.
  Returns [pscustomobject]{ ShaBefore; ShaAfter; Restored; ActionError }.
  Throws 'DEPLOYED ENGINE NOT RESTORED ... restore by hand from <bak>' when the
  restored bytes do not match -- the backup is then KEPT, and named.
  The action's output stream is discarded; pipe it to Out-Host inside the
  action when it must be seen.
#>
Set-StrictMode -Version Latest

function Invoke-WithEngineBackup {
  param([Parameter(Mandatory)][string]$EnginePath, [Parameter(Mandatory)][scriptblock]$Action,
        [string]$BackupDir = "$env:TEMP\drag-lint-engine-backup-$PID")
  if (-not (Test-Path -LiteralPath $EnginePath)) { throw "engine not found: $EnginePath" }
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
  $bak = Join-Path $BackupDir ([IO.Path]::GetFileName($EnginePath) + '.bak')
  $shaBefore = (Get-FileHash -LiteralPath $EnginePath -Algorithm SHA256).Hash
  Copy-Item -LiteralPath $EnginePath -Destination $bak -Force
  if ((Get-FileHash -LiteralPath $bak -Algorithm SHA256).Hash -ne $shaBefore) { throw "backup copy does not match the deployed engine ($bak)" }
  $result = [pscustomobject]@{ ShaBefore = $shaBefore; ShaAfter = ''; Restored = $false; ActionError = $null }
  try { & $Action | Out-Null }
  catch { $result.ActionError = $_.Exception.Message }
  finally {
    try {
      Copy-Item -LiteralPath $bak -Destination $EnginePath -Force
      $result.ShaAfter = (Get-FileHash -LiteralPath $EnginePath -Algorithm SHA256).Hash
      $result.Restored = ($result.ShaAfter -eq $shaBefore)
    } catch { $result.Restored = $false; $result.ShaAfter = "restore failed: $($_.Exception.Message)" }
    if ($result.Restored) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
  }
  if (-not $result.Restored) { throw "DEPLOYED ENGINE NOT RESTORED: $EnginePath (sha before $shaBefore, after $($result.ShaAfter)) -- restore by hand from $bak" }
  return $result
}
