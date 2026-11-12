<#
  run_doc_attr_decl_apply_152b.ps1 -- 152b DOC handover guard (RED until the Facts.ReadDeclLine
  attribute skip AND the `document --apply` declaration-line check accept an attributed routine).

  `[Test] [Ignore('why: x')]` above `function Calc: Integer;` puts the index start line on the
  ATTRIBUTE line. Base 1.50.0-alpha: `document --unit --apply` answers
  "REFUSED 1 edit(s) -- the declaration is not at the line the index reports" and writes nothing.
  Asserts: the file gains a <summary> above the attribute line and a <returns> tag for Calc;
  CONTROL: the same routine without attributes is documented (guard can fail the other way).
  Owner of the Facts edit: DF (Doc.Facts.pas:3124). The refusal text lives in DRagLint.CLI.pas.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-docattr152b-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$src = Join-Path $WorkDir 'attrapply.pas'
$db  = Join-Path $WorkDir 'attrapply.sqlite'
$lines = @('unit attrapply;', '', 'interface', '', 'type', '  TFx = class', '  public',
  "    [Test] [Ignore('why: not now')]", '    function Calc: Integer;',
  '    function Plain: Integer;', '  end;', '', 'implementation', '',
  'function TFx.Calc: Integer;', 'begin', '  Result:= 1;', 'end;', '',
  'function TFx.Plain: Integer;', 'begin', '  Result:= 2;', 'end;', '', 'end.')
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
Push-Location $WorkDir
try {
  & $Exe index $WorkDir --db $db --library-db none 2>&1 | Out-Null
  $o = (& $Exe document --unit $src --apply --db $db --library-db none 2>&1 | Out-String)
  $t = [IO.File]::ReadAllText($src)
  Check 'SANITY: document ran' ($o -match 'doc:') $o
  Check 'CONTROL: Plain (no attribute) got a returns tag' ($t -match '(?s)<returns>.*function TFx\.Plain|(?s)<returns>[^\r\n]*\r\n\s*function Plain') $t
  Check 'A: attributed Calc was not REFUSED' ($o -notmatch 'REFUSED') $o
  Check 'A: attributed Calc got a <returns> above its attribute line' ($t -match "(?s)<returns>[^\r\n]*</returns>\s*\r\n\s*\[Test\]") $t
} finally { Pop-Location }
if (-not $script:Failed -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
