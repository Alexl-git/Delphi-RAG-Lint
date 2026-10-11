<#
  run_convert_apply_strip_db.ps1 -- 1.27.0 (C15, owner ruling 2026-10-10): the
  StripDB VALUE cast. `#link TableName <- TableName : StripDB` removes a
  trailing `.db` (any case) from the linked string value; every other value
  is left exactly as it is.

  THE CONTRACT
    * castlib: `cast StripDB` with `value strip-db` -- a built-in transform the
      engine implements, ONE fixed name, no parameters; the SHIPPED
      docs\examples\convrules\casts.castlib declares it (the editor lists cast
      names from there). An unknown `value` keyword is a load error.
    * .dfm: the value is rewritten on each converted instance, only when it
      changes ('MET1.db' -> 'MET1', 'X.DB' -> 'X'; 'A.dbf', 'A.db.bak', 'MET1'
      and '' untouched).
    * .pas: `<inst>.TableName := '<one literal>';` has its literal rewritten
      (quote escaping kept) -- only when the literal is followed on the SAME
      line by blanks / closed comments and ';' (review fix wave: a hidden
      continuation, '#nn', a two-line assignment, an else-ended statement are
      checks; a comment or TAB before ':=' is fine). Any other right-hand side,
      and any read, gets NO edit and a warning naming the line. Every OTHER
      reference (a with block) is one value-cast-check naming its line. A
      literal without .db: no edit, no item.
    * .dfm: a value that is not one string literal (multi-line, #nn) is a
      value-cast-check and is kept.
    * pas_uses rows never change an edit (B1).
    * Every change is an item (value-cast-applied: old_value, value, file,
      line); a text count per unit; info capability value_cast_strip_db.
    * The class-cast refusal (1.27.0) does NOT apply to a value cast.
    * pas_uses[]: a member a StripDB link covers is `mapped`.
  Fixture under a $PID scratch folder; nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_strip_db_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$ShippedCastlib = (Resolve-Path "$PSScriptRoot\..\..\docs\examples\convrules\casts.castlib").Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$CRLF = "`r`n"
function W([string]$Dir, [string]$n, [string]$t) { [IO.File]::WriteAllText((Join-Path $Dir $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$shippedText = [IO.File]::ReadAllText($ShippedCastlib)
Check 'S0 the SHIPPED castlib declares cast StripDB with value strip-db' `
  ($shippedText -match '(?ms)^cast StripDB\s*\r?\n.*?^\s*value\s+strip-db\s*\r?\n.*?^end') ''

function Fixture([string]$Dir, [string]$Link, [string]$ExtraLine = '') {
  New-Item -ItemType Directory $Dir -Force | Out-Null
  W $Dir 'LibTbl.pas' @'
unit LibTbl;

interface

uses
  Classes;

type
  TOldTable = class(TComponent)
  private
    FTableName: string;
  public
    procedure OldOnly;
  published
    property TableName: string read FTableName write FTableName;
  end;

  TNewTable = class(TComponent)
  private
    FTableName: string;
  published
    property TableName: string read FTableName write FTableName;
  end;

implementation

procedure TOldTable.OldOnly;
begin
end;

end.
'@
  # Line numbers below are asserted -- keep the body as is.
  $sform = @'
unit SForm;

interface

uses
  Classes, LibTbl;

type
  TSForm = class(TComponent)
    t1: TOldTable;
    t2: TOldTable;
    t3: TOldTable;
    t4: TOldTable;
    t5: TOldTable;
    t6: TOldTable;
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TSForm.Run;
var
  S: string;
begin
  t1.TableName := 'MET1.db';
  t2.TableName := 'Pre' + 'X.db';
  S := t1.TableName;
  t3.TableName := 'A.dbf';
  t5.TableName := 'Q.Db';
  t4.TableName := 'O''Neil.db';
  if S = '' then Exit;
end;

end.
'@
  # B1: an extra line just before the last statement -- nothing asserted moves
  if ($ExtraLine -ne '') { $sform = $sform.Replace("  if S = '' then Exit;", "$ExtraLine`n  if S = '' then Exit;") }
  W $Dir 'SForm.pas' $sform
  $objs = @(@('t1', "'MET1.db'"), @('t2', "'X.DB'"), @('t3', "'A.dbf'"), @('t4', "'A.db.bak'"), @('t5', "'MET1'"), @('t6', "''"))
  $d = @('object SForm: TSForm')
  foreach ($o in $objs) { $d += "  object $($o[0]): TOldTable"; $d += "    TableName = $($o[1])"; $d += '  end' }
  $d += 'end'
  W $Dir 'SForm.dfm' (($d -join "`n") + "`n")
  W $Dir 'P.dpr' "program P;`n`nuses`n  LibTbl, SForm;`n`nbegin`nend.`n"
  W $Dir 's.rules' "#convert TOldTable -> TNewTable`n$Link`n"
  & $Exe index --project (Join-Path $Dir 'P.dpr') --db (Join-Path $Dir 'fx.sqlite') 2>&1 | Out-Null
}
$main = Join-Path $WorkDir 'main'; Fixture $main '#link TableName <- TableName : StripDB'
$ctl  = Join-Path $WorkDir 'ctl';  Fixture $ctl  '#link TableName <- TableName'

function Run([string]$Dir, [string[]]$Extra = @(), [string]$Castlib = $ShippedCastlib) {
  $a = @('convert-apply', '--unit', (Join-Path $Dir 'SForm.pas'), '--rules', (Join-Path $Dir 's.rules'), '--db', (Join-Path $Dir 'fx.sqlite'), '--castlib', $Castlib) + $Extra
  $o = (& $Exe @a 2>&1) -join "`n"
  $code = $LASTEXITCODE
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j }
}
function Items($r, [string]$Kind) { if ($null -eq $r.J) { return @() }; return @($r.J.items | Where-Object { $_.kind -eq $Kind }) }
function Show($x) { return ($x | ConvertTo-Json -Compress -Depth 4) }

# ============================== dry run ======================================
$r = Run $main @('--format', 'json')
Check 'V the run converts all six instances' (($r.Code -eq 0) -and (@($r.J.converted).Count -eq 6)) $r.Out
$dfmIt = Items $r 'value-cast-applied' | Where-Object { $_.file -like '*.dfm' }
$t1d = @($dfmIt | Where-Object { $_.instance -eq 't1' })
$t2d = @($dfmIt | Where-Object { $_.instance -eq 't2' })
Check 'D1 .dfm t1: TableName MET1.db -> MET1, one value-cast-applied item with old_value/value' `
  (($t1d.Count -eq 1) -and ($t1d[0].old_value -eq "'MET1.db'") -and ($t1d[0].value -eq "'MET1'") -and ($t1d[0].path -eq 'TableName') -and ($t1d[0].line -eq 3)) (Show $dfmIt)
Check 'D2 .dfm t2: MIXED CASE X.DB -> X' (($t2d.Count -eq 1) -and ($t2d[0].value -eq "'X'")) (Show $dfmIt)
Check 'D3 .dfm: A.dbf, A.db.bak, MET1 and '''' are NOT changed -- exactly two .dfm items' ($dfmIt.Count -eq 2) (Show $dfmIt)

$pasIt = Items $r 'value-cast-applied' | Where-Object { $_.file -like '*.pas' }
Check 'P1 .pas literal assignments rewritten: lines 27 (MET1.db), 31 (Q.Db), 32 (O''''Neil.db) -- and nothing else' `
  ((((@($pasIt | ForEach-Object { $_.line }) | Sort-Object) -join ',') -eq '27,31,32') -and
   (@($pasIt | Where-Object { $_.line -eq 32 -and $_.value -eq "'O''Neil'" -and $_.old_value -eq "'O''Neil.db'" }).Count -eq 1)) (Show $pasIt)
$chk = Items $r 'value-cast-check'
Check 'P2 the concatenation (line 28) and the read (line 29) are warnings naming their line, no edit' `
  (($chk.Count -eq 2) -and (@($chk | Where-Object { $_.line -eq 28 -and $_.text -match 'value cast StripDB: non-literal assignment, check by hand' }).Count -eq 1) -and
   (@($chk | Where-Object { $_.line -eq 29 -and $_.text -match 'value cast StripDB: read of TableName, check by hand' }).Count -eq 1) -and
   (@($chk | Where-Object { $_.field -ne 'warnings' }).Count -eq 0)) (Show $chk)
Check 'P3 a literal with no .db (line 30, A.dbf): no edit, no item' `
  ((@($r.J.items | Where-Object { $_.line -eq 30 -and $_.file -like '*.pas' }).Count -eq 0)) (Show ($r.J.items | Where-Object { $_.file -like '*.pas' }))
Check 'R1 the CLASS-cast refusal does not fire for a value cast: no cast-not-applied' (@(Items $r 'cast-not-applied').Count -eq 0) (Show (Items $r 'cast-not-applied'))
$pu = @($r.J.pas_uses | Where-Object { $_.member -eq 'TableName' })
Check 'U1 pas_uses: TableName covered by the StripDB link is mapped, for every instance it is used on' `
  (($pu.Count -ge 1) -and (@($pu | Where-Object { $_.status -ne 'mapped' }).Count -eq 0)) (Show $pu)

$t = Run $main
Check 'T1 text: a per-unit value-cast count' ($t.Out -match '(?m)^value casts: 5 value\(s\) changed \(\.dfm 2, \.pas 3\), 2 site\(s\) to check by hand\s*$') $t.Out

# ============================== --apply ======================================
$a = Run $main @('--apply', '--no-backup', '--no-reindex')
$dfm = [IO.File]::ReadAllText((Join-Path $main 'SForm.dfm'))
$pas = [IO.File]::ReadAllText((Join-Path $main 'SForm.pas'))
Check 'A1 --apply exit 0; .dfm t1 = MET1, t2 = X, and t3..t6 untouched' `
  (($a.Code -eq 0) -and ($dfm -match "object t1: TNewTable\r\n    TableName = 'MET1'\r\n") -and ($dfm -match "object t2: TNewTable\r\n    TableName = 'X'\r\n") -and
   ($dfm -match "TableName = 'A\.dbf'") -and ($dfm -match "TableName = 'A\.db\.bak'") -and ($dfm -match "object t5: TNewTable\r\n    TableName = 'MET1'\r\n") -and
   ($dfm -match "object t6: TNewTable\r\n    TableName = ''\r\n")) ($a.Out + "`n" + $dfm)
Check 'A2 .pas: the three literals rewritten, escaping kept; the concatenation, the read and A.dbf untouched' `
  ($pas.Contains("  t1.TableName := 'MET1';") -and $pas.Contains("  t5.TableName := 'Q';") -and $pas.Contains("  t4.TableName := 'O''Neil';") -and
   $pas.Contains("  t2.TableName := 'Pre' + 'X.db';") -and $pas.Contains('  S := t1.TableName;') -and $pas.Contains("  t3.TableName := 'A.dbf';")) $pas

# ---- idempotence: a second run changes nothing ------------------------------
& $Exe index --project (Join-Path $main 'P.dpr') --db (Join-Path $main 'fx.sqlite') 2>&1 | Out-Null
$h1 = (Get-FileHash (Join-Path $main 'SForm.pas')).Hash + (Get-FileHash (Join-Path $main 'SForm.dfm')).Hash
$a2 = Run $main @('--apply', '--no-backup', '--no-reindex')
$h2 = (Get-FileHash (Join-Path $main 'SForm.pas')).Hash + (Get-FileHash (Join-Path $main 'SForm.dfm')).Hash
Check 'I1 a second --apply changes no byte of the .pas or the .dfm' ($h1 -eq $h2) $a2.Out

# ---- compile ----------------------------------------------------------------
New-Item -ItemType Directory (Join-Path $main 'bin'), (Join-Path $main 'dcu') -Force | Out-Null
$bat = Join-Path $main 'c.bat'; $log = Join-Path $main 'c.log'
[IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$main`"",
  "dcc64 -Q -B -NSSystem -E`"$main\bin`" -NU`"$main\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
Check 'C1 the converted unit compiles (dcc64)' (($cl -match 'BUILD_EXITCODE=0') -and -not ($cl -match '(?m)\bError\b')) (@(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' }) -join ' | ')

# ---- positive control: no ': StripDB' leaves MET1.db -------------------------
$c = Run $ctl @('--apply', '--no-backup', '--no-reindex')
$cdfm = [IO.File]::ReadAllText((Join-Path $ctl 'SForm.dfm'))
$cpas = [IO.File]::ReadAllText((Join-Path $ctl 'SForm.pas'))
Check 'PC POSITIVE CONTROL: the same fixture without : StripDB converts and keeps MET1.db / X.DB in the .dfm and the .pas' `
  (($c.Code -eq 0) -and ($cdfm -match "object t1: TNewTable\r\n    TableName = 'MET1\.db'") -and ($cdfm -match "TableName = 'X\.DB'") -and
   $cpas.Contains("  t1.TableName := 'MET1.db';")) ($c.Out + "`n" + $cdfm)

# ---- an unknown value keyword is a load error -------------------------------
$bad = Join-Path $WorkDir 'bad.castlib'
W $WorkDir 'bad.castlib' "cast StripZip`n  value strip-zip`nend`n"
$b = Run $ctl @('--format', 'json') $bad
Check 'L1 a castlib with an unknown value keyword fails the run, naming the line and the keyword' `
  (($b.Code -ne 0) -and ($b.Out -match 'bad\.castlib') -and ($b.Out -match 'line 2') -and ($b.Out -match 'strip-zip')) $b.Out

# ---- 1.27.0 review fix wave: the .pas literal is rewritten ONLY when it is the
# whole value -- the literal, then on the SAME line optional blanks/comments and
# ';'. Anything else is a check. A `with` site is a check, never silent. ------
$edge = Join-Path $WorkDir 'edge'
New-Item -ItemType Directory $edge -Force | Out-Null
Copy-Item (Join-Path $main 'LibTbl.pas') $edge
# Line numbers below are asserted -- keep the body as is. Line 35 has a TAB before :=.
W $edge 'EForm.pas' (@'
unit EForm;

interface

uses
  Classes, LibTbl;

type
  TEForm = class(TComponent)
    e1: TOldTable;
    e2: TOldTable;
    e3: TOldTable;
    e4: TOldTable;
    e5: TOldTable;
    e6: TOldTable;
    e7: TOldTable;
    e8: TOldTable;
    e9: TOldTable;
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TEForm.Run;
begin
  e1.TableName := 'A.db'
    // note
    + 'x';
  e2.TableName := 'B.db'#0;
  e3.TableName :=
    'C.db';
  e4.TableName {c} := 'D.db';
  e5.TableName<TAB>:= 'E.db';
  e6.TableName := 'F.db' { c } ; // tail
  with e7 do TableName := 'W.db';
  e8.TableName := 'G.db';
  if e8 = nil then
    e9.TableName := 'H.db'
  else
    Exit;
end;

end.
'@).Replace('<TAB>', "`t")
$ed = @('object EForm: TEForm', '  object e1: TOldTable', "    TableName = 'A' +", "      'B.db'", '  end',
        '  object e2: TOldTable', "    TableName = 'X.db'#0", '  end')
foreach ($n in 3..9) { $ed += "  object e$($n): TOldTable"; $ed += "    TableName = 'Q$($n).db'"; $ed += '  end' }
$ed += 'end'
W $edge 'EForm.dfm' (($ed -join "`n") + "`n")
W $edge 'P.dpr' "program P;`n`nuses`n  LibTbl, EForm;`n`nbegin`nend.`n"
W $edge 's.rules' "#convert TOldTable -> TNewTable`n#link TableName <- TableName : StripDB`n"
& $Exe index --project (Join-Path $edge 'P.dpr') --db (Join-Path $edge 'fx.sqlite') 2>&1 | Out-Null
$eo = (& $Exe convert-apply --unit (Join-Path $edge 'EForm.pas') --rules (Join-Path $edge 's.rules') --db (Join-Path $edge 'fx.sqlite') --castlib $ShippedCastlib --format json 2>&1) -join "`n"
$er = [pscustomobject]@{ Code = $LASTEXITCODE; Out = $eo; J = $null }
try { $er.J = $eo.Substring($eo.IndexOf('{')) | ConvertFrom-Json } catch {}
$ePas = @(Items $er 'value-cast-applied' | Where-Object { $_.file -like '*.pas' })
$eChk = @(Items $er 'value-cast-check' | Where-Object { $_.file -like '*.pas' })
function LineSet($xs) { return ((@($xs | ForEach-Object { $_.line }) | Sort-Object) -join ',') }
Check 'E0 the edge fixture converts all nine instances' (($er.Code -eq 0) -and (@($er.J.converted).Count -eq 9)) $eo
Check 'E1 a continuation HIDDEN behind a comment line (28-30) is a check, not a rewrite' `
  ((@($eChk | Where-Object { $_.line -eq 28 }).Count -eq 1) -and (@($ePas | Where-Object { $_.line -eq 28 }).Count -eq 0)) (Show ($er.J.items | Where-Object { $_.file -like '*.pas' }))
Check 'E2 a literal followed by a #nn char code (31) is a check' (@($eChk | Where-Object { $_.line -eq 31 }).Count -eq 1) (Show $eChk)
Check 'E3 a two-line assignment (32-33) is a check' (@($eChk | Where-Object { $_.line -eq 32 }).Count -eq 1) (Show $eChk)
Check 'E4 a {comment} and a TAB before := are still assignments, and literal + comment + ; is rewritten: 34, 35, 36, 38 applied -- nothing else' `
  ((LineSet $ePas) -eq '34,35,36,38') (Show $ePas)
Check 'E5 a statement ended by else, not ;, (40) is a check' (@($eChk | Where-Object { $_.line -eq 40 }).Count -eq 1) (Show $eChk)
$wChk = @($eChk | Where-Object { $_.line -eq 37 })
Check 'E6 a `with e7 do TableName := ...` site is EXACTLY ONE value-cast-check naming line 37, no edit' `
  (($wChk.Count -eq 1) -and ($wChk[0].text -match 'EForm\.pas:37') -and ($wChk[0].field -eq 'warnings') -and (@($ePas | Where-Object { $_.line -eq 37 }).Count -eq 0)) (Show $eChk)
Check 'E7 the .pas checks are exactly lines 28, 31, 32, 37, 40' ((LineSet $eChk) -eq '28,31,32,37,40') (Show $eChk)
$eDfmChk = @(Items $er 'value-cast-check' | Where-Object { $_.file -like '*.dfm' })
$eDfmApp = @(Items $er 'value-cast-applied' | Where-Object { $_.file -like '*.dfm' })
Check 'E8 .dfm: a MULTI-LINE value (e1) and a #nn char-code value (e2) are value-cast-check, not rewritten; e3..e9 are applied' `
  ((@($eDfmChk | Where-Object { $_.instance -eq 'e1' }).Count -eq 1) -and (@($eDfmChk | Where-Object { $_.instance -eq 'e2' }).Count -eq 1) -and
   ($eDfmChk.Count -eq 2) -and ($eDfmApp.Count -eq 7) -and (@($eDfmApp | Where-Object { $_.instance -in 'e1','e2' }).Count -eq 0)) (Show (@($eDfmChk) + @($eDfmApp)))
$ea = (& $Exe convert-apply --unit (Join-Path $edge 'EForm.pas') --rules (Join-Path $edge 's.rules') --db (Join-Path $edge 'fx.sqlite') --castlib $ShippedCastlib --apply --no-backup --no-reindex 2>&1) -join "`n"
$eaCode = $LASTEXITCODE
$eDfm = [IO.File]::ReadAllText((Join-Path $edge 'EForm.dfm'))
$ePasTxt = [IO.File]::ReadAllText((Join-Path $edge 'EForm.pas'))
# The re-emit re-indents a continuation line (6 -> 8 blanks) whatever the cast does; the VALUE is what is asserted.
Check 'E9 --apply: the .dfm keeps e1''s two-line value and e2''s #0; the .pas keeps every checked site byte for byte' `
  (($eaCode -eq 0) -and ($eDfm -match "    TableName = 'A' \+\r\n +'B\.db'\r\n") -and $eDfm.Contains("    TableName = 'X.db'#0`r`n") -and
   $ePasTxt.Contains("  e1.TableName := 'A.db'`r`n    // note`r`n    + 'x';") -and $ePasTxt.Contains("  e2.TableName := 'B.db'#0;") -and
   $ePasTxt.Contains("  e3.TableName :=`r`n    'C.db';") -and $ePasTxt.Contains("  with e7 do TableName := 'W.db';") -and
   $ePasTxt.Contains("    e9.TableName := 'H.db'`r`n") -and $ePasTxt.Contains("  e4.TableName {c} := 'D';") -and
   $ePasTxt.Contains("  e5.TableName`t:= 'E';") -and $ePasTxt.Contains("  e6.TableName := 'F' { c } ; // tail")) ($ea + "`n" + $ePasTxt)

# ---- pas_uses rows never change an edit: the same fixture plus one line that
# only adds an UNMAPPED pas_uses row writes the same .dfm bytes and the same
# .pas bytes apart from that line ------------------------------------------------
$ba = Join-Path $WorkDir 'ba'; Fixture $ba '#link TableName <- TableName : StripDB'
$bb = Join-Path $WorkDir 'bb'; Fixture $bb '#link TableName <- TableName : StripDB' '  t6.OldOnly;'
$bj = Run $bb @('--format', 'json')
Check 'B0 the extra line is an UNMAPPED pas_uses row (t6.OldOnly, line 33)' `
  (@($bj.J.pas_uses | Where-Object { $_.instance -eq 't6' -and $_.member -eq 'OldOnly' -and $_.status -eq 'unmapped' -and ((@($_.lines) -join ',') -eq '33') }).Count -eq 1) (Show $bj.J.pas_uses)
$baR = Run $ba @('--apply', '--no-backup', '--no-reindex')
$bbR = Run $bb @('--apply', '--no-backup', '--no-reindex')
$baPas = [IO.File]::ReadAllText((Join-Path $ba 'SForm.pas'))
$bbPas = [IO.File]::ReadAllText((Join-Path $bb 'SForm.pas')).Replace("  t6.OldOnly;`r`n", '')
Check 'B1 identical .dfm bytes and identical .pas bytes (apart from the extra line) with and without the pas_uses row' `
  (($baR.Code -eq 0) -and ($bbR.Code -eq 0) -and ($baPas -eq $bbPas) -and
   ((Get-FileHash (Join-Path $ba 'SForm.dfm')).Hash -eq (Get-FileHash (Join-Path $bb 'SForm.dfm')).Hash)) ($baR.Out + "`n" + $bbR.Out)

# ---- capability -------------------------------------------------------------
$info = (& $Exe info --json 2>$null) -join "`n"
$ij = $null; try { $ij = $info.Substring($info.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'K info --json: capabilities.value_cast_strip_db is true' (($null -ne $ij) -and ($ij.capabilities.value_cast_strip_db -eq $true)) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
