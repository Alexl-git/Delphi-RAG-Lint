<#
  run_v1511_RENAME_b23_gate.ps1 -- B23 (1.51.1 SCOPE, fixed in 1.46 by cded68332): `rename --kind param --apply` on a
  method whose name another class's method shares edits only ITS OWN declaration, header and body, and the compile gate
  builds the result clean (no E2037 "declaration differs from previous declaration").

  FIXTURE (real msbuild, under %TEMP%): uSame.pas with TA.Go(pX) and TB.Go(pX), declared and implemented; Same.dproj.
  CASES
    s1  rename TA.Go's pX -> pY through the gate: exit 0, TA's declaration + header + body renamed.
    s2  TB.Go keeps pX in its declaration and its header (the old bug renamed it too).
    s3  the gate built it: no E2037 in the output, the exe prints 3.
  REGRESSION GUARD: green on 1.51.0-alpha too (the fix predates this run); RED on 1.44.1 per cded68332.
  Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$EngineDir = '',
  [string]$RsVars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $EngineDir) { $EngineDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }; $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $Name) -ForegroundColor $c
  if ($Ok) { $script:Passed++ } else { $script:FailCount++; if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
function WriteAscii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function Txt([string]$Path) { [IO.File]::ReadAllText($Path) }

$EngineDir = (Resolve-Path $EngineDir).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$work = Join-Path $env:TEMP ('draglint-v1511-b23-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng, "$work\p" | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'sqlite3.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
Copy-Item (Join-Path $Repo 'rules') "$eng\rules" -Recurse
WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [] } }')
$Exe = Join-Path $eng 'drag-lint.exe'
function Run([string[]]$EngArgs) {
  Push-Location $work
  try { $o = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe @EngArgs 2>&1 | ForEach-Object { "$_" } } | Out-String); $script:LastExit = $LASTEXITCODE } finally { Pop-Location }
  return $o
}
$x = Txt (Join-Path $Repo 'tests\fixtures\refactor\rename\PrecRen.dproj')
$x = $x -replace 'PrecRen', 'Same' -replace '\{6A1F3C52-91B7-4D3E-8E20-5C7A2B9D1E44\}', '{C3C3C3C3-0000-4000-8000-000000000023}'
$x = $x -replace '(?m)^\s*<DCCReference Include="RnTypes\.pas"/>\r?\n', '' -replace '(?m)^\s*<DCCReference Include="RnUse\.pas"/>\r?\n', ''
$x = $x -replace '<DelphiCompile ', "<DCCReference Include=`"uSame.pas`"/>`r`n        <DelphiCompile "
[IO.File]::WriteAllText("$work\p\Same.dproj", $x, [Text.Encoding]::ASCII)
WriteAscii "$work\p\Same.dpr" @('program Same;', '', '{$APPTYPE CONSOLE}', '', 'uses', "  uSame in 'uSame.pas';", '', 'begin', '  Writeln(Run);', 'end.')
WriteAscii "$work\p\uSame.pas" @('unit uSame;', '', 'interface', '', 'type', '  TA = class', '  public', '    function Go(pX: Integer): Integer;', '  end;',
  '  TB = class', '  public', '    function Go(pX: Integer): Integer;', '  end;', '', 'function Run: Integer;', '', 'implementation', '',
  'function TA.Go(pX: Integer): Integer;', 'begin', '  Result:= pX + 1;', 'end;', '',
  'function TB.Go(pX: Integer): Integer;', 'begin', '  Result:= pX * 2;', 'end;', '',
  'function Run: Integer;', 'var', '  A: TA;', '  B: TB;', 'begin', '  A:= TA.Create;', '  B:= TB.Create;', '  Result:= A.Go(0) + B.Go(1);', '  A.Free;', '  B.Free;', 'end;', '', 'end.')
$Db = "$work\p\Same.sqlite"
try {
  Write-Host '== B23: --kind param renames the one header the method implements, and it compiles ==' -ForegroundColor Cyan
  $null = Run @('index', '--project', "$work\p\Same.dproj", '--db', $Db, '--library-db', 'none')
  $hdr = 0; $i = 0; foreach ($l in [IO.File]::ReadAllLines("$work\p\uSame.pas")) { $i++; if ($l -eq 'function TA.Go(pX: Integer): Integer;') { $hdr = $i } }
  $o = Run @('rename', '--kind', 'param', '--in', "$work\p\uSame.pas", '--line', "$hdr", '--col', '16', '--to', 'pY', '--db', $Db,
             '--project', "$work\p\Same.dproj", '--build-timeout', '600', '--apply', '--no-backup')
  $t = Txt "$work\p\uSame.pas"
  Check 's1 apply through the gate: exit 0; TA declaration, header and body renamed' ($script:LastExit -eq 0 -and $t.Contains('    function Go(pY: Integer): Integer;') -and $t.Contains('function TA.Go(pY: Integer): Integer;') -and $t.Contains('Result:= pY + 1;')) $o
  Check 's2 TB.Go keeps pX in its declaration and header' ($t.Contains('function TB.Go(pX: Integer): Integer;') -and $t.Contains('Result:= pX * 2;') -and ([regex]::Matches($t, 'function Go\(pX: Integer\)')).Count -eq 1) $t
  $exe = Get-ChildItem "$work\p" -Recurse -Filter Same.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Check 's3 no E2037; the gate built it and the exe prints 3' ($o -notmatch 'E2037' -and $o -match 'compile gate' -and $exe -and ((& $exe.FullName | Out-String).Trim() -eq '3')) $o
} finally {
  Write-Host ("run_v1511_RENAME_b23_gate: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: $work not deleted" }
}
if ($script:Failed) { exit 1 } else { exit 0 }