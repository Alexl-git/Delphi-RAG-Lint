<#
  run_target_compiler_d5.ps1 -- Delphi 5 and older as a target compiler (backlog
  D5-COMPILERVER; owner: "Do it", DL is used occasionally on a Delphi 5 VM).

  THE DEFECT. 1.40 on the VM refused D5: ParseCompilerToken knew nothing below
  CompilerVersion 14. D5 has no CompilerVersion constant (D6 = 14.0 introduced it);
  it defines VER130. An `auto` on a D5 project also refused: a .dpr has no ProjectVersion.

  THE FIX (lane d5b, 1.43)
    * tokens 5 / D5 / Delphi 5 / VER130 -> 13; D1..D4 likewise; VER<N> -> N div 10;
    * a BARE 13 stays Delphi 13 (37): product and CompilerVersion numbers only stay
      unambiguous when a bare number below 14 is a product;
    * auto on a .dpr / .dpk: a sibling .dproj still decides; with none nothing names
      the compiler, so D5 (13) is assumed WITH A NOTE on stderr;
    * auto with no project at all and an unknown token still refuse (a typo must not
      silently mean Delphi 5);
    * below 14 the preprocessor describes that compiler's own symbols, not Delphi 13's
      with a new version number: WIN32 and VER130 on, CONDITIONALEXPRESSIONS, UNICODE,
      MSWINDOWS, WIN64 off, whatever --platform says. D5's set is from the Delphi 5
      documentation and is NOT measured here (no dcc32 for it on this box).

  Run from a neutral cwd, pwsh 7. Default -Exe has no drag-lint.json beside it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_tc_d5_$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
$sib = Join-Path $WorkDir 'sib'
$cwd = Join-Path $WorkDir 'cwd'
foreach ($d in @($src, $sib, $cwd)) { [void][IO.Directory]::CreateDirectory($d) }
$ascii = New-Object System.Text.ASCIIEncoding
function WriteLines([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, ($Lines -join "`r`n") + "`r`n", $ascii)
}
function Exec([string[]]$ArgList) {
  Push-Location $cwd
  try {
    $errFile = Join-Path $WorkDir 'stderr.txt'
    $o = & $Exe @ArgList 2>$errFile | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $e = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  } finally { Pop-Location }
  return @{ Code = $code; Out = ($o -join "`n"); Err = $e }
}
function TargetOf([string[]]$Extra) {
  $r = Exec (@('rules', '--json') + $Extra)
  if ($r.Code -ne 0) { return "exit$($r.Code)" }
  return [string](($r.Out | ConvertFrom-Json).target_compiler)
}

# ---- tokens -----------------------------------------------------------------------
foreach ($t in @(@('5', 13), @('D5', 13), @('d5', 13), @('Delphi 5', 13), @('5.0', 13), @('VER130', 13), @('ver130', 13),
                 @('4', 12), @('D4', 12), @('VER120', 12), @('3', 10), @('VER100', 10), @('2', 9), @('VER90', 9),
                 @('1', 8), @('VER80', 8), @('VER110', 11), @('VER125', 12), @('VER140', 14), @('VER185', 18), @('VER370', 37))) {
  $got = TargetOf @('--target-compiler', $t[0])
  Check "token '$($t[0])' -> $($t[1])" ($got -eq [string]$t[1]) "got $got"
}
# CONTROLS: the old tokens did not move, a bare number below 14 stays a product.
foreach ($t in @(@('13', 37), @('12', 36), @('8', 16), @('7', 15), @('6', 14), @('14', 14), @('37', 37))) {
  $got = TargetOf @('--target-compiler', $t[0])
  Check "CONTROL token '$($t[0])' -> $($t[1])" ($got -eq [string]$t[1]) "got $got"
}
foreach ($bad in @('0', '38', 'VER133', 'VER70', 'VER380', 'VER', 'D9', 'florence2')) {
  $r = Exec @('rules', '--json', '--target-compiler', $bad)
  Check "CONTROL unknown token '$bad' refuses, naming the D5 tokens" (($r.Code -eq 2) -and ($r.Err -match 'unknown version') -and ($r.Err -match 'VER130')) "exit $($r.Code)"
}

# ---- auto ---------------------------------------------------------------------------
WriteLines (Join-Path $src 'UD5.pas') @(
  'unit UD5;', '', 'interface', '',
  '{$IFDEF VER130}', 'const K_VER130 = 1;', '{$ENDIF}',
  '{$IFDEF VER370}', 'const K_VER370 = 1;', '{$ENDIF}',
  '{$IFDEF WIN32}', 'const K_WIN32 = 1;', '{$ENDIF}',
  '{$IFDEF WIN64}', 'const K_WIN64 = 1;', '{$ENDIF}',
  '{$IFDEF MSWINDOWS}', 'const K_MSWINDOWS = 1;', '{$ENDIF}',
  '{$IFDEF UNICODE}', 'const K_UNICODE = 1;', '{$ENDIF}',
  '{$IFDEF CONDITIONALEXPRESSIONS}', 'const K_CONDEXPR = 1;', '{$ENDIF}',
  '{$IF CompilerVersion = 13}', 'const K_CV13 = 1;', '{$IFEND}',
  '', 'implementation', '', 'end.')
