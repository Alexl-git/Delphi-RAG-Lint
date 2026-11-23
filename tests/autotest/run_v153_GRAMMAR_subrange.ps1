<#
  run_v153_GRAMMAR_subrange.ps1 -- grammar tree-sitter-delphi13 v1.4.15 (2d7ed53): a subrange bound is a
  constant EXPRESSION, and the extractor reads the names of both bounds in every position.
  Live case: C:\Projects\M2022 MetrologyCategories.pas:496, `Available: set of 1 .. MAXCOLUMNCOUNT * 2;`
  (a local var section), docs\INBOX-grammar-set-of-subrange-const-expr.md.

  P1      no parse error in the fixture (grammar).
  T*      the declared type text is the WHOLE type, upper bound included (an ERROR cut it at `1 .. CMul`).
  R*      each name of a bound is ONE `read` ref at its exact line:col -- the column says which side of `..`.
  G1      a subrange-typed GLOBAL (`G: 0..CGlob`, no `type` wrapper node) reads its bound (extractor).
  L*      a classic LOCAL's set / subrange / array / string[N] type: bounds read, element + index types type_use;
          the inline `var` form stays at exactly one ref (the body walk already emits it).
  N*      no stray symbols: an inline record / enum type of a local adds no symbol, `(N1)` is still an enum.

  RED: grammar v1.4.14 fails P1 and T2-T11; the 1.42.0 extractor (any grammar) fails G1 and L1-L6.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v153-subrange-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[void][IO.Directory]::CreateDirectory($WorkDir)

# Every checked fixture line carries its check id in a trailing comment; the checks look the line up by that id.
$src = @"
unit subr153;

interface

const
  MAXCOLUMNCOUNT = 10;
  CMul = 2; CLo = 1; CHi = 3; CShl = 1; CAnd = 7; COr = 8; CXor = 3; CMod = 5; CParen = 4; CNeg = 5;
  CSetT = 4; CRecF = 5; CRecS = 6; CIx = 7; CEl = 8; CGlob = 9; CLoc = 8; CLocArr = 6; CLocStr = 12;
  CInl = 3; CCase = 4;

type
  TEnumQ = (qA, qB, qC);
  TElem  = class end;
  TPlain = 1..10;                              //T1
  TMul   = 1 .. CMul * 2;                      //T2
  TLow   = CLo - 1 .. CHi + 1;                 //T3
  TShl   = 0 .. 1 shl CShl;                    //T4
  TAnd   = 0 .. CAnd and 15;                   //T5
  TOr    = 0 .. COr or 1;                      //T6
  TXor   = 0 .. CXor xor 1;                    //T7
  TDivM  = CMod mod 2 .. (CParen - 1) * 2 + 1; //T8
  TCall  = 0 .. High(Byte) - 1;                //T9
  TSetT  = set of 1 .. CSetT * 2;              //T10
  TNeg   = -CNeg .. CNeg;                      //T12
  TNegL  = -10 .. -1;                          //T13
  TChr   = 'a'..'z';                           //T14
  TChrN  = #65..#90;                           //T15
  TQual  = TEnumQ.qA .. TEnumQ.qB;             //T16
  TOne   = (N1);                               //N2
  TRec = record
    F: 0 .. CRecF * 2;                         //T11
    S: set of 0 .. CRecS - 1;                  //T17
  end;
  TArr = array[0 .. CIx * 2] of 0 .. CEl + 1;  //T18

var
  G : 0..CGlob;                                //G1

procedure P(V: Integer);

implementation

procedure P(V: Integer);
var
  Available: set of 1 .. MAXCOLUMNCOUNT * 2;   //L1
  B: 0 .. CLoc * 2;                            //L2
  A: array[0..CLocArr] of TElem;               //L3
  X: array[TEnumQ] of TElem;                   //L4
  S: string[CLocStr];                          //L5
  R: record Inner: Integer; end;               //N1
begin
  var Z: array[0..CInl] of TElem;              //L7
  case V of
    CCase .. CCase * 2: B:= 1;                 //L8
  end;
end;

end.
"@ -replace "`r?`n", "`r`n"
$pas = Join-Path $WorkDir 'subr153.pas'
[IO.File]::WriteAllText($pas, $src, [Text.Encoding]::ASCII)
$lines = $src -split "`r`n"
function LineOf([string]$id) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "//$id$") { return $i + 1 } }
  throw "no fixture line $id"
}

$db  = Join-Path $WorkDir 'subr153.sqlite'
$out = & { $ErrorActionPreference = 'Continue'; & $Exe index $WorkDir --db $db 2>&1 | ForEach-Object { "$_" } }
$done = ($out | Where-Object { $_ -match '^Done\.' } | Select-Object -Last 1)

$py = Join-Path $WorkDir 'dump.py'
@"
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
print(json.dumps({
  'refs': [{'l': r[0], 'c': r[1], 'k': r[2], 'n': r[3]} for r in c.execute('SELECT start_line, start_col, kind, name_text FROM refs')],
  'syms': [{'l': r[0], 'k': r[1], 'n': r[2], 's': r[3], 'q': r[4]} for r in c.execute('SELECT start_line, kind, name, signature, qualified_name FROM symbols')]}))
