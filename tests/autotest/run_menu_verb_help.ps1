<#
  run_menu_verb_help.ps1 -- `menu-tree --help` and `menu-drift --help` print THEIR OWN
  help (the registry entry's `help` line, features\entries\menu-tree.json), not the
  global banner (W6-cli item c).

  Source of truth is the entry: the printed text must contain every `help` line of
  the verb's surface verbatim, and every flag the entry lists. Positive controls:
  bare `--help` and another verb's `--help` still print the banner (COMMON QUESTIONS),
  so a verb that merely lost the banner text everywhere cannot pass.
  Run with pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$entry = Get-Content (Join-Path $PSScriptRoot '..\..\features\entries\menu-tree.json') -Raw | ConvertFrom-Json
function Help([string[]]$A) {
  $o = & $Exe @A 2>$null
  return @{ Text = ($o -join "`n"); Code = $LASTEXITCODE }
}
foreach ($s in $entry.surfaces | Where-Object { $_.type -eq 'cli' }) {
  foreach ($tok in '--help', '-h') {
    $r = Help @($s.verb, $tok)
    $n = "$($s.verb) $tok"
    Check "$n exit 0" ($r.Code -eq 0) "code=$($r.Code)"
    Check "$n has no global banner" (($r.Text -notmatch 'COMMON QUESTIONS') -and ($r.Text -notmatch 'Delphi-RAG-Lint: symbol-aware'))
    foreach ($h in $s.help) { Check "$n prints entry help line" ($r.Text.Contains($h.TrimEnd())) }
    foreach ($f in $s.flags) { Check "$n mentions $($f.name)" ($r.Text.Contains($f.name)) }
  }
}
# X-26b (CLI lane 2026-10-26): BYTE check. `verb --help` stdout is exactly the entry's help lines,
# each CRLF-terminated, nothing before or after -- a Contains() test above passes on a superset.
function Get-RawStdout([string[]]$A) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $null = Start-Process -FilePath $Exe -ArgumentList $A -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait -PassThru
  $b = [IO.File]::ReadAllBytes($o); [IO.File]::Delete($o); [IO.File]::Delete($e)
  return $b
}
function Test-SameBytes([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
  return $true
}
foreach ($s in $entry.surfaces | Where-Object { $_.type -eq 'cli' }) {
  $want = [Text.Encoding]::ASCII.GetBytes((($s.help | ForEach-Object { "$_`r`n" }) -join ''))
  $got = Get-RawStdout @($s.verb, '--help')
  Check "$($s.verb) --help stdout is byte-identical to the registry help lines" (Test-SameBytes $got $want) "got=$($got.Length) want=$($want.Length) bytes"
  if ($s.verb -eq 'menu-tree') {
    $planted = [byte[]]($want + [byte]0x20)
    Check 'control: the byte check rejects one extra byte' (-not (Test-SameBytes $planted $want))
  }
}# X-26: the per-verb text is GENERATED (DRagLint.CLI.HelpText.WriteVerbHelp), never a hard-coded copy in CLI.pas.
function Test-HardCoded([string]$src) {
  $m = [regex]::Match($src, '(?s)procedure PrintMenuVerbHelp\(.*?\r?\nend;')
  return ($m.Success -and ($m.Value -match "Writeln\('\s+drag-lint menu-"))
}
$cli = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\src\cli\DRagLint.CLI.pas'))
Check 'X-26: PrintMenuVerbHelp has no hard-coded verb text' (-not (Test-HardCoded $cli))
Check 'X-26: PrintMenuVerbHelp calls the generated WriteVerbHelp' ($cli -match '(?s)procedure PrintMenuVerbHelp\(.*?WriteVerbHelp\(AVerb\)')
$planted = "procedure PrintMenuVerbHelp(const AVerb: string);`r`nbegin`r`n  Writeln('  drag-lint menu-tree --project');`r`nend;"
Check 'control: the check detects a hard-coded Writeln' (Test-HardCoded $planted)
# positive controls: the banner is still the answer elsewhere
$b = Help @('--help')
Check 'control: bare --help prints the banner' (($b.Code -eq 0) -and ($b.Text -match 'COMMON QUESTIONS'))
$b = Help @('index', '--help')
Check 'control: index --help still prints the banner' (($b.Code -eq 0) -and ($b.Text -match 'COMMON QUESTIONS'))
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
