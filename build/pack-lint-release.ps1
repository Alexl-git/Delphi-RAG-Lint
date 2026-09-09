<#
  pack-lint-release.ps1 -Version <X.Y.Z-alpha>

  Builds drag-lint.exe Release for Win64 + Win32, deploys the Win64 exe to
  third_party\dll-win64, and stages + zips a self-contained release archive per
  platform that BUNDLES the rules\ folder next to the exe.

  It also ships the COMPONENT CONVERTER, which until 2026-09-09 existed only in
  this checkout: ConvRulesEditor.exe (the visual rule-book editor), the starter
  rule books under convrules\, the casts.castlib that convert-apply --castlib and
  the editor both read, and the converter documentation. The editor is Win64 ONLY
  -- it is built by dcc64 straight from a .dpr with no Win32 configuration -- so
  the win32 archive omits it AND SAYS SO, rather than dropping it silently.

  Output: C:\TEMP\rel-<Version>\drag-lint-v<Version>-win64.zip (and -win32.zip)
  Prints the two zip paths on success. Tag + gh release create are done separately.

  -SkipBuild stages and zips from the binaries ALREADY on disk. It exists so the
  PAYLOAD can be checked without paying for two Release builds -- the half of this
  script that decides what a user receives is the half with no compiler in it, and
  it used to be unverifiable except by cutting a release. It also does NOT refresh
  third_party\dll-win64\drag-lint.exe, so it is safe to run while something else
  is using that engine. Never cut a real release with it: the archive then carries
  whatever was last built, which is not necessarily this checkout.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version,
      [switch]$SkipBuild)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$rs = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"'
$dproj = Join-Path $repo "src\cli\drag-lint.dproj"

