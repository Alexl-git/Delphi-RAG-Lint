# run_tsblank_selfcheck.ps1 -- property check of the tsblank comment blanker on fixtures\blank\sample.pas.
# usage: pwsh -File tools\grammar\run_tsblank_selfcheck.ps1 -Tsblank <path to tsblank.exe> [-Out <scratch dir>] [-PositiveControl]
# Asserts on the blanked copy: same byte length; every CR/LF byte at the same offset; every {$...} and
# (*$...*) directive byte-identical at its offset; string literals untouched; every KeepN token present;
# no COMMENT_TEXT_N marker left; the blanked bytes are spaces or line breaks wherever the original had a
# comment. -PositiveControl feeds the UNBLANKED file as if it were the output: the check must then FAIL.
# Exit 0 = PASS, 1 = FAIL. 7-bit ASCII, CRLF. pwsh 7.
param(
  [Parameter(Mandatory)][string]$Tsblank,
  [string]$Out = (Join-Path ([IO.Path]::GetTempPath()) 'tsblank-selfcheck'),
  [switch]$PositiveControl
)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $PSScriptRoot 'fixtures\blank\sample.pas'
New-Item -ItemType Directory -Force $Out | Out-Null
$outFile = Join-Path $Out 'sample.blanked.pas'
$r = & $Tsblank blank $fixture $outFile 2>&1
if ($LASTEXITCODE -ne 0) { "FAIL tsblank exit $LASTEXITCODE : $r"; exit 1 }
$src = [IO.File]::ReadAllBytes($fixture)
$bl = if ($PositiveControl) { $src } else { [IO.File]::ReadAllBytes($outFile) }
$fails = New-Object System.Collections.Generic.List[string]
if ($bl.Length -ne $src.Length) { $fails.Add("length $($bl.Length) <> $($src.Length)") }
$n = [Math]::Min($bl.Length, $src.Length)
$lb = 0
for ($i = 0; $i -lt $n; $i++) {
  $a = $src[$i]; $b = $bl[$i]
  if (($a -eq 13 -or $a -eq 10) -and $b -ne $a) { $lb++ }
  if (($b -eq 13 -or $b -eq 10) -and $b -ne $a) { $lb++ }
}
if ($lb -gt 0) { $fails.Add("$lb line-break bytes moved") }
$srcText = [Text.Encoding]::ASCII.GetString($src)
$blText = [Text.Encoding]::ASCII.GetString($bl)
foreach ($m in [regex]::Matches($srcText, '\{\$[^}]*\}|\(\*\$.*?\*\)')) {
  # a {$..} inside a // comment is comment text, not a directive: skip it (the fixture has one)
  $lineStart = $srcText.LastIndexOf("`n", $m.Index) + 1
  if ($srcText.Substring($lineStart, $m.Index - $lineStart).Contains('//')) { continue }
  if ($blText.Substring($m.Index, $m.Length) -ne $m.Value) { $fails.Add("directive changed at $($m.Index): $($m.Value)") }
}
foreach ($lit in @("'{not a comment}'", "'// not a comment either'", "'it''s {still} a string'", "'(* nor this *)'")) {
  if (-not $blText.Contains($lit)) { $fails.Add("string literal lost: $lit") }
}
foreach ($k in 1..8) { if (-not $blText.Contains("Keep$k")) { $fails.Add("Keep$k lost") } }
foreach ($k in 1..9) { if ($blText.Contains("COMMENT_TEXT_$k")) { $fails.Add("COMMENT_TEXT_$k still present") } }
# `{ COMMENT_TEXT_8 }` is 18 bytes + the space before Integer = 19 spaces
if (-not $blText.Contains('TList<' + (' ' * 19) + 'Integer>')) { $fails.Add('generic-arg comment not blanked to spaces') }
if ($blText.Contains('LOOKS_LIKE_DIRECTIVE_IN_COMMENT')) { $fails.Add('a directive-looking text inside a // comment was kept') }
$bad = 0
for ($i = 0; $i -lt $n; $i++) { if ($bl[$i] -ne $src[$i] -and $bl[$i] -ne 32) { $bad++ } }
if ($bad -gt 0) { $fails.Add("$bad changed bytes are not spaces") }
$label = if ($PositiveControl) { 'positive-control' } else { 'selfcheck' }
if ($PositiveControl) {
  if ($fails.Count -gt 0) { "PASS $label (the unblanked file fails $($fails.Count) assertion(s): $($fails[0]))"; exit 0 }
  "FAIL $label : the unblanked file passed every assertion -- the guard cannot fail"; exit 1
}
if ($fails.Count -eq 0) { "PASS $label $($src.Length) bytes, $r"; exit 0 }
"FAIL $label"; $fails | ForEach-Object { "  $_" }; exit 1
