<#
  run_docregions_equivalence.ps1 -- E-TDOCREGIONS-RFC (wave 147 lane G2): proves the TDocRegions
  split (TDocMarkers / TDocBlockScanner / TDocFactsRenderer / TDocCommentMerger behind the
  TDocRegions facade) is behaviour-preserving: the OLD engine (built before the split) and the
  NEW engine print BYTE-EQUAL output for every document mode that runs the region engine, on
  real project indexes.

  Per project: the DB is COPIED to -WorkDir (never the real one), then both engines run, each
  output captured as raw bytes and compared by SHA-256:
    document --project P --db <copy> --json                (MergeComment, RenderFactsBlock, markers)
    document --project P --db <copy> --stubs --json        (the stub arms of MergeComment)
    document --project P --db <copy> --strip --json        (Doc.Strip over the managed markers)
  and each of the three again WITHOUT --json: the text mode prints every planned edit with the
  full generated comment text, so a changed byte of generated doc fails the comparison (the
  json mode only carries the counts).
  Nothing is written to a source: every run is a dry run (no --apply).

  Controls (a harness that cannot fail is a defect):
    * DETERMINISM: the old engine run twice on the first project is byte-equal (else a
      difference below could be noise, not the split);
    * POSITIVE: the old engine with --no-seealso against the old engine without it MUST
      differ, proving the comparison sees a change in generated doc text;
    * NON-EMPTY: every compared output is larger than 2 bytes (a crash printing nothing on
      both sides would otherwise compare equal).
  Exit 0 = equivalent everywhere, 1 = a difference or a failed control, 2 = setup.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OldExe,
  [Parameter(Mandatory)][string]$NewExe,
  [string]$WorkDir = "$env:TEMP\drag-lint-docregions-eq-$PID",
  [string[]]$Projects = @(
    'C:\Projects\DataCopy\DataCopy.dproj|C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite',
    'C:\Projects\YADF\YADF.dproj|C:\Projects\YADF\_D-RAG\YADF.sqlite',
    'C:\Projects\TableTools\TableTools370P.dproj|C:\Projects\TableTools\_D-RAG\TableTools370P.sqlite')
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
foreach ($e in $OldExe, $NewExe) { if (-not (Test-Path $e)) { Write-Host "FATAL: exe not found: $e"; exit 2 } }
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

# Runs one engine, stdout to a file as raw bytes; returns @{ Sha; Len; Exit; Path }.
function Run([string]$Exe, [string]$Tag, [string[]]$ArgList) {
  $out = Join-Path $WorkDir "$Tag.out"
  $err = Join-Path $WorkDir "$Tag.err"
  $q = $ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
  $p = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput $out -RedirectStandardError $err -Wait -NoNewWindow -PassThru
  $b = [IO.File]::ReadAllBytes($out)
  $h = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace('-', '')
  @{ Sha = $h; Len = $b.Length; Exit = $p.ExitCode; Path = $out }
}

$modes = [ordered]@{
  'merge' = @('--json'); 'merge-text' = @(); 'stubs' = @('--stubs', '--json'); 'stubs-text' = @('--stubs')
  'strip' = @('--strip', '--json'); 'strip-text' = @('--strip') }
$first = $true
foreach ($pair in $Projects) {
  $proj, $db = $pair.Split('|')
  $name = [IO.Path]::GetFileNameWithoutExtension($proj)
  if (-not (Test-Path $proj) -or -not (Test-Path $db)) { Write-Host "FATAL: missing $proj or $db"; exit 2 }
  $copy = Join-Path $WorkDir "$name.sqlite"
  [IO.File]::Copy($db, $copy, $true)
  Write-Host "-- $name ($([int]((Get-Item $copy).Length / 1MB)) MB copy)"
  foreach ($m in $modes.Keys) {
    $a = @('document', '--project', $proj, '--db', $copy) + $modes[$m]
    $o = Run $OldExe "$name-$m-old" $a
    $n = Run $NewExe "$name-$m-new" $a
    Check "$name $m non-empty" ($o.Len -gt 2 -and $n.Len -gt 2) "old=$($o.Len) new=$($n.Len) bytes"
    Check "$name $m BYTE-EQUAL old vs new" ($o.Sha -eq $n.Sha -and $o.Exit -eq $n.Exit) "sha old=$($o.Sha.Substring(0,12)) new=$($n.Sha.Substring(0,12)) exit $($o.Exit)/$($n.Exit)"
  }
  if ($first) {
    $first = $false
    $a = @('document', '--project', $proj, '--db', $copy)
    $o2 = Run $OldExe "$name-merge-old2" $a
    $o1 = [IO.File]::ReadAllBytes((Join-Path $WorkDir "$name-merge-text-old.out"))
    Check "CONTROL determinism: old twice is byte-equal" ($o2.Len -eq $o1.Length -and $o2.Sha -eq ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($o1)).Replace('-', ''))) "len=$($o2.Len)"
    $c = Run $OldExe "$name-noseealso-old" ($a + @('--no-seealso'))
    Check "CONTROL positive: --no-seealso output differs (the comparison can fail)" ($c.Len -gt 2 -and $c.Sha -ne $o2.Sha) "len=$($c.Len) vs $($o2.Len)"
  }
}
if ($script:Failed) { Write-Host 'run_docregions_equivalence: FAILED'; exit 1 }
Write-Host 'run_docregions_equivalence: OK'
