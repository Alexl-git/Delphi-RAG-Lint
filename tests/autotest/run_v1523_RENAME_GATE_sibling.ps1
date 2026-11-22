<#
  run_v1523_RENAME_GATE_sibling.ps1 -- B24 (1.52.3): `rename --apply` in a unit a SIBLING project also compiles builds
  that sibling even when its index was never built. The manifest names the sibling; its DB file does not exist
  (Ruling 14: not an owner, never proved), but its compile closure holds the unit, so the gate builds it before and
  after the write. A rename that breaks the sibling is refused and rolled back.

  FIXTURE (real msbuild, under %TEMP%, engine COPY with its own manifest, no real DB is read):
    shared\uShared.pas  TShared.Compute
    A\A.dproj           uShared + uA (calls Compute) + uOnlyA; A.sqlite built
    B\B.dproj           uShared + uB; the manifest names B.sqlite, which is NEVER built
  CASES
    g1  uB calls Compute; --project A: A builds after the rename, B does not (uB was never renamed).
        Refused [compile-error] naming B.dproj, sources byte-identical, exit 1.
    g2  uB does not call Compute: renamed, exit 0, the gate names B.dproj (2 projects), a note says B has no index.
    g3  --plan on g1's lab (run before g1's apply): the `also:` line names B, nothing written.
    g4  POSITIVE CONTROL: uOnlyA.OnlyA (B's closure does not hold uOnlyA): renamed, exit 0, one project, B not named.
  RED on 1.52.2-alpha: g1 writes (exit 0, B left broken), g2 and g3 never name B.
  Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$EngineDir = '',
  [string]$RsVars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block.
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
$work = Join-Path $env:TEMP ('draglint-rengate-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
Copy-Item (Join-Path $Repo 'rules') "$eng\rules" -Recurse
$Exe = Join-Path $eng 'drag-lint.exe'
function Run([string[]]$EngArgs) {
  Push-Location $work
  try { $o = ($null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe @EngArgs 2>&1 | ForEach-Object { "$_" } } | Out-String); $script:LastExit = $LASTEXITCODE } finally { Pop-Location }
  return $o
}
$libDir = Join-Path $work 'libsrc'; New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item (Join-Path $Repo 'tests\fixtures\refactor\rename\libstub\LibStub.pas') $libDir
$Lib = Join-Path $work 'lib.sqlite'
$null = Run @('index', $libDir, '--db', $Lib, '--library-db', 'none')
$DprojTemplate = Txt (Join-Path $Repo 'tests\fixtures\refactor\rename\PrecRen.dproj')

function Write-Project([string]$Dir, [string]$P, [string]$Guid) {
  $x = $DprojTemplate -replace 'PrecRen', $P -replace '\{6A1F3C52-91B7-4D3E-8E20-5C7A2B9D1E44\}', "{$Guid}"
  $x = $x -replace '(?m)^\s*<DCCReference Include="RnTypes\.pas"/>\r?\n', '' -replace '(?m)^\s*<DCCReference Include="RnUse\.pas"/>\r?\n', ''
  $x = $x -replace '<DelphiCompile ', "<DCCReference Include=`"..\shared\uShared.pas`"/>`r`n        <DCCReference Include=`"u$P.pas`"/>`r`n        <DelphiCompile "
  [IO.File]::WriteAllText("$Dir\$P.dproj", $x, [Text.Encoding]::ASCII)
  WriteAscii "$Dir\$P.dpr" @("program $P;", '', '{$APPTYPE CONSOLE}', '', 'uses', "  uShared in '..\shared\uShared.pas',", "  u$P in 'u$P.pas';", '', 'begin', "  Writeln(u$P.Get);", 'end.')
}
function UnitUser([string]$Name, [string[]]$Body) {
  return @("unit $Name;", '', 'interface', '', 'function Get: Integer;', '', 'implementation', '', 'uses', '  uShared;', '', 'function Get: Integer;', 'var', '  S: TShared;', 'begin', '  S:= TShared.Create;') + $Body + @('  S.Free;', 'end;', '', 'end.')
}
# Fresh lab: A indexed, B configured in the manifest but its DB never built.
function New-Lab([string]$Name, [string[]]$BBody = @('  Result:= S.Compute;')) {
  $root = Join-Path $work $Name
  New-Item -ItemType Directory -Force "$root\shared", "$root\A", "$root\B" | Out-Null
  WriteAscii "$root\shared\uShared.pas" @('unit uShared;', '', 'interface', '', 'type', '  TShared = class', '  public', '    function Compute: Integer;', '  end;', '', 'implementation', '', 'function TShared.Compute: Integer;', 'begin', '  Result:= 42;', 'end;', '', 'end.')
  WriteAscii "$root\A\uA.pas" (UnitUser 'uA' @('  Result:= S.Compute + OnlyA;'))
  [IO.File]::WriteAllText("$root\A\uA.pas", ((Txt "$root\A\uA.pas") -replace 'uses\r\n  uShared;', "uses`r`n  uShared, uOnlyA;"), [Text.Encoding]::ASCII)
  WriteAscii "$root\A\uOnlyA.pas" @('unit uOnlyA;', '', 'interface', '', 'function OnlyA: Integer;', '', 'implementation', '', 'function OnlyA: Integer;', 'begin', '  Result:= 0;', 'end;', '', 'end.')
  WriteAscii "$root\B\uB.pas" (UnitUser 'uB' $BBody)
  Write-Project "$root\A" 'A' 'A1A1A1A1-0000-4000-8000-000000000001'
  Write-Project "$root\B" 'B' 'B2B2B2B2-0000-4000-8000-000000000002'
  $j = $root -replace '\\', '\\'
  $secs = @(
    "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dproj`"], `"db`": `"$j\\A.sqlite`" }",
    "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dproj`"], `"db`": `"$j\\B.sqlite`" }")
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [', ($secs -join ",`r`n"), ']}}')
  $null = Run @('index', '--project', "$root\A\A.dproj", '--db', "$root\A.sqlite", '--library-db', 'none')
  return $root
}
function Sources([string]$Root) { (Txt "$Root\shared\uShared.pas") + (Txt "$Root\A\uA.pas") + (Txt "$Root\B\uB.pas") + (Txt "$Root\A\uOnlyA.pas") }
function Apply([string]$Root, [string]$QName = 'uShared.TShared.Compute', [string]$To = 'Tally') {
  return Run @('rename', '--kind', 'symbol', '--name', $QName, '--to', $To, '--db', "$Root\A.sqlite", '--library-db', $Lib, '--project', "$Root\A\A.dproj", '--build-timeout', '600', '--apply', '--no-backup')
}

