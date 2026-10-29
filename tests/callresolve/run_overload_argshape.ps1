<#
  run_overload_argshape.ps1 -- same-arity overloads are told apart by the
  SHAPE of the arguments at the call site (lane rb5-ovl, resolver 1.17.0-alpha).

  THE GAP (lane rb5-gen measurement, 2026-10-28)
  --------------------------------------------------------------------------------
  On ORM3 CLIENT all 163 ambiguous interface call edges (+19 on SERVER) are
  same-arity overloads that differ only by parameter TYPE. 159 are
  IABZLoggingSys.LogMessage:

      LogMessage(const AMessageType: TMessageType; const AFormat: string;
                 const Args: array of const; const ALogLevel: cardinal = 4)
      LogMessage(const AMessageType: TMessageType; const AFormat: string;
                 const ALogLevel: cardinal = 4)

  A 3-argument call fits both by arity. 145 sites pass an integer literal as the
  3rd argument (only the second overload can take it) and 14 pass `[..]` (only
  the first can). Arity alone answered 'ambiguous' for every one.

  THE RULE: a candidate is dropped only when some argument is IMPOSSIBLE for its
  parameter -- an integer literal for an open array or a string, a set/array
  constructor for an Integer, a literal for a var/out parameter. A parameter of a
  type the resolver cannot classify (an enum, an alias, a record, a generic T)
  never rejects. Narrowing only: when the survivors are not exactly one, the
  site stays 'ambiguous'. The controls below pin that half, because a fix that
  simply started claiming 'certain' would pass the positive checks alone.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-overload-argshape-$PID"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# One Drive* routine per call site, so each assertion names its site by the
# enclosing routine. Put is the four-way set the lane brief names (Integer, open
# array, string, Double); Tag pairs a type the resolver cannot classify (TMyInt)
# with string; ILogger.Log is the ORM3 LogMessage shape.
Write-Ascii (Join-Path $WorkDir 'ovlshape.pas') @'
unit ovlshape;

interface

type
  TMsgKind = (mkInfo, mkError);
  TMyInt = Integer;

  ILogger = interface
    ['{6A1C2D3E-1111-4222-8333-444455556666}']
    procedure Log(const AKind: TMsgKind; const AFmt: string; const Args: array of const; const ALevel: Cardinal = 4); overload;
    procedure Log(const AKind: TMsgKind; const AFmt: string; const ALevel: Cardinal = 4); overload;
  end;

procedure Put(const A: Integer); overload;
procedure Put(const A: array of Integer); overload;
procedure Put(const A: string); overload;
procedure Put(const A: Double); overload;

procedure Tag(const A: TMyInt); overload;
procedure Tag(const A: string); overload;

function GetLevel: Cardinal;

procedure DriveFloat;
procedure DriveNegFloat;
procedure DriveStr;
procedure DriveSet;
procedure DriveInt;
procedure DriveHex;
procedure DriveIntVar;
procedure DriveStrVar;
procedure DriveFloatVar;
procedure DriveUnknown;
procedure DriveNamedInt;
procedure DriveNamedStr;
procedure DriveLogInt(const L: ILogger);
procedure DriveLogSet(const L: ILogger);
procedure DriveLogMultiline(const L: ILogger);
procedure DriveLogUnknown(const L: ILogger);

implementation

procedure Put(const A: Integer);
begin
end;

procedure Put(const A: array of Integer);
begin
end;

procedure Put(const A: string);
begin
end;

procedure Put(const A: Double);
begin
end;

procedure Tag(const A: TMyInt);
begin
end;

procedure Tag(const A: string);
begin
end;

function GetLevel: Cardinal;
begin
  Result := 2;
end;

procedure DriveFloat;
begin
  Put(1.5);
end;

procedure DriveNegFloat;
begin
  Put(-2.5e3);
end;

procedure DriveStr;
begin
  Put('abc');
end;

procedure DriveSet;
begin
  Put([1, 2]);
end;

procedure DriveInt;
begin
  Put(5);
end;

procedure DriveHex;
begin
  Put($FF);
end;

procedure DriveIntVar;
var
  N: Integer;
begin
  N := 3;
  Put(N);
end;

procedure DriveStrVar;
var
  S: string;
begin
  S := 'q';
  Put(S);
end;

procedure DriveFloatVar;
var
  D: Double;
begin
  D := 0.5;
  Put(D);
end;

procedure DriveUnknown;
var
  N: Integer;
begin
  N := 3;
  Put(Ord(N));
end;

procedure DriveNamedInt;
begin
  Tag(5);
end;

procedure DriveNamedStr;
begin
  Tag('abc');
end;

procedure DriveLogInt(const L: ILogger);
begin
  L.Log(mkInfo, 'level %d', 3);
end;

procedure DriveLogSet(const L: ILogger);
begin
  L.Log(mkInfo, 'level %d', [GetLevel]);
end;

procedure DriveLogMultiline(const L: ILogger);
begin
  L.Log(mkError,
        'two %d %s',
        [1, 'x']);
end;

procedure DriveLogUnknown(const L: ILogger);
begin
  L.Log(mkInfo, 'level', GetLevel + 1);
end;

end.
'@

