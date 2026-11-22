<#
  run_v152_BK-TAILS-ENG.ps1 -- lane v152 BK-TAILS-ENG: three engine tails of 1.52.

  X  BK-XPROJ follow-up: a .groupproj peer .dproj that LISTS a unit but has NO index DB
     makes the cross-project verdict undecidable: unused-global / member-could-be-private on
     that unit are withheld (not fired), and ONE info line on stderr names the unindexed peer.
       X1  App2 unindexed, lists UShared: UsedOnlyByApp2 + UsedNowhere silent (unused-global)
       X2  stderr names App2 and says it has no index (once)
       X3  member-could-be-private: WriteChunk + OnlyLocal silent
       X4  positive control: App2 unindexed but NOT listing UShared -> UsedOnlyByApp2 fires,
           and no info line names App2
       X5  positive control: App1 alone (no groupproj) -> UsedOnlyByApp2 fires
  C  BK-COLS2 tails: CHARACTER (UTF-16) columns
       C1  the index DIAG line for a .dfm parse error after three e-acute on the line
           prints the character column (19), not the byte column (22)
       C2  invisible-char after a non-BMP character (U+1F600, two UTF-16 units) reports
           column 6, not the code-point column 5; C2c ASCII twin stays at 5 (control)
       C3  deprecated-rtl-function after a BLANKED inactive {$IFDEF} holding three e-acute
           reports the character column of StrPas; C3c ASCII twin (control)
       C4  field-by-name-in-loop on the same shape; C4c ASCII twin (control)
  R  index gap (HBFIX 11-18): `var B:= Br[K]` with Br a TDictionary / TObjectDictionary
     types B as the dictionary's VALUE type, so `B.Side` binds to TBranch.Side
       R1  Br an untyped inline var := TObjectDictionary<string, TBranch>.Create
       R2  D a parameter typed TDictionary<string, TBranch>
       R3  positive control: `var G: TBranch:= Br['v']` (written type) binds
       R4  positive control: `var L0:= Lst[0]` on a TList<TBranch> still binds
       R5  negative control: TDictionary<TBranch, string> subscripts to string -- `.Side` on
           it stays unbound (the KEY type is never taken)

  pwsh -File tests\autotest\run_v152_BK-TAILS-ENG.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { $script:Pass++; Write-Host "[PASS] $n" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "[FAIL] $n  $d" -ForegroundColor Red }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-tailseng-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
