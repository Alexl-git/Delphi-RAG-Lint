<#
  parse-corpus.ps1 -- parse every .dfm / .fmx of tools\dfm\corpus-manifest-plus.txt (+ the 2 non-ASCII fixtures of
  tests\fixtures\dfm-nonascii) with the DFM grammar that sits BESIDE the given engine, and write one TSV row per file:
      <stage-relative name> <TAB> <errors> <TAB> <original path>
  (wave 150 DF2, DF-F1; recreated from the 149 DF lane's parse-corpus.bat + corpus-manifest-plus.txt.)

  Why the engine and not `tree-sitter parse`: the CLI caches its compiled grammar by NAME (~\AppData\Local\tree-sitter\lib\dfm.dll),
  so an A/B of two grammar directories silently measures one grammar twice (the 149 notes needed a parser.c touch). The engine loads
  tree-sitter-dfm.dll from its own folder, so engine copy A (old DLL) vs engine copy B (new DLL) is exact AND is what ships.
  The engine indexes only *.dfm, so .fmx files are staged under a .dfm name (same grammar, same walker).
  Corpus is staged by COPY into -Stage (never indexed in place); the DB is scratch and deleted afterwards.
  Run compare-corpus.ps1 on the two TSVs. HEAVY (ledger HEAVY-START/END): ~2300 files.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,
  [Parameter(Mandatory)][string]$OutTsv,
  [string]$Manifest = "$PSScriptRoot\corpus-manifest-plus.txt",
  [string]$Stage    = "$([IO.Path]::GetTempPath())dfm_corpus_stage_$PID"
)
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$fx  = Join-Path $PSScriptRoot '..\..\tests\fixtures\dfm-nonascii'
$paths = @(Get-Content $Manifest | Where-Object { $_.Trim() -ne '' })
$paths += @((Get-ChildItem $fx -Filter *.dfm).FullName)
if (Test-Path $Stage) { [IO.Directory]::Delete($Stage, $true) }
New-Item -ItemType Directory $Stage | Out-Null
$map = @{}; $n = 0; $missing = 0
foreach ($p in $paths) {
  if (-not (Test-Path -LiteralPath $p)) { $missing++; continue }
  $n++
  $name = ('{0:D5}_{1}.dfm' -f $n, [IO.Path]::GetFileNameWithoutExtension($p))
  Copy-Item -LiteralPath $p -Destination (Join-Path $Stage $name)
  $map[$name] = $p
}
Write-Host "staged $n file(s), $missing missing, from $($paths.Count) manifest rows"
$db = "$OutTsv.sqlite"
$log = "$db.log"
try {
  & $Exe index $Stage --db $db *> $log
  $rows = @()
  foreach ($l in (Get-Content $log)) {
    if ($l -match '^\s*(?<f>\S+\.dfm) -> (?<s>\d+) symbols, (?<r>\d+) refs, (?<e>\d+) errors') {
      $leaf = Split-Path $Matches.f -Leaf
      $rows += ("{0}`t{1}`t{2}" -f $leaf, $Matches.e, $map[$leaf])
    }
  }
  if ($rows.Count -eq 0) { throw "no per-file rows parsed from $log (engine output shape changed?)" }
  [IO.File]::WriteAllLines($OutTsv, $rows, [Text.Encoding]::UTF8)
  $bad = @($rows | Where-Object { ($_ -split "`t")[1] -ne '0' }).Count
  Write-Host "rows=$($rows.Count) staged=$n failing(errors>0)=$bad -> $OutTsv"
  if ($rows.Count -ne $n) { Write-Host "WARNING: rows ($($rows.Count)) <> staged ($n): the engine did not report every file" -ForegroundColor Yellow }
} finally {
  foreach ($f in @($db, "$db-wal", "$db-shm", $log)) { if (Test-Path $f) { [IO.File]::Delete($f) } }
  if (Test-Path $Stage) { [IO.Directory]::Delete($Stage, $true) }
}
