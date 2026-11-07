<#
  run_rename_multiproject_gate.ps1 -- E-RENAME-MULTIPROJECT: `rename --apply` in a unit other projects also compile proves the
  rename in EVERY owner's index, merges the edits and builds EVERY owner before and after the write.

  FIXTURE (real msbuild, under %TEMP%, engine COPY with its own manifest, no real DB is read):
    shared\uShared.pas  TShared.Compute
    A\A.dproj           uShared + uA, which calls Compute
    B\B.dproj           uShared + uB, which calls Compute
  CASES
    c1  --project A: uB (which A's index never saw) is renamed too; A and B both build; two projects named.
    c2  B does not build before: [dirty-baseline] naming B, nothing written.
    c3  uB reads Compute through a {$I} text the index cannot see: the proof passes, B's after build fails: [compile-error]
        naming B, rolled back. This is the case only the second gate catches: A builds clean on its own.
    c4  uB has the name in an inactive branch: [no-ref-occurrence] naming B, nothing written.
    c5  --plan names both projects and refusals of B without writing.
    c6  POSITIVE CONTROL: a unit only A owns: one project, as before.
    c7  a library owner refuses, by name.
  RED on 1.44.1: c1-c5 write or say nothing about B. Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$EngineDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug",
  [string]$RsVars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
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
$work = Join-Path $env:TEMP ('draglint-renmp-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
Copy-Item (Join-Path $Repo 'rules') "$eng\rules" -Recurse
$Exe = Join-Path $eng 'drag-lint.exe'
function Run([string[]]$EngArgs) {
  Push-Location $work
  try { $o = ($null | & $Exe @EngArgs 2>&1 | Out-String); $script:LastExit = $LASTEXITCODE } finally { Pop-Location }
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
function UnitUser([string]$Name, [string[]]$Body, [string[]]$ExtraUses = @()) {
  $uses = (@('uShared') + $ExtraUses) -join ', '
  return @("unit $Name;", '', 'interface', '', 'function Get: Integer;', '', 'implementation', '', 'uses', "  $uses;", '', 'function Get: Integer;', 'var', '  S: TShared;', 'begin', '  S:= TShared.Create;') + $Body + @('  S.Free;', 'end;', '', 'end.')
}
# Fresh lab; $BBody changes uB. $Library adds a registry section whose DB holds the shared folder.
function New-Lab([string]$Name, [string[]]$BBody = @('  Result:= S.Compute;'), [switch]$Library, [switch]$BBroken) {
  $root = Join-Path $work $Name
  New-Item -ItemType Directory -Force "$root\shared", "$root\A", "$root\B" | Out-Null
  WriteAscii "$root\shared\uShared.pas" @('unit uShared;', '', 'interface', '', 'type', '  TShared = class', '  public', '    function Compute: Integer;', '  end;', '', 'implementation', '', 'function TShared.Compute: Integer;', 'begin', '  Result:= 42;', 'end;', '', 'end.')
  WriteAscii "$root\A\uA.pas" (UnitUser 'uA' @('  Result:= S.Compute;'))
  WriteAscii "$root\A\uOnlyA.pas" @('unit uOnlyA;', '', 'interface', '', 'function OnlyA: Integer;', '', 'implementation', '', 'function OnlyA: Integer;', 'begin', '  Result:= 1;', 'end;', '', 'end.')
  WriteAscii "$root\B\uB.pas" (UnitUser 'uB' $BBody)
  Write-Project "$root\A" 'A' 'A1A1A1A1-0000-4000-8000-000000000001'
  Write-Project "$root\B" 'B' 'B2B2B2B2-0000-4000-8000-000000000002'
  # uOnlyA belongs to A alone: the single-owner control.
  [IO.File]::WriteAllText("$root\A\uA.pas", ((Txt "$root\A\uA.pas") -replace 'uses\r\n  uShared;', "uses`r`n  uShared, uOnlyA;"), [Text.Encoding]::ASCII)
  $j = $root -replace '\\', '\\'
  $secs = @(
    "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dproj`"], `"db`": `"$j\\A.sqlite`" }",
    "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dproj`"], `"db`": `"$j\\B.sqlite`" }")
  if ($Library) { $secs += "  { `"name`": `"LIB`", `"source`": `"registry-libraries`", `"platforms`": [`"Win32`", `"Win64`"], `"db`": `"$j\\LIB.sqlite`" }" }
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [', ($secs -join ",`r`n"), ']}}')
  foreach ($p in 'A', 'B') { $null = Run @('index', '--project', "$root\$p\$p.dproj", '--db', "$root\$p.sqlite", '--library-db', 'none') }
  if ($Library) { $null = Run @('index', "$root\shared", '--db', "$root\LIB.sqlite", '--library-db', 'none') }
  if ($BBroken) { [IO.File]::WriteAllText("$root\B\B.dpr", "this line does not compile`r`n" + (Txt "$root\B\B.dpr"), [Text.Encoding]::ASCII) }  # at the top: dcc reads nothing after the final end
  return $root
}
function Sources([string]$Root) { (Txt "$Root\shared\uShared.pas") + (Txt "$Root\A\uA.pas") + (Txt "$Root\B\uB.pas") }
function Apply([string]$Root, [string]$QName = 'uShared.TShared.Compute', [string]$To = 'Tally') {
  return Run @('rename', '--kind', 'symbol', '--name', $QName, '--to', $To, '--db', "$Root\A.sqlite", '--library-db', $Lib, '--project', "$Root\A\A.dproj", '--build-timeout', '600', '--apply', '--no-backup')
}

try {
  Write-Host '== E-RENAME-MULTIPROJECT: every owning project is proved and built ==' -ForegroundColor Cyan
  $p = New-Lab 'c1'
  $o = Apply $p
  Check 'c1 apply: exit 0' ($script:LastExit -eq 0) $o
  Check 'c1 the unit, A''s caller AND B''s caller are renamed' ((Txt "$p\shared\uShared.pas") -cmatch 'TShared\.Tally' -and (Txt "$p\A\uA.pas") -cmatch 'S\.Tally' -and (Txt "$p\B\uB.pas") -cmatch 'S\.Tally') (Txt "$p\B\uB.pas")
  Check 'c1 the gate says it built both projects' ($o -match '2 project\(s\)' -and $o -match 'B\.dproj') $o
  $exeB = Get-ChildItem "$p\B" -Recurse -Filter B.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Check 'c1 B''s binary, rebuilt after the rename, still prints 42' ($exeB -and ((& $exeB.FullName | Out-String).Trim() -eq '42'))

  $p = New-Lab 'c2' -BBroken
  $h = Sources $p
  $o = Apply $p
  Check 'c2 B dirty before: [dirty-baseline] naming B, exit 1' ($script:LastExit -eq 1 -and $o -match 'refused \[dirty-baseline\]' -and $o -match 'B\.dproj') $o
  Check 'c2 nothing written' ((Sources $p) -ceq $h)

  $p = New-Lab 'c3' -BBody @('  {$I refs.txt}')
  WriteAscii "$p\B\refs.txt" @('  Result:= S.Compute;')
  $null = Run @('index', '--project', "$p\B\B.dproj", '--db', "$p\B.sqlite", '--library-db', 'none')
  $h = Sources $p
  $o = Apply $p
  Check 'c3 B fails after, A alone would pass: [compile-error] naming B, exit 1' ($script:LastExit -eq 1 -and $o -match 'refused \[compile-error\]' -and $o -match 'B\.dproj') $o
  Check 'c3 rolled back: sources byte-identical' ((Sources $p) -ceq $h)

  $p = New-Lab 'c4' -BBody @('  {$IFDEF NEVER_DEFINED}', '  Result:= S.Compute + 1;', '  {$ELSE}', '  Result:= S.Compute;', '  {$ENDIF}')
  $h = Sources $p
  $o = Apply $p
  Check 'c4 B''s inactive branch: exit 2, [no-ref-occurrence] in uB.pas' ($script:LastExit -eq 2 -and $o -match 'uB\.pas' -and $o -match 'no-ref-occurrence') $o
  Check 'c4 nothing written' ((Sources $p) -ceq $h)

  $h = Sources $p
  $pl = Run @('rename', '--kind', 'symbol', '--name', 'uShared.TShared.Compute', '--to', 'Tally', '--db', "$p\A.sqlite", '--library-db', $Lib, '--plan')
  Check 'c5 --plan: exit 0, names project B and B''s refusal, writes nothing' ($script:LastExit -eq 0 -and $pl -match 'also: .*B' -and $pl -match 'no-ref-occurrence' -and (Sources $p) -ceq $h) $pl

  $p = New-Lab 'c6'
  $o = Run @('rename', '--kind', 'symbol', '--name', 'uOnlyA.OnlyA', '--to', 'SoleA', '--db', "$p\A.sqlite", '--library-db', $Lib, '--project', "$p\A\A.dproj", '--build-timeout', '600', '--apply', '--no-backup')
  Check 'c6 control: a unit only A owns: renamed, exit 0, one project' ($script:LastExit -eq 0 -and $o -match 'compile gate' -and $o -notmatch 'project\(s\)' -and (Txt "$p\A\uOnlyA.pas") -cmatch 'SoleA') $o

  $p = New-Lab 'c7' -Library
  $h = Sources $p
  $o = Apply $p
  Check 'c7 a library owner refuses by name, exit 2, nothing written' ($script:LastExit -eq 2 -and $o -match 'owner-library' -and $o -match 'LIB' -and (Sources $p) -ceq $h) $o
} finally {
  Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: $work not deleted" }
}
if ($script:Failed) { exit 1 } else { exit 0 }
