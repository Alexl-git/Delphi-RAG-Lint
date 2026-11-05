<#
  run_draglintexe_guarded.ps1 -- lane plugin (1.44 B13). SOURCE-ANCHOR GUARD (the plugin lives in a
  design-time BPL; no headless harness can run its spawn sites).

  DragLintExe never fails closed: with no engine beside the BPL it answers the bare name
  'drag-lint.exe' and 10 of its 27 call sites spawned it unchecked. Every plugin site now goes
  through RequireEngine / EngineExeOrEmpty (DragLint.Plugin.ExeResolver), which refuse a missing
  engine. Asserted:
    1. no code outside ExeResolver.pas names DragLintExe (comments and strings stripped first);
    2. ExeResolver.pas declares RequireEngine and EngineExeOrEmpty and carries the shared
       'engine not found' message constant;
    3. positive control: the same counter finds the raw call in a synthetic unit and ignores a
       comment/string mention of it.
  -SrcDir lets the RED run point at an older copy of src\delphi-plugin.
#>
[CmdletBinding()]
param(
  [string]$Root = '',
  [string]$SrcDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
Add-Type -TypeDefinition @'
using System.Text;
public static class PasStrip {
  public static string Code(string s) {
    var o = new StringBuilder(s.Length); int i = 0, n = s.Length;
    while (i < n) {
      char c = s[i];
      if (c == '\'') { i++; while (i < n) { if (s[i] == '\'') { if (i + 1 < n && s[i+1] == '\'') { i += 2; continue; } break; } if (s[i] == '\n') break; i++; } i++; o.Append(' '); }
      else if (c == '/' && i + 1 < n && s[i+1] == '/') { while (i < n && s[i] != '\n') i++; }
      else if (c == '{') { i++; while (i < n && s[i] != '}') i++; i++; o.Append(' '); }
      else if (c == '(' && i + 1 < n && s[i+1] == '*') { i += 2; while (i + 1 < n && !(s[i] == '*' && s[i+1] == ')')) i++; i += 2; o.Append(' '); }
      else { o.Append(c); i++; }
    }
    return o.ToString();
  }
}
'@
function Get-CodeOnly([string]$text) { return [PasStrip]::Code($text) }
function Count-Raw([string]$text) {
  return ([regex]::Matches((Get-CodeOnly $text), '\bDragLintExe\b')).Count
}
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) }
$dir = if ($SrcDir) { $SrcDir } else { Join-Path $Root 'src\delphi-plugin' }
$resolver = Join-Path $dir 'DragLint.Plugin.ExeResolver.pas'
if (-not (Test-Path $resolver)) { Write-Host "FATAL: missing $resolver" -ForegroundColor Red; exit 2 }

$total = 0; $where = @()
foreach ($f in Get-ChildItem $dir -Filter 'DragLint.Plugin.*.pas') {
  if ($f.Name -eq 'DragLint.Plugin.ExeResolver.pas') { continue }
  $n = Count-Raw ([IO.File]::ReadAllText($f.FullName))
  if ($n -gt 0) { $total += $n; $where += ("{0}={1}" -f $f.Name, $n) }
}
Check 'no raw DragLintExe call site outside ExeResolver.pas' ($total -eq 0) ("count=$total " + ($where -join ' '))

$r = [IO.File]::ReadAllText($resolver)
Check 'ExeResolver declares RequireEngine'    ($r -match 'function\s+RequireEngine\s*\(')
Check 'ExeResolver declares EngineExeOrEmpty' ($r -match 'function\s+EngineExeOrEmpty\s*:')
Check 'ExeResolver carries ENGINE_NOT_FOUND_MSG' ($r -match 'ENGINE_NOT_FOUND_MSG\s*=')

# PLUGIN_VERSION (1.44 owner/gate addition): About must show the real product version, so the
# plugin literal(s) must equal 'v' + DRAGLINT_VERSION. It sat at 'v1.1.0-alpha' for 40 releases.
$model = Join-Path $Root 'src\core\DRagLint.Core.Model.pas'
$pv = [regex]::Match([IO.File]::ReadAllText($model), "DRAGLINT_VERSION\s*=\s*'([^']+)'")
Check 'DRAGLINT_VERSION located' $pv.Success
$want = 'v' + $pv.Groups[1].Value
$ed = [regex]::Match([IO.File]::ReadAllText((Join-Path $dir 'DragLint.Plugin.Editor.pas')), "PLUGIN_VERSION\s*=\s*'([^']+)'")
Check "Editor.pas PLUGIN_VERSION = $want" ($ed.Success -and $ed.Groups[1].Value -eq $want) ("got " + $ed.Groups[1].Value)
$uf = [regex]::Matches([IO.File]::ReadAllText((Join-Path $dir 'DragLint.Plugin.UsagesForm.pas')), "'(v\d+\.\d+\.\d+-alpha)[ ']")
$bad = @($uf | Where-Object { $_.Groups[1].Value -ne $want })
Check "UsagesForm.pas version literals = $want" ($uf.Count -gt 0 -and $bad.Count -eq 0) ("literals=" + $uf.Count + " stale=" + $bad.Count)
$synth = "unit X;`r`n{ DragLintExe in a brace comment }`r`n// DragLintExe in a line comment`r`nvar s: string = 'DragLintExe';`r`nbegin`r`n  e:= DragLintExe;`r`n  f:= DragLintExe;`r`nend."
$sc = Count-Raw $synth
Check 'positive control: counter sees 2 raw calls, ignores comment/string mentions' ($sc -eq 2) "got $sc"

if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASSED' -ForegroundColor Green