try {
  Write-Host '== B24: the compile gate builds a sibling project whose index was never built ==' -ForegroundColor Cyan
  $p = New-Lab 'g1'
  Check 'g1 setup: B.sqlite does not exist' (-not (Test-Path "$p\B.sqlite"))
  $h = Sources $p
  $pl = Run @('rename', '--kind', 'symbol', '--name', 'uShared.TShared.Compute', '--to', 'Tally', '--db', "$p\A.sqlite", '--library-db', $Lib, '--project', "$p\A\A.dproj", '--plan')
  Check 'g3 --plan: exit 0, the also: line names B, nothing written' ($script:LastExit -eq 0 -and $pl -match 'also: .*B\.dproj' -and (Sources $p) -ceq $h) $pl
  $o = Apply $p
  Check 'g1 B breaks after, A alone passes: [compile-error] naming B, exit 1' ($script:LastExit -eq 1 -and $o -match 'refused \[compile-error\]' -and $o -match 'B\.dproj') $o
  Check 'g1 rolled back: sources byte-identical' ((Sources $p) -ceq $h) (Txt "$p\shared\uShared.pas")


  $p = New-Lab 'g2' -BBody @('  Result:= 7;')
  $o = Apply $p
  Check 'g2 apply: exit 0' ($script:LastExit -eq 0) $o
  Check 'g2 renamed in uShared and uA' ((Txt "$p\shared\uShared.pas") -cmatch 'TShared\.Tally' -and (Txt "$p\A\uA.pas") -cmatch 'S\.Tally') (Txt "$p\A\uA.pas")
  Check 'g2 the gate built both projects, naming B' ($o -match '2 project\(s\)' -and $o -match 'B\.dproj') $o
  Check 'g2 a note says B has no index' ($o -match 'note: .*B.*no index') $o

  $p = New-Lab 'g4'
  $o = Apply $p 'uOnlyA.OnlyA' 'SoleA'
  Check 'g4 control: a unit only A compiles: renamed, exit 0, one project, B not named' ($script:LastExit -eq 0 -and $o -match 'compile gate' -and $o -notmatch 'project\(s\)' -and $o -notmatch 'B\.dproj' -and (Txt "$p\A\uOnlyA.pas") -cmatch 'SoleA') $o
} finally {
  Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: $work not deleted" }
}
if ($script:Failed) { exit 1 } else { exit 0 }
