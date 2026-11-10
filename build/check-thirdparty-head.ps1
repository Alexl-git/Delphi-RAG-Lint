<#
  check-thirdparty-head.ps1 -- every TRACKED *.dll under third_party\dll-win64, dll-win32 and dll
  must equal git HEAD (index AND working tree) before anything builds against it or parses with it.

  Why (2026-11-10): `git merge --ff-only` into main wrote 213 files and then aborted on
  "unable to unlink old third_party/dll-win64/tree-sitter-dfm.dll" -- a running engine had the
  DLL loaded. The error line was cut by `| Select-Object -Last 3`; main was moved by update-ref,
  so the July v1.1 DFM grammar (22016 B) stayed deployed under a HEAD that says v1.2.0. The
  1.49 re-parse then extracted every .dfm with the old grammar, and `info` still said current
  (the DLL is not in the index fingerprint). One `git diff HEAD` would have caught it.

  BPL/DCP and drag-lint.json are NOT checked: builds and config edits rewrite them before the
  commit that records them. The grammar/runtime DLLs are only ever committed, never built here.

  Usage:  pwsh -NoProfile -File build\check-thirdparty-head.ps1 [-Root <repo>]
  Exit 0 = all equal HEAD; 1 = drift (files listed); 2 = not a git work tree.
  Override for a lane that deliberately stages an uncommitted DLL: env DRAGLINT_ALLOW_DLL_DRIFT=1
  (prints the drift as WARNING and exits 0).
  Guard: tests\autotest\run_thirdparty_head_guard.ps1.
#>
param([string]$Root = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path
$inside = & git -C $Root rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') { Write-Host "ERROR: check-thirdparty-head: not a git work tree: $Root"; exit 2 }
$specs = @('third_party/dll-win64/*.dll', 'third_party/dll-win32/*.dll', 'third_party/dll/*.dll')
# Refresh the stat cache first so a touched-but-identical file is not reported.
& git -C $Root update-index -q --refresh 2>$null | Out-Null
$drift = @(& git -C $Root diff HEAD --name-only -- @specs)
$gone = @(& git -C $Root ls-files --deleted -- @specs)
$all = @($drift + $gone | Where-Object { $_ } | Sort-Object -Unique)
if ($all.Count -eq 0) { Write-Host "OK: third_party DLLs equal HEAD"; exit 0 }
$label = if ($env:DRAGLINT_ALLOW_DLL_DRIFT -eq '1') { 'WARNING' } else { 'ERROR' }
Write-Host "${label}: $($all.Count) tracked third_party DLL(s) differ from HEAD (a locked file a checkout/merge could not replace?):"
foreach ($p in $all) {
  $full = Join-Path $Root $p
  $len = if (Test-Path -LiteralPath $full) { (Get-Item -LiteralPath $full).Length } else { 'missing' }
  $headLen = & git -C $Root cat-file -s "HEAD:$p" 2>$null
  Write-Host "  $p  working=$len B  HEAD=$headLen B"
}
Write-Host "  Fix: stop the holder, then restore from HEAD (git show HEAD:<path> > file via [IO.File]) -- or set DRAGLINT_ALLOW_DLL_DRIFT=1 for a lane that stages one on purpose."
if ($label -eq 'WARNING') { exit 0 }
exit 1