"@ | Set-Content $py -Encoding ascii
$d = (& python -I $py $db) -join "`n" | ConvertFrom-Json | ForEach-Object { $_ }

Write-Host 'P -- the grammar parses every bound' -ForegroundColor Cyan
Check 'P0 control: the fixture is indexed' (@($d.syms | Where-Object { $_.n -eq 'MAXCOLUMNCOUNT' }).Count -eq 1) "symbols=$(@($d.syms).Count)"
Check 'P1 parse-errors=0' ("$done" -match 'parse-errors=0\b') "$done"

function Sig([string]$id, [string]$name, [string]$want) {
  $got = @($d.syms | Where-Object { $_.l -eq (LineOf $id) -and $_.n -eq $name } | ForEach-Object { $_.s })
  Check "$id $name type text" ($got.Count -eq 1 -and $got[0] -ceq $want) "got '$($got -join '|')'"
}
# Every ref of $name on the fixture line of $id, as 'kind@col', col 1-based, left to right -- must equal the
# kind at each place $name occurs on that line as a word. Exact, so a missing and a doubled ref both fail.
function Refs([string]$id, [string]$name, [string]$kind = 'read') {
  $ln   = LineOf $id
  $text = $lines[$ln - 1] -replace '//.*$', ''
  $want = @([regex]::Matches($text, "\b$name\b") | ForEach-Object { "$kind@$($_.Index + 1)" }) -join ' '
  $got  = @($d.refs | Where-Object { $_.l -eq $ln -and $_.n -eq $name } | Sort-Object c | ForEach-Object { "$($_.k)@$($_.c)" }) -join ' '
  Check "$id $name refs" (($want -ne '') -and ($got -ceq $want)) "want '$want' got '$got'"
}

Write-Host ''
Write-Host 'T -- type text and bound refs' -ForegroundColor Cyan
Sig T1  TPlain '1..10'
Sig T2  TMul   '1 .. CMul * 2';                       Refs T2 CMul
Sig T3  TLow   'CLo - 1 .. CHi + 1';                  Refs T3 CLo;  Refs T3 CHi
Sig T4  TShl   '0 .. 1 shl CShl';                     Refs T4 CShl
Sig T5  TAnd   '0 .. CAnd and 15';                    Refs T5 CAnd
Sig T6  TOr    '0 .. COr or 1';                       Refs T6 COr
Sig T7  TXor   '0 .. CXor xor 1';                     Refs T7 CXor
Sig T8  TDivM  'CMod mod 2 .. (CParen - 1) * 2 + 1';  Refs T8 CMod; Refs T8 CParen
Sig T9  TCall  '0 .. High(Byte) - 1';                 Refs T9 High
Sig T10 TSetT  'set of 1 .. CSetT * 2';               Refs T10 CSetT
Sig T11 F      '0 .. CRecF * 2';                      Refs T11 CRecF
Sig T12 TNeg   '-CNeg .. CNeg';                       Refs T12 CNeg
Sig T13 TNegL  '-10 .. -1'
Sig T14 TChr   "'a'..'z'"
Sig T15 TChrN  '#65..#90'
Sig T16 TQual  'TEnumQ.qA .. TEnumQ.qB';              Refs T16 TEnumQ; Refs T16 qA; Refs T16 qB
Sig T17 S      'set of 0 .. CRecS - 1';               Refs T17 CRecS
Sig T18 TArr   'array[0 .. CIx * 2] of 0 .. CEl + 1'; Refs T18 CIx; Refs T18 CEl
$plain = @($d.refs | Where-Object { $_.l -in @((LineOf T1), (LineOf T13), (LineOf T14), (LineOf T15)) })
Check 'T1/T13/T14/T15 a literal-only subrange emits no ref' ($plain.Count -eq 0) "refs=$($plain.Count)"

Write-Host ''
Write-Host 'G / L -- globals and locals' -ForegroundColor Cyan
Refs G1 CGlob
Sig  L1 Available 'set of 1 .. MAXCOLUMNCOUNT * 2'; Refs L1 MAXCOLUMNCOUNT
Sig  L2 B '0 .. CLoc * 2';                          Refs L2 CLoc
Refs L3 CLocArr; Refs L3 TElem type_use
Refs L4 TEnumQ type_use; Refs L4 TElem type_use
Refs L5 CLocStr
Refs L7 CInl; Refs L7 TElem type_use
Refs L8 CCase

Write-Host ''
Write-Host 'N -- no stray symbols' -ForegroundColor Cyan
$n1 = @($d.syms | Where-Object { $_.l -eq (LineOf N1) } | ForEach-Object { "$($_.k):$($_.n)" }) -join ' '
Check 'N1 an inline record of a local adds no symbol' ($n1 -ceq 'local_var:R') "got '$n1'"
$n2 = @($d.syms | Where-Object { $_.l -eq (LineOf N2) } | ForEach-Object { "$($_.k):$($_.n)" }) -join ' '
Check 'N2 (N1) is still an enumeration' ($n2 -ceq 'enum:TOne enum_value:N1') "got '$n2'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (($WorkDir -like "*-$PID") -and [IO.Directory]::Exists($WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Verbose "$_" } }
}