<#
.SYNOPSIS
  One-time CLI flag audit (LSP stream C7 / S0b). Read-only: compares the flags
  DRagLint.CLI.pas parses with the flags --help documents.
.DESCRIPTION
  P = flags in `A = '--x'` forms in CLI.pas; H = `--x` tokens in --help.
  P\H probed with `drag-lint --x <dummy>`: accepted unless the answer is
  "Unknown argument: --x" (exit 3) -> ACCEPTED-UNDOCUMENTED. H\P = documented
  but unparsed. Positive controls (-AcceptedUndocumentedControl, -DocumentedControl)
  are reported PASS / FAIL / UNAVAILABLE (flag absent from this CLI.pas).
.PARAMETER Exe     engine to run (default: deployed dll-win64; use a lane engine for lane-P flags)
.PARAMETER CliPas  CLI source to scan (default: this worktree's src\cli\DRagLint.CLI.pas)
#>
param(
  [string]$Exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe',
  [string]$CliPas = (Join-Path $PSScriptRoot '..\src\cli\DRagLint.CLI.pas'),
  [string]$HelpText = (Join-Path $PSScriptRoot '..\src\cli\DRagLint.CLI.HelpText.pas'),
  [string]$SrcRoot = (Join-Path $PSScriptRoot '..\src'),
  [switch]$HelpFromExe,
  [string]$AcceptedUndocumentedControl = '--merge-diagnostics',
  [string]$DocumentedControl = '--trace',
  [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
$CliPas = (Resolve-Path $CliPas).Path
$lines = [IO.File]::ReadAllLines($CliPas)
$P = [ordered]@{}
for ($n = 0; $n -lt $lines.Count; $n++) {
  foreach ($m in [regex]::Matches($lines[$n], "\bA\s*=\s*'(--[a-z][a-z0-9-]*)'")) {
    $f = $m.Groups[1].Value
    if (-not $P.Contains($f)) { $P[$f] = @{ Line = $n + 1; Ctx = $lines[$n].Trim() } }
  }
}
# H from the SAME revision as P: the generated HelpText.pas next to CLI.pas (default), or the exe's --help (-HelpFromExe).
if ($HelpFromExe) { $help = (& $Exe --help 2>&1 | Out-String) } else { $help = [IO.File]::ReadAllText((Resolve-Path $HelpText).Path) }
# V = '--x' literals in ANY src unit (verb-local parsers), for classifying H\P rows.
$V = @{}
foreach ($u in Get-ChildItem (Resolve-Path $SrcRoot).Path -Recurse -Filter *.pas) {
  if ($u.Name -eq 'DRagLint.CLI.HelpText.pas') { continue }
  $ul = [IO.File]::ReadAllLines($u.FullName)
  for ($k = 0; $k -lt $ul.Count; $k++) { foreach ($mm in [regex]::Matches($ul[$k], "'(--[a-z][A-Za-z0-9-]*)'")) { if (-not $V.ContainsKey($mm.Groups[1].Value)) { $V[$mm.Groups[1].Value] = "$($u.Name):$($k+1)" } } }
}
$H = [ordered]@{}
foreach ($m in [regex]::Matches($help, '(?<![A-Za-z0-9-])(--[a-z][A-Za-z0-9-]*)')) { $H[$m.Groups[1].Value] = 1 }

function Test-Accepted([string]$flag) {
  $tmp = Join-Path $env:TEMP 'cli-flag-audit-cwd'
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $psi = New-Object Diagnostics.ProcessStartInfo $Exe
  $psi.Arguments = "$flag x"; $psi.WorkingDirectory = $tmp
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch {}; return 'accepted(timeout)' }
  $txt = $o.Result + $e.Result
  if ($txt -match [regex]::Escape("Unknown argument: $flag")) { return 'rejected' }
  return 'accepted'
}

$accUndoc = @(); $docUnparsed = @(); $rejected = @()
foreach ($f in $P.Keys) {
  if (-not $H.Contains($f)) {
    if ((Test-Accepted $f) -like 'accepted*') { $accUndoc += $f } else { $rejected += $f }
  }
}
foreach ($f in $H.Keys) { if (-not $P.Contains($f)) { $docUnparsed += $f } }

$out = New-Object Collections.Generic.List[string]
$out.Add('## Table 1: ACCEPTED-UNDOCUMENTED (parsed in CLI.pas, accepted by the engine, absent from --help)')
$out.Add('| flag | CLI.pas line | parser line |'); $out.Add('|---|---|---|')
foreach ($f in $accUndoc) { $out.Add("| ``$f`` | $($P[$f].Line) | ``$($P[$f].Ctx.Replace('|','/'))`` |") }
$out.Add(''); $out.Add('## Table 2: DOCUMENTED-UNPARSED (in --help, no `A = ''--x''` parser form)')
$out.Add('| flag | note |'); $out.Add('|---|---|')
foreach ($f in $docUnparsed) { $out.Add("| ``$f`` | " + $(if ($V.ContainsKey($f)) { "verb-local parser in $($V[$f])" } else { "UNLOCATED: no '--x' literal in any src unit" }) + " |") }
$out.Add('')
$out.Add("Counts: parsed=$($P.Count) documented=$($H.Count) accepted-undocumented=$($accUndoc.Count) documented-unparsed=$($docUnparsed.Count) parsed-undocumented-but-rejected=$($rejected.Count)")
$out.Add("Engine: $Exe ; CLI.pas: $CliPas")
function Ctl([string]$name, [bool]$expectUndoc) {
  if (-not $P.Contains($name)) { return "UNAVAILABLE ($name not parsed in this CLI.pas)" }
  $isU = $accUndoc -contains $name
  $inH = $H.Contains($name)
  if ($expectUndoc) { if ($isU) { return 'PASS' } else { return "FAIL (parsed; accepted-undocumented=$isU documented=$inH)" } }
  if ($inH -and -not ($accUndoc -contains $name)) { return 'PASS' } else { return "FAIL (documented=$inH)" }
}
$out.Add("Control accepted-undocumented $AcceptedUndocumentedControl : $(Ctl $AcceptedUndocumentedControl $true)")
$out.Add("Control documented+accepted $DocumentedControl : $(Ctl $DocumentedControl $false)")
if ($OutFile) { [IO.File]::WriteAllLines($OutFile, $out) } else { $out }
