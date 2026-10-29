<#
  run_lsp_exe_resolver_wiring.ps1 -- lane CLIFIX C4 (#19). SOURCE-ANCHOR GUARD ONLY (no headless
  harness can run EnsureLspClient: it lives in a design-time BPL inside a running RAD Studio).

  EnsureLspClient spawned the language server from its OWN copy of the exe lookup (win64 sibling,
  then the BPL dir, then PATH), so the Settings ExePath override that every other spawn site honours
  (DragLintExe) never reached the editor's server. Asserted, structurally:
    1. inside the `if GLspClient = nil then` block, `ExePath:= DragLintExe` appears BEFORE any
       `FileExists(Win64Dir + ...)` lookup and before the server is started;
    2. the old lookup is only a fallback: it follows an `else` of the resolver branch;
    3. the shared resolver itself tries the Settings override FIRST (LoadSettings.ExePath before
       the dll-win64 sibling) - so wiring to it is what carries the override;
    4. positive control: the same test on a copy with the resolver line removed reports it absent.
  The BPL is not built here; the owner builds the Debug BPL with the IDE closed at deploy.
  -EditorSource lets the RED run point at an older copy of Editor.pas.
#>
[CmdletBinding()]
param(
  [string]$Root = "$PSScriptRoot\..\..",
  [string]$EditorSource = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
$editor   = if ($EditorSource) { $EditorSource } else { Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.Editor.pas' }
$resolver = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.ExeResolver.pas'
foreach ($f in @($editor, $resolver)) { if (-not (Test-Path $f)) { Write-Host "FATAL: missing $f" -ForegroundColor Red; exit 2 } }
$eSrc = Get-Content $editor -Raw
$rSrc = Get-Content $resolver -Raw

$spawn = [regex]::Match($eSrc,
  'if\s+GLspClient\s*=\s*nil\s+then\s*begin(?<body>.*?)GLspClient\s*\.\s*Start\s*\(', 'Singleline')
Check 'the server-spawn block was located in Editor.pas' $spawn.Success
$body = if ($spawn.Success) { $spawn.Groups['body'].Value } else { '' }

function Has-ResolverFirst([string]$B) {
  $r = [regex]::Match($B, 'ExePath\s*:=\s*DragLintExe\s*;')
  $w = [regex]::Match($B, "FileExists\s*\(\s*Win64Dir")
  return ($r.Success -and $w.Success -and ($r.Index -lt $w.Index))
}
Check '1. ExePath:= DragLintExe precedes the private win64 lookup' (Has-ResolverFirst $body)
Check '2. the private lookup is only an else-fallback of the resolver' ($body -match 'else\s+if\s+FileExists\s*\(\s*Win64Dir')

$res = [regex]::Match($rSrc, 'function\s+DragLintExe\s*:\s*string;\s*var.*?begin(?<b>.*?)initialization', 'Singleline')
$rb = if ($res.Success) { $res.Groups['b'].Value } else { '' }
$iOv = $rb.IndexOf('LoadSettings.ExePath'); $iWin = $rb.IndexOf('dll-win64')
Check '3. the shared resolver reads the Settings override before the dll-win64 sibling' (($iOv -ge 0) -and ($iWin -gt $iOv))

$stripped = [regex]::Replace($body, 'ExePath\s*:=\s*DragLintExe\s*;', '')
Check '4. positive control: with the resolver line removed the test reports it absent' (-not (Has-ResolverFirst $stripped))

if ($script:Failed) { Write-Host 'run_lsp_exe_resolver_wiring: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_exe_resolver_wiring: PASS' -ForegroundColor Green
exit 0