if ($SkipBuild) {
  Write-Host "-SkipBuild: staging from the binaries already on disk (NOT a releasable archive)" -ForegroundColor Yellow
} else {

foreach ($plat in 'Win64','Win32') {
  $out = cmd /c "$rs && msbuild /t:Build /p:Config=Release /p:Platform=$plat /v:minimal `"$dproj`"" 2>&1
  $err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
  if ($err) { Write-Host "$plat BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
  Write-Host ("{0}: {1}" -f $plat, ($out | Select-Object -Last 1))
}
# keep the canonical Win64 exe (used by tests / IDE plugin) in sync
Copy-Item (Join-Path $repo "src\cli\Win64\Release\drag-lint.exe") (Join-Path $repo "third_party\dll-win64\drag-lint.exe") -Force

# ConvRulesEditor.exe (Win64). The batch compiles the VCL-style .res with brcc32
# FIRST and gates on it, because dcc64 cannot compile a .rc and a stale .res would
# otherwise be linked in while the build still printed success.
#
# Gated on BOTH the batch's exit code and the BUILD_EXITCODE=0 line it echoes. A
# batch file's own exit code is easy to lose across `cmd /c`, and the failure this
# guards is the one the repo has already paid for once: a build script reporting
# green for code that was never compiled.
$edBat = Join-Path $repo "build\_build_convrules_editor_local.bat"
$edOut = cmd /c "`"$edBat`"" 2>&1
if (($LASTEXITCODE -ne 0) -or -not ($edOut | Select-String -SimpleMatch "BUILD_EXITCODE=0" -Quiet)) {
  Write-Host "ConvRulesEditor BUILD FAILED:"; $edOut | Select-Object -Last 15; exit 1
}
Write-Host "ConvRulesEditor: built Win64"

}  # end -SkipBuild

$rel = "C:\TEMP\rel-$Version"
if (Test-Path $rel) { Remove-Item $rel -Recurse -Force }
$zips = @()
foreach ($plat in 'win64','win32') {
  if ($plat -eq 'win64') { $exe = "src\cli\Win64\Release\drag-lint.exe"; $dll = "third_party\dll-win64" }
  else                   { $exe = "src\cli\Win32\Release\drag-lint.exe"; $dll = "third_party\dll-win32" }
  $stg = Join-Path $rel "drag-lint-v$Version-$plat"
  New-Item -ItemType Directory -Path (Join-Path $stg "rules"), (Join-Path $stg "docs\lint"),
                                     (Join-Path $stg "docs\converter"),
                                     (Join-Path $stg "convrules\vendor") -Force | Out-Null
  Copy-Item (Join-Path $repo $exe) $stg
  foreach ($d in 'tree-sitter-delphi13.dll','tree-sitter-dfm.dll','tree-sitter.dll') { Copy-Item (Join-Path $repo "$dll\$d") $stg }
  Copy-Item (Join-Path $repo "rules\*.scm") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\*.json") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\builtin-symbols.txt") (Join-Path $stg "rules")
  Copy-Item (Join-Path $repo "rules\README.md") (Join-Path $stg "rules")
  foreach ($f in 'README.md','CHANGELOG.md','LICENSE','INSTALL.md') { Copy-Item (Join-Path $repo $f) $stg }
  if (Test-Path (Join-Path $repo "docs\AI-USAGE.md")) { Copy-Item (Join-Path $repo "docs\AI-USAGE.md") (Join-Path $stg "docs") }
  # "Three Ways to Read Delphi" -- background on the parsing layer this engine is
  # built on. Shipped in BOTH forms on purpose: the .md renders anywhere, and the
  # .html is the styled version the article was authored as, which is the one worth
  # reading offline. NOT copied blind -- a missing file here would fail the pack.
  foreach ($a in 'PARSING-LAYERS.md','PARSING-LAYERS.html') {
    $src = Join-Path $repo "docs\$a"
    if (Test-Path $src) { Copy-Item $src (Join-Path $stg "docs") }
    else { Write-Host "  WARNING: docs\$a is missing -- not in this release" -ForegroundColor Yellow }
  }
  Copy-Item (Join-Path $repo "docs\lint\REPORT-1-delphi-lint-landscape.md") (Join-Path $stg "docs\lint")
  Copy-Item (Join-Path $repo "docs\lint\REPORT-2-draglint-implementation-plan.md") (Join-Path $stg "docs\lint")

  # --- component converter ---------------------------------------------------
  # Copied WITHOUT a Test-Path guard on purpose: $ErrorActionPreference is Stop, so
  # a missing source fails the pack loudly. The one fail-open block in this script
  # (PARSING-LAYERS, above) is a deliberate exception and is announced when it fires;
  # everything here is required, and a release that quietly lost the rule books would
  # ship an editor with nothing to open.
  #
  # Rule books and the DSL reference go in BOTH archives: convert-scaffold /
  # convert-validate / convert-apply are CLI verbs, so a win32 user authors and
  # applies the same books, just without the GUI.
  Copy-Item (Join-Path $repo "docs\CONVERSION-RULES.md")         (Join-Path $stg "docs")
  Copy-Item (Join-Path $repo "docs\converter\convrules-dsl.md")  (Join-Path $stg "docs\converter")
  Copy-Item (Join-Path $repo "convrules\sample.rules")           (Join-Path $stg "convrules")
  Copy-Item (Join-Path $repo "convrules\BDE-to-FireDAC.rules")   (Join-Path $stg "convrules")
  Copy-Item (Join-Path $repo "convrules\vendor\*")               (Join-Path $stg "convrules\vendor")
  # Read beside the exe by the editor (ResolveCastLib) and named explicitly by
  # `convert-apply --castlib`, so it belongs at the archive ROOT on both platforms.
  Copy-Item (Join-Path $repo "docs\examples\convrules\casts.castlib") $stg
  # convrules-catalog.index is DELIBERATELY NOT copied. It stores ABSOLUTE paths
  # into this build machine's checkout, so shipping it hands the user a coverage
  # index that points at folders they do not have. The editor rebuilds it for the
  # real folder on the first "Rescan rules"; an absent index is the correct state.

  if ($plat -eq 'win64') {
    Copy-Item (Join-Path $repo "src\tools\convrules-editor\ConvRulesEditor.exe") $stg
    # The manual documents a GUI, so it ships only where the GUI does -- a manual
    # for an exe that is not in the archive is worse than no manual.
    Copy-Item (Join-Path $repo "docs\converter\convrules-editor-manual.md") (Join-Path $stg "docs\converter")
  } else {
    Write-Host "  note: ConvRulesEditor.exe is Win64-only -- omitted from the win32 archive" -ForegroundColor Yellow
  }
  $z = Join-Path $rel "drag-lint-v$Version-$plat.zip"
  Compress-Archive -Path $stg -DestinationPath $z
  Write-Host ("{0} -> {1:N0} bytes" -f $plat, (Get-Item $z).Length)
  $zips += $z
}
Write-Host ("ZIPS: " + ($zips -join " "))