$db = Join-Path $WorkDir 'ovlshape.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$py = Join-Path $WorkDir 'edges.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = []
for row in c.execute("""
    SELECT enc.name, r.name_text, ce.confidence, tgt.signature
    FROM refs r
    JOIN call_edges ce ON ce.ref_id = r.id
    JOIN symbols enc ON enc.id = r.enclosing_symbol_id
    JOIN symbols tgt ON tgt.id = ce.target_symbol_id
    WHERE r.kind IN ('call', 'member-access') AND r.name_text IN ('Put', 'Tag', 'Log')"""):
    out.append({"from": row[0], "callee": row[1], "conf": row[2], "sig": row[3] or ""})
# A dotted call is recorded as a 'call' AND a 'member-access' ref; the site has
# lost its edge only when NEITHER carries one.
noedge = [r[0] + "/" + r[1] for r in c.execute("""
    SELECT enc.name, r.name_text FROM refs r
    JOIN symbols enc ON enc.id = r.enclosing_symbol_id
    WHERE r.kind IN ('call', 'member-access') AND r.name_text IN ('Put', 'Tag', 'Log')
    GROUP BY r.enclosing_symbol_id, r.name_text, r.start_line, r.start_col
    HAVING SUM(EXISTS(SELECT 1 FROM call_edges ce WHERE ce.ref_id = r.id)) = 0""")]
print(json.dumps({"edges": out, "noedge": noedge}))
c.close()
'@ | Set-Content $py -Encoding ascii
$res = (& python $py $db) -join "`n" | ConvertFrom-Json
$edges = @($res.edges)

function Site($from, $callee) {
  @($edges | Where-Object { $_.from -eq $from -and $_.callee -eq $callee }) | Select-Object -First 1
}
# The parameter that tells the overloads apart, read off the TARGET's signature.
function ParamOf($e) { if ($null -eq $e) { return '<no edge>' }; return $e.sig }
function CertainTo($from, $callee, $pattern, $label) {
  $e = Site $from $callee
  Check "$from binds $label, CERTAIN" `
    ($null -ne $e -and $e.conf -eq 'certain' -and $e.sig -match $pattern) `
    "conf=$($e.conf) sig=$(ParamOf $e)"
}
function StaysAmbiguous($from, $callee, $why) {
  $e = Site $from $callee
  Check "$from stays ambiguous ($why)" ($null -ne $e -and $e.conf -eq 'ambiguous') `
    "conf=$($e.conf) sig=$(ParamOf $e)"
  return $e
}

Write-Host 'Literal and constructor shapes decide the overload' -ForegroundColor Cyan
CertainTo 'DriveFloat'    'Put' 'A: Double'           'Put(Double) for 1.5'
CertainTo 'DriveNegFloat' 'Put' 'A: Double'           'Put(Double) for -2.5e3'
CertainTo 'DriveStr'      'Put' 'A: string'           'Put(string) for a string literal'
CertainTo 'DriveSet'      'Put' 'array of Integer'    'Put(array of Integer) for [1, 2]'
CertainTo 'DriveNamedInt' 'Tag' 'TMyInt'              'Tag(TMyInt) for 5 (string is impossible, TMyInt is not)'

Write-Host ''
Write-Host 'Variables of a known built-in type' -ForegroundColor Cyan
CertainTo 'DriveStrVar'   'Put' 'A: string'           'Put(string) for a string variable'
CertainTo 'DriveFloatVar' 'Put' 'A: Double'           'Put(Double) for a Double variable'

Write-Host ''
Write-Host 'The ORM3 LogMessage shape (interface receiver)' -ForegroundColor Cyan
CertainTo 'DriveLogInt'       'Log' '^(?!.*array of const).*ALevel' 'the 3-parameter Log for an integer literal'
CertainTo 'DriveLogSet'       'Log' 'array of const'                'the array-of-const Log for [GetLevel]'
CertainTo 'DriveLogMultiline' 'Log' 'array of const'                'the array-of-const Log for a [..] on its own line'

Write-Host ''
Write-Host 'Controls -- what the shape must NOT decide' -ForegroundColor Cyan
$i = StaysAmbiguous 'DriveInt' 'Put' 'an integer literal fits Integer AND Double'
Check 'DriveInt still targets a numeric overload' ($null -ne $i -and $i.sig -match 'Integer\)|Double\)' -and $i.sig -notmatch 'array') "sig=$(ParamOf $i)"
[void](StaysAmbiguous 'DriveHex'        'Put' '$FF fits Integer AND Double')
[void](StaysAmbiguous 'DriveIntVar'     'Put' 'an Integer variable fits Integer AND Double')
[void](StaysAmbiguous 'DriveUnknown'    'Put' 'Ord(N) is an expression of unknown shape')
[void](StaysAmbiguous 'DriveNamedStr'   'Tag' 'a string literal may suit TMyInt as far as the resolver knows')
[void](StaysAmbiguous 'DriveLogUnknown' 'Log' 'GetLevel + 1 is an expression of unknown shape')
Check 'no Put/Tag/Log call site lost its edge' (@($res.noedge).Count -eq 0) "unresolved=$($res.noedge -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-overload-argshape-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
