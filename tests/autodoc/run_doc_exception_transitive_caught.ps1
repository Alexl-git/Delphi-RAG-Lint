<#
  run_doc_exception_transitive_caught.ps1 -- a one-hop callee raise that the
  caller CATCHES at the call site is not an <exception cref> of the caller.

  THE DEFECT (INBOX-2026-09-29-engine-followups-from-1.20.4 #5, still
  reproduced 2026-10-23): `document` wrote
      <exception cref="EManifestError">via ...TManifestIO.ParseTextEx: ...
  on TManifestIO.Load, whose ParseTextEx call sits inside
      try .. except on E: Exception do NoteLoadError(..); end
  -- the exception never leaves Load. The writer's one-hop walk
  (TDocFactsBuilder.MineCalleeRaises) harvested every resolved callee's raises
  without looking at the call SITE.

  RED, MEASURED ON THE 1.36.0-alpha BASE (gaps/stage 7dc3b0f2) BEFORE THE FIX:
  CatchAll, CatchBare, CatchExact, CatchNested and CatchElse all rendered
  `<exception cref="EBoom">...via transitive_caught.Raiser: boom`.

  POSITIVE CONTROLS: CatchOther, CatchReraise, CallInHandler, CallOutside,
  FinallyOnly and Mixed must KEEP the via tag, so the fix cannot pass by
  dropping every callee raise; Raiser keeps its own-body tag.

  Usage: pwsh -File tests\autodoc\run_doc_exception_transitive_caught.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Fixture = "$PSScriptRoot\fixtures\docdrift\transitive_caught.pas"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_doc_exc_transitive_caught_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
$srcDir = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $srcDir | Out-Null
$db = Join-Path $scratch 'w.sqlite'
try {
  Copy-Item (Resolve-Path $Fixture).Path (Join-Path $srcDir 'transitive_caught.pas') -Force
  & $exePath index $srcDir --db $db 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "index failed ($LASTEXITCODE)" }

  # `document --qname` renders the edit for an undocumented declaration; the
  # emitter may wrap a tag, so flatten continuation lines before matching.
  function DocFor([string]$Name) {
    $raw = (& $exePath document --qname "transitive_caught.$Name" --db $db 2>$null | Out-String)
    return (($raw -replace "`r?`n\s*///\s?", ' ') -replace '\s+', ' ')
  }
  $viaTag = 'cref="EBoom"><!-- drag-lint:auto exc -->via transitive_caught.Raiser'

  Write-Host "== caught at the call site: no via tag"
  foreach ($n in 'CatchAll', 'CatchBare', 'CatchExact', 'CatchNested', 'CatchElse') {
    $d = DocFor $n
    Check "$n renders a doc block" ($d -match '<summary>') "empty render: $d"
    Check "$n has no EBoom cref" (-not $d.Contains('cref="EBoom"')) $d
  }

  Write-Host "== positive controls: the via tag stays"
  foreach ($n in 'CatchOther', 'CatchReraise', 'CallInHandler', 'CallOutside', 'FinallyOnly', 'Mixed') {
    $d = DocFor $n
    Check "$n keeps the via EBoom cref" ($d.Contains($viaTag)) $d
  }
  $d = DocFor 'Raiser'
  Check "Raiser keeps its own-body EBoom cref" ($d -match 'cref="EBoom"><!-- drag-lint:auto exc -->boom') $d
}
finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host "FAIL" -ForegroundColor Red; exit 1 }
Write-Host "PASS" -ForegroundColor Green
exit 0