try {
  # ---------------- X: unindexed groupproj peer ----------------
  $X = Join-Path $Work 'x'
  [IO.Directory]::CreateDirectory($X) | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot '..\lint\xproj\*') -Destination $X -Recurse
  $P1 = Join-Path $X 'App1\App1.dproj'
  $Real1 = Join-Path $X 'App1\_D-RAG\App1.sqlite'
  [IO.Directory]::CreateDirectory((Split-Path $Real1)) | Out-Null
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $P1 --db $Real1 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $o; throw 'index App1 failed' }
  # App2 is deliberately NOT indexed: no App2\_D-RAG\App2.sqlite exists.

  function LintX([string]$rule) {
    $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
    $raw = (& { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($errFile); [IO.File]::WriteAllText($dlErrFile, ''); & $Exe lint-all --db $Real1 --project $P1 --json --no-stand-down --rule $rule 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }) -join "`n"
    $arr = @(); try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { Write-Host ('  unparsed: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length))) }
    $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    return [pscustomobject]@{ F = $arr; Err = $err }
  }
  function Hits($findings, [string]$rule, [string]$word) {
    return @($findings | Where-Object { $_.rule -eq $rule -and ('' + $_.message) -match "\b$word\b" }).Count
  }
  $UG = 'unused-global'; $MP = 'member-could-be-private'
  $peerLine = { param($e) @(($e -split "`r?`n") | Where-Object { $_ -match 'App2' -and $_ -match 'no index' }) }

  $u = LintX $UG
  Check 'X1 unindexed peer lists UShared: UsedOnlyByApp2 + UsedNowhere withheld' ((Hits $u.F $UG 'UsedOnlyByApp2') -eq 0 -and (Hits $u.F $UG 'UsedNowhere') -eq 0) ("only=$(Hits $u.F $UG 'UsedOnlyByApp2') nowhere=$(Hits $u.F $UG 'UsedNowhere')")
  $pl = @(& $peerLine $u.Err)
  Check 'X2 one stderr info line names the unindexed peer App2' ($pl.Count -eq 1) ("lines=$($pl.Count) err=" + ($u.Err -replace "`r?`n", ' | ').Substring(0, [Math]::Min(300, $u.Err.Length)))
  $m = LintX $MP
  Check 'X3 member-could-be-private: WriteChunk + OnlyLocal withheld' ((Hits $m.F $MP 'WriteChunk') -eq 0 -and (Hits $m.F $MP 'OnlyLocal') -eq 0) ("wc=$(Hits $m.F $MP 'WriteChunk') ol=$(Hits $m.F $MP 'OnlyLocal')")

  # X4: App2 still unindexed, but it no longer lists UShared (dproj + dpr stripped).
  $d2 = Join-Path $X 'App2\App2.dproj'; $p2 = Join-Path $X 'App2\App2.dpr'
  $sd = [IO.File]::ReadAllText($d2); $sp = [IO.File]::ReadAllText($p2)
  [IO.File]::WriteAllText($d2, ($sd -replace '(?m)^\s*<DCCReference Include="\.\.\\App1\\UShared\.pas"/>\r?\n', ''))
  [IO.File]::WriteAllText($p2, ($sp -replace "UShared in '\.\.\\App1\\UShared\.pas',", ''))
  $u4 = LintX $UG
  Check 'X4 control: unindexed peer NOT listing UShared -> UsedOnlyByApp2 fires, no peer line' ((Hits $u4.F $UG 'UsedOnlyByApp2') -eq 1 -and (& $peerLine $u4.Err).Count -eq 0) ("hits=$(Hits $u4.F $UG 'UsedOnlyByApp2') lines=$((& $peerLine $u4.Err).Count)")
  [IO.File]::WriteAllText($d2, $sd); [IO.File]::WriteAllText($p2, $sp)

  # X5: no groupproj -> App2 is no peer at all -> the finding fires (pre-1.52 behaviour).
  [IO.File]::Move((Join-Path $X 'Group.groupproj'), (Join-Path $X 'Group.groupproj.off'))
  $u5 = LintX $UG
  Check 'X5 control: no groupproj -> UsedOnlyByApp2 fires' ((Hits $u5.F $UG 'UsedOnlyByApp2') -eq 1) ("hits=$(Hits $u5.F $UG 'UsedOnlyByApp2')")

  # ---------------- C: character columns ----------------
  $C = Join-Path $Work 'c'
  [IO.Directory]::CreateDirectory($C) | Out-Null
  $E = [string][char]0xE9
  $Cp = [Text.Encoding]::GetEncoding(1252)
  $Unit = @'
unit uCol;

interface

procedure P1(PC: PChar; Q: TObject);

implementation

uses SysUtils, DB;

procedure P1(PC: PChar; Q: TObject);
var
  S: string;
  I: Integer;
begin
  {$IFDEF NEVER_DEFINED_X} ~~~ {$ENDIF} S:= StrPas(PC);
  {$IFDEF NEVER_DEFINED_X} eee {$ENDIF} S:= StrPas(PC);
  for I:= 0 to 3 do begin {$IFDEF NEVER_DEFINED_X} ~~~ {$ENDIF} S:= TDataSet(Q).FieldByName('a').AsString; end;
  for I:= 0 to 3 do begin {$IFDEF NEVER_DEFINED_X} eee {$ENDIF} S:= TDataSet(Q).FieldByName('b').AsString; end;
end;

end.
'@
  $UnitText = ($Unit -replace "`r?`n", "`r`n").Replace('~', $E)
  [IO.File]::WriteAllBytes((Join-Path $C 'uCol.pas'), $Cp.GetBytes($UnitText))
  [IO.File]::WriteAllBytes((Join-Path $C 'uCol.dfm'), $Cp.GetBytes(("object Form1: TForm1`r`n  Left = 0`r`n  Caption = '~~~' @@@`r`nend`r`n").Replace('~', $E)))
  $Bom = [byte[]](0xEF, 0xBB, 0xBF)
  $Txt = "unit uTxt;`r`ninterface`r`nimplementation`r`n// " + [char]::ConvertFromUtf32(0x1F600) + [string][char]0x200B + "x`r`n// a" + [string][char]0x200B + "x`r`nend.`r`n"
  [IO.File]::WriteAllBytes((Join-Path $C 'uTxt.pas'), $Bom + (New-Object Text.UTF8Encoding($false)).GetBytes($Txt))
  $CDb = Join-Path $Work 'c.sqlite'
  $idx = (& { $ErrorActionPreference = 'Continue'; & $Exe index $C --db $CDb 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  $diag = @(($idx -split "`r?`n") | Where-Object { $_ -match 'uCol\.dfm\((\d+),(\d+)\): parse error' })
  $dcol = if ($diag.Count -gt 0 -and $diag[0] -match 'uCol\.dfm\((\d+),(\d+)\)') { [int]$Matches[2] } else { -1 }
  Check 'C1 .dfm parse-error DIAG prints the character column 19 (byte column 22)' ($dcol -eq 19) ("got=$dcol line=$($diag | Select-Object -First 1)")

  function LintC([string]$file) {
    $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint (Join-Path $C $file) --db $CDb --json 2>$null }) -join "`n"
    $arr = @(); try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { }
    return ,$arr
  }
  $t = LintC 'uTxt.pas'
  $inv = { param($ln) @($t | Where-Object { $_.rule -eq 'invisible-char' -and [int]$_.start_line -eq $ln }) }
  $i4 = @(& $inv 4); $i5 = @(& $inv 5)
  Check 'C2 invisible-char after U+1F600 is at UTF-16 column 6' ($i4.Count -eq 1 -and [int]$i4[0].start_col -eq 6) ("got=" + ($i4 | ForEach-Object { $_.start_col }))
  Check 'C2c control: ASCII twin stays at column 5' ($i5.Count -eq 1 -and [int]$i5[0].start_col -eq 5) ("got=" + ($i5 | ForEach-Object { $_.start_col }))

  $lines = $UnitText -split "`r`n"
  $u = LintC 'uCol.pas'
  $at = { param($rule, $ln) @($u | Where-Object { $_.rule -eq $rule -and [int]$_.start_line -eq $ln }) }
  $want16 = $lines[15].IndexOf('StrPas') + 1; $want17 = $lines[16].IndexOf('StrPas') + 1
  $r16 = @(& $at 'deprecated-rtl-function' 16); $r17 = @(& $at 'deprecated-rtl-function' 17)
  Check 'C3 deprecated-rtl-function after a blanked non-ASCII directive: character column' ($r16.Count -eq 1 -and [int]$r16[0].start_col -eq $want16) ("want=$want16 got=" + ($r16 | ForEach-Object { $_.start_col }))
  Check 'C3c control: ASCII twin column' ($r17.Count -eq 1 -and [int]$r17[0].start_col -eq $want17) ("want=$want17 got=" + ($r17 | ForEach-Object { $_.start_col }))
  $want18 = $lines[17].IndexOf('FieldByName') + 1; $want19 = $lines[18].IndexOf('FieldByName') + 1
  $f18 = @(& $at 'field-by-name-in-loop' 18); $f19 = @(& $at 'field-by-name-in-loop' 19)
  Check 'C4 field-by-name-in-loop after a blanked non-ASCII directive: character column' ($f18.Count -eq 1 -and [int]$f18[0].start_col -eq $want18) ("want=$want18 got=" + ($f18 | ForEach-Object { $_.start_col }))
  Check 'C4c control: ASCII twin column' ($f19.Count -eq 1 -and [int]$f19[0].start_col -eq $want19) ("want=$want19 got=" + ($f19 | ForEach-Object { $_.start_col }))

  # ---------------- R: generic dictionary indexer types an inline var ----------------
  $R = Join-Path $Work 'r'
  [IO.Directory]::CreateDirectory($R) | Out-Null
  $Gen = @'
unit uGen;

interface

uses System.Generics.Collections;

type
  TBranch = class
  public
    Side: string;
  end;

procedure Go(const D: TDictionary<string, TBranch>; const Lst: TList<TBranch>; const Rev: TDictionary<TBranch, string>);

implementation

procedure Go(const D: TDictionary<string, TBranch>; const Lst: TList<TBranch>; const Rev: TDictionary<TBranch, string>);
begin
  var Br:= TObjectDictionary<string, TBranch>.Create;
  var B:= Br['x'];
  B.Side:= 'r1';
  var C:= D['y'];
  C.Side:= 'r2';
  var G: TBranch:= Br['v'];
  G.Side:= 'r3';
  var L0:= Lst[0];
  L0.Side:= 'r4';
  var K:= Rev[nil];
  K.Side:= 'r5';
end;

end.
'@
  [IO.File]::WriteAllText((Join-Path $R 'uGen.pas'), ($Gen -replace "`r?`n", "`r`n"))
  $RDb = Join-Path $Work 'r.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $R --db $RDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $q = "SELECT r.receiver_text AS rcv, s.qualified_name AS target FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id WHERE r.name_text = 'Side' AND r.receiver_text IS NOT NULL AND r.receiver_text <> ''"
  $rawR = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $RDb --query $q --json 2>$null }) -join "`n"
  $bound = @{}
  try {
    $j = $rawR | ConvertFrom-Json | ForEach-Object { $_ }
    $ci = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    foreach ($row in @($j.rows)) {
      $rcv = '' + $row[[array]::IndexOf($ci, 'rcv')]; $tg = '' + $row[[array]::IndexOf($ci, 'target')]
      if ($tg -ne '') { $bound[$rcv] = $tg } elseif (-not $bound.ContainsKey($rcv)) { $bound[$rcv] = '' }
    }
  } catch { Write-Host ('  unparsed sql: ' + $rawR.Substring(0, [Math]::Min(200, $rawR.Length))) }
  $is = { param($rcv) ('' + $bound[$rcv]) -eq 'uGen.TBranch.Side' }
  Check 'R1 var B:= Br[K] (Br an inline TObjectDictionary) -> B.Side binds TBranch.Side' (& $is 'B') ("got='$($bound['B'])'")
  Check 'R2 var C:= D[K] (D a TDictionary parameter) -> C.Side binds' (& $is 'C') ("got='$($bound['C'])'")
  Check 'R3 control: written type var G: TBranch:= Br[K] binds' (& $is 'G') ("got='$($bound['G'])'")
  Check 'R4 control: var L0:= Lst[0] on TList<TBranch> binds' (& $is 'L0') ("got='$($bound['L0'])'")
  Check 'R5 negative: TDictionary<TBranch, string>[K] is a string -- K.Side stays unbound' (-not (& $is 'K')) ("got='$($bound['K'])'")
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
Write-Host ("RESULT: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
