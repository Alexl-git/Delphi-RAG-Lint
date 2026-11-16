<#
  run_v1511_RENAME_t09_gate.ps1 -- T09 (1.51.1): a `lint --fix --apply` naming rename in a unit SEVERAL projects compile
  is built in EVERY one of them, and an IDE-style call with only --db (a DB at <project>\_D-RAG\<base>.sqlite) is gated
  by that project, as `rename --apply` already is.

  FIXTURE (real msbuild, under %TEMP%, engine COPY with its own manifest; no real DB is read or written):
    shared\uShared.pas  const My_Const (a const-casing finding -> MyConst)
    A\A.dproj           uShared + uOnlyA + uA (reads My_Const, Only_Const)
    B\B.dproj           uShared + uB (reads My_Const)
    DBs at A\_D-RAG\A.sqlite and B\_D-RAG\B.sqlite; the manifest names both.
  CASES
    t1  uB reads My_Const through a {$I} text the index cannot see; --project A: A builds after the rename, B does not.
        The gate must build B: refused [compile-error] naming B.dproj, sources byte-identical, exit 1.
    t2  plain: the rename lands in uShared, uA AND uB; the gate built B too (its name is in the output); B's exe runs.
    t3  as t1 with NO --project: the DB's own project (A\A.dproj) gates the write -- refused naming B, nothing written.
    t4  POSITIVE CONTROL: Only_Const in uOnlyA (only A compiles it): renamed, exit 0, B is not built.
  RED on 1.51.0-alpha: t1 and t3 write (B left broken), t2 never names B.
  Needs RAD Studio; SKIPs (exit 0) without it.
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
$work = Join-Path $env:TEMP ('draglint-v1511-t09-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'sqlite3.dll', 'casts.castlib') {
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
WriteAscii "$work\drag-lint-lint.json" @('{ "autofix": ["const-casing"] }')

function Write-Project([string]$Dir, [string]$P, [string]$Guid, [string[]]$Units) {
  $x = $DprojTemplate -replace 'PrecRen', $P -replace '\{6A1F3C52-91B7-4D3E-8E20-5C7A2B9D1E44\}', "{$Guid}"
  $x = $x -replace '(?m)^\s*<DCCReference Include="RnTypes\.pas"/>\r?\n', '' -replace '(?m)^\s*<DCCReference Include="RnUse\.pas"/>\r?\n', ''
  $refs = (@('..\shared\uShared.pas') + ($Units | ForEach-Object { "$_.pas" }) | ForEach-Object { "<DCCReference Include=`"$_`"/>" }) -join "`r`n        "
  $x = $x -replace '<DelphiCompile ', "$refs`r`n        <DelphiCompile "
  [IO.File]::WriteAllText("$Dir\$P.dproj", $x, [Text.Encoding]::ASCII)
  $uses = @("  uShared in '..\shared\uShared.pas'") + ($Units | ForEach-Object { "  $_ in '$_.pas'" })
  WriteAscii "$Dir\$P.dpr" (@("program $P;", '', '{$APPTYPE CONSOLE}', '', 'uses', (($uses -join ",`r`n") + ';'), '', 'begin', "  Writeln(u$P.Get);", 'end.'))
}
function UnitUser([string]$Name, [string[]]$Body, [string[]]$Uses = @('uShared')) {
  return @("unit $Name;", '', 'interface', '', 'function Get: Integer;', '', 'implementation', '', 'uses', ('  ' + ($Uses -join ', ') + ';'), '', 'function Get: Integer;', 'begin') + $Body + @('end;', '', 'end.')
}
function New-Lab([string]$Name, [string[]]$BBody = @('  Result:= My_Const;')) {
  $root = Join-Path $work $Name
  New-Item -ItemType Directory -Force "$root\shared", "$root\A\_D-RAG", "$root\B\_D-RAG" | Out-Null
  WriteAscii "$root\shared\uShared.pas" @('unit uShared;', '', 'interface', '', 'const', '  My_Const = 42;', '', 'implementation', '', 'end.')
  WriteAscii "$root\A\uOnlyA.pas" @('unit uOnlyA;', '', 'interface', '', 'const', '  Only_Const = 1;', '', 'implementation', '', 'end.')
  WriteAscii "$root\A\uA.pas" (UnitUser 'uA' @('  Result:= My_Const + Only_Const;') @('uShared', 'uOnlyA'))
  WriteAscii "$root\B\uB.pas" (UnitUser 'uB' $BBody)
  Write-Project "$root\A" 'A' 'A1A1A1A1-0000-4000-8000-000000000011' @('uOnlyA', 'uA')
  Write-Project "$root\B" 'B' 'B2B2B2B2-0000-4000-8000-000000000012' @('uB')
  $j = $root -replace '\\', '\\'
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [',
    "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dproj`"], `"db`": `"$j\\A\\_D-RAG\\A.sqlite`" },",
    "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dproj`"], `"db`": `"$j\\B\\_D-RAG\\B.sqlite`" }",
    ']}}')
  foreach ($p in 'A', 'B') { $null = Run @('index', '--project', "$root\$p\$p.dproj", '--db', "$root\$p\_D-RAG\$p.sqlite", '--library-db', 'none') }
  return $root
}
function Sources([string]$Root) { (Txt "$Root\shared\uShared.pas") + (Txt "$Root\A\uA.pas") + (Txt "$Root\A\uOnlyA.pas") + (Txt "$Root\B\uB.pas") }
function Fix([string]$Root, [string]$File, [int]$Line, [switch]$NoProject) {
  $a = @('lint', '--file', $File, '--db', "$Root\A\_D-RAG\A.sqlite", '--library-db', $Lib, '--fix', '--fix-line', "$Line",
         '--fix-rule', 'const-casing', '--apply', '--no-backup', '--build-timeout', '600')
  if (-not $NoProject) { $a += @('--project', "$Root\A\A.dproj") }
  return Run $a
}
function HiddenB { return @('  {$I refs.txt}') }

try {
  Write-Host '== T09: a naming fix in a shared unit builds every project that compiles it ==' -ForegroundColor Cyan
  $p = New-Lab 't1' -BBody (HiddenB)
  WriteAscii "$p\B\refs.txt" @('  Result:= My_Const;')
  $h = Sources $p
  $o = Fix $p "$p\shared\uShared.pas" 6
  Check 't1 B breaks after, A alone would pass: refused [compile-error] naming B.dproj, exit 1' ($script:LastExit -eq 1 -and $o -match 'compile-error' -and $o -match 'B\.dproj') $o
  Check 't1 rolled back: sources byte-identical' ((Sources $p) -ceq $h)

  $p = New-Lab 't2'
  $o = Fix $p "$p\shared\uShared.pas" 6
  Check 't2 apply: exit 0' ($script:LastExit -eq 0) $o
  Check 't2 uShared, uA AND uB read MyConst' ((Txt "$p\shared\uShared.pas") -cmatch 'MyConst = 42' -and (Txt "$p\A\uA.pas") -cmatch 'MyConst \+' -and (Txt "$p\B\uB.pas") -cmatch 'Result:= MyConst;') (Sources $p)
  Check 't2 the gate built B too (B.dproj named)' ($o -match 'B\.dproj') $o
  $exeB = Get-ChildItem "$p\B" -Recurse -Filter B.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Check 't2 B''s binary, rebuilt after the rename, prints 42' ($exeB -and ((& $exeB.FullName | Out-String).Trim() -eq '42'))

  $p = New-Lab 't3' -BBody (HiddenB)
  WriteAscii "$p\B\refs.txt" @('  Result:= My_Const;')
  $h = Sources $p
  $o = Fix $p "$p\shared\uShared.pas" 6 -NoProject
  Check 't3 no --project: the DB''s project gates it -- refused naming B.dproj, exit 1' ($script:LastExit -eq 1 -and $o -match 'compile-error' -and $o -match 'B\.dproj') $o
  Check 't3 nothing written' ((Sources $p) -ceq $h)

  $p = New-Lab 't4'
  $o = Fix $p "$p\A\uOnlyA.pas" 6
  Check 't4 POSITIVE CONTROL: a unit only A compiles: renamed, exit 0, B not built' ($script:LastExit -eq 0 -and (Txt "$p\A\uOnlyA.pas") -cmatch 'OnlyConst = 1' -and $o -notmatch 'B\.dproj') $o
} finally {
  Write-Host ("run_v1511_RENAME_t09_gate: {0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: $work not deleted" }
}
if ($script:Failed) { exit 1 } else { exit 0 }
