<#
  UriHandlerExe.ps1 -- dot-source, then call Initialize-UriHandlerExe -Path <default handler path>.

  WHY: drag-lint-open.exe lives under src\tools\uri-handler\Win64\ (gitignored build output), so a
  FRESH WORKTREE has none and run_uri_handler / run_protocol_verb exit 2 (SETUP) there (backlog X-06).
  The guards still build nothing: this STAGES an already-built copy, searched in order
  (1) <repo>\third_party\dll-win64, (2) the main checkout's uri-handler Win64\Debug and dll-win64.
  Returns $true when -Path exists afterwards; the caller keeps its own SETUP exit 2 otherwise.
#>
function Initialize-UriHandlerExe {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  if (Test-Path -LiteralPath $Path) { return $true }
  $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
  $cands = New-Object System.Collections.Generic.List[string]
  $cands.Add((Join-Path $repo 'third_party\dll-win64\drag-lint-open.exe'))
  $common = & git -C $repo rev-parse --path-format=absolute --git-common-dir 2>$null
  if ($LASTEXITCODE -eq 0 -and $common) {
    $main = Split-Path -Parent ($common | Select-Object -First 1)
    $cands.Add((Join-Path $main 'src\tools\uri-handler\Win64\Debug\drag-lint-open.exe'))
    $cands.Add((Join-Path $main 'third_party\dll-win64\drag-lint-open.exe'))
  }
  foreach ($c in $cands) {
    if (Test-Path -LiteralPath $c) {
      New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
      Copy-Item -LiteralPath $c -Destination $Path -Force
      Write-Host "staged drag-lint-open.exe from $c" -ForegroundColor DarkGray
      return $true
    }
  }
  return $false
}