$dpr = Join-Path $src 'D5App.dpr'
WriteLines $dpr @('program D5App;', '', 'uses', "  UD5 in 'UD5.pas';", '', 'begin', 'end.')
$dprSib = Join-Path $sib 'Modern.dpr'
WriteLines $dprSib @('program Modern;', '', 'begin', 'end.')
WriteLines (Join-Path $sib 'Modern.dproj') @('<Project><PropertyGroup><ProjectVersion>20.4</ProjectVersion></PropertyGroup></Project>')

$r = Exec @('rules', '--json', '--target-compiler', 'auto', '--project', $dpr)
$got = if ($r.Code -eq 0) { [string](($r.Out | ConvertFrom-Json).target_compiler) } else { "exit$($r.Code)" }
Check 'auto on a .dpr with no .dproj assumes 13' ($got -eq '13') "got $got; $($r.Err.Trim())"
Check 'auto on a .dpr: the assumption is noted on stderr, once' (([regex]::Matches($r.Err, 'assuming Delphi 5')).Count -eq 1) $r.Err.Trim()
$r = Exec @('rules', '--json', '--target-compiler', 'auto', '--project', $dprSib)
$got = if ($r.Code -eq 0) { [string](($r.Out | ConvertFrom-Json).target_compiler) } else { "exit$($r.Code)" }
Check 'CONTROL auto on a .dpr with a sibling .dproj reads its ProjectVersion' ($got -eq '37') "got $got"
Check 'CONTROL ... and notes no assumption' ($r.Err -notmatch 'assuming') $r.Err.Trim()
$r = Exec @('rules', '--json', '--target-compiler', 'auto')
Check 'CONTROL auto with no project still refuses, naming the D5 way out' (($r.Code -eq 2) -and ($r.Err -match 'needs the owning') -and ($r.Err -match 'target-compiler 5')) "exit $($r.Code): $($r.Err.Trim())"

# ---- the preprocessor ---------------------------------------------------------------
# sql --json rows are POSITIONAL arrays.
function Names([string]$Db) {
  $r = Exec @('sql', '--db', $Db, '--query', "SELECT name FROM symbols WHERE kind = 'const'", '--json')
  return ,@((($r.Out | ConvertFrom-Json).rows) | ForEach-Object { [string]$_[0] })
}
$db5 = Join-Path $WorkDir 'd5.sqlite'
$r = Exec @('index', '--project', $dpr, '--db', $db5, '--target-compiler', '5', '--library-db', 'none')
Check 'index --target-compiler 5: exit 0' ($r.Code -eq 0) "exit $($r.Code): $($r.Err.Trim())"
$n = Names $db5
Write-Host ("  D5 consts: {0}" -f ($n -join ','))
foreach ($k in @('K_VER130', 'K_WIN32', 'K_CV13')) { Check "D5 defines: $k active" ($n -contains $k) ($n -join ',') }
foreach ($k in @('K_VER370', 'K_WIN64', 'K_MSWINDOWS', 'K_UNICODE', 'K_CONDEXPR')) { Check "D5 defines: $k inactive" ($n -notcontains $k) ($n -join ',') }

$db5p = Join-Path $WorkDir 'd5p.sqlite'
$r = Exec @('index', '--project', $dpr, '--db', $db5p, '--target-compiler', 'VER130', '--platform', 'Win64', '--library-db', 'none')
$n = Names $db5p
Check 'VER130 with --platform Win64: D5 has no Win64, still WIN32' (($n -contains 'K_WIN32') -and ($n -notcontains 'K_WIN64')) ($n -join ',')

$dbAuto = Join-Path $WorkDir 'auto.sqlite'
$r = Exec @('index', '--project', $dpr, '--db', $dbAuto, '--target-compiler', 'auto', '--library-db', 'none')
$n = Names $dbAuto
Check 'index auto on the .dpr: exit 0 and preprocessed as D5' (($r.Code -eq 0) -and ($n -contains 'K_VER130')) "exit $($r.Code); $($n -join ',')"

# CONTROLS: the default and a modern old target are untouched.
$db37 = Join-Path $WorkDir 'd37.sqlite'
$r = Exec @('index', '--project', $dpr, '--db', $db37, '--target-compiler', '13', '--library-db', 'none')
$n = Names $db37
Check 'CONTROL target 13 = Delphi 13: VER370 + UNICODE + WIN64 + CONDEXPR' (($n -contains 'K_VER370') -and ($n -contains 'K_UNICODE') -and ($n -contains 'K_WIN64') -and ($n -contains 'K_CONDEXPR') -and ($n -notcontains 'K_VER130')) ($n -join ',')
$db14 = Join-Path $WorkDir 'd14.sqlite'
$r = Exec @('index', '--project', $dpr, '--db', $db14, '--target-compiler', '6', '--library-db', 'none')
$n = Names $db14
Check 'CONTROL target 6 (14): the set above 13 did not move' (($n -contains 'K_WIN64') -and ($n -contains 'K_CONDEXPR')) ($n -join ',')

# ---- lint under D5: the display name and the gate -----------------------------------
$r = Exec @('lint', (Join-Path $src 'UD5.pas'), '--db', $db5, '--target-compiler', '5', '--library-db', 'none')
Check 'lint status line says Delphi 5' ($r.Err -match 'target-compiler: 13 \(Delphi 5\)') $r.Err.Trim()

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_target_compiler_d5: FAIL' -ForegroundColor Red; exit 1 }
Write-Host "run_target_compiler_d5: PASS ($script:Passed)" -ForegroundColor Green
exit 0
