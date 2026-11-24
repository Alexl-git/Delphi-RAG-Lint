<#
  run_v1531_AUTODOCFIX.ps1 -- the review of lane v153 AUTODOC (HIGH-1, M1-M3, M5, M6, the LOW items).

    STAMP   HIGH-1: a one-file index into a stamped DB never commits a DB-level fingerprint the other
            files were not parsed under. (Before: `document` after a define change stamped the whole
            project, and the next `index --project` skipped every stale file.)
    BUILD   M1: the one-file index takes platform, config and preprocess from the DB's stored
            fingerprint, so plain `index <file> --db <project DB>` and a doc verb's rescan keep it,
            also on a DB copy outside _D-RAG; when the build cannot be reproduced it refuses (exit 2)
            and names `index --project`. Control: a folder DB still takes one file.
    CTX     M2: the file is parsed with the project's include search path and used-unit constants.
    OPEN    `document --apply` refuses an index no run finished (no fingerprint / no resolver stamp);
            a dry run warns.
    TRIPLE  M3: a multi-line (triple-quote) string is one string: a comment opener inside it opens nothing.
    SLASH   M5: a slashes-only <summary> written by 1.53 is dropped; a human one holding slashes stays.
    GUARD   M6: the doc-damage guard catches a deleted banner line.
    GAP     doc + banner + blank + declaration is one doc block, rewritten in place.
    TAMPER  comments between an attribute and its heading are neither the heading nor tampering.
    STRIP   --strip --qname takes only the declaration's own block, never one above a banner.
  Needs python (sqlite3) for the stamp edits. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v1531-autodocfix-$PID")
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Total = 0
function Check($n, $ok, $d = '') {
  $script:Total++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Run([string[]]$A) {
  $r = & { $ErrorActionPreference = 'Continue'; (& $Exe @A 2>&1 | ForEach-Object { "$_" }) -join "`n" }
  $script:Code = $LASTEXITCODE
  return $r
}
function Text([string]$Path) { return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n") }
function Meta([string]$Db, [string]$Key) { & python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); r=c.execute('select value from schema_meta where key=?',(sys.argv[2],)).fetchone(); print(r[0] if r else '')" $Db $Key }
function Set-Meta([string]$Db, [string]$Key, [string]$Value) { & python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('insert or replace into schema_meta(key,value) values(?,?)',(sys.argv[2],'' if sys.argv[3]=='-' else sys.argv[3])); c.commit()" $Db $Key $Value }
function Fp([string]$Db) { Meta $Db 'indexer_fingerprint' }
function Names([string]$Db) { & python -c "import sqlite3,sys; print(' '.join(r[0] for r in sqlite3.connect(sys.argv[1]).execute('select name from symbols')))" $Db }
function Copy-Db([string]$From, [string]$To) { foreach ($x in '', '-wal', '-shm') { if (Test-Path "$From$x") { [IO.File]::Copy("$From$x", "$To$x", $true) } } }
function Tamper([string]$Path, [string]$Old, [string]$New) {
  $when = (Get-Item $Path).LastWriteTimeUtc
  [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($Path).Replace($Old, $New), [Text.Encoding]::ASCII)
  (Get-Item $Path).LastWriteTimeUtc = $when
}
function Touch([string]$Path) { [IO.File]::AppendAllText($Path, "`r`n", [Text.Encoding]::ASCII) }

$Exe = (Resolve-Path $Exe).Path
[void][IO.Directory]::CreateDirectory($WorkDir)

# A Win64 Debug project: uA depends on the project's define, on an include file only its search path
# reaches, and on a constant of another unit of the project.
function New-Project([string]$Root) {
  [void][IO.Directory]::CreateDirectory("$Root\app\_D-RAG"); [void][IO.Directory]::CreateDirectory("$Root\elsewhere\a\b\c\d\inc")
  Write-Ascii "$Root\elsewhere\a\b\c\d\inc\farinc1531.inc" "{`$DEFINE FROMINC}`n"
  Write-Ascii "$Root\app\P.dpr" @'
program P;
uses
  uK in 'uK.pas',
  uA in 'uA.pas',
  uB in 'uB.pas';
begin
  Go;
end.
'@
  Write-Ascii "$Root\app\P.dproj" @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>P.dpr</MainSource><Config Condition="'$(Config)'==''">Debug</Config><Platform Condition="'$(Platform)'==''">Win64</Platform></PropertyGroup>
  <PropertyGroup><DCC_UnitSearchPath>..\elsewhere\a\b\c\d\inc;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Debug' or '$(Cfg_1)'!=''"><Cfg_1>true</Cfg_1></PropertyGroup>
  <PropertyGroup Condition="'$(Cfg_1)'!=''"><DCC_Define>MYDEBUG;$(DCC_Define)</DCC_Define></PropertyGroup>
  <ItemGroup><DelphiCompile Include="P.dpr"><MainSource>MainSource</MainSource></DelphiCompile><DCCReference Include="uK.pas"/><DCCReference Include="uA.pas"/><DCCReference Include="uB.pas"/></ItemGroup>
</Project>
'@
  Write-Ascii "$Root\app\uK.pas" @'
unit uK;

interface

const
  KLevel = 5;

implementation

end.
'@
  Write-Ascii "$Root\app\uA.pas" @'
unit uA;

interface

{$I farinc1531.inc}

uses
  uK;

type
  EOne = class(TObject);

{$IFDEF MYDEBUG}
procedure OnlyDebug;
{$ENDIF}
{$IFDEF WIN64}
procedure OnlyWin64;
{$ENDIF}
{$IFDEF FROMINC}
procedure OnlyInc;
{$ENDIF}
{$IF KLevel > 3}
procedure OnlyLevel;
{$ELSE}
procedure OnlyLow;
{$IFEND}
procedure Always;

implementation

{$IFDEF MYDEBUG}
procedure OnlyDebug;
begin
end;
{$ENDIF}
{$IFDEF WIN64}
procedure OnlyWin64;
begin
end;
{$ENDIF}
{$IFDEF FROMINC}
procedure OnlyInc;
begin
end;
{$ENDIF}
{$IF KLevel > 3}
procedure OnlyLevel;
begin
end;
{$ELSE}
procedure OnlyLow;
begin
end;
{$IFEND}

procedure Always;
begin
  Writeln('a');
end;

end.
'@
  Write-Ascii "$Root\app\uB.pas" @'
unit uB;

interface

procedure Go;
{$IFDEF MYOTHER}
procedure OnlyOther;
{$ENDIF}

implementation

uses
  uA;

{$IFDEF MYOTHER}
procedure OnlyOther;
begin
end;
{$ENDIF}

procedure Go;
begin
  Always;
end;

end.
'@
}
try {
# ---------------------------------------------------------------- STAMP (HIGH-1)
$r = "$WorkDir\stamp"; New-Project $r; $db = "$r\app\_D-RAG\P.sqlite"; $dproj = "$r\app\P.dproj"
[void](Run @('index', '--project', $dproj, '--db', $db))
$fp0 = Fp $db; $n0 = Names $db
Check 'STAMP control: the project index is Win64 Debug' ($fp0 -match 'plat=win64;cfg=debug;defs=') $fp0
foreach ($n in 'OnlyDebug', 'OnlyWin64', 'OnlyInc', 'OnlyLevel') { Check "STAMP control: --project sees $n" ($n0 -match "\b$n\b") $n0 }
[IO.File]::WriteAllText($dproj, [IO.File]::ReadAllText($dproj).Replace('MYDEBUG;', 'MYDEBUG;MYOTHER;'), [Text.Encoding]::ASCII)
Tamper "$r\app\uA.pas" 'EOne' 'ETwo'
$d = Run @('document', '--unit', "$r\app\uA.pas", '--db', $db)
Check 'STAMP control: the tamper is seen' ($d -match 'look unchanged by timestamp') $d
Check 'STAMP a rescan after a define change leaves the DB fingerprint' ((Fp $db) -eq $fp0) (Fp $db)
$p = Run @('index', '--project', $dproj, '--db', $db)
Check 'STAMP the next index --project re-parses the stale files' (($p -match 'uB\.pas -> \d+ symbols') -and ((Names $db) -match '\bOnlyOther\b')) $p
# an older extractor's stamp: the one file is refreshed, the DB stays marked as older
$fp1 = Fp $db; $old = $fp1 -replace '^v=[^;]*', 'v=1.0.0-alpha'
Set-Meta $db 'indexer_fingerprint' $old
& python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('update files set indexed_at_fingerprint=?',(sys.argv[2],)); c.commit()" $db $old
Touch "$r\app\uA.pas"
$o = Run @('index', "$r\app\uA.pas", '--db', $db)
Check 'STAMP an older extractor: the one file is parsed' (($script:Code -eq 0) -and ($o -match 'uA\.pas -> \d+ symbols')) $o
Check 'STAMP an older extractor: the DB fingerprint stays the older one' ((Fp $db) -eq $old) (Fp $db)
$p = Run @('index', '--project', $dproj, '--db', $db)
Check 'STAMP an older extractor: index --project then finishes and stamps' ((Fp $db) -eq $fp1) "$(Fp $db) || $p"
# an unfinished --rebuild is not closed by one file
Set-Meta $db 'rebuild_in_progress' '1'
Touch "$r\app\uA.pas"; [void](Run @('index', "$r\app\uA.pas", '--db', $db))
Check 'STAMP one file does not close an interrupted --rebuild' ((Meta $db 'rebuild_in_progress') -eq '1') (Meta $db 'rebuild_in_progress')

# ---------------------------------------------------------------- BUILD (M1) / CTX (M2)
$r = "$WorkDir\build"; New-Project $r; $db = "$r\app\_D-RAG\P.sqlite"; $dproj = "$r\app\P.dproj"
[void](Run @('index', '--project', $dproj, '--db', $db))
$fp0 = Fp $db
$copy = "$WorkDir\copy.sqlite"; Copy-Db $db $copy
$db3 = "$WorkDir\P3.sqlite"; Copy-Db $db $db3
Touch "$r\app\uA.pas"
$o = Run @('index', "$r\app\uA.pas", '--db', $db)
Check 'BUILD plain index <file>: parsed, exit 0' (($script:Code -eq 0) -and ($o -match 'uA\.pas -> \d+ symbols')) $o
Check 'BUILD plain index <file> keeps the project fingerprint' ((Fp $db) -eq $fp0) (Fp $db)
$n = Names $db
foreach ($x in 'OnlyDebug', 'OnlyWin64') { Check "BUILD plain index <file> still sees $x" ($n -match "\b$x\b") $n }
foreach ($x in 'OnlyInc', 'OnlyLevel') { Check "CTX plain index <file> still sees $x" ($n -match "\b$x\b") $n }
Check 'CTX and not the other branch' ($n -notmatch '\bOnlyLow\b') $n
$o = Run @('index', "$r\app\uA.pas", '--db', $copy); $n = Names $copy
Check 'BUILD a DB copy outside _D-RAG keeps the fingerprint too' (((Fp $copy) -eq $fp0) -and ($o -match 'uA\.pas -> \d+ symbols')) "$(Fp $copy) $o"
foreach ($x in 'OnlyDebug', 'OnlyWin64', 'OnlyInc', 'OnlyLevel') { Check "BUILD the copy still sees $x" ($n -match "\b$x\b") $n }
[IO.File]::Move($dproj, "$dproj.away")
$o = Run @('index', "$r\app\uA.pas", '--db', $db3)
Check 'BUILD no project file left: refused, naming index --project' (($script:Code -eq 2) -and ($o -match 'index --project') -and ((Fp $db3) -eq $fp0)) "exit=$($script:Code) $o"
Check 'BUILD refused: the rows stay' ((Names $db3) -match '\bOnlyDebug\b') (Names $db3)
[IO.File]::Move("$dproj.away", $dproj)
# the IDE indexes with --platform <active>: the .dproj marker says Win64, the DB is Win32
$db32 = "$WorkDir\P32.sqlite"
[void](Run @('index', '--project', $dproj, '--db', $db32, '--platform', 'Win32')); $fp32 = Fp $db32
Check 'BUILD control: --platform Win32 stamped win32' ($fp32 -match 'plat=win32;cfg=debug') $fp32
Tamper "$r\app\uA.pas" 'EOne' 'ETwo'
$d = Run @('document', '--unit', "$r\app\uA.pas", '--db', $db32)
Check 'BUILD control: the tamper is seen (Win32 DB)' ($d -match 'look unchanged by timestamp') $d
Check 'BUILD a doc rescan keeps the Win32 stamp of a Win64-marked project' ((Fp $db32) -eq $fp32) (Fp $db32)
Check 'BUILD and parses as Win32' (((Names $db32) -notmatch '\bOnlyWin64\b') -and ((Names $db32) -match '\bETwo\b')) (Names $db32)
$o = Run @('index', "$r\app\uA.pas", '--db', $db32, '--platform', 'Win64', '--force-reparse')
Check 'BUILD an explicit other platform into a project DB is refused' (($script:Code -eq 2) -and ($o -match 'index --project') -and ((Fp $db32) -eq $fp32)) "exit=$($script:Code) $o"
# controls: no project stamp
$dir = "$WorkDir\loose"; [void][IO.Directory]::CreateDirectory($dir)
foreach ($u in 'uL1', 'uL2') { Write-Ascii "$dir\$u.pas" "unit $u;`n`ninterface`n`n{`$IFDEF WIN64}`nprocedure Only64$u;`n{`$ENDIF}`nprocedure Any$u;`n`nimplementation`n`nprocedure Any$u;`nbegin`nend;`n`nend.`n" }
$ldb = "$WorkDir\loose.sqlite"
[void](Run @('index', $dir, '--db', $ldb, '--platform', 'Win64')); $lfp = Fp $ldb
[IO.File]::WriteAllText("$dir\uL1.pas", [IO.File]::ReadAllText("$dir\uL1.pas").Replace('AnyuL1', 'RenameduL1'), [Text.Encoding]::ASCII)
$o = Run @('index', "$dir\uL1.pas", '--db', $ldb)
Check 'BUILD control: a folder DB still takes one file' (($script:Code -eq 0) -and ((Names $ldb) -match '\bRenameduL1\b')) $o
Check 'BUILD one file keeps the platform of a folder DB' (((Fp $ldb) -eq $lfp) -and ((Names $ldb) -match '\bOnly64uL1\b')) (Fp $ldb)
Touch "$dir\uL1.pas"
$o = Run @('index', "$dir\uL1.pas", '--db', $ldb, '--platform', 'Win32')
Check 'BUILD an explicit other platform: taken for the file, the folder DB is not stamped Win32' (($script:Code -eq 0) -and ((Fp $ldb) -notmatch 'plat=win32') -and ((Names $ldb) -notmatch '\bOnly64uL1\b')) "$(Fp $ldb) $o"
$o = Run @('index', $dir, '--db', $ldb, '--platform', 'Win64')
Check 'BUILD the next folder run re-parses just that file' (($o -match 'uL1\.pas -> \d+ symbols') -and ($o -notmatch 'uL2\.pas -> \d+ symbols') -and ((Fp $ldb) -eq $lfp) -and ((Names $ldb) -match '\bOnly64uL1\b')) "$(Fp $ldb) $o"
$adb = "$WorkDir\adhoc.sqlite"
[void](Run @('index', "$dir\uL1.pas", '--db', $adb)); $a1 = Fp $adb
[void](Run @('index', "$dir\uL2.pas", '--db', $adb))
Check 'BUILD control: an ad-hoc DB is stamped and takes a second file' (($a1 -match 'plat=') -and ((Fp $adb) -eq $a1) -and ((Names $adb) -match '\bAnyuL2\b')) "$a1 | $(Fp $adb)"

# ---------------------------------------------------------------- OPEN
$oDb = "$WorkDir\open.sqlite"; $oDir = "$WorkDir\open"; [void][IO.Directory]::CreateDirectory($oDir)
Write-Ascii "$oDir\uO.pas" "unit uO;`n`ninterface`n`nprocedure Work;`nprocedure Caller;`n`nimplementation`n`nprocedure Work;`nbegin`n  Writeln('x');`nend;`n`nprocedure Caller;`nbegin`n  Work;`nend;`n`nend.`n"
[void](Run @('index', $oDir, '--db', $oDb))
$before = Text "$oDir\uO.pas"
foreach ($key in 'resolver_fingerprint', 'indexer_fingerprint') {
  $keep = Meta $oDb $key
  Set-Meta $oDb $key '-'
  $d = Run @('document', '--unit', "$oDir\uO.pas", '--db', $oDb)
  Check "OPEN no $key : a dry run WARNs" ($d -match 'doc: WARN -- .*did not finish') $d
  $d = Run @('document', '--unit', "$oDir\uO.pas", '--apply', '--no-backup', '--db', $oDb)
  Check "OPEN no $key : --apply is refused, nothing written" (($script:Code -eq 1) -and ($d -match 'doc: REFUSED') -and ((Text "$oDir\uO.pas") -ceq $before)) "exit=$($script:Code) $d"
  [IO.File]::WriteAllText("$oDir\uO.pas", $before.Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
  Set-Meta $oDb $key $keep
}
[void](Run @('index', $oDir, '--db', $oDb))
$d = Run @('document', '--unit', "$oDir\uO.pas", '--apply', '--no-backup', '--db', $oDb)
Check 'OPEN control: a finished index is documented, no WARN' (($script:Code -eq 0) -and ($d -notmatch 'did not finish') -and ((Text "$oDir\uO.pas") -cne $before)) $d

# ---------------------------------------------------------------- TRIPLE (M3)
$tDir = "$WorkDir\triple"; [void][IO.Directory]::CreateDirectory($tDir); $tDb = "$WorkDir\triple.sqlite"
Write-Ascii "$tDir\uT.pas" @"
unit uT;

interface

const
  CAfterParen = 1;
  CAfterBrace = 2;
  CInTriple   = 4;
  CDead       = 5;

procedure Run;

implementation

procedure Run;
var
  S: string;
begin
  S:= '''
    select COUNT(*) as CInTriple from T
    it's {
    ''';
  Writeln(S);
end;

{`$IF CAfterParen > 1}
{`$IFEND}
procedure OneB;
begin
  Writeln('''''
    { '''
    (*
    ''''');
end;

{`$IF CAfterBrace > 1}
{`$IFEND}
procedure Two;
var
  S: string;
begin
  S:= ''' x''' + ''; { CDead }
end;

end.
"@
[void](Run @('index', $tDir, '--db', $tDb))
$g = Run @('lint-all', '--db', $tDb, '--rule', 'unused-global', '--quiet')
foreach ($x in 'CAfterParen', 'CAfterBrace', 'CInTriple') { Check "TRIPLE $x is named after/in a multi-line string: silent" ($g -notmatch "const $x \(") $g }
Check 'TRIPLE control: CDead (a comment after the strings only) is reported' ($g -match 'const CDead \(') $g

# ---------------------------------------------------------------- DOCNAME
# iLoggingServiceP.FromLMT: a public routine nothing calls, named in another unit's managed doc block
# (the seealso / fact lines `document --apply` writes), is unused for BOTH rules; a called one is not.
$nDir = "$WorkDir\docname"; [void][IO.Directory]::CreateDirectory($nDir); $nDb = "$WorkDir\docname.sqlite"
Write-Ascii "$nDir\uN1.pas" "unit uN1;`n`ninterface`n`nconst`n  CDocNamed = 1;`n`nfunction FromLMT(const S: string): string;`nprocedure Used;`n`nimplementation`n`nfunction FromLMT(const S: string): string;`nbegin`n  Result:= S;`nend;`n`nprocedure Used;`nbegin`nend;`n`nend.`n"
Write-Ascii "$nDir\uN2.pas" "unit uN2;`n`ninterface`n`n/// <remarks>`n/// <!-- drag-lint:auto BEGIN -->`n/// <para>Calls: uN1.FromLMT, FromLMT, uN1.CDocNamed, CDocNamed</para>`n/// <seealso cref=`"uN1.FromLMT`"/>`n/// <!-- drag-lint:auto END -->`n/// </remarks>`nprocedure Go;`n`nimplementation`n`nuses`n  uN1;`n`nprocedure Go;`nbegin`n  Used;`nend;`n`nend.`n"
[void](Run @('index', $nDir, '--db', $nDb))
$g = Run @('lint-all', '--db', $nDb, '--rule', 'unused-public-symbol', '--quiet')
Check 'DOCNAME unused-public-symbol: FromLMT (only doc comments name it) is reported' ($g -match 'FromLMT') $g
Check 'DOCNAME control: unused-public-symbol: Used (called) is silent' ($g -notmatch '\bUsed\b is not') $g
$g = Run @('lint-all', '--db', $nDb, '--rule', 'unused-global', '--quiet')
Check 'DOCNAME unused-global: CDocNamed (only doc comments name it) is reported' ($g -match 'const CDocNamed \(') $g

# ---------------------------------------------------------------- SLASH (M5)
$sDir = "$WorkDir\slash"; [void][IO.Directory]::CreateDirectory($sDir); $sDb = "$WorkDir\slash.sqlite"
Write-Ascii "$sDir\uS.pas" @'
unit uS;

interface

/// <summary>//////////////////</summary>
procedure Hurt;

/// <summary>Reads a //server/share path or a/b.</summary>
procedure Human;

implementation

procedure Hurt;
begin
  Human;
end;

procedure Human;
begin
  Hurt;
end;

end.
'@
[void](Run @('index', $sDir, '--db', $sDb))
$d = Run @('document', '--unit', "$sDir\uS.pas", '--apply', '--no-backup', '--db', $sDb); $t = Text "$sDir\uS.pas"
Check 'SLASH a slashes-only summary is dropped, facts stay' (($t -notmatch '<summary>/') -and ($t -match '(?s)interface.*<remarks>.*procedure Hurt;')) $t
Check 'SLASH control: a human summary holding slashes stays' ($t.Contains('<summary>Reads a //server/share path or a/b.</summary>')) $t

# ---------------------------------------------------------------- GUARD (M6)
$gDir = "$WorkDir\guard"; [void][IO.Directory]::CreateDirectory($gDir); $gDb = "$WorkDir\guard.sqlite"
Write-Ascii "$gDir\uG.pas" ("unit uG;`n`ninterface`n`n" + ('/' * 40) + "`n`nprocedure Work;`nprocedure Caller;`n`nimplementation`n`nprocedure Work;`nbegin`n  Writeln('x');`nend;`n`nprocedure Caller;`nbegin`n  Work;`nend;`n`nend.`n")
[void](Run @('index', $gDir, '--db', $gDb)); $before = Text "$gDir\uG.pas"
try {
  $env:DRAGLINT_DOC_SELFTEST_DAMAGE = 'banner'
  $d = Run @('document', '--unit', "$gDir\uG.pas", '--apply', '--no-backup', '--db', $gDb)
} finally { $env:DRAGLINT_DOC_SELFTEST_DAMAGE = $null }
Check 'GUARD a write that deletes a banner is refused, the file restored' (($script:Code -ne 0) -and ($d -match 'doc apply REFUSED') -and ((Text "$gDir\uG.pas") -ceq $before)) "exit=$($script:Code) $d"
[IO.File]::WriteAllText("$gDir\uG.pas", $before.Replace("`n", "`r`n"), [Text.Encoding]::ASCII); [void](Run @('index', $gDir, '--db', $gDb))
$d = Run @('document', '--unit', "$gDir\uG.pas", '--apply', '--no-backup', '--db', $gDb)
Check 'GUARD control: the same write without the damage passes' (($script:Code -eq 0) -and ($d -match 'documented, \d+ edit') -and (Text "$gDir\uG.pas").Contains(('/' * 40) + "`n")) $d

# ---------------------------------------------------------------- GAP / STRIP
$bDir = "$WorkDir\gap"; [void][IO.Directory]::CreateDirectory($bDir); $bDb = "$WorkDir\gap.sqlite"
$bar = '/' * 30; $sp = "$bDir\uG2.pas"
Write-Ascii $sp @"
unit uG2;

interface

/// <summary>Documented above a banner.</summary>
$bar

procedure Gap;

/// <summary>Plain one.</summary>
procedure Plain;

implementation

procedure Gap;
begin
  Plain;
end;

procedure Plain;
begin
  Gap;
end;

end.
"@
[void](Run @('index', $bDir, '--db', $bDb))
$d = Run @('document', '--unit', $sp, '--apply', '--no-backup', '--db', $bDb); $t = Text $sp
$head = $t.Substring(0, $t.IndexOf('procedure Gap;'))
Check 'GAP doc + banner + blank + decl: one block, the summary kept, the facts in it' ($head -match "(?s)<summary>Documented above a banner\.</summary>\n/// <remarks>.*</remarks>\n$bar\n\n$") $head
[void](Run @('index', $bDir, '--db', $bDb))
$d = Run @('document', '--unit', $sp, '--db', $bDb)
Check 'GAP pass 2 is a no-op' ($d -match 'nothing to document') $d
$d = Run @('document', '--qname', 'uG2.Gap', '--strip', '--apply', '--no-backup', '--db', $bDb); $t = Text $sp
$head = $t.Substring(0, $t.IndexOf('procedure Gap;'))
Check 'STRIP --qname removes what apply wrote above a banner' ($head -match "interface\n\n/// <summary>Documented above a banner\.</summary>\n$bar\n\n$") "$d || $head"
$s2 = "$WorkDir\strip2"; [void][IO.Directory]::CreateDirectory($s2); $s2Db = "$WorkDir\strip2.sqlite"
Write-Ascii "$s2\uS2.pas" @"
unit uS2;

interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: SomethingElse</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
$bar
/// <summary>Own.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: Mine</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Own;

implementation

procedure Own;
begin
end;

end.
"@
[void](Run @('index', $s2, '--db', $s2Db))
$d = Run @('document', '--qname', 'uS2.Own', '--strip', '--apply', '--no-backup', '--db', $s2Db); $t = Text "$s2\uS2.pas"
Check 'STRIP --qname takes its own facts' ($t -match '<summary>Own\.</summary>\nprocedure Own;') "$d || $t"
Check 'STRIP --qname leaves the block above the banner' ($t.Contains('Calls: SomethingElse')) $t

# ---------------------------------------------------------------- TAMPER
$mDir = "$WorkDir\tam"; [void][IO.Directory]::CreateDirectory($mDir); $mDb = "$WorkDir\tam.sqlite"
Write-Ascii "$mDir\uM.pas" @'
unit uM;

interface

type
  MarkAttribute = class(TCustomAttribute)
  end;

  TM = class
  public
    [Mark] { inline } procedure InlineBrace;
    [Mark]
    (* a star comment *)
    procedure StarLine;
    [Mark]
    { a brace comment
      over two lines }
    procedure TwoLines;
    [Mark]
    (* a star comment
       over two lines *) procedure StarTwo;
  end;

implementation

procedure TM.InlineBrace;
begin
  StarLine;
end;

procedure TM.StarLine;
begin
  TwoLines;
end;

procedure TM.TwoLines;
begin
  StarTwo;
end;

procedure TM.StarTwo;
begin
  InlineBrace;
end;

end.
'@
[void](Run @('index', $mDir, '--db', $mDb))
$d = Run @('document', '--unit', "$mDir\uM.pas", '--db', $mDb)
Check 'TAMPER comments between an attribute and its heading are not tampering' ($d -notmatch 'look unchanged by timestamp') $d
$d = Run @('document', '--unit', "$mDir\uM.pas", '--apply', '--no-backup', '--db', $mDb); $t = Text "$mDir\uM.pas"
foreach ($x in 'InlineBrace', 'StarLine', 'TwoLines', 'StarTwo') { Check "TAMPER $x (decorated, commented) is documented above its attribute" ($t -match "</remarks>\n    \[Mark\][^;]*procedure $x;") "$d || $t" }
Check 'TAMPER no edit was refused' ($d -notmatch 'REFUSED') $d
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host "checks=$script:Total"
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
